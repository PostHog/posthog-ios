#if os(iOS) && canImport(Metal)
    import QuartzCore
    import UIKit

    extension PostHogInlineMask {
        /// A copy in an `ExtentTree`.
        struct ExtentEntry {
            let copy: CALayer
            /// Window coordinates: the bounding box when rotated, or Core Animation's conversion where the mirror
            /// couldn't place the copy (3D or flipped geometry, or through a portal).
            let frame: CGRect
            /// Bounds-to-window map, when affine and sublayers sit unchanged in bounds, so a cover can be placed.
            let coverable: CGAffineTransform?
            /// `frame` with every descendant's: a zero-size layer (a portal source) still reaches what it holds.
            var subtreeFrame: CGRect
            /// The index past its last descendant: in pre-order, a subtree is the range up to it.
            var subtreeEnd: Int
        }

        /// The mirror flattened in paint order (the window's pre-order), with each copy's window place. A masked view
        /// is painted before its reporter's overlay; UI above it, in any host, after.
        struct ExtentTree {
            private(set) var entries: [ExtentEntry] = []
            private let root: CALayer
            private let reporterCopies: Set<ObjectIdentifier>
            /// Where each reporter copy sits in paint order.
            private var reporters: [ObjectIdentifier: Int] = [:]
            /// Entries with a non-zero `zPosition`. It reorders only among siblings, since copies flatten their subtree.
            private var layered: [(index: Int, parent: Int?)] = []

            /// nil when the root lands nowhere finite, so no extent can be located in it.
            init?(root: CALayer, copies: CopyIndex, reporterCopies: Set<ObjectIdentifier>) {
                self.root = root
                self.reporterCopies = reporterCopies
                entries.reserveCapacity(copies.count)
                let frame = collect(root, parent: nil, copies: copies)
                guard !frame.isNull, frame.minX.isFinite, frame.minY.isFinite, frame.width.isFinite, frame.height.isFinite else { return nil }
            }

            /// Entries `rect` reaches in paint order, up to the reporter's own copy unless a `zPosition` can reorder
            /// them against it. `ordered` is false when it can, or when the reporter's copy isn't drawn here.
            func entries(reachedBy rect: CGRect, reporter copies: Set<ObjectIdentifier>) -> (indices: [Int], ordered: Bool) {
                let reporterIndex = copies.compactMap { reporters[$0] }.min()
                let reordered = reporterIndex.map { reporter in layered.contains { canReorder($0, against: reporter, in: rect) } } ?? false
                let end = reordered ? entries.count : reporterIndex ?? entries.count
                var indices: [Int] = []
                var index = 0
                while index < end {
                    let entry = entries[index]
                    guard entry.subtreeFrame.intersects(rect) else {
                        index = entry.subtreeEnd
                        continue
                    }
                    if entry.frame.intersects(rect) { indices.append(index) }
                    index += 1
                }
                return (indices, reporterIndex != nil && !reordered)
            }

            /// A `zPosition` moves a layer only among its siblings. So it changes what's painted before the reporter only
            /// when its parent is on the reporter's branch: it's the branch itself, or a sibling of it whose subtree
            /// reaches the extent. Anywhere else, it reorders a subtree that's wholly before or after the reporter.
            private func canReorder(_ layered: (index: Int, parent: Int?), against reporter: Int, in rect: CGRect) -> Bool {
                guard let parent = layered.parent, isOnBranch(parent, of: reporter) else { return false }
                return isOnBranch(layered.index, of: reporter) || entries[layered.index].subtreeFrame.intersects(rect)
            }

            /// Whether the entry is the reporter or one of its ancestors: in pre-order, the reporter lies in its subtree.
            private func isOnBranch(_ index: Int, of reporter: Int) -> Bool {
                index <= reporter && reporter < entries[index].subtreeEnd
            }

            /// Appends the layer and its visible subtree in pre-order, and returns the subtree's frame.
            private mutating func collect(_ layer: CALayer, parent: Int?, copies: CopyIndex) -> CGRect {
                let placement = copies.placement(of: layer)
                let frame = placement.map { layer.bounds.applying($0.toWindow) } ?? layer.convert(layer.bounds, to: root)
                let index = entries.count
                entries.append(ExtentEntry(copy: layer, frame: frame, coverable: placement.flatMap { $0.hasPlainSublayers ? $0.toWindow : nil },
                                           subtreeFrame: frame, subtreeEnd: index + 1))
                if reporterCopies.contains(ObjectIdentifier(layer)) { reporters[ObjectIdentifier(layer)] = index }
                if layer.zPosition != 0 { layered.append((index, parent)) }
                var subtreeFrame = frame
                for sublayer in layer.sublayers ?? [] where !sublayer.isHidden {
                    subtreeFrame = subtreeFrame.union(collect(sublayer, parent: index, copies: copies))
                }
                entries[index].subtreeFrame = subtreeFrame
                entries[index].subtreeEnd = entries.count
                return subtreeFrame
            }
        }

        /// How a copy the extent reaches is masked.
        enum ExtentTreatment {
            /// Its content, as the walk masks it.
            case redact(Kind)
            /// A backdrop draws what's behind it: covered over the extent, or hidden.
            case backdrop
            /// Colour of its own and nothing else to mask (or already masked): black.
            case color(strippingFirst: Bool)
        }

        /// Rounding slack for extent containment, so edge-aligned copies count as inside.
        fileprivate static let extentTolerance: CGFloat = 0.5

        /// Whether the copy draws content of its own: contents, a shape, text, or a mask (which can give a plain
        /// background a glyph's shape).
        static func drawsContent(_ copy: CALayer) -> Bool {
            copy.contents != nil || (copy as? CAShapeLayer)?.path != nil || (copy as? CATextLayer)?.string != nil || copy.mask != nil
        }

        /// Whether the copy shows colour of its own without content: a background, border, gradient or shadow.
        static func drawsColor(_ copy: CALayer) -> Bool {
            isVisible(copy.backgroundColor) || copy.borderWidth > 0 && isVisible(copy.borderColor)
                || (copy as? CAGradientLayer)?.colors?.isEmpty == false || copy.shadowOpacity > 0 && isVisible(copy.shadowColor)
        }

        /// Whether a sublayer can cover the copy's content: a mask would clip the cover, and a blend could let the
        /// content through it.
        static func layerAllowsCover(_ copy: CALayer) -> Bool {
            copy.mask == nil && copy.compositingFilter == nil
        }

        /// The part of `rect` (window coordinates) to cover in a copy placed by `toWindow`, in its bounds coordinates:
        /// out to whole output pixels at `scale`, and clipped to the bounds unless the content can spill past them.
        static func hole(_ rect: CGRect, in copy: CALayer, toWindow: CGAffineTransform, scale: CGFloat) -> CGRect? {
            guard abs(toWindow.a * toWindow.d - toWindow.b * toWindow.c) > .ulpOfOne, scale > 0 else { return nil }
            // A cover edge inside a pixel would leave that pixel to rounding.
            let pixels = rect.applying(CGAffineTransform(scaleX: scale, y: scale)).integral
            let local = pixels.applying(CGAffineTransform(scaleX: 1 / scale, y: 1 / scale).concatenating(toWindow.inverted()))
            // A shape's path and stroke aren't bounded by its bounds.
            let spills = !copy.masksToBounds && (copy.filters != nil || copy is CAShapeLayer || copy.contents != nil
                && copy.contentsGravity != .resize && copy.contentsGravity != .resizeAspect)
            let hole = spills ? local : local.intersection(copy.bounds)
            return hole.isNull || hole.isEmpty ? nil : hole
        }

        /// Black over `hole`, painted over the copy's own background and content and under its sublayers. Its border
        /// and shadow are drawn past any sublayer, so they turn black and off all round.
        static func cover(_ hole: CGRect, in copy: CALayer) {
            let cover = CALayer()
            cover.frame = hole
            cover.backgroundColor = black
            copy.insertSublayer(cover, at: 0)
            blackOut(copy, .edges)
        }
    }

    extension PostHogInlineMask.Pass {
        private struct Reporter {
            let region: Int
            let copies: Set<ObjectIdentifier>
        }

        /// Masks everything painted under each reporter region's extent before the reporter, and returns the indices of
        /// the regions it covered. A reporter with no copy in the mirror keeps its rect.
        mutating func redactExtents(_ regions: [PostHogReplayIntegration.MaskedRegion]) -> Set<Int> {
            #if TESTING
                guard mask.isExtentEnabledForTesting else { return [] }
            #endif
            guard let root else { return [] }
            var reporters: [Reporter] = []
            for (regionIndex, region) in regions.enumerated() where region.inline == .extent {
                guard let view = region.object as? UIView else { continue }
                let copies = Set(index.copies(of: view.layer).map(ObjectIdentifier.init))
                if !copies.isEmpty { reporters.append(Reporter(region: regionIndex, copies: copies)) }
            }
            // Flattened once, and only when a reporter needs it.
            let reporterCopies = reporters.reduce(into: Set<ObjectIdentifier>()) { $0.formUnion($1.copies) }
            guard !reporters.isEmpty, let tree = PostHogInlineMask.ExtentTree(root: root, copies: index, reporterCopies: reporterCopies) else {
                return []
            }
            for reporter in reporters {
                redactExtent(regions[reporter.region].rect, in: tree, reporter: reporter.copies)
            }
            #if TESTING
                mask.extentStatsForTesting.count = reporters.count
            #endif
            return Set(reporters.map(\.region))
        }

        /// Masks what the extent reaches before the reporter, whichever view drew it: content as the walk does, colour
        /// black. Partly inside, the layer is covered over the extent, or replaced whole when it can't be. Later paint
        /// is kept.
        private mutating func redactExtent(_ rect: CGRect, in tree: PostHogInlineMask.ExtentTree, reporter: Set<ObjectIdentifier>) {
            let reached = tree.entries(reachedBy: rect, reporter: reporter)
            #if TESTING
                if !reached.ordered { mask.extentStatsForTesting.unordered += 1 }
            #endif
            let inside = rect.insetBy(dx: -PostHogInlineMask.extentTolerance, dy: -PostHogInlineMask.extentTolerance)
            // The end of a subtree a redaction hid.
            var skipUntil = 0
            for entryIndex in reached.indices where entryIndex >= skipUntil {
                let entry = tree.entries[entryIndex]
                let copy = entry.copy
                let source = index.source(of: copy)
                guard let treatment = extentTreatment(of: copy, source: source) else { continue }
                let kind: PostHogInlineMask.Kind
                switch treatment {
                case .backdrop:
                    if coverOrHide(backdrop: entry, under: rect) { skipUntil = entry.subtreeEnd }
                    continue
                case let .redact(redacted): kind = redacted
                case .color: kind = .container
                }
                let isPartial = !inside.contains(entry.frame)
                if isPartial, coverPartially(entry, under: rect, kind: kind) { continue }
                if maskWhole(entry, source: source, treatment: treatment, kind: kind, replacing: isPartial) { skipUntil = entry.subtreeEnd }
                #if TESTING
                    if isPartial { mask.extentStatsForTesting.replaced += 1 }
                #endif
            }
        }

        /// Masks the whole copy: black, or its content as the walk does. Whether its subtree was hidden with it.
        private mutating func maskWhole(_ entry: PostHogInlineMask.ExtentEntry, source: CALayer?, treatment: PostHogInlineMask.ExtentTreatment,
                                        kind: PostHogInlineMask.Kind, replacing: Bool) -> Bool
        {
            let copy = entry.copy
            guard case let .color(strippingFirst) = treatment else {
                let hid = redactOwnContent(copy, source: source, as: kind, replacingWhole: replacing)
                PostHogInlineMask.blackOut(copy, [.colors, .edges])
                return hid
            }
            visited.insert(ObjectIdentifier(copy))
            PostHogInlineMask.blackOut(copy, strippingFirst ? [.content, .colors, .edges] : [.colors, .edges])
            return false
        }

        /// nil when the copy shows nothing of its own. Copies already masked keep their redaction and only lose their
        /// colour; filters stay, since their redaction may have set them (an image's blur).
        private func extentTreatment(of copy: CALayer, source: CALayer?) -> PostHogInlineMask.ExtentTreatment? {
            let drawsColor = PostHogInlineMask.drawsColor(copy)
            if visited.contains(ObjectIdentifier(copy)) { return drawsColor ? .color(strippingFirst: false) : nil }
            if isBackdrop(copy) { return .backdrop }
            let kind = kind(of: copy, source: source)
            if PostHogInlineMask.drawsContent(copy) || kind.isTextInput { return .redact(kind) }
            return drawsColor ? .color(strippingFirst: true) : nil
        }

        /// Covers a backdrop over the extent rather than hiding it, which would take its sublayers outside the extent
        /// with it. Where no cover can be placed, hides it. Whether its subtree was hidden with it.
        private mutating func coverOrHide(backdrop entry: PostHogInlineMask.ExtentEntry, under rect: CGRect) -> Bool {
            guard !coverPartially(entry, under: rect, kind: .container) else { return false }
            entry.copy.isHidden = true
            visited.insert(ObjectIdentifier(entry.copy))
            return true
        }

        /// Covers the part of a partly reached copy under `rect`; false when only replacing it whole is safe.
        private func coverPartially(_ entry: PostHogInlineMask.ExtentEntry, under rect: CGRect, kind: PostHogInlineMask.Kind) -> Bool {
            guard kind.allowsCover, let toWindow = entry.coverable, PostHogInlineMask.layerAllowsCover(entry.copy) else { return false }
            if let hole = PostHogInlineMask.hole(rect, in: entry.copy, toWindow: toWindow, scale: scale) {
                PostHogInlineMask.cover(hole, in: entry.copy)
            }
            return true
        }
    }
#endif
