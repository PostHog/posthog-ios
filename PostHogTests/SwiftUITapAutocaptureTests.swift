#if os(iOS)
    @testable import PostHog
    import Testing
    import UIKit

    @Suite(.serialized)
    @MainActor
    struct SwiftUITapAutocaptureTests {
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
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
            let host = PrototypeHostingView(frame: window.bounds)
            window.addSubview(host)
            window.isHidden = false
            return (window, host)
        }

        private func resolve(_ view: UIView, _ window: UIWindow, _ point: CGPoint) -> PostHogAutocaptureEventTracker.EventData? {
            SwiftUITapElementResolver.resolve(hit: view, window: window, point: point)
        }
    }

    private final class PrototypeHostingView: UIView {}

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
            CGPoint(x: 10, y: 10)
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
