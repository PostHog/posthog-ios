#if os(iOS)
    import UIKit

    /// Single-pointer tap classifier. Remember maximum movement, not just the end position:
    /// a drag that returns to its origin is still a drag.
    struct SwiftUITapClassifier {
        private var start: CGPoint?
        private var startedAt: TimeInterval = 0
        private var movedTooFar = false

        mutating func begin(at point: CGPoint, timestamp: TimeInterval) {
            start = point
            startedAt = timestamp
            movedTooFar = false
        }

        mutating func move(to point: CGPoint) {
            guard let start else { return }
            let deltaX = point.x - start.x
            let deltaY = point.y - start.y
            movedTooFar = movedTooFar || deltaX * deltaX + deltaY * deltaY > 100
        }

        mutating func end(at point: CGPoint, timestamp: TimeInterval) -> Bool {
            move(to: point)
            defer { cancel() }
            return start != nil && !movedTooFar && timestamp >= startedAt && timestamp - startedAt <= 0.5
        }

        mutating func cancel() {
            start = nil
        }
    }

    /// Observes the existing application event publisher without adding a competing recognizer.
    /// Only the new subscription and its touch state are owned here; UIKit capture remains on
    /// the existing action/gesture route.
    final class SwiftUITapAutocapture {
        private weak var processor: (any AutocaptureEventProcessing)?
        private let publisher: any ApplicationEventPublishing
        private var token: RegistrationToken?
        private var classifier = SwiftUITapClassifier()
        private var candidate: PostHogAutocaptureEventTracker.EventData?
        private var touchID: ObjectIdentifier?
        private let stateLock = NSLock()
        private var generation = 0
        private var enabled = false

        init(processor: any AutocaptureEventProcessing, publisher: any ApplicationEventPublishing = DI.main.applicationEventPublisher) {
            self.processor = processor
            self.publisher = publisher
        }

        func setEnabled(_ enabled: Bool) {
            let request = stateLock.withLock { () -> Int in
                self.enabled = enabled
                generation += 1
                return generation
            }
            let update = { [self] in
                guard stateLock.withLock({ generation == request }) else { return }
                token = nil
                cancel()
                if enabled {
                    token = publisher.onApplicationEvent.subscribe { [weak self] event, _ in
                        self?.handle(event)
                    }
                }
            }
            if Thread.isMainThread { update() } else { DispatchQueue.main.async(execute: update) }
        }

        /// Legacy capture wins if UIKit already emitted an action or recognized gesture.
        func cancel() {
            guard Thread.isMainThread else { return }
            candidate = nil
            touchID = nil
            classifier.cancel()
        }

        private func handle(_ event: UIEvent) {
            guard Thread.isMainThread, stateLock.withLock({ enabled }), event.type == .touches else { return }
            guard let touches = event.allTouches, touches.count == 1, let touch = touches.first,
                  let window = touch.window, !window.isKeyboardWindow
            else {
                cancel()
                return
            }
            let point = touch.location(in: window)
            switch touch.phase {
            case .began:
                cancel()
                // Stateless hit testing only: never re-enter UIKit with the live UIEvent.
                let hit = touch.view ?? window.hitTest(point, with: nil)
                candidate = SwiftUITapElementResolver.resolve(hit: hit, window: window, point: point)
                if candidate != nil {
                    touchID = ObjectIdentifier(touch)
                    classifier.begin(at: point, timestamp: touch.timestamp)
                }
            case .moved, .stationary:
                guard touchID == ObjectIdentifier(touch) else {
                    cancel()
                    return
                }
                classifier.move(to: point)
            case .ended:
                guard touchID == ObjectIdentifier(touch), let candidate,
                      classifier.end(at: point, timestamp: touch.timestamp),
                      let endTarget = SwiftUITapElementResolver.resolve(hit: window.hitTest(point, with: nil), window: window, point: point),
                      endTarget.getElementChain() == candidate.getElementChain()
                else {
                    cancel()
                    return
                }
                cancel()
                processor?.process(source: .swiftUITap, event: candidate)
            case .cancelled:
                cancel()
            default:
                break
            }
        }
    }

    enum SwiftUITapElementResolver {
        /// No visible/accessibility text is captured. Identifiers are developer supplied; fallback
        /// paths contain class names and sibling indices only, never object addresses.
        static func resolve(hit: UIView?, window: UIWindow, point: CGPoint) -> PostHogAutocaptureEventTracker.EventData? {
            guard let hit, !window.isKeyboardWindow else { return nil }
            let ancestors = Array(sequence(first: hit, next: \.superview))
            guard ancestors.contains(where: isSwiftUI),
                  !ancestors.contains(where: { $0 is UIControl || $0 is UITextView || $0 is UITextField }),
                  !ancestors.contains(where: { $0.isNoCapture() || $0.isHidden || $0.alpha <= 0.01 || !$0.isUserInteractionEnabled })
            else { return nil }

            let masks = PostHogSessionReplayMaskRegistry.shared.maskedRects(in: window)
            guard !masks.hasUnsettledReporters, !masks.rects.contains(where: { $0.contains(point) }) else { return nil }

            // SwiftUI primitives often share one hosting view. Resolve passive label markers
            // geometrically instead of applying one label to the entire hosting view.
            var label: String?
            var labelArea = CGFloat.greatestFiniteMagnitude
            var excluded = false
            var remaining = 512
            func walk(_ view: UIView, depth: Int) {
                guard remaining > 0, depth < 32 else {
                    excluded = true
                    return
                }
                remaining -= 1
                guard !view.isHidden, view.alpha > 0.01 else { return }
                let local = window.convert(point, to: view)
                let contains = view.bounds.contains(local)
                if contains, view.isNoCapture() {
                    excluded = true
                    return
                }
                if contains, view is UIControl || view is UITextView {
                    excluded = true
                    return
                }
                if contains, let marker = view as? PostHogLabelTaggerView {
                    let area = view.bounds.width * view.bounds.height
                    if area < labelArea {
                        label = marker.label
                        labelArea = area
                    }
                }
                if !contains, view.clipsToBounds { return }
                for child in view.subviews {
                    walk(child, depth: depth + 1)
                }
            }
            // Restrict to the tapped hosting subtree, avoiding UI behind presented screens.
            let host = ancestors.first(where: isSwiftUI) ?? hit
            walk(host, depth: 0)
            guard !excluded else { return nil }

            let screenPoint = window.convert(point, to: window.screen.coordinateSpace)
            let accessibility = identifier(in: host, at: screenPoint)
            guard !accessibility.excluded else { return nil }
            let developerLabel = label ?? accessibility.developerIdentifier ?? ancestors.compactMap(\.accessibilityIdentifier).first
            label = developerLabel ?? accessibility.identifier
            // A flattened hosting surface can also contain excluded elements that UIKit
            // cannot resolve. Do not attribute an unknown point to the entire screen.
            guard let label, !label.isEmpty else { return nil }

            let hierarchy = ancestors.prefix(12).map { view in
                let name = String(describing: type(of: view)).components(separatedBy: "<").first ?? "View"
                return PostHogAutocaptureEventTracker.Element(
                    text: "", targetClass: name, baseClass: nil,
                    label: nil
                )
            }
            // The title formatter reads the target tag and aria label, not attr_id.
            // Reuse only the developer identifier; never include accessibility display text.
            let target = PostHogAutocaptureEventTracker.Element(
                text: "", targetClass: accessibility.traits.contains(.button) ? "button" : "SwiftUIElement",
                baseClass: nil, label: label, ariaLabel: developerLabel
            )
            return .init(touchCoordinates: point, value: nil,
                         screenName: hit.nearestViewController.flatMap(UIViewController.getViewControllerName),
                         viewHierarchy: [target] + hierarchy, debounceInterval: 0)
        }

        static func isSwiftUI(_ view: UIView) -> Bool {
            let name = String(reflecting: type(of: view))
            return name.hasPrefix("SwiftUI.") || name.hasPrefix("SwiftUICore.")
        }

        /// Public accessibility-container APIs support flattened SwiftUI views without depending
        /// on private rendering fields. Bounded traversal fails closed when the tree is too large.
        static func identifier(in root: NSObject, at point: CGPoint) -> AccessibilityTarget {
            var remaining = 256
            var visited = Set<ObjectIdentifier>()
            var best: String?
            var fallback: String?
            var fallbackArea = CGFloat.greatestFiniteMagnitude
            var area = CGFloat.greatestFiniteMagnitude
            var excluded = false
            var traits: UIAccessibilityTraits = []
            var traitArea = CGFloat.greatestFiniteMagnitude
            func visit(_ object: NSObject, depth: Int, path: String) {
                guard visited.insert(ObjectIdentifier(object)).inserted else { return }
                guard remaining > 0, depth < 20 else {
                    excluded = true
                    return
                }
                remaining -= 1
                let frame = object.accessibilityFrame
                if frame.contains(point) {
                    if object.isAccessibilityElement, frame.width * frame.height < traitArea {
                        traits = object.accessibilityTraits
                        traitArea = frame.width * frame.height
                    }
                    let id = accessibilityIdentifier(of: object)
                    if id?.localizedCaseInsensitiveContains("ph-no-capture") == true
                        || object.accessibilityLabel?.localizedCaseInsensitiveContains("ph-no-capture") == true
                        || object.accessibilityTraits.contains(.notEnabled)
                    {
                        excluded = true
                    }
                    if object.isAccessibilityElement, !path.isEmpty, frame.width * frame.height < fallbackArea {
                        fallback = "SwiftUIElement\(path)"
                        fallbackArea = frame.width * frame.height
                    }
                    if let id, !id.isEmpty, !id.hasPrefix("_"), frame.width * frame.height < area {
                        best = id
                        area = frame.width * frame.height
                    }
                }
                let elements = object.accessibilityElements
                let count = elements?.count ?? object.accessibilityElementCount()
                guard count != NSNotFound, count > 0 else { return }
                guard count <= remaining else {
                    excluded = true
                    return
                }
                for index in 0 ..< count {
                    if let child = (elements?[index] ?? object.accessibilityElement(at: index)) as? NSObject {
                        visit(child, depth: depth + 1, path: "\(path)[\(index)]")
                    }
                }
            }
            #if compiler(>=6.0)
                if #available(iOS 18.0, *),
                   let element = root.accessibilityHitTest(point, event: nil) as? NSObject,
                   element !== root
                {
                    visit(element, depth: 0, path: "")
                    // Indexed traversal must still assign a path to an unlabeled hit-test leaf.
                    visited.removeAll(keepingCapacity: true)
                }
            #endif
            visit(root, depth: 0, path: "")
            return AccessibilityTarget(identifier: best ?? fallback, excluded: excluded, traits: traits, developerIdentifier: best)
        }

        struct AccessibilityTarget {
            let identifier: String?
            let excluded: Bool
            let traits: UIAccessibilityTraits
            let developerIdentifier: String?
        }

        private static func accessibilityIdentifier(of object: NSObject) -> String? {
            if let identified = object as? UIAccessibilityIdentification {
                return identified.accessibilityIdentifier
            }
            // SwiftUI accessibility objects can implement the public getter without
            // declaring conformance to UIAccessibilityIdentification.
            let selector = #selector(getter: UIAccessibilityIdentification.accessibilityIdentifier)
            guard object.responds(to: selector) else { return nil }
            return object.perform(selector)?.takeUnretainedValue() as? String
        }
    }
#endif
