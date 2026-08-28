/// Pure geometry analysis for deciding whether masks have settled between two samples.
/// Every function here takes its inputs as parameters and touches no instance state.
#if os(iOS)
    import Foundation
    import UIKit

    extension PostHogReplayIntegration {
        /// A maskable rect tagged with its view/layer identity, so two samples taken moments
        /// apart pair by identity rather than array index — traversal order isn't stable across
        /// cell recycling or z-order changes. `object` is retained because a deallocation would
        /// otherwise let `owner`'s address be reused by an unrelated view.
        struct MaskedRegion {
            let owner: ObjectIdentifier
            let object: AnyObject
            let rect: CGRect

            init(_ object: AnyObject, rect: CGRect) {
                owner = ObjectIdentifier(object)
                self.object = object
                self.rect = rect
            }

            init(_ view: UIView, in window: UIWindow?) {
                self.init(view, rect: view.toPresentationRect(window))
            }

            init(_ layer: CALayer, in window: UIWindow?) {
                self.init(layer, rect: layer.toPresentationRect(window))
            }
        }

        // Tuning surface for the settle check. Defaults are deliberately conservative: measured on
        // device, a 25ms window sees ~1.5pt of slow drift, ~4pt of CA animation and 185pt+ of a
        // scroll fling, so everything except a fling keeps the same renderer session replay has
        // always used, and only a fling trades fidelity for exactly-aligned masks.

        /// Gap between the two geometry samples. Raising it delays each capture by that much and
        /// holds the render-in-flight slot longer; lowering it makes the velocity estimate noisier.
        /// The band thresholds derive from it, so changing it rescales them rather than
        /// invalidating them.
        static let settleWindowSeconds: TimeInterval = 0.025

        /// At or below 80pt/s, geometry counts as unmoved and rects are used exactly as sampled.
        /// Raise only to stop idle screens paying for inflation, and only a little: this much
        /// displacement then goes uncompensated, so it is the one knob that trades directly
        /// against coverage.
        private static let settleTolerancePoints = 80 * CGFloat(settleWindowSeconds)

        /// Above 2000pt/s, drop to the presentation-tree renderer, whose masks cannot disagree with
        /// its pixels but which flattens blur, video and Metal. Raise to keep more motion at full
        /// fidelity, paying for it in larger inflated masks; lower for tighter masks and more flat
        /// frames. Sits between animation and fling so ordinary movement never flattens.
        private static let driftBudgetPoints = 2000 * CGFloat(settleWindowSeconds)

        /// Lead added past the newer sample, as a fraction of the measured displacement — the union
        /// of both samples does the real covering, this only pads the direction of travel. On device
        /// every value from 1 down to 1/64 held without exposing content, so it stays small; raise
        /// it only if content is ever seen escaping the leading edge, since it grows every mask.
        private static let driftLeadFraction: CGFloat = 1.0 / 16.0

        /// Displacement between the two rect samples estimates how far the displayed pixels
        /// trail current geometry — the display pipeline is about one settle window deep.
        enum SettleBand {
            case still, drift, motion

            /// Only motion needs the presentation-tree renderer, which is aligned by construction.
            var usesFidelity: Bool { self != .motion }
        }

        /// Old rects in `after` order, or nil when the two samples can't be paired one-to-one:
        /// a nil sample, a count mismatch, a duplicate owner in either, or an owner with no
        /// counterpart. Index-pairing would fail open into `.still`, so pairing is by identity.
        /// Rects keyed by owner, or nil on a repeated owner — one object can match two maskable
        /// heuristics and be collected twice, and pairing is then ambiguous. Built by hand rather
        /// than Dictionary(uniqueKeysWithValues:), which traps on a duplicate key, and an SDK must
        /// not turn that into a host-app crash.
        private static func rectsByOwner(_ regions: [MaskedRegion]) -> [ObjectIdentifier: CGRect]? {
            var byOwner: [ObjectIdentifier: CGRect] = [:]
            byOwner.reserveCapacity(regions.count)
            for region in regions where byOwner.updateValue(region.rect, forKey: region.owner) != nil {
                return nil
            }
            return byOwner
        }

        private static func pairedOldRects(before: [MaskedRegion]?, after: [MaskedRegion]?) -> [CGRect]? {
            guard let before, let after, before.count == after.count,
                  let beforeByOwner = rectsByOwner(before)
            else {
                return nil
            }
            // Ordered to match `after` one-for-one: the result substitutes positionally
            // for the `after` sample downstream.
            var oldRects: [CGRect] = []
            oldRects.reserveCapacity(after.count)
            var seenAfterOwners: Set<ObjectIdentifier> = []
            seenAfterOwners.reserveCapacity(after.count)
            for region in after {
                // No counterpart in `before` — something appeared/disappeared, fail closed.
                guard let oldRect = beforeByOwner[region.owner] else {
                    return nil
                }
                // A duplicate here would silently pair two `after` entries with the same old
                // rect, hiding whatever the repeated owner displaced — fail closed instead.
                guard seenAfterOwners.insert(region.owner).inserted else {
                    return nil
                }
                oldRects.append(oldRect)
            }
            return oldRects
        }

        /// Per-owner union of two samples taken either side of a render: covers wherever the
        /// content sat while the render ran. An owner present in only one sample was still on
        /// screen for part of that window, so its rect is emitted as collected rather than
        /// discarding the frame — a scroll that recycles cells changes the owner set constantly,
        /// and dropping every such frame freezes the recording across the whole interaction.
        /// Unlike `pairedOldRects` the result is a mask list, not positionally tied to `after`.
        /// nil only for a repeated owner within one sample, where the pairing is genuinely
        /// ambiguous and there is no safe rect to emit.
        static func sweptRects(before: [MaskedRegion]?, after: [MaskedRegion]?) -> [CGRect]? {
            guard let before, let after, let beforeByOwner = rectsByOwner(before) else {
                return nil
            }

            var rects: [CGRect] = []
            rects.reserveCapacity(max(before.count, after.count))
            var seenAfterOwners: Set<ObjectIdentifier> = []
            seenAfterOwners.reserveCapacity(after.count)
            for region in after {
                guard seenAfterOwners.insert(region.owner).inserted else {
                    return nil
                }
                // No counterpart means the owner appeared mid-render; cover where it landed.
                rects.append(beforeByOwner[region.owner].map { $0.union(region.rect) } ?? region.rect)
            }
            // Owners that went away mid-render were still displayed for part of it.
            for region in before where !seenAfterOwners.contains(region.owner) {
                rects.append(region.rect)
            }
            return rects
        }

        /// Banded by measured drift:
        /// - still (≤ tolerance): rects as collected.
        /// - drift (≤ budget): each mask inflated to the swept region (both sampled positions
        ///   plus `driftLeadFraction` of it as lead).
        /// - motion (anything else, or unreadable geometry): fail-closed default.
        static func settleVerdict(
            before: [MaskedRegion]?, after: [MaskedRegion]?
        ) -> (band: SettleBand, inflatedRects: [CGRect]?) {
            guard let after, let oldRects = pairedOldRects(before: before, after: after) else {
                return (.motion, nil)
            }
            let maxDisplacement = zip(oldRects, after).map { old, new in
                max(abs(old.minX - new.rect.minX), abs(old.minY - new.rect.minY),
                    abs(old.width - new.rect.width), abs(old.height - new.rect.height))
            }.max() ?? 0
            if maxDisplacement <= settleTolerancePoints {
                return (.still, nil)
            }
            if maxDisplacement <= driftBudgetPoints {
                let inflated = zip(oldRects, after).map { old, region -> CGRect in
                    let new = region.rect
                    let deltaX = new.midX - old.midX
                    let deltaY = new.midY - old.midY
                    return old.union(new)
                        .union(new.offsetBy(dx: deltaX * driftLeadFraction, dy: deltaY * driftLeadFraction))
                        // Full displacement, not a fraction like the lead: this covers a position
                        // that was never sampled, since a render pipeline deeper than one settle
                        // window leaves the displayed pixels behind `before`.
                        .union(old.offsetBy(dx: -deltaX, dy: -deltaY))
                }
                return (.drift, inflated)
            }
            return (.motion, nil)
        }
    }
#endif
