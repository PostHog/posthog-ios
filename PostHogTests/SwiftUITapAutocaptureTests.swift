#if os(iOS)
    @testable import PostHog
    import SwiftUI
    import Testing
    import UIKit

    @Suite(.serialized)
    @MainActor
    struct SwiftUITapAutocaptureTests {
        @Test func hostingNamedUIKitViewKeepsGestureCapture() {
            let view = ImageHostingView()
            let processor = TapTestProcessor()
            let previousProcessor = PostHogAutocaptureEventTracker.eventProcessor
            PostHogAutocaptureEventTracker.eventProcessor = processor
            defer { PostHogAutocaptureEventTracker.eventProcessor = previousProcessor }
            let tap = UITapGestureRecognizer()
            view.addGestureRecognizer(tap)
            tap.state = .ended
            #expect(processor.events.count == 1)
            #expect(processor.events.first?.viewHierarchy.first?.targetClass == "ImageHostingView")
        }

        @Test func genuineSwiftUIHostingViewCapturesOnlyThroughTouchObserver() {
            guard #available(iOS 13.4, *) else { return }
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
            let controller = UIHostingController(rootView: Color.clear)
            window.rootViewController = controller
            window.isHidden = false
            let host = controller.view!
            host.accessibilityIdentifier = "swiftui-dedup-target"
            let publisher = TapTestPublisher()
            let processor = TapTestProcessor()
            let observer = SwiftUITapAutocapture(processor: processor, publisher: publisher)
            let previousProcessor = PostHogAutocaptureEventTracker.eventProcessor
            PostHogAutocaptureEventTracker.eventProcessor = processor
            observer.setEnabled(true)
            defer {
                observer.setEnabled(false)
                PostHogAutocaptureEventTracker.eventProcessor = previousProcessor
                window.isHidden = true
            }
            let touch = PointerTestTouch(target: host, window: window)
            let event = PointerTestEvent(touch: touch)
            publisher.onApplicationEvent.invoke((event, Date()))
            let tap = UITapGestureRecognizer()
            host.addGestureRecognizer(tap)
            tap.state = .ended
            #expect(processor.events.isEmpty)
            touch.recordedPhase = .ended
            touch.recordedTimestamp = 1.1
            publisher.onApplicationEvent.invoke((event, Date()))
            #expect(processor.events.count == 1)
            #expect(processor.events.first?.viewHierarchy.first?.label == "swiftui-dedup-target")
        }

        @Test func tapClassifierAcceptsShortStationaryTouchOnlyOnce() {
            var classifier = SwiftUITapClassifier()
            classifier.begin(at: .zero, timestamp: 10)
            let accepted = classifier.end(at: CGPoint(x: 3, y: 4), timestamp: 10.2)
            let duplicate = classifier.end(at: .zero, timestamp: 10.3)
            #expect(accepted)
            #expect(!duplicate)
        }

        @Test func dragReturningToOriginIsNotATap() {
            var classifier = SwiftUITapClassifier()
            classifier.begin(at: .zero, timestamp: 1)
            classifier.move(to: CGPoint(x: 0, y: 25))
            let accepted = classifier.end(at: .zero, timestamp: 1.2)
            #expect(!accepted)
        }

        @Test func longPressCancellationAndInvalidTimeAreNotTaps() {
            var classifier = SwiftUITapClassifier()
            classifier.begin(at: .zero, timestamp: 1)
            let longPress = classifier.end(at: .zero, timestamp: 2)
            #expect(!longPress)
            classifier.begin(at: .zero, timestamp: 1)
            classifier.cancel()
            let cancelled = classifier.end(at: .zero, timestamp: 1.1)
            #expect(!cancelled)
            classifier.begin(at: .zero, timestamp: 1)
            let invalidTime = classifier.end(at: .zero, timestamp: 0)
            #expect(!invalidTime)
        }

        @Test func developerMarkerWinsAndDoesNotLabelNeighbor() {
            let (window, host) = fixture()
            let marker = PostHogLabelTaggerView(label: "stable-button")
            marker.frame = CGRect(x: 0, y: 0, width: 100, height: 60)
            host.addSubview(marker)
            let button = resolve(host, window, CGPoint(x: 20, y: 20))
            #expect(button?.viewHierarchy.first?.label == "stable-button")
            let neighbor = resolve(host, window, CGPoint(x: 150, y: 150))
            #expect(neighbor?.viewHierarchy.first?.label != "stable-button")
            #expect(host.postHogLabel == nil)
            marker.label = "updated-button"
            #expect(resolve(host, window, CGPoint(x: 20, y: 20))?.viewHierarchy.first?.label == "updated-button")
        }

        @Test func logicalTargetUsesDeveloperLabelWithoutInventingButtonRole() throws {
            let (window, host) = fixture()
            let marker = PostHogLabelTaggerView(label: "Product card")
            marker.frame = CGRect(x: 0, y: 0, width: 100, height: 60)
            host.addSubview(marker)
            let event = try #require(resolve(host, window, CGPoint(x: 20, y: 20)))
            #expect(event.viewHierarchy.first?.targetClass == "SwiftUIElement")
            #expect(event.getElementChain().hasPrefix("SwiftUIElement:attr_id=\"Product card\"attr__aria-label=\"Product card\";"))
            #expect(event.viewHierarchy.dropFirst().first?.label == nil)
            let hasNoDisplayText = event.viewHierarchy.allSatisfy(\.text.isEmpty)
            #expect(hasNoDisplayText)
        }

        @Test(arguments: [true, false])
        func accessibilityTraitsDetermineLogicalButtonRole(isButton: Bool) throws {
            let (window, host) = fixture(content: Color.clear
                .accessibilityElement()
                .accessibility(identifier: "Checkout")
                .accessibility(label: Text("PRIVATE_DISPLAY_TEXT"))
                .accessibility(addTraits: isButton ? .isButton : .isStaticText))
            let event = try #require(resolve(host, window, CGPoint(x: window.bounds.midX, y: window.bounds.midY)))
            #expect(event.viewHierarchy.first?.targetClass == (isButton ? "button" : "SwiftUIElement"))
            #expect(event.getElementChain().contains("attr__aria-label=\"Checkout\""))
            #expect(!event.getElementChain().contains("PRIVATE_DISPLAY_TEXT"))
            #expect(event.viewHierarchy.dropFirst().first?.targetClass == String(describing: type(of: host)).components(separatedBy: "<").first)
        }

        @Test func structuralFallbackIsNotAnAriaLabel() throws {
            let (window, host) = fixture(content: Color.clear
                .accessibilityElement()
                .accessibility(label: Text("PRIVATE_DISPLAY_TEXT"))
                .accessibility(addTraits: .isButton))
            let event = try #require(resolve(host, window, CGPoint(x: window.bounds.midX, y: window.bounds.midY)))
            #expect(event.viewHierarchy.first?.label == "SwiftUIElement[0]")
            #expect(!event.getElementChain().contains("attr__aria-label"))
        }

        @Test func identifierGetterWithoutProtocolConformanceHonorsExclusion() {
            let root = UIView()
            let element = IdentifierGetterElement()
            element.isAccessibilityElement = true
            element.accessibilityFrame = CGRect(x: 0, y: 0, width: 100, height: 60)
            element.accessibilityIdentifier = "prototype.ph-no-capture"
            root.accessibilityElements = [element]
            #expect((element as NSObject) as? UIAccessibilityIdentification == nil)
            #expect(SwiftUITapElementResolver.identifier(in: root, at: CGPoint(x: 20, y: 20)).excluded)
        }

        @Test(arguments: ["ph-no-capture", "Private PH-NO-CAPTURE control"])
        func accessibilityLabelExclusionPreventsStructuralFallback(label: String) {
            let (window, host) = fixture(content: Color.clear
                .accessibilityElement()
                .accessibility(label: Text(label))
                .accessibility(addTraits: .isButton))
            #expect(resolve(host, window, CGPoint(x: window.bounds.midX, y: window.bounds.midY)) == nil)
        }

        @Test func smallestNestedMarkerWins() {
            let (window, host) = fixture()
            for (label, size) in [("outer", CGFloat(150)), ("inner", CGFloat(50))] {
                let marker = PostHogLabelTaggerView(label: label)
                marker.frame = CGRect(x: 0, y: 0, width: size, height: size)
                host.addSubview(marker)
            }
            #expect(resolve(host, window, CGPoint(x: 10, y: 10))?.viewHierarchy.first?.label == "inner")
        }

        @Test func nativeControlsAreLeftToUIKitCaptureEvenInsideHostingView() {
            let (window, host) = fixture()
            let button = UIButton(frame: CGRect(x: 0, y: 0, width: 80, height: 40))
            host.addSubview(button)
            let child = UIView(frame: button.bounds)
            button.addSubview(child)
            #expect(resolve(child, window, CGPoint(x: 10, y: 10)) == nil)
            #expect(resolve(host, window, CGPoint(x: 10, y: 10)) == nil)
        }

        @Test func noCaptureAndHiddenTargetsAreExcluded() {
            let (window, host) = fixture()
            host.accessibilityIdentifier = "ph-no-capture"
            #expect(resolve(host, window, CGPoint(x: 10, y: 10)) == nil)
            host.accessibilityIdentifier = nil
            host.isHidden = true
            #expect(resolve(host, window, CGPoint(x: 10, y: 10)) == nil)
        }

        @Test func explicitMaskRegionIsExcluded() {
            let (window, host) = fixture()
            host.accessibilityIdentifier = "safe-target"
            let mask = PostHogMaskReporterUIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
            host.addSubview(mask)
            mask.layoutSubviews()
            #expect(resolve(host, window, CGPoint(x: 10, y: 10)) == nil)
            mask.removeFromSuperview()
            #expect(resolve(host, window, CGPoint(x: 10, y: 10)) != nil)
        }

        @Test func accessibilityIdentifierNotUserFacingTextIsUsed() {
            let container = UIView()
            let element = UIAccessibilityElement(accessibilityContainer: container)
            element.accessibilityFrame = CGRect(x: 0, y: 0, width: 100, height: 100)
            element.accessibilityIdentifier = "stable-id"
            element.accessibilityLabel = "Synthetic private display text"
            container.accessibilityElements = [element]
            let result = SwiftUITapElementResolver.identifier(in: container, at: CGPoint(x: 5, y: 5))
            #expect(result.identifier == "stable-id")
            #expect(!result.excluded)
            element.accessibilityIdentifier = nil
            #expect(SwiftUITapElementResolver.identifier(in: container, at: CGPoint(x: 5, y: 5)).identifier == "SwiftUIElement[0]")
            element.accessibilityIdentifier = "ph-no-capture"
            #expect(SwiftUITapElementResolver.identifier(in: container, at: CGPoint(x: 5, y: 5)).excluded)
        }

        @Test func unresolvedHostingSurfaceIsSkippedRatherThanCapturingDisplayText() {
            let (window, host) = fixture()
            host.accessibilityLabel = "Synthetic private display text"
            #expect(resolve(host, window, CGPoint(x: 10, y: 10)) == nil)
        }

        @Test func labelMarkerDoesNotTagUnrelatedUIKitControl() {
            let (window, host) = fixture()
            let markerContainer = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
            let controlContainer = UIView(frame: CGRect(x: 0, y: 100, width: 100, height: 40))
            host.addSubview(markerContainer)
            host.addSubview(controlContainer)
            let marker = PostHogLabelTaggerView(label: "swiftui-target")
            marker.frame = markerContainer.bounds
            markerContainer.addSubview(marker)
            let button = UIButton(frame: controlContainer.bounds)
            button.postHogLabel = "native-target"
            controlContainer.addSubview(button)
            marker.layoutSubviews()
            #expect(button.postHogLabel == "native-target")
            #expect(resolve(host, window, CGPoint(x: 10, y: 10))?.viewHierarchy.first?.label == "swiftui-target")
        }

        @Test func labelMarkerFindsMatchingCousinAndClearsSupersededTarget() {
            let (window, host) = fixture()
            defer { window.isHidden = true }
            let controls = UIView(frame: host.bounds)
            let markers = UIView(frame: host.bounds)
            host.addSubview(controls)
            host.addSubview(markers)
            let first = UIButton(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
            let second = UIButton(frame: CGRect(x: 0, y: 100, width: 100, height: 40))
            controls.addSubview(first)
            controls.addSubview(second)
            let marker = PostHogLabelTaggerView(label: "moving-label")
            markers.addSubview(marker)
            marker.frame = first.frame
            marker.layoutSubviews()
            #expect(first.postHogLabel == "moving-label")
            marker.frame = second.frame
            marker.layoutSubviews()
            #expect(first.postHogLabel == nil)
            #expect(second.postHogLabel == "moving-label")
            marker.frame.origin.y = 200
            marker.layoutSubviews()
            #expect(second.postHogLabel == nil)
            #expect(marker.taggedView == nil)
        }

        @Test func edgeReleaseOutsideMarkerDoesNotCapture() {
            guard #available(iOS 13.4, *) else { return }
            let (window, host) = fixture()
            let marker = PostHogLabelTaggerView(label: "edge-target")
            marker.frame = CGRect(x: 0, y: 0, width: 20, height: 40)
            host.addSubview(marker)
            let publisher = TapTestPublisher()
            let processor = TapTestProcessor()
            let observer = SwiftUITapAutocapture(processor: processor, publisher: publisher)
            observer.setEnabled(true)
            defer { observer.setEnabled(false) }
            let touch = PointerTestTouch(target: host, window: window)
            touch.point = CGPoint(x: 18, y: 10)
            let event = PointerTestEvent(touch: touch)
            publisher.onApplicationEvent.invoke((event, Date()))
            touch.point = CGPoint(x: 22, y: 10)
            touch.recordedPhase = .ended
            touch.recordedTimestamp = 1.1
            publisher.onApplicationEvent.invoke((event, Date()))
            #expect(processor.events.isEmpty)
        }

        @Test func observerStartIsIdempotentAndStopRemovesSubscription() {
            let publisher = TapTestPublisher()
            let processor = TapTestProcessor()
            let observer = SwiftUITapAutocapture(processor: processor, publisher: publisher)
            observer.setEnabled(true)
            #expect(publisher.subscriberCount == 1)
            observer.setEnabled(true)
            #expect(publisher.subscriberCount == 1)
            observer.setEnabled(false)
            #expect(publisher.subscriberCount == 0)
            observer.setEnabled(false)
            #expect(publisher.subscriberCount == 0)
            observer.setEnabled(true)
            #expect(publisher.subscriberCount == 1)
            observer.setEnabled(false)
        }

        @Test func pointerTapUsesTheSameCaptureRoute() {
            guard #available(iOS 13.4, *) else { return }
            let (window, host) = fixture()
            host.accessibilityIdentifier = "pointer-target"
            let publisher = TapTestPublisher()
            let processor = TapTestProcessor()
            let observer = SwiftUITapAutocapture(processor: processor, publisher: publisher)
            observer.setEnabled(true)
            defer { observer.setEnabled(false) }
            let touch = PointerTestTouch(target: host, window: window)
            let event = PointerTestEvent(touch: touch)
            publisher.onApplicationEvent.invoke((event, Date()))
            touch.recordedPhase = .ended
            touch.recordedTimestamp = 1.1
            publisher.onApplicationEvent.invoke((event, Date()))
            #expect(processor.events.count == 1)
            #expect(processor.events.first?.viewHierarchy.first?.label == "pointer-target")
        }

        @Test func hitTestLeafStillReceivesItsIndexedFallback() {
            guard #available(iOS 18.0, *) else { return }
            let container = HitTestContainer()
            let leaf = UIAccessibilityElement(accessibilityContainer: container)
            leaf.accessibilityFrame = CGRect(x: 0, y: 0, width: 100, height: 100)
            leaf.isAccessibilityElement = true
            container.leaf = leaf
            container.accessibilityElements = [leaf]
            let result = SwiftUITapElementResolver.identifier(in: container, at: CGPoint(x: 5, y: 5))
            #expect(result.identifier == "SwiftUIElement[0]")
        }

        private func fixture() -> (UIWindow, UIView) {
            fixture(content: Color.clear)
        }

        private func fixture<Content: View>(content: Content) -> (UIWindow, UIView) {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
            let controller = UIHostingController(rootView: content.edgesIgnoringSafeArea(.all))
            window.rootViewController = controller
            window.isHidden = false
            controller.view.layoutIfNeeded()
            return (window, controller.view)
        }

        private func resolve(_ view: UIView, _ window: UIWindow, _ point: CGPoint) -> PostHogAutocaptureEventTracker.EventData? {
            SwiftUITapElementResolver.resolve(hit: view, window: window, point: point)
        }
    }

    private final class IdentifierGetterElement: NSObject {
        @objc var accessibilityIdentifier: String?
    }

    private final class ImageHostingView: UIView {}

    private final class TapTestPublisher: ApplicationEventPublishing {
        var subscriberCount = 0
        lazy var onApplicationEvent = PostHogMulticastCallback<ApplicationEventData> { [weak self] count in
            self?.subscriberCount = count
        }
    }

    private final class TapTestProcessor: AutocaptureEventProcessing {
        var events: [PostHogAutocaptureEventTracker.EventData] = []
        func process(source _: PostHogAutocaptureEventTracker.EventSource, event: PostHogAutocaptureEventTracker.EventData) {
            events.append(event)
        }
    }

    @available(iOS 13.4, *)
    private final class PointerTestTouch: UITouch {
        let target: UIView
        let targetWindow: UIWindow
        var recordedPhase: UITouch.Phase = .began
        var recordedTimestamp: TimeInterval = 1
        var point = CGPoint(x: 10, y: 10)
        init(target: UIView, window: UIWindow) {
            self.target = target
            targetWindow = window
            super.init()
        }
        override var type: UITouch.TouchType { .indirectPointer }
        override var phase: UITouch.Phase { recordedPhase }
        override var timestamp: TimeInterval { recordedTimestamp }
        override var view: UIView? { target }
        override var window: UIWindow? { targetWindow }
        override func location(in _: UIView?) -> CGPoint {
            point
        }
    }

    private final class PointerTestEvent: UIEvent {
        let touch: UITouch
        init(touch: UITouch) {
            self.touch = touch
            super.init()
        }
        override var type: UIEvent.EventType { .touches }
        override var allTouches: Set<UITouch>? { [touch] }
    }

    @available(iOS 18.0, *)
    private final class HitTestContainer: UIView {
        var leaf: UIAccessibilityElement?
        override func accessibilityHitTest(_: CGPoint, event _: UIEvent?) -> Any? {
            leaf
        }
    }
#endif
