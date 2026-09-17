#if os(iOS)
    import Foundation
    @_spi(PostHogInternal) @testable import PostHog
    import Testing
    import UIKit

    @Suite("Autocapture text privacy", .serialized)
    @MainActor
    struct PostHogAutocaptureTextPrivacyTest {
        @Test("Existing text capture is the default")
        func defaultRetainsText() throws {
            let config = PostHogConfig(projectToken: testProjectToken)
            #expect(config.captureElementText)
            let button = UIButton()
            button.setTitle("  SYNTHETIC_BUTTON  ", for: .normal)
            let event = try #require(button.eventData(touchCoordinates: nil, captureElementText: config.captureElementText))
            #expect(event.value == "SYNTHETIC_BUTTON")
            #expect(event.getElementChain().contains("text=\"SYNTHETIC_BUTTON\""))
        }

        @Test("No-text mode strips target and ancestor text but preserves labels and geometry")
        func removesAncestorText() throws {
            let ancestor = UIButton()
            ancestor.setTitle("SYNTHETIC_ANCESTOR", for: .normal)
            ancestor.postHogLabel = "stable-parent"
            let button = UIButton()
            button.setTitle("SYNTHETIC_CHILD", for: .normal)
            button.postHogLabel = "stable-child"
            ancestor.addSubview(button)
            let location = CGPoint(x: 12, y: 24)
            let original = try #require(button.eventData(touchCoordinates: location, captureElementText: true))
            let privateEvent = try #require(button.eventData(touchCoordinates: location, captureElementText: false))
            #expect(original.getElementChain().contains("SYNTHETIC_ANCESTOR"))
            #expect(original.value == "SYNTHETIC_CHILD")
            #expect(privateEvent.value == nil)
            let allTextEmpty = privateEvent.viewHierarchy.allSatisfy(\.text.isEmpty)
            #expect(allTextEmpty)
            #expect(privateEvent.viewHierarchy.map(\.targetClass) == original.viewHierarchy.map(\.targetClass))
            #expect(privateEvent.touchCoordinates == location)
            #expect(privateEvent.getElementChain().contains("stable-parent"))
            #expect(privateEvent.getElementChain().contains("stable-child"))
            #expect(!privateEvent.getElementChain().contains("SYNTHETIC"))
            #expect(original.getElementChain(captureElementText: false) == privateEvent.getElementChain())
        }

        @Test("No-text mode never reads control text, including ancestors")
        func doesNotReadText() throws {
            let parent = TextReadCountingView()
            let child = TextReadCountingView()
            parent.addSubview(child)
            _ = try #require(child.eventData(touchCoordinates: nil, captureElementText: false))
            #expect(child.reads == 0)
            #expect(parent.reads == 0)
            _ = try #require(child.eventData(touchCoordinates: nil, captureElementText: true))
            #expect(child.reads > 0)
            #expect(parent.reads > 0)
        }

        @Test("Ordinary inputs and selected control values are omitted only in no-text mode")
        func removesInputAndSelectionValues() throws {
            let field = UITextField()
            field.text = "SYNTHETIC_FIELD"
            let textView = UITextView()
            textView.text = "SYNTHETIC_TEXT_VIEW"
            let segments = UISegmentedControl(items: ["SYNTHETIC_FIRST", "SYNTHETIC_SECOND"])
            segments.selectedSegmentIndex = 1
            let slider = UISlider()
            slider.value = 0.75
            let stepper = UIStepper()
            stepper.value = 7
            let toggle = UISwitch()
            toggle.isOn = true
            let picker = UIPickerView()
            let pickerDelegate = SyntheticPickerDelegate()
            picker.dataSource = pickerDelegate
            picker.delegate = pickerDelegate
            picker.selectRow(1, inComponent: 0, animated: false)

            for view in [field, textView, segments, slider, stepper, toggle, picker] as [UIView] {
                view.postHogLabel = "stable-control"
                let original = try #require(view.eventData(touchCoordinates: nil, captureElementText: true))
                let privateEvent = try #require(view.eventData(touchCoordinates: nil, captureElementText: false))
                #expect(original.value?.isEmpty == false)
                #expect(original.getElementChain().contains("text="))
                #expect(privateEvent.value == nil)
                #expect(!privateEvent.getElementChain().contains("text="))
                #expect(privateEvent.getElementChain().contains("stable-control"))
                #expect(privateEvent.debounceInterval == original.debounceInterval)
            }
        }

        @Test("Existing exclusion rules still apply in both modes", arguments: [true, false])
        func exclusions(captureText: Bool) {
            let secureField = UITextField()
            secureField.isSecureTextEntry = true
            #expect(secureField.eventData(touchCoordinates: nil, captureElementText: captureText) == nil)
            let sensitiveField = UITextField()
            sensitiveField.textContentType = .emailAddress
            #expect(sensitiveField.eventData(touchCoordinates: nil, captureElementText: captureText) == nil)
            let excluded = UIButton()
            excluded.accessibilityIdentifier = "ph-no-capture"
            #expect(excluded.eventData(touchCoordinates: nil, captureElementText: captureText) == nil)
        }

        @Test("Pipeline preserves default text, respects no-text, and stops on opt-out and close", arguments: [true, false])
        func pipeline(captureText: Bool) throws {
            let server = MockPostHogServer()
            server.start()
            defer { server.stop() }
            let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
            config.captureElementInteractions = true
            config.captureElementText = captureText
            config.captureScreenViews = false
            config.captureApplicationLifecycleEvents = false
            config.preloadFeatureFlags = false
            config.disableQueueTimerForTesting = true
            config.disableFlushOnBackgroundForTesting = true
            config.persistOptOut = false
            PostHogStorage(config).reset()
            let recorded = RecordedEvents()
            config.setBeforeSend { event in
                recorded.append(event)
                return nil
            }
            let sdk = PostHogSDK.with(config)
            defer {
                sdk.close()
                deleteSafely(applicationSupportDirectoryURL())
            }
            let integration = try #require(sdk.getAutocaptureIntegration())
            let field = UITextField()
            field.text = "SYNTHETIC_INPUT"
            field.postHogLabel = "stable-input"
            #expect(field.eventData?.value == (captureText ? "SYNTHETIC_INPUT" : nil))

            // One editing notification must emit exactly one event in either mode.
            let notification = NSNotification(name: UITextField.textDidEndEditingNotification, object: field)
            PostHogAutocaptureEventTracker.didEndEditing(notification)
            let events = recorded.events.filter { $0.event == "$autocapture" }
            #expect(events.count == 1)
            let event = try #require(events.first)
            let chain = try #require(event.properties["$elements_chain"] as? String)
            #expect(chain.contains("SYNTHETIC_INPUT") == captureText)
            #expect(chain.contains("stable-input"))
            #expect(event.properties["$event_type"] as? String == "change")

            sdk.capture("synthetic manual", properties: ["text": "SYNTHETIC_MANUAL"])
            #expect(recorded.events.last?.properties["text"] as? String == "SYNTHETIC_MANUAL")

            let pending = try #require(field.eventData)
            sdk.optOut()
            let count = recorded.events.count
            integration.process(source: .notification(name: "change"), event: pending)
            #expect(recorded.events.count == count)
            #expect(PostHogAutocaptureEventTracker.eventProcessor == nil)
            sdk.optIn()
            #expect(PostHogAutocaptureEventTracker.eventProcessor?.captureElementText == captureText)
            sdk.close()
            let closedCount = recorded.events.count
            integration.process(source: .notification(name: "change"), event: pending)
            #expect(recorded.events.count == closedCount)
            #expect(PostHogAutocaptureEventTracker.eventProcessor == nil)
        }
    }

    private final class TextReadCountingView: UIView {
        var reads = 0
        override var ph_autocaptureText: String? {
            reads += 1
            return "SYNTHETIC_READ"
        }
    }

    private final class SyntheticPickerDelegate: NSObject, UIPickerViewDelegate, UIPickerViewDataSource {
        func numberOfComponents(in _: UIPickerView) -> Int {
            1
        }
        func pickerView(_: UIPickerView, numberOfRowsInComponent _: Int) -> Int {
            2
        }
        func pickerView(_: UIPickerView, titleForRow row: Int, forComponent _: Int) -> String? {
            "SYNTHETIC_PICKER_\(row)"
        }
    }

    private final class RecordedEvents {
        private let lock = NSLock()
        private var storage: [PostHogEvent] = []
        var events: [PostHogEvent] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func append(_ event: PostHogEvent) {
            lock.lock()
            defer { lock.unlock() }
            storage.append(event)
        }
    }
#endif
