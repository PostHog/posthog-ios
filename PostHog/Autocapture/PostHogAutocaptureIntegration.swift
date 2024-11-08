//
//  PostHogAutocaptureIntegration.swift
//  PostHog
//
//  Created by Yiannis Josephides on 22/10/2024.
//

#if os(iOS) || targetEnvironment(macCatalyst)
    import UIKit

    class PostHogAutocaptureIntegration: AutocaptureEventProcessing {
        private let postHogConfig: PostHogConfig
        private var debounceTimers: [Int: Timer] = [:]

        init(_ config: PostHogConfig) {
            postHogConfig = config
        }

        /**
         Activates the autocapture integration by routing events from PostHogAutocaptureEventTracker to this instance.
         */
        func start() {
            PostHogAutocaptureEventTracker.eventProcessor = self
            hedgeLog("Autocapture integration started")
        }

        /**
         Disables the autocapture integration by clearing the PostHogAutocaptureEventTracker routing
         */
        func stop() {
            if PostHogAutocaptureEventTracker.eventProcessor != nil {
                PostHogAutocaptureEventTracker.eventProcessor = nil
                debounceTimers.values.forEach { $0.invalidate() }
                debounceTimers.removeAll()
                hedgeLog("Autocapture integration stopped")
            }
        }

        /**
         Processes an autocapture event, with optional debounce logic for controls that emit frequent events.

         - Parameters:
            - source: The source of the event (e.g., gesture recognizer, action method, or notification).
            - event: The autocapture event data, containing properties, screen name, and other metadata.

         If the event has a `debounceInterval` greater than 0, the event is debounced.
         This is useful for UIControls like `UISlider` that emit frequent value changes, ensuring only the last value is captured.
         The debounce interval is defined per UIControl by the `ph_autocaptureDebounceInterval` property of `AutoCapturable`
         */
        func process(source: PostHogAutocaptureEventTracker.EventSource, event: PostHogAutocaptureEventTracker.EventData) {
            guard PostHogSDK.shared.isAutocaptureActive() else {
                return
            }

            let eventHash = event.viewHierarchy.map(\.targetClass).hashValue
            // debounce frequent UIControl events (e.g., UISlider) to reduce event noise
            if event.debounceInterval > 0 {
                debounceTimers[eventHash]?.invalidate() // Keep cancelling existing
                debounceTimers[eventHash] = Timer.scheduledTimer(withTimeInterval: event.debounceInterval, repeats: false) { [weak self] _ in
                    self?.handleEventProcessing(source: source, event: event)
                    self?.debounceTimers.removeValue(forKey: eventHash) // Clean up once fired
                }
            } else {
                handleEventProcessing(source: source, event: event)
            }
        }

        private static let viewHierarchyDelimiter = ";"
        /**
         Handles the processing of autocapture events by extracting event details, building properties, and sending them to PostHog.

         - Parameters:
            - source: The source of the event (action method, gesture, or notification). Values are already mapped to `$event_type` earlier in the chain
            - event: The event data including view hierarchy, screen name, and other metadata.

         This function extracts event details such as the event type, view hierarchy, and touch coordinates.
         It creates a structured payload with relevant properties (e.g., tag_name, elements, element_chain) and sends it to the
         associated PostHog instance for further processing.
         */
        private func handleEventProcessing(source: PostHogAutocaptureEventTracker.EventSource, event: PostHogAutocaptureEventTracker.EventData) {
            let eventType: String = switch source {
            case let .actionMethod(description): description
            case let .gestureRecognizer(description): description
            case let .notification(name): name
            }

            var properties: [String: Any] = [:]

            if let screenName = event.screenName {
                properties["$screen_name"] = screenName
            }

            let elements = event.viewHierarchy.map { node -> [String: Any] in
                [
                    "text": node.text,
                    "tag_name": node.targetClass, // required
                    "order": node.index,
                    "attributes": [ // required
                        "attr__class": node.targetClass,
                    ],
                ].compactMapValues { $0 }
            }

            let elementsChain = event.viewHierarchy
                .map(\.description)
                .joined(separator: PostHogAutocaptureIntegration.viewHierarchyDelimiter)

            if let coordinates = event.touchCoordinates {
                properties["$touch_x"] = coordinates.x
                properties["$touch_y"] = coordinates.y
            }

            PostHogSDK.shared.autocapture(
                eventType: eventType,
                elements: elements,
                elementsChain: elementsChain,
                properties: properties
            )
        }
    }
#endif
