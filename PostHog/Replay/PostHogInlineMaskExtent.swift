#if os(iOS) && canImport(Metal)
    import QuartzCore
    import UIKit

    extension PostHogInlineMask {
        /// A copy in an `ExtentHost`.
        struct ExtentEntry {
            let copy: CALayer
            let parent: Int?
            /// Window coordinates: the bounding box when rotated, or Core Animation's conversion where the mirror
            /// couldn't place the copy (3D or flipped geometry, or through a portal).
            let frame: CGRect
            /// Bounds-to-window map, when affine and sublayers sit unchanged in bounds, so a cover can be placed.
            let coverable: CGAffineTransform?
            /// `frame` with every descendant's: a zero-size layer (a portal source) still reaches what it holds.
            var subtreeFrame: CGRect
        }

        /// A SwiftUI host copy flattened in paint order, with each copy's window place. Masked pixels are painted
        /// before their reporter's overlay; UI above them after.
        struct ExtentHost {
            private(set) var entries: [ExtentEntry] = []
            private var indexByCopy: [ObjectIdentifier: Int] = [:]
            /// Entries with a non-zero `zPosition`, which reorders them against their siblings.
            private var layered: [Int] = []

            /// nil when the host's copy isn't under `root` or lands nowhere finite, so no extent can be located in it.
            init?(_ hostCopy: CALayer, root: CALayer, copies: CopyIndex, skip: (CALayer) -> Bool) {
                guard hostCopy.isInside(root) else { return nil }
                collect(hostCopy, parent: nil, root: root, copies: copies, skip: skip)
                let frame = entries[0].frame
                guard !frame.isNull, frame.minX.isFinite, frame.minY.isFinite, frame.width.isFinite, frame.height.isFinite else { return nil }
            }

            /// Entries `rect` reaches in paint order, up to the reporter's own copy unless a `zPosition` reorders them.
            /// `ordered` is false when it did, or when the reporter has no copy here.
            func entries(reachedBy rect: CGRect, reporter: Set<ObjectIdentifier>) -> (indices: [Int], ordered: Bool) {
                let reporterIndex = reporter.compactMap { indexByCopy[$0] }.min()
                let reordered = layered.contains { entries[$0].subtreeFrame.intersects(rect) }
                let end = reordered ? entries.count : reporterIndex ?? entries.count
                let indices = (0 ..< end).filter { entries[$0].frame.intersects(rect) }
                return (indices, reporterIndex != nil && !reordered)
            }

            func hasAncestor(_ index: Int, in indices: Set<Int>) -> Bool {
                var current = entries[index].parent
                while let parent = current {
                    if indices.contains(parent) { return true }
                    current = entries[parent].parent
                }
                return false
            }

            private mutating func collect(_ layer: CALayer, parent: Int?, root: CALayer, copies: CopyIndex, skip: (CALayer) -> Bool) {
                let placement = copies.placement(of: layer)
                let frame = placement.map { layer.bounds.applying($0.toWindow) } ?? layer.convert(layer.bounds, to: root)
                let index = entries.count
                entries.append(ExtentEntry(copy: layer, parent: parent, frame: frame,
                                           coverable: placement.flatMap { $0.hasPlainSublayers ? $0.toWindow : nil }, subtreeFrame: frame))
                indexByCopy[ObjectIdentifier(layer)] = index
                if layer.zPosition != 0 { layered.append(index) }
                for sublayer in layer.sublayers ?? [] where !sublayer.isHidden && !skip(sublayer) {
                    collect(sublayer, parent: index, root: root, copies: copies, skip: skip)
                }
                if let parent { entries[parent].subtreeFrame = entries[parent].subtreeFrame.union(entries[index].subtreeFrame) }
            }
        }

        /// Rounding slack for extent containment, so edge-aligned copies count as inside.
        fileprivate static let extentTolerance: CGFloat = 0.5
        fileprivate static let coverColor = UIColor.black.cgColor

        /// The SwiftUI host a reporter's masked content is drawn in: its nearest `_UIHostingView`, or a List row's
        /// `CellHostingView`. nil outside SwiftUI.
        func extentHost(of reporter: UIView) -> UIView? {
            var current = reporter.superview
            while let view = current {
                let key = ObjectIdentifier(type(of: view))
                let isHost = hostingClasses[key] ?? Self.isHostingView(type(of: view))
                hostingClasses[key] = isHost
                if isHost { return view }
                current = view.superview
            }
            return nil
        }

        // Matched by name: SwiftUI's hosting views are private generic classes.
        private static func isHostingView(_ cls: AnyClass) -> Bool {
            var current: AnyClass? = cls
            while let next = current, next != UIView.self {
                let name = NSStringFromClass(next)
                if name.hasPrefix("_TtGC7SwiftUI") || name.hasPrefix("_TtC7SwiftUI"), name.contains("HostingView") { return true }
                current = class_getSuperclass(next)
            }
            return false
        }

        /// Whether the copy draws anything of its own besides chrome (background, border, corners, gradient colours).
        static func drawsContent(_ copy: CALayer) -> Bool {
            copy.contents != nil || (copy as? CAShapeLayer)?.path != nil || (copy as? CATextLayer)?.string != nil
                // A mask can give a plain background a glyph's shape.
                || copy.mask != nil
        }

        /// Whether a sublayer can cover the copy's content: a mask would clip the cover, and a blend could let the
        /// content through it.
        static func layerAllowsCover(_ copy: CALayer) -> Bool {
            copy.mask == nil && copy.compositingFilter == nil
        }

        /// The part of `rect` (window coordinates) to cover in a copy placed by `toWindow`, in its bounds coordinates:
        /// clipped to its bounds unless its content can spill past them.
        static func hole(_ rect: CGRect, in copy: CALayer, toWindow: CGAffineTransform) -> CGRect? {
            guard abs(toWindow.a * toWindow.d - toWindow.b * toWindow.c) > .ulpOfOne else { return nil }
            let local = rect.applying(toWindow.inverted())
            let spills = !copy.masksToBounds && (copy.filters != nil || copy.contents != nil
                && copy.contentsGravity != .resize && copy.contentsGravity != .resizeAspect)
            let hole = spills ? local : local.intersection(copy.bounds)
            return hole.isNull || hole.isEmpty ? nil : hole
        }

        /// Black over `hole`, painted over the copy's own content and under its sublayers.
        static func cover(_ hole: CGRect, in copy: CALayer) {
            let cover = CALayer()
            cover.frame = hole
            cover.backgroundColor = coverColor
            copy.insertSublayer(cover, at: 0)
            // A shadow is made from the content, and can fall outside the hole.
            if copy.shadowOpacity != 0 { copy.shadowOpacity = 0 }
        }
    }

    extension PostHogInlineMask.Pass {
        private struct Reporter {
            let region: Int
            let copies: Set<ObjectIdentifier>
        }

        /// Masks the content under each reporter region's extent in its SwiftUI host, and returns the indices of the
        /// regions it covered. A reporter outside a host, or with a host copy it can't place, keeps its rect.
        mutating func redactExtents(_ regions: [PostHogReplayIntegration.MaskedRegion]) -> Set<Int> {
            #if TESTING
                guard mask.isExtentEnabledForTesting else { return [] }
            #endif
            guard let root else { return [] }
            // By host copy, so each is flattened once however many reporters it holds.
            var hosts: [(copy: CALayer, reporters: [Reporter])] = []
            var hostPositions: [ObjectIdentifier: Int] = [:]
            var unplaced: Set<Int> = []
            for (regionIndex, region) in regions.enumerated() where region.inline == .extent {
                guard let view = region.object as? UIView, let host = mask.extentHost(of: view) else { continue }
                let hostCopies = index.copies(of: host.layer)
                guard !hostCopies.isEmpty else {
                    unplaced.insert(regionIndex)
                    continue
                }
                let reporter = Reporter(region: regionIndex, copies: Set(index.copies(of: view.layer).map(ObjectIdentifier.init)))
                for copy in hostCopies {
                    if let position = hostPositions[ObjectIdentifier(copy)] {
                        hosts[position].reporters.append(reporter)
                    } else {
                        hostPositions[ObjectIdentifier(copy)] = hosts.count
                        hosts.append((copy, [reporter]))
                    }
                }
            }
            var covered: Set<Int> = []
            for (hostCopy, reporters) in hosts {
                let done = visited
                guard let host = PostHogInlineMask.ExtentHost(hostCopy, root: root, copies: index, skip: { done.contains(ObjectIdentifier($0)) }) else {
                    unplaced.formUnion(reporters.map(\.region))
                    continue
                }
                var dropped: Set<Int> = []
                for reporter in reporters {
                    redactExtent(regions[reporter.region].rect, in: host, reporter: reporter.copies, dropped: &dropped)
                    covered.insert(reporter.region)
                }
            }
            let inline = covered.subtracting(unplaced)
            #if TESTING
                mask.extentStatsForTesting.count = inline.count
            #endif
            return inline
        }

        /// Inside the extent, content is masked as the walk masks it; partly inside, it's covered over the extent, or
        /// replaced whole when it can't be. Chrome is kept, and so is anything painted after the reporter.
        private mutating func redactExtent(_ rect: CGRect, in host: PostHogInlineMask.ExtentHost, reporter: Set<ObjectIdentifier>,
                                           dropped: inout Set<Int>)
        {
            let reached = host.entries(reachedBy: rect, reporter: reporter)
            #if TESTING
                if !reached.ordered { mask.extentStatsForTesting.unordered += 1 }
            #endif
            let inside = rect.insetBy(dx: -PostHogInlineMask.extentTolerance, dy: -PostHogInlineMask.extentTolerance)
            for entryIndex in reached.indices {
                let entry = host.entries[entryIndex]
                let copy = entry.copy
                guard !visited.contains(ObjectIdentifier(copy)), !host.hasAncestor(entryIndex, in: dropped) else { continue }
                let source = index.source(of: copy)
                let kind = kind(of: copy, source: source)
                let isBackdrop = isBackdrop(copy)
                guard isBackdrop || PostHogInlineMask.drawsContent(copy) || kind.isTextInput else { continue }
                let isPartial = !isBackdrop && !inside.contains(entry.frame)
                if isPartial, coverPartially(entry, under: rect, kind: kind) { continue }
                if redactOwnContent(copy, source: source, as: kind, replacingWhole: isPartial) { dropped.insert(entryIndex) }
                #if TESTING
                    if isPartial { mask.extentStatsForTesting.replaced += 1 }
                #endif
            }
        }

        /// Covers the part of a partly reached copy under `rect`; false when only replacing it whole is safe.
        private func coverPartially(_ entry: PostHogInlineMask.ExtentEntry, under rect: CGRect, kind: PostHogInlineMask.Kind) -> Bool {
            guard kind.allowsCover, let toWindow = entry.coverable, PostHogInlineMask.layerAllowsCover(entry.copy) else { return false }
            if let hole = PostHogInlineMask.hole(rect, in: entry.copy, toWindow: toWindow) {
                PostHogInlineMask.cover(hole, in: entry.copy)
            }
            return true
        }
    }
#endif
