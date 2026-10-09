#if os(iOS) && canImport(Metal)
    import QuartzCore
    import UIKit

    /// Liquid Glass shapes are signed-distance fields only the render server evaluates; CARenderer draws nothing for
    /// them. `PostHogGPUMirrorCapture` gives the shapes under a glass background a flat fill and a hairline edge
    /// instead, so platters and glass buttons keep a visible background. Tinted glass takes its tint from the colour
    /// matrix the material applies, else from the control that owns it, else a grey that both white and dark labels
    /// read on.
    enum PostHogGlassStandIn {
        struct Kind {
            /// Clear glass barely refracts: its shape's output range ends at 1 rather than tens of points. Sheets share
            /// its untracked luminance and zero margin, so those alone don't tell it apart.
            let clear: Bool
            /// The group holds a tint layer, composited `destIn`, beside its background.
            fileprivate let hasTintCutout: Bool
            fileprivate let group: CALayer?
            fileprivate let tints: [Tint]

            /// Whether `shape` is tinted, and with what colour matrix if its material's could be read. One
            /// group can hold several shapes (a toolbar's buttons) of which only some are tinted: those are the ones
            /// whose own outline the tint layer draws.
            func tint(for shape: CALayer) -> (tinted: Bool, matrix: [Float]?) {
                guard let group, !tints.isEmpty else { return (hasTintCutout, nil) }
                let frame = group.convert(shape.bounds, from: shape)
                for tint in tints where tint.shapes.contains(where: { matches(group.convert($0.bounds, from: $0), frame) }) {
                    return (true, tint.matrix)
                }
                return (false, nil)
            }

            private func matches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
                abs(lhs.minX - rhs.minX) < 1 && abs(lhs.minY - rhs.minY) < 1 && abs(lhs.width - rhs.width) < 1 && abs(lhs.height - rhs.height) < 1
            }
        }

        /// A tint layer's colour matrix and the shapes it's drawn in.
        fileprivate struct Tint {
            let matrix: [Float]
            let shapes: [CALayer]
        }

        private static let glassBackgroundFilter = "glassBackground"
        private static let destInFilter = "destIn"
        private static let colorMatrixFilter = "vibrantColorMatrix"
        private static let gradientEffectClass = "CASDFGradientEffect"
        private static let shapeClass = "CASDFElementLayer"
        /// `CAColorMatrix`: four rows (red, green, blue, alpha) of five floats.
        private static let colorMatrixSize = 20 * MemoryLayout<Float>.size
        private static let colorMatrixType = "{CAColorMatrix=ffffffffffffffffffff}"
        private static let ownerSearchDepth = 12
        private static let tintSearchDepth = 6
        private static let clearOutputMaximum = 1.0
        private static let barClassFragments = ["BarButton", "TabBar", "FloatingBar"]
        /// Sheets, alerts and dialogs let much more of what's behind them through than controls do. They draw as a
        /// blurred backdrop through a colour matrix; this flat fill is the fallback when that can't be built.
        private static let panelAlpha: CGFloat = 0.6
        /// Empirical: least-squares fits of backdrop pixels to iOS 26 `drawHierarchy` output under sheets, alerts and
        /// dialogs, over colours and greys, in each appearance.
        private static let lightPanelMatrix: [Float] = [0.554, -0.167, -0.004, 0, 0.630,
                                                        -0.091, 0.397, -0.036, 0, 0.713,
                                                        -0.058, -0.170, 0.561, 0, 0.669,
                                                        0, 0, 0, 1, 0]
        private static let darkPanelMatrix: [Float] = [0.598, -0.208, 0.085, 0, 0.059,
                                                       -0.094, 0.399, -0.068, 0, 0.099,
                                                       -0.087, -0.290, 0.607, 0, 0.103,
                                                       0, 0, 0, 1, 0]
        private static let panelBlurRadius: CGFloat = 12
        /// Lets the blur sample past the panel's edge instead of pulling in transparency there.
        private static let panelBackdropMargin = panelBlurRadius * 3
        /// A glass shape this size on both sides is a panel rather than a control or bar.
        private static let panelMinimumSide: CGFloat = 100

        static func isGlassBackground(_ backdrop: CALayer) -> Bool {
            backdrop.filters?.contains { ($0 as? NSObject)?.value(forKey: "name") as? String == glassBackgroundFilter } == true
        }

        static func kind(of backdrop: CALayer) -> Kind {
            // The background sits in a material layer; the tint layer, when there is one, in a sibling material layer.
            let group = backdrop.superlayer?.superlayer
            let hasTintCutout = group.map { containsDestIn($0, depth: tintSearchDepth) } ?? false
            var tints: [Tint] = []
            if hasTintCutout, let group { collectTints(in: group, depth: tintSearchDepth, into: &tints) }
            return Kind(clear: backdrop.value(forKey: "tracksLuma") as? Bool == false
                && (backdrop.value(forKey: "marginWidth") as? NSNumber)?.doubleValue == 0
                && outputMaximum(under: backdrop).map { $0 <= clearOutputMaximum } == true,
                hasTintCutout: hasTintCutout, group: group, tints: tints)
        }

        /// Fills `copy`, the mirror of the glass shape `source`.
        static func fill(_ copy: CALayer, source: CALayer, kind: Kind) {
            let view = source.delegate as? UIView
            let traits = nearestView(of: source)?.traitCollection ?? UITraitCollection.current
            let owner = owningControl(of: view)
            let effectTint = glassEffectTint(of: owner)
            let material = kind.tint(for: source)
            let fill: UIColor
            if material.tinted || effectTint != nil {
                if kind.clear {
                    fill = UIColor.systemGray.withAlphaComponent(0.25)
                } else {
                    fill = material.matrix.map { tintColor($0, over: UIColor.systemBackground.resolvedColor(with: traits)) }
                        ?? effectTint ?? buttonTint(of: owner)
                        ?? UIColor.systemGray.withAlphaComponent(0.85)
                }
            } else if hasLightLabel(owner, traits: traits) {
                fill = UIColor.systemGray.withAlphaComponent(0.85)
            } else if !kind.clear, isPanel(copy) {
                if let material = panelMaterial(for: copy, style: traits.userInterfaceStyle) {
                    copy.sublayers = [material]
                    fill = .clear
                } else {
                    fill = UIColor.systemBackground.withAlphaComponent(panelAlpha)
                }
            } else if traits.userInterfaceStyle == .dark {
                // Dark glass lightens even black: on iOS 26 it reads as 8% white there on buttons and 10% on bars, not
                // systemBackground's black.
                let white = kind.clear ? 0.25 : isInBar(nearestView(of: source)) ? 0.12 : 0.09
                fill = UIColor(white: white, alpha: kind.clear ? 0.3 : 0.85)
            } else {
                fill = UIColor.systemBackground.withAlphaComponent(kind.clear ? 0.3 : 0.85)
            }
            copy.backgroundColor = fill.resolvedColor(with: traits).cgColor
            copy.borderColor = UIColor.separator.resolvedColor(with: traits).cgColor
            copy.borderWidth = 0.5
        }

        /// A blurred, colour-matrixed backdrop clipped to the panel's shape, or nil when the shape's corners or the
        /// private classes aren't available. The clip is a separate layer because a backdrop's margin
        /// defeats its own corner clipping.
        private static func panelMaterial(for shape: CALayer, style: UIUserInterfaceStyle) -> CALayer? {
            let cornerRadiiKey = PostHogGPUMirrorCapture.cornerRadiiKey
            let cornerRadii = cornerRadiiKey?.changedValue(in: shape)
            var matrix = style == .dark ? darkPanelMatrix : lightPanelMatrix
            guard shape.cornerRadius > 0 || cornerRadii != nil,
                  let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type,
                  let blur = makeFilter("gaussianBlur"), let colorMatrix = makeFilter("colorMatrix")
            else { return nil }
            blur.setValue(panelBlurRadius, forKey: "inputRadius")
            blur.setValue(true, forKey: "inputNormalizeEdges")
            colorMatrix.setValue(NSValue(bytes: &matrix, objCType: colorMatrixType), forKey: "inputColorMatrix")
            let backdrop = backdropClass.init()
            backdrop.frame = shape.bounds
            backdrop.filters = [blur, colorMatrix]
            backdrop.setValue(panelBackdropMargin, forKey: "marginWidth")
            let clip = CALayer()
            clip.frame = shape.bounds
            clip.cornerRadius = shape.cornerRadius
            clip.cornerCurve = shape.cornerCurve
            if let cornerRadii { cornerRadiiKey?.set(cornerRadii, on: clip) }
            clip.masksToBounds = true
            clip.sublayers = [backdrop]
            return clip
        }

        private static func makeFilter(_ type: String) -> NSObject? {
            (NSClassFromString("CAFilter") as AnyObject?)?.perform(NSSelectorFromString("filterWithType:"), with: type)?
                .takeUnretainedValue() as? NSObject
        }

        /// Takes the copy, whose bounds come from the presentation layer: UIKit sizes these shapes with a
        /// match-bounds animation, so the model layer's bounds are empty.
        private static func isPanel(_ shape: CALayer) -> Bool {
            min(shape.bounds.width, shape.bounds.height) >= panelMinimumSide
        }

        /// The far end of the output range of the shape layer under `backdrop`.
        private static func outputMaximum(under backdrop: CALayer) -> Double? {
            for sublayer in backdrop.sublayers ?? [] {
                guard let effect = sublayer.value(forKey: "effect") as? NSObject, effect.responds(to: NSSelectorFromString("maximum")) else { continue }
                return (effect.value(forKey: "maximum") as? NSNumber)?.doubleValue
            }
            return nil
        }

        private static func containsDestIn(_ layer: CALayer, depth: Int) -> Bool {
            let filter = layer.compositingFilter
            if (filter as? String ?? (filter as? NSObject)?.value(forKey: "name") as? String) == destInFilter { return true }
            guard depth > 0 else { return false }
            return (layer.sublayers ?? []).contains { containsDestIn($0, depth: depth - 1) }
        }

        /// Tinted glass draws its tint as a gradient shape through a colour matrix. The shapes it's drawn in are the
        /// visible glass shapes below it. (The highlight beside it has its own matrix, on a key-fill shape.)
        private static func collectTints(in layer: CALayer, depth: Int, into tints: inout [Tint]) {
            if let effect = layer.value(forKey: "effect") as AnyObject?, NSStringFromClass(type(of: effect)) == gradientEffectClass,
               let matrix = colorMatrix(of: layer)
            {
                var shapes: [CALayer] = []
                collectVisibleShapes(in: layer, depth: tintSearchDepth, into: &shapes)
                tints.append(Tint(matrix: matrix, shapes: shapes))
                return
            }
            guard depth > 0 else { return }
            for sublayer in layer.sublayers ?? [] {
                collectTints(in: sublayer, depth: depth - 1, into: &tints)
            }
        }

        private static func collectVisibleShapes(in layer: CALayer, depth: Int, into shapes: inout [CALayer]) {
            guard !layer.isHidden, layer.opacity > 0 else { return }
            if NSStringFromClass(type(of: layer)) == shapeClass { shapes.append(layer) }
            guard depth > 0 else { return }
            for sublayer in layer.sublayers ?? [] {
                collectVisibleShapes(in: sublayer, depth: depth - 1, into: &shapes)
            }
        }

        /// The tint matrix's rows are weights on what's behind the glass plus an offset, so the tint is the matrix
        /// applied to the background: white in light mode, black in dark.
        private static func tintColor(_ matrix: [Float], over background: UIColor) -> UIColor {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
            background.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            let rgba = [red, green, blue, alpha]
            func channel(_ row: Int) -> CGFloat {
                let weights = matrix[row * 5 ..< row * 5 + 4].enumerated().map { CGFloat($0.element) * rgba[$0.offset] }
                return min(max(weights.reduce(CGFloat(matrix[row * 5 + 4]), +), 0), 1)
            }
            return UIColor(red: channel(0), green: channel(1), blue: channel(2), alpha: 1)
        }

        private static func colorMatrix(of layer: CALayer) -> [Float]? {
            for case let filter as NSObject in layer.filters ?? [] where filter.value(forKey: "name") as? String == colorMatrixFilter {
                guard let value = filter.value(forKey: "inputColorMatrix") as? NSValue else { return nil }
                var size = 0
                NSGetSizeAndAlignment(value.objCType, &size, nil)
                guard size == colorMatrixSize else { return nil }
                var matrix = [Float](repeating: 0, count: 20)
                value.getValue(&matrix, size: colorMatrixSize)
                return matrix
            }
            return nil
        }

        /// SwiftUI's glass shapes have no view of their own, so their traits (dark mode) come from the nearest one above.
        private static func nearestView(of layer: CALayer) -> UIView? {
            var current: CALayer? = layer
            while let candidate = current {
                if let view = candidate.delegate as? UIView { return view }
                current = candidate.superlayer
            }
            return nil
        }

        /// Whether `view` is part of a navigation bar, toolbar, tab bar or search bar, including iOS 26's bar items, tab bar
        /// platter and floating bottom bar, which sit outside the bar views themselves.
        private static func isInBar(_ view: UIView?) -> Bool {
            var current = view
            while let candidate = current {
                if candidate is UINavigationBar || candidate is UIToolbar || candidate is UITabBar || candidate is UISearchBar {
                    return true
                }
                let name = NSStringFromClass(type(of: candidate))
                if barClassFragments.contains(where: name.contains) { return true }
                current = candidate.superview
            }
            return false
        }

        /// The control a glass shape belongs to: the nearest button or visual effect view above it.
        private static func owningControl(of view: UIView?) -> UIView? {
            var current = view
            for _ in 0 ..< ownerSearchDepth {
                guard let candidate = current else { return nil }
                if candidate is UIButton || candidate is UIVisualEffectView { return candidate }
                current = candidate.superview
            }
            return nil
        }

        private static func buttonTint(of owner: UIView?) -> UIColor? {
            guard let button = owner as? UIButton else { return nil }
            var candidates: [UIColor?] = [button.tintColor]
            if #available(iOS 15.0, *), let configuration = button.configuration {
                candidates.insert(contentsOf: [configuration.baseBackgroundColor, configuration.background.backgroundColor], at: 0)
            }
            return candidates.lazy.compactMap { $0 }.first { $0.cgColor.alpha > 0 }
        }

        private static func glassEffectTint(of owner: UIView?) -> UIColor? {
            // UIGlassEffect ships with the iOS 26 SDK (Swift 6.2); older toolchains still build the SDK.
            #if compiler(>=6.2)
                if #available(iOS 26.0, *), let effect = (owner as? UIVisualEffectView)?.effect as? UIGlassEffect {
                    return effect.tintColor
                }
            #endif
            return nil
        }

        private static func hasLightLabel(_ owner: UIView?, traits: UITraitCollection) -> Bool {
            guard #available(iOS 15.0, *),
                  let foreground = (owner as? UIButton)?.configuration?.baseForegroundColor?.resolvedColor(with: traits)
            else { return false }
            var white: CGFloat = 0
            return foreground.getWhite(&white, alpha: nil) && white > 0.8
        }
    }
#endif
