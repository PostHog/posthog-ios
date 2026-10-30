#if os(iOS) && canImport(Metal)
    import QuartzCore
    import UIKit

    extension PostHogInlineMask {
        /// A copy in an `ExtentTree`.
        struct ExtentEntry {
            let copy: CALayer
            /// Where the copy's own drawing can reach, in window coordinates: the bounding box when rotated, or Core
            /// Animation's conversion where the mirror couldn't place the copy (3D or flipped geometry, or through a
            /// portal). The whole window when that drawing can't be bounded.
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
            private let isBackdrop: (CALayer) -> Bool
            /// Where each reporter copy sits in paint order.
            private var reporters: [ObjectIdentifier: Int] = [:]
            /// Entries with a non-zero `zPosition`. It reorders only among siblings, since copies flatten their subtree.
            private var layered: [(index: Int, parent: Int?)] = []

            /// nil when the root lands nowhere finite, so no extent can be located in it.
            init?(root: CALayer, copies: CopyIndex, reporterCopies: Set<ObjectIdentifier>, isBackdrop: @escaping (CALayer) -> Bool) {
                self.root = root
                self.reporterCopies = reporterCopies
                self.isBackdrop = isBackdrop
                entries.reserveCapacity(copies.count)
                let frame = collect(root, parent: nil, isDrawn: true, copies: copies)
                guard !frame.isNull, frame.minX.isFinite, frame.minY.isFinite, frame.width.isFinite, frame.height.isFinite else { return nil }
            }

            /// Entries `rect` reaches in paint order, up to the reporter's own copy unless a `zPosition` can reorder
            /// them against it. `ordered` is false when it can, or when the reporter's copy isn't drawn here.
            func entries(reachedBy rect: CGRect, reporter copies: Set<ObjectIdentifier>) -> (indices: [Int], ordered: Bool) {
                // The last copy: a portal painted earlier can show the reporter while its source is still drawn.
                let reporterIndex = copies.compactMap { reporters[$0] }.max()
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

            /// Appends the layer and its subtree in pre-order, and returns the subtree's frame. Hidden copies are kept: a
            /// portal hides the source it shows, and what's masked there has to be masked in the portal's copy too.
            private mutating func collect(_ layer: CALayer, parent: Int?, isDrawn parentIsDrawn: Bool, copies: CopyIndex) -> CGRect {
                let isDrawn = parentIsDrawn && !layer.isHidden
                let placement = copies.placement(of: layer)
                let frame = reach(of: layer, copies: copies)
                let index = entries.count
                entries.append(ExtentEntry(copy: layer, frame: frame, coverable: placement.flatMap { $0.hasPlainSublayers ? $0.toWindow : nil },
                                           subtreeFrame: frame, subtreeEnd: index + 1))
                if isDrawn, reporterCopies.contains(ObjectIdentifier(layer)) { reporters[ObjectIdentifier(layer)] = index }
                if isDrawn, layer.zPosition != 0 { layered.append((index, parent)) }
                var subtreeFrame = frame
                for sublayer in layer.sublayers ?? [] {
                    subtreeFrame = subtreeFrame.union(collect(sublayer, parent: index, isDrawn: isDrawn, copies: copies))
                }
                entries[index].subtreeFrame = subtreeFrame
                entries[index].subtreeEnd = entries.count
                return subtreeFrame
            }

            /// Where the layer's own drawing can reach in the window: the whole window when filters can spread it.
            private func reach(of layer: CALayer, copies: CopyIndex) -> CGRect {
                // A backdrop's filters draw what's behind it inside its bounds.
                guard let local = PostHogInlineMask.drawnRect(layer) ?? (isBackdrop(layer) ? layer.bounds : nil) else { return root.bounds }
                return copies.windowFrame(of: layer, root: root, local: local)
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

            var redactsContent: Bool {
                if case .redact = self { return true }
                return false
            }
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

        /// Whether a sublayer can cover the copy's content: a mask would clip the cover, a blend could let the
        /// content through it, and a filter (a blur) could spread the content over it.
        static func layerAllowsCover(_ copy: CALayer) -> Bool {
            copy.mask == nil && copy.compositingFilter == nil && copy.filters == nil
        }

        /// The rect, in bounds coordinates, the copy's own drawing can reach: its bounds, or past them for a shape's
        /// path and stroke and contents that don't scale to the bounds. nil when filters can spread it anywhere.
        private static func drawnRect(_ copy: CALayer) -> CGRect? {
            let bounds = copy.bounds
            guard !copy.masksToBounds else { return bounds }
            guard copy.filters == nil else { return nil }
            var rect = bounds
            let gravity = copy.contentsGravity
            if let contents = copy.contents, gravity != .resize, gravity != .resizeAspect {
                rect = PostHogGPUMirrorCapture.contentsExtent(copy, contents: contents, gravity: gravity, bounds: bounds)
            }
            if let shape = copy as? CAShapeLayer, let path = shape.path {
                // A stroke reaches half its width past the path, and a miter join up to `miterLimit` half-widths; a
                // square cap stays within twice.
                let outset = shape.lineWidth / 2 * max(shape.miterLimit, 2)
                rect = rect.union(path.boundingBox.insetBy(dx: -outset, dy: -outset))
            }
            return rect
        }

        /// The part of `rect` (window coordinates) to cover in a copy placed by `toWindow`, in its bounds coordinates:
        /// out to whole output pixels at `scale`, and clipped to the bounds unless the content can spill past them.
        static func hole(_ rect: CGRect, in copy: CALayer, toWindow: CGAffineTransform, scale: CGFloat) -> CGRect? {
            guard abs(toWindow.a * toWindow.d - toWindow.b * toWindow.c) > .ulpOfOne, scale > 0 else { return nil }
            // A cover edge inside a pixel would leave that pixel to rounding.
            let pixels = rect.applying(CGAffineTransform(scaleX: scale, y: scale)).integral
            let local = pixels.applying(CGAffineTransform(scaleX: 1 / scale, y: 1 / scale).concatenating(toWindow.inverted()))
            let hole = local.intersection(drawnRect(copy) ?? .infinite)
            return hole.isNull || hole.isEmpty ? nil : hole
        }

        /// A reporter left to the rect pass can't mask what a portal shows elsewhere of a source it covers, so each such
        /// portal is masked whole.
        static func wholePortals(coveredBy rects: [CGRect], of sources: [PostHogPortalSource]) -> [PostHogReplayIntegration.MaskedRegion] {
            guard !rects.isEmpty else { return [] }
            return sources.compactMap { source in
                guard let elsewhere = source.elsewhere else { return nil }
                let sourceRect = source.view.toPresentationRect(source.view.window)
                guard rects.contains(where: { $0.intersects(sourceRect) }) else { return nil }
                return PostHogReplayIntegration.MaskedRegion(source.view, rect: elsewhere.portalRect, inline: .rectOnly)
            }
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
            guard !reporters.isEmpty,
                  let tree = PostHogInlineMask.ExtentTree(root: root, copies: index, reporterCopies: reporterCopies, isBackdrop: isBackdrop)
            else { return [] }
            for reporter in reporters {
                redactExtent(regions[reporter.region].rect, in: tree, reporter: reporter.copies)
            }
            #if TESTING
                mask.extentStatsForTesting.count = reporters.count
            #endif
            return Set(reporters.map(\.region))
        }

        /// Masks what the extent reaches before the reporter, whichever view drew it: content as the walk does, and
        /// colour black. Partly inside, the layer is covered over the extent, or replaced whole when it can't be. Later
        /// paint is kept. Each copy's other copies, where a portal shows its source again, are masked the same way.
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
                let others = source.map { index.copies(of: $0).filter { $0 !== copy } } ?? []
                let isPartial = !inside.contains(entry.frame)
                let kind: PostHogInlineMask.Kind
                switch treatment {
                case .backdrop:
                    if maskBackdrop(entry, under: rect, others: others) { skipUntil = entry.subtreeEnd }
                    continue
                case let .redact(redacted): kind = redacted
                case .color: kind = .container
                }
                if isPartial, coverPartially(entry, under: rect, kind: kind, others: others) { continue }
                if maskWhole(copy, others: others, treatment: treatment, kind: kind, replacing: isPartial) {
                    skipUntil = entry.subtreeEnd
                }
                #if TESTING
                    if isPartial { mask.extentStatsForTesting.replaced += 1 }
                #endif
            }
        }

        /// Masks a backdrop, which the walk's redaction doesn't: covered over the extent, or hidden. Whether the copy's
        /// subtree was hidden.
        private mutating func maskBackdrop(_ entry: PostHogInlineMask.ExtentEntry, under rect: CGRect, others: [CALayer]) -> Bool {
            guard !coverPartially(entry, under: rect, kind: .container, others: others) else { return false }
            // Hidden only where no cover can be placed: hiding takes its sublayers, outside the extent too.
            ([entry.copy] + others).forEach { hide($0) }
            return true
        }

        /// Masks the whole copy and each other copy of its source not masked yet. Whether `copy`'s subtree was hidden.
        private mutating func maskWhole(_ copy: CALayer, others: [CALayer], treatment: PostHogInlineMask.ExtentTreatment,
                                        kind: PostHogInlineMask.Kind, replacing: Bool) -> Bool
        {
            let source = index.source(of: copy)
            for other in others where !visited.contains(ObjectIdentifier(other)) || !treatment.redactsContent {
                _ = maskWhole(other, source: source, treatment: treatment, kind: kind, replacing: replacing)
            }
            return maskWhole(copy, source: source, treatment: treatment, kind: kind, replacing: replacing)
        }

        /// Masks the whole copy: black, or its content as the walk does. Whether its subtree was hidden with it.
        private mutating func maskWhole(_ copy: CALayer, source: CALayer?, treatment: PostHogInlineMask.ExtentTreatment,
                                        kind: PostHogInlineMask.Kind, replacing: Bool) -> Bool
        {
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
        /// colour.
        private func extentTreatment(of copy: CALayer, source: CALayer?) -> PostHogInlineMask.ExtentTreatment? {
            let drawsColor = PostHogInlineMask.drawsColor(copy)
            if visited.contains(ObjectIdentifier(copy)) {
                return drawsColor ? .color(strippingFirst: false) : nil
            }
            if isBackdrop(copy) { return .backdrop }
            let kind = kind(of: copy, source: source)
            if PostHogInlineMask.drawsContent(copy) || kind.isTextInput { return .redact(kind) }
            return drawsColor ? .color(strippingFirst: true) : nil
        }

        /// Covers the part of a partly reached copy under `rect`, and the same part of its other copies; false when only
        /// replacing it whole is safe.
        private mutating func coverPartially(_ entry: PostHogInlineMask.ExtentEntry, under rect: CGRect, kind: PostHogInlineMask.Kind,
                                             others: [CALayer]) -> Bool
        {
            guard kind.allowsCover, let toWindow = entry.coverable, PostHogInlineMask.layerAllowsCover(entry.copy) else { return false }
            apply(PostHogInlineMask.hole(rect, in: entry.copy, toWindow: toWindow, scale: scale), to: entry.copy, others: others)
            return true
        }

        /// Covers the hole in `copy` and in each other copy of its source: a hole in bounds coordinates is the same
        /// part of the source in every copy. A copy whose bounds or sublayer space differs, or that can't take a cover,
        /// is blacked out whole.
        private mutating func apply(_ hole: CGRect?, to copy: CALayer, others: [CALayer]) {
            guard let hole else { return }
            PostHogInlineMask.cover(hole, in: copy)
            for other in others {
                if other.bounds == copy.bounds, CATransform3DIsIdentity(other.sublayerTransform), !other.isGeometryFlipped,
                   PostHogInlineMask.layerAllowsCover(other)
                {
                    PostHogInlineMask.cover(hole, in: other)
                } else {
                    visited.insert(ObjectIdentifier(other))
                    PostHogInlineMask.blackOut(other, [.content, .fill, .colors, .edges])
                }
            }
        }

        private mutating func hide(_ copy: CALayer) {
            copy.isHidden = true
            visited.insert(ObjectIdentifier(copy))
        }
    }
#endif
