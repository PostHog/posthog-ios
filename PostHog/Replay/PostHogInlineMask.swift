#if os(iOS) && canImport(Metal)
    import QuartzCore
    import UIKit

    /// Masks a GPU capture's mirror in place, between the mask walk and `freeze`: text as `*`, drawn off main (bars
    /// until drawn), images blurred, any other content black. `postHogMask()` reporters, whole-portal regions and
    /// objects with no copy go to the rect pass. Main thread.
    final class PostHogInlineMask {
        /// How copies of a class are redacted, before the instance it applies to is known.
        enum Tag {
            case label, textField, textView, unreadableText, image, opaque, container
        }

        /// How a masked copy's content is redacted, chosen from its source.
        enum Kind {
            /// Text read from the view, drawn as `*` in its own style and place.
            case label(UILabel), textField(UITextField), textView(UITextView)
            /// Text that can't be read (SwiftUI, React Native): rows of `*` sized from the bounds alone, in the
            /// traits' label colour.
            case unreadableText(UITraitCollection)
            /// Blurred on the GPU, keeping the shared contents; black when the blur isn't verified.
            case image
            /// Filled black, with nothing below it drawn: web views, sandboxed views, controls.
            case opaque
            /// Chrome (geometry, background, border, corners, opacity, gradients) kept, content filled black.
            case container

            /// A tag whose instance doesn't match it (it can't, short of a class lying about itself) is filled black.
            fileprivate init(_ tag: Tag, view: UIView?, layer: CALayer) {
                switch tag {
                case .label: self = (view as? UILabel).map(Kind.label) ?? .opaque
                case .textField: self = (view as? UITextField).map(Kind.textField) ?? .opaque
                case .textView: self = (view as? UITextView).map(Kind.textView) ?? .opaque
                case .unreadableText:
                    self = .unreadableText((view ?? PostHogGlassStandIn.nearestView(of: layer))?.traitCollection ?? UITraitCollection.current)
                case .image: self = .image
                case .opaque: self = .opaque
                case .container: self = .container
                }
            }

            /// Kinds whose descendants are dropped: a text input's caret and selection are contentless layers whose
            /// positions give away glyph widths, and the other kinds replace their whole subtree.
            var dropsDescendants: Bool {
                switch self {
                case .image, .container: return false
                case .label, .textField, .textView, .unreadableText, .opaque: return true
                }
            }

            /// Images keep their shared contents for the blur; everything else loses them.
            var keepsContents: Bool {
                if case .image = self { return true }
                return false
            }

            /// The cache key of this kind's `*` bitmap; nil for kinds without text.
            fileprivate func textSignature(size: CGSize, scale: CGFloat) -> TextSignature? {
                switch self {
                case let .label(label): return TextSignature(label, size: size, scale: scale)
                case let .textField(field): return TextSignature(field, size: size, scale: scale)
                case let .textView(textView): return TextSignature(textView, size: size, scale: scale)
                case let .unreadableText(traits): return TextSignature(rowsOf: size, scale: scale, traits: traits)
                case .image, .opaque, .container: return nil
                }
            }

            /// The main-thread read the draw queue draws from; nil when there's nothing to draw.
            fileprivate func readText(size: CGSize) -> TextSource? {
                switch self {
                case let .label(label): return TextSource(label, size: size)
                case let .textField(field): return TextSource(field, size: size)
                case let .textView(textView): return TextSource(textView, size: size)
                case let .unreadableText(traits): return TextSource(rowsOf: size, traits: traits)
                case .image, .opaque, .container: return nil
                }
            }
        }

        /// Every copy a mirror made, with its source, in build order. One source can have several copies: where it
        /// sits and under each portal that shows it.
        struct CopyMap {
            private var pairs: [(source: CALayer, copy: CALayer)] = []

            var count: Int { pairs.count }

            mutating func reserve(_ capacity: Int) {
                pairs.reserveCapacity(capacity)
            }

            mutating func record(_ copy: CALayer, of source: CALayer) {
                pairs.append((source, copy))
            }

            fileprivate func index() -> CopyIndex {
                var index = CopyIndex()
                index.bySource.reserveCapacity(pairs.count)
                index.sources.reserveCapacity(pairs.count)
                for (source, copy) in pairs {
                    index.bySource[ObjectIdentifier(source), default: []].append(copy)
                    index.sources[ObjectIdentifier(copy)] = source
                }
                return index
            }
        }

        fileprivate struct CopyIndex {
            var bySource: [ObjectIdentifier: [CALayer]] = [:]
            var sources: [ObjectIdentifier: CALayer] = [:]

            func copies(of source: CALayer) -> [CALayer] {
                bySource[ObjectIdentifier(source)] ?? []
            }

            func source(of copy: CALayer) -> CALayer? {
                sources[ObjectIdentifier(copy)]
            }
        }

        enum ImageBlur {
            /// Not checked yet: images are filled black until a check passes.
            case unchecked
            case checking
            case verified
            /// `CARenderer` left detail through the blur, or the check couldn't run: black for the life of the process.
            case failed
        }

        /// Images blur only once a render through the blur has been checked to lose its detail (see
        /// `PostHogGPUMirrorCapture.Target.checkImageBlur`). A failure sticks.
        private(set) var imageBlur = ImageBlur.unchecked
        /// Main-thread time per capture for reading the text of views whose `*` isn't drawn yet. Past it, text keeps its
        /// bars and is read by a later capture.
        var textBudget: CFTimeInterval = 0.001

        private var tags: [ClassPair: Tag] = [:]

        /// `*` bitmaps by signature, drawn on `drawQueue`; guarded by `lock`, as is `drawnOrder`, oldest first.
        private var entries: [TextSignature: TextEntry] = [:]
        private var drawnOrder: [TextSignature] = []
        private var cacheBytes = 0
        private let lock = NSLock()
        private let drawQueue = DispatchQueue(label: "com.posthog.PostHogInlineMask.text", qos: .utility)

        private enum TextEntry {
            case drawing
            /// Nothing to draw: the view has no text.
            case empty
            case drawn(CGImage)
        }

        private struct ClassPair: Hashable {
            let view: ObjectIdentifier?
            let layer: ObjectIdentifier
        }

        private static let maxCacheBytes = 16 * 1024 * 1024
        private static let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        /// Cells across an image's long side that survive the blur.
        private static let blurCellsAcross: CGFloat = 6
        private static let blurFilterType = "gaussianBlur"
        private static let barHeightFraction: CGFloat = 0.55
        private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        #if TESTING
            /// Replaces the colour masked text is drawn in, so a test can tell `*` from the source's own pixels.
            static var textColorForTesting: UIColor?

            private var drawsForTesting = 0
            private var drawsOnMainForTesting = 0
            private(set) var textCacheHitsForTesting = 0
            private(set) var textBarsForTesting = 0
            private(set) var lastInlineRegionCountForTesting = 0
            /// Off leaves every region to the rect pass.
            var isEnabledForTesting = true

            var textDrawsForTesting: Int {
                lock.withLock { drawsForTesting }
            }

            var textDrawsOnMainForTesting: Int {
                lock.withLock { drawsOnMainForTesting }
            }

            /// Returns once every `*` bitmap queued so far is drawn.
            func waitForTextDrawsForTesting() {
                drawQueue.sync {}
            }

            func clearCacheForTesting() {
                waitForTextDrawsForTesting()
                purgeTextCache()
            }
        #endif

        /// Any thread. Frees the drawn `*` bitmaps; text being drawn stays queued.
        func purgeTextCache() {
            let freed: [TextSignature: TextEntry] = lock.withLock {
                let all = entries
                entries = entries.filter { if case .drawing = $0.value { return true } else { return false } }
                drawnOrder.removeAll()
                cacheBytes = 0
                return all
            }
            // Released here, outside the lock.
            withExtendedLifetime(freed) {}
        }

        /// Main thread. Whether a blur check should start now; images stay black until one passes.
        func beginImageBlurCheck() -> Bool {
            guard imageBlur == .unchecked else { return false }
            imageBlur = .checking
            return true
        }

        /// Main thread.
        func recordImageBlurCheck(passed: Bool) {
            if !passed {
                imageBlur = .failed
            } else if imageBlur != .failed {
                imageBlur = .verified
            }
        }

        /// Redacts the regions' copies it can and returns the regions left for the rect pass, in order.
        func mask(_ regions: [PostHogReplayIntegration.MaskedRegion], in frame: PostHogGPUMirrorCapture.Frame,
                  tag: (_ viewClass: AnyClass?, _ layerClass: AnyClass) -> Tag, isBackdrop: (CALayer) -> Bool) -> [PostHogReplayIntegration.MaskedRegion]
        {
            #if TESTING
                lastInlineRegionCountForTesting = 0
                guard isEnabledForTesting else { return regions }
            #endif
            guard !regions.isEmpty else { return regions }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            let remaining = withoutActuallyEscaping(tag) { tag in
                withoutActuallyEscaping(isBackdrop) { isBackdrop in
                    var pass = Pass(mask: self, index: frame.copies.index(), portals: PortalIndex(frame.portalSources), scale: frame.scale, tag: tag,
                                    isBackdrop: isBackdrop)
                    var handled: [ObjectIdentifier: Bool] = [:]
                    return regions.filter { region in
                        guard region.inlineEligible else { return true }
                        let owns = handled[region.owner] ?? pass.redact(region.object)
                        handled[region.owner] = owns
                        return !owns
                    }
                }
            }
            #if TESTING
                lastInlineRegionCountForTesting = regions.count - remaining.count
            #endif
            return remaining
        }

        private func kind(of layer: CALayer, tag: (AnyClass?, AnyClass) -> Tag) -> Kind {
            let view = (layer.delegate as? UIView).flatMap { $0.layer === layer ? $0 : nil }
            let viewClass: AnyClass? = view.map { type(of: $0) }
            let layerClass: AnyClass = type(of: layer)
            let pair = ClassPair(view: viewClass.map(ObjectIdentifier.init), layer: ObjectIdentifier(layerClass))
            let known = tags[pair] ?? tag(viewClass, layerClass)
            tags[pair] = known
            return Kind(known, view: view, layer: layer)
        }

        // MARK: - One capture

        /// The frame's portal sources, each with the layers above it, so finding the ones under a masked object costs a
        /// set lookup per source.
        private struct PortalIndex {
            private var sources: [(layer: CALayer, ancestors: Set<ObjectIdentifier>)] = []

            init(_ portalSources: [PostHogPortalSource]) {
                for source in portalSources {
                    var ancestors: Set<ObjectIdentifier> = []
                    var current = source.view.layer.superlayer
                    while let next = current {
                        ancestors.insert(ObjectIdentifier(next))
                        current = next.superlayer
                    }
                    sources.append((source.view.layer, ancestors))
                }
            }

            func sources(under layer: CALayer) -> [CALayer] {
                let id = ObjectIdentifier(layer)
                return sources.filter { $0.ancestors.contains(id) }.map(\.layer)
            }
        }

        private struct Pass {
            let mask: PostHogInlineMask
            let index: CopyIndex
            let portals: PortalIndex
            let scale: CGFloat
            let tag: (AnyClass?, AnyClass) -> Tag
            let isBackdrop: (CALayer) -> Bool
            var visited: Set<ObjectIdentifier> = []
            var signatures: [ObjectIdentifier: TextSignature?] = [:]
            var spent: CFTimeInterval = 0

            /// Redacts every copy of `object`, and every copy of a portal source under it (a portal draws those
            /// outside the object's own copies). False when it has no copy, so its pixels aren't the mirror's to mask.
            mutating func redact(_ object: AnyObject) -> Bool {
                guard let layer = (object as? UIView)?.layer ?? (object as? CALayer) else { return false }
                let own = index.copies(of: layer)
                guard !own.isEmpty else { return false }
                let kind = mask.kind(of: layer, tag: tag)
                for copy in own {
                    redactTree(copy, source: layer, kind: kind)
                }
                for source in portals.sources(under: layer) {
                    for copy in index.copies(of: source) {
                        if kind.dropsDescendants {
                            copy.isHidden = true
                        } else {
                            redactTree(copy, source: source, kind: nil)
                        }
                    }
                }
                return true
            }

            private mutating func redactTree(_ copy: CALayer, source: CALayer?, kind known: Kind?) {
                guard visited.insert(ObjectIdentifier(copy)).inserted else { return }
                let kind = known ?? source.map { mask.kind(of: $0, tag: tag) } ?? .container
                if kind.dropsDescendants {
                    // Before the redaction, which can add bars of its own.
                    copy.sublayers?.forEach { $0.isHidden = true }
                }
                redactCopy(copy, source: source, as: kind)
                guard !kind.dropsDescendants else { return }
                for sublayer in copy.sublayers ?? [] {
                    redactTree(sublayer, source: index.source(of: sublayer), kind: nil)
                }
            }

            /// Redacts one copy's own content in place.
            private mutating func redactCopy(_ copy: CALayer, source: CALayer?, as kind: Kind) {
                if isBackdrop(copy) {
                    // A backdrop draws what's behind it, and has no chrome of its own.
                    copy.isHidden = true
                    return
                }
                let hadContent = PostHogInlineMask.stripContent(copy, keepingContents: kind.keepsContents)
                switch kind {
                case .container:
                    if hadContent { PostHogInlineMask.fillBlack(copy) }
                case .opaque:
                    PostHogInlineMask.fillBlack(copy)
                case .image:
                    redactImage(copy, hadContent: hadContent)
                case .unreadableText:
                    // Rows only where the layer drew something, so nothing reads as text that wasn't there.
                    if hadContent { setText(copy, source: source, kind: kind, fallbackToBlack: true) }
                case .label, .textField, .textView:
                    setText(copy, source: source, kind: kind, fallbackToBlack: false)
                }
            }

            /// The blur draws the shared contents `stripContent` kept, or black replaces them.
            private func redactImage(_ copy: CALayer, hadContent: Bool) {
                guard hadContent else { return }
                if mask.imageBlur != .verified || !PostHogInlineMask.applyBlur(to: copy) {
                    PostHogInlineMask.fillBlack(copy)
                }
            }

            /// A drawn `*` bitmap costs a lookup. Otherwise the text shows as glyph-free bars this frame and, within the
            /// budget, is read on main and drawn on the draw queue for a later capture.
            private mutating func setText(_ copy: CALayer, source: CALayer?, kind: Kind, fallbackToBlack: Bool) {
                let key = source.map(ObjectIdentifier.init) ?? ObjectIdentifier(copy)
                let size = copy.bounds.size
                let known = signatures[key] ?? kind.textSignature(size: size, scale: scale)
                signatures[key] = known
                guard let signature = known else { return }
                switch mask.entry(for: signature) {
                case let .drawn(image)?:
                    PostHogInlineMask.setContents(image, on: copy, scale: scale)
                    return
                case .empty?:
                    if fallbackToBlack { PostHogInlineMask.fillBlack(copy) }
                    return
                case .drawing?:
                    break
                case nil:
                    guard spent < mask.textBudget else { break }
                    let start = CACurrentMediaTime()
                    let text = kind.readText(size: size)
                    spent += CACurrentMediaTime() - start
                    guard let text else {
                        mask.recordEmpty(signature)
                        if fallbackToBlack { PostHogInlineMask.fillBlack(copy) }
                        return
                    }
                    mask.enqueue(text, for: signature, scale: scale)
                }
                PostHogInlineMask.addBars(signature, to: copy)
                #if TESTING
                    mask.textBarsForTesting += 1
                #endif
            }
        }

        // MARK: - Copy redaction

        /// Removes everything the copy draws besides chrome: contents (unless kept for the blur), shape paths, text,
        /// shadows, filters, compositing and masks (a mask can be glyph-shaped). Whether it drew content of its own.
        private static func stripContent(_ copy: CALayer, keepingContents: Bool) -> Bool {
            var hadContent = copy.contents != nil
            if hadContent, !keepingContents { copy.contents = nil }
            if let shape = copy as? CAShapeLayer, shape.path != nil {
                shape.path = nil
                hadContent = true
            }
            if let text = copy as? CATextLayer, text.string != nil {
                text.string = nil
                hadContent = true
            }
            if copy.shadowOpacity != 0 { copy.shadowOpacity = 0 }
            if copy.filters != nil { copy.filters = nil }
            if copy.backgroundFilters != nil { copy.backgroundFilters = nil }
            if copy.compositingFilter != nil { copy.compositingFilter = nil }
            if copy.mask != nil { copy.mask = nil }
            return hadContent
        }

        private static func fillBlack(_ copy: CALayer) {
            copy.contents = nil
            copy.backgroundColor = UIColor.black.cgColor
        }

        private static func setContents(_ image: CGImage, on copy: CALayer, scale: CGFloat) {
            copy.contents = image
            copy.contentsGravity = .resize
            copy.contentsScale = scale
            copy.contentsRect = unitRect
            copy.contentsCenter = unitRect
            for key in PostHogGPUMirrorCapture.contentsKeys {
                key.reset(on: copy)
            }
        }

        /// Blurs the copy's shared contents to about `blurCellsAcross` cells over its long side, clipped to its
        /// bounds. False when the filter can't be made.
        static func applyBlur(to copy: CALayer) -> Bool {
            let bounds = copy.bounds
            guard let filterClass = NSClassFromString("CAFilter") as AnyObject?,
                  let filter = filterClass.perform(NSSelectorFromString("filterWithType:"), with: blurFilterType)?.takeUnretainedValue() as? NSObject
            else { return false }
            filter.setValue(max(bounds.width, bounds.height) / blurCellsAcross, forKey: "inputRadius")
            // Without it the edges fade towards transparent instead of keeping the image's colours.
            filter.setValue(true, forKey: "inputNormalizeEdges")
            copy.filters = [filter]
            copy.masksToBounds = true
            return true
        }

        // MARK: - Text cache

        private func entry(for signature: TextSignature) -> TextEntry? {
            let entry = lock.withLock { entries[signature] }
            #if TESTING
                if case .drawn? = entry { textCacheHitsForTesting += 1 }
            #endif
            return entry
        }

        private func recordEmpty(_ signature: TextSignature) {
            lock.withLock { entries[signature] = .empty }
        }

        private func enqueue(_ text: TextSource, for signature: TextSignature, scale: CGFloat) {
            lock.withLock { entries[signature] = .drawing }
            drawQueue.async { [weak self] in
                guard let self else { return }
                let image = Self.draw(text, scale: scale)
                // Released after the lock, outside it.
                var evicted: [CGImage] = []
                self.lock.withLock {
                    #if TESTING
                        self.drawsForTesting += 1
                        if Thread.isMainThread { self.drawsOnMainForTesting += 1 }
                    #endif
                    guard let image else {
                        self.entries[signature] = nil
                        return
                    }
                    let bytes = image.bytesPerRow * image.height
                    while self.cacheBytes + bytes > Self.maxCacheBytes, !self.drawnOrder.isEmpty {
                        let oldest = self.drawnOrder.removeFirst()
                        if case let .drawn(old)? = self.entries.removeValue(forKey: oldest) {
                            self.cacheBytes -= old.bytesPerRow * old.height
                            evicted.append(old)
                        }
                    }
                    self.entries[signature] = .drawn(image)
                    self.drawnOrder.append(signature)
                    self.cacheBytes += bytes
                }
                evicted.removeAll()
            }
        }

        // MARK: - Text

        /// The colour masked text is drawn in.
        fileprivate static func starColor(_ color: UIColor) -> UIColor {
            #if TESTING
                return textColorForTesting ?? color
            #else
                return color
            #endif
        }

        /// Non-whitespace becomes `*` (rrweb's `maskText`), or every character does (rrweb's `maskInputValue`).
        fileprivate static func masked(_ text: String, keepingWhitespace: Bool) -> String {
            keepingWhitespace ? String(text.map { $0.isWhitespace ? $0 : "*" }) : text.mask()
        }

        /// `masked(_:keepingWhitespace:)` for each run, keeping its attributes but not attachments, which draw images, or
        /// shadows. So the masked text wraps or clips as the view would.
        fileprivate static func masked(_ text: NSAttributedString, keepingWhitespace: Bool, lineBreakMode: NSLineBreakMode) -> NSAttributedString {
            let result = NSMutableAttributedString()
            text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
                var kept = attributes
                kept[.attachment] = nil
                kept[.shadow] = nil
                let style = ((attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                style.lineBreakMode = lineBreakMode
                kept[.paragraphStyle] = style
                let run = (text.string as NSString).substring(with: range)
                result.append(NSAttributedString(string: masked(run, keepingWhitespace: keepingWhitespace), attributes: kept))
            }
            return result
        }

        /// Contentless bars in the text's colour, one per line the bounds hold: no glyph shapes, no layout, no bitmap.
        private static func addBars(_ signature: TextSignature, to copy: CALayer) {
            let bounds = copy.bounds
            let lineHeight = min(signature.lineHeight, bounds.height)
            guard lineHeight > 0 else { return }
            let lines = signature.singleLine ? 1 : min(200, max(1, Int(bounds.height / lineHeight)))
            let barHeight = lineHeight * barHeightFraction
            let top = bounds.minY + (bounds.height - CGFloat(lines) * lineHeight) / 2
            let color = signature.barColor()
            for line in 0 ..< lines {
                let bar = CALayer()
                bar.frame = CGRect(x: bounds.minX, y: top + CGFloat(line) * lineHeight + (lineHeight - barHeight) / 2, width: bounds.width, height: barHeight)
                bar.backgroundColor = color
                copy.addSublayer(bar)
            }
        }

        /// Any thread. Masks and lays out `source`, then draws it in Core Animation's own pixel format, so committing the
        /// bitmap needs no conversion.
        private static func draw(_ source: TextSource, scale: CGFloat) -> CGImage? {
            guard let laidOut = source.laidOut() else { return nil }
            let size = source.size
            let width = Int((size.width * scale).rounded(.up)), height = Int((size.height * scale).rounded(.up))
            guard width > 0, height > 0,
                  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: sRGB, bitmapInfo: PostHogGPUMirrorCapture.Target.bgraBitmapInfo)
            else { return nil }
            // Cleared so no stale bytes show wherever no text is drawn.
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: scale, y: -scale)
            context.clip(to: laidOut.clip ?? CGRect(origin: .zero, size: size))
            UIGraphicsPushContext(context)
            // Clipping line breaks keep a single line from wrapping; without this option the rect's origin would be the
            // baseline.
            laidOut.text.draw(with: laidOut.rect, options: .usesLineFragmentOrigin, context: nil)
            UIGraphicsPopContext()
            return context.makeImage()
        }
    }

    // MARK: - Text inputs

    /// What a `*` bitmap is drawn from, cheap to read on every capture and free of the text itself: the masked string
    /// with the style and layout inputs. Two views with equal signatures draw the same bitmap.
    private struct TextSignature: Hashable {
        let masked: String
        let size: CGSize
        let scale: CGFloat
        let font: UIFont?
        let color: UIColor?
        let alignment: Int
        let lines: Int
        let flags: Int
        /// Where a text view's text starts, scrolled, and how wide it lays out.
        let origin: CGPoint
        let layoutWidth: CGFloat
        let style: Int
        /// For the bars shown until the `*` are drawn: one per line of this height, or one for single-line text.
        let lineHeight: CGFloat
        let singleLine: Bool

        init(_ label: UILabel, size: CGSize, scale: CGFloat) {
            masked = Self.key(label.text ?? "", keepingWhitespace: true)
            self.size = size
            self.scale = scale
            font = label.font
            color = label.textColor
            alignment = label.textAlignment.rawValue
            lines = label.numberOfLines
            flags = label.lineBreakMode.rawValue
            origin = .zero
            layoutWidth = 0
            style = label.traitCollection.userInterfaceStyle.rawValue
            lineHeight = label.font.lineHeight
            singleLine = label.numberOfLines == 1
        }

        init(_ field: UITextField, size: CGSize, scale: CGFloat) {
            // The placeholder shows only when there's no text; a leading NUL keeps the two apart.
            let text = field.text ?? ""
            masked = text.isEmpty ? "\u{0}" + Self.key(field.placeholder ?? "", keepingWhitespace: false) : Self.key(text, keepingWhitespace: false)
            self.size = size
            self.scale = scale
            font = field.font
            color = field.textColor
            alignment = field.textAlignment.rawValue
            lines = 1
            flags = (field.isEditing ? 1 : 0) | (field.isSecureTextEntry ? 2 : 0)
            origin = .zero
            layoutWidth = 0
            style = field.traitCollection.userInterfaceStyle.rawValue
            lineHeight = field.font?.lineHeight ?? size.height
            singleLine = true
        }

        init(_ textView: UITextView, size: CGSize, scale: CGFloat) {
            masked = Self.key(textView.text ?? "", keepingWhitespace: true)
            self.size = size
            self.scale = scale
            font = textView.font
            color = textView.textColor
            alignment = textView.textAlignment.rawValue
            lines = 0
            flags = 0
            let layout = TextSource.textViewLayout(textView)
            origin = layout.origin
            layoutWidth = layout.width
            style = textView.traitCollection.userInterfaceStyle.rawValue
            lineHeight = textView.font?.lineHeight ?? UIFont.preferredFont(forTextStyle: .body).lineHeight
            singleLine = false
        }

        init(rowsOf size: CGSize, scale: CGFloat, traits: UITraitCollection) {
            masked = ""
            self.size = size
            self.scale = scale
            let body = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
            font = body
            color = nil
            alignment = 0
            lines = 0
            flags = 0
            origin = .zero
            layoutWidth = 0
            style = traits.userInterfaceStyle.rawValue
            lineHeight = body.lineHeight
            singleLine = false
        }

        /// The text masked per unicode scalar, which is cheap: equal masked text gives an equal key, and the bitmap is
        /// drawn per character.
        private static func key(_ text: String, keepingWhitespace: Bool) -> String {
            var masked = String.UnicodeScalarView()
            for scalar in text.unicodeScalars {
                masked.append(keepingWhitespace && scalar.properties.isWhitespace ? scalar : "*")
            }
            return String(masked)
        }

        /// The text's colour where it was read, else the label colour.
        func barColor() -> CGColor {
            let traits = UITraitCollection(userInterfaceStyle: UIUserInterfaceStyle(rawValue: style) ?? .unspecified)
            return PostHogInlineMask.starColor(color ?? .label).resolvedColor(with: traits).cgColor
        }
    }

    /// A view's text as read on main: what only UIKit can give (the text, its rects, colours resolved against the
    /// view's traits), for the draw queue to mask, lay out and draw.
    private struct TextSource {
        enum Layout {
            /// UILabel centres its text vertically in `rect`.
            case label(rect: CGRect, singleLine: Bool, lineHeight: CGFloat)
            /// One line centred in `rect`, scrolled to its end while editing as the field shows it.
            case field(rect: CGRect, editing: Bool, lineHeight: CGFloat)
            /// Already scrolled into the visible bounds' space.
            case textView(rect: CGRect)
            /// Rows of `*` filling the bounds, which depend only on the bounds, so they reveal nothing about the text.
            case rows(font: UIFont, color: UIColor)
        }

        /// Not mutated after it's read: the draw queue reads it.
        let text: NSAttributedString?
        let layout: Layout
        let size: CGSize

        init?(_ label: UILabel, size: CGSize) {
            guard let text = label.attributedText, text.length > 0 else { return nil }
            self.text = Self.resolvingColors(text, traits: label.traitCollection)
            let rect = label.textRect(forBounds: CGRect(origin: .zero, size: size), limitedToNumberOfLines: label.numberOfLines)
            layout = .label(rect: rect, singleLine: label.numberOfLines == 1, lineHeight: Self.firstFont(text, default: label.font).lineHeight)
            self.size = size
        }

        init?(_ field: UITextField, size: CGSize) {
            let bounds = CGRect(origin: .zero, size: size)
            let source: NSAttributedString
            let rect: CGRect
            if let text = field.attributedText, text.length > 0 {
                source = text
                rect = field.isEditing ? field.editingRect(forBounds: bounds) : field.textRect(forBounds: bounds)
            } else if let placeholder = field.attributedPlaceholder, placeholder.length > 0 {
                source = placeholder
                rect = field.placeholderRect(forBounds: bounds)
            } else if let placeholder = field.placeholder, !placeholder.isEmpty {
                source = NSAttributedString(string: placeholder, attributes: [.font: field.font as Any, .foregroundColor: UIColor.placeholderText])
                rect = field.placeholderRect(forBounds: bounds)
            } else {
                return nil
            }
            text = Self.resolvingColors(source, traits: field.traitCollection)
            layout = .field(rect: rect, editing: field.isEditing, lineHeight: Self.firstFont(source, default: field.font).lineHeight)
            self.size = size
        }

        init?(_ textView: UITextView, size: CGSize) {
            guard let text = textView.attributedText, text.length > 0 else { return nil }
            self.text = Self.resolvingColors(text, traits: textView.traitCollection)
            let layout = Self.textViewLayout(textView)
            self.layout = .textView(rect: CGRect(x: layout.origin.x, y: layout.origin.y, width: layout.width,
                                                 height: max(size.height - layout.origin.y, textView.contentSize.height)))
            self.size = size
        }

        init(rowsOf size: CGSize, traits: UITraitCollection) {
            text = nil
            let body = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
            let font = size.height < body.lineHeight ? body.withSize(max(1, body.pointSize * size.height / body.lineHeight)) : body
            layout = .rows(font: font, color: PostHogInlineMask.starColor(.label).resolvedColor(with: traits))
            self.size = size
        }

        /// Where a text view's text starts in its visible bounds (scrolled by the offset) and how wide it lays out.
        static func textViewLayout(_ textView: UITextView) -> (origin: CGPoint, width: CGFloat) {
            let inset = textView.textContainerInset, padding = textView.textContainer.lineFragmentPadding, offset = textView.contentOffset
            return (CGPoint(x: inset.left + padding - offset.x, y: inset.top - offset.y),
                    max(0, textView.bounds.width - inset.left - inset.right - 2 * padding))
        }

        /// The masked text, where it's drawn and where it's clipped.
        struct LaidOut {
            let text: NSAttributedString
            let rect: CGRect
            var clip: CGRect?
        }

        /// Any thread. nil when there's nothing to draw.
        func laidOut() -> LaidOut? {
            switch layout {
            case let .label(rect, singleLine, lineHeight):
                guard let text else { return nil }
                let masked = PostHogInlineMask.masked(text, keepingWhitespace: true, lineBreakMode: singleLine ? .byClipping : .byWordWrapping)
                var drawn = rect
                drawn.origin.y = (size.height - rect.height) / 2
                // Clipped rather than wrapped or truncated: `*` can be wider than the glyphs it replaces.
                if singleLine { drawn.size.height = max(rect.height, lineHeight) }
                return LaidOut(text: masked, rect: drawn)
            case let .field(rect, editing, lineHeight):
                guard let text else { return nil }
                let masked = PostHogInlineMask.masked(text, keepingWhitespace: false, lineBreakMode: .byClipping)
                let width = masked.size().width
                let left = editing && width > rect.width ? rect.maxX - width : rect.minX
                return LaidOut(text: masked, rect: CGRect(x: left, y: rect.midY - lineHeight / 2, width: max(rect.maxX - left, width), height: lineHeight),
                               clip: rect)
            case let .textView(rect):
                guard let text else { return nil }
                return LaidOut(text: PostHogInlineMask.masked(text, keepingWhitespace: true, lineBreakMode: .byWordWrapping), rect: rect)
            case let .rows(font, color):
                return Self.rows(size: size, font: font, color: color)
            }
        }

        private static func rows(size: CGSize, font: UIFont, color: UIColor) -> LaidOut? {
            let starWidth = NSAttributedString(string: "*", attributes: [.font: font]).size().width
            let rows = max(1, Int(size.height / font.lineHeight))
            let perRow = starWidth > 0 ? Int(size.width / starWidth) : 0
            guard perRow > 0 else { return nil }
            let string = Array(repeating: String(repeating: "*", count: perRow), count: rows).joined(separator: "\n")
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byClipping
            style.minimumLineHeight = font.lineHeight
            style.maximumLineHeight = font.lineHeight
            let text = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
            let height = CGFloat(rows) * font.lineHeight
            return LaidOut(text: text, rect: CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height))
        }

        /// Colours resolved against `traits`, since drawing runs off main where dynamic colours can't be.
        private static func resolvingColors(_ text: NSAttributedString, traits: UITraitCollection) -> NSAttributedString {
            let resolved = NSMutableAttributedString(attributedString: text)
            text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
                for (key, value) in attributes {
                    guard let color = value as? UIColor else { continue }
                    let drawn = key == .foregroundColor ? PostHogInlineMask.starColor(color) : color
                    resolved.addAttribute(key, value: drawn.resolvedColor(with: traits), range: range)
                }
            }
            return resolved
        }

        private static func firstFont(_ text: NSAttributedString, default font: UIFont?) -> UIFont {
            (text.length > 0 ? text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont : nil) ?? font ?? UIFont.systemFont(ofSize: UIFont.labelFontSize)
        }
    }
#endif
