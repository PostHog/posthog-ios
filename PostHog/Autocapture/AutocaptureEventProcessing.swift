//
//  AutocaptureEventProcessing.swift
//  PostHog
//
//  Created by Yiannis Josephides on 22/10/2024.
//

#if os(iOS) || targetEnvironment(macCatalyst)
    import UIKit

    protocol AutocaptureEventProcessing: AnyObject {
        func process(source: PostHogAutocaptureIntegration.EventData.EventSource, event: PostHogAutocaptureIntegration.EventData)
    }

    class PostHogAutocaptureEventProcessor: AutocaptureEventProcessing {
        private static let viewHierarchyDelimiter = ";"

        private unowned var postHogInstance: PostHogSDK

        init(postHogInstance: PostHogSDK) {
            self.postHogInstance = postHogInstance
            PostHogAutocaptureIntegration.addEventProcessor(self)
        }

        deinit {
            PostHogAutocaptureIntegration.removeEventProcessor(self)
        }

        func process(source: PostHogAutocaptureIntegration.EventData.EventSource, event: PostHogAutocaptureIntegration.EventData) {
            
            let eventType: String = switch source {
            case let .actionMethod(description): description
            case let .gestureRecognizer(description): description
            case let .notification(name): name
            }

            var properties: [String: Any] = [:]

            if let screenName = event.screenName {
                properties["$screen_name"] = event.screenName
            }

            let elements = event.viewHierarchy.map { node in
                [
                    "text": node.text,
                    "tag_name": node.targetClass, // required
                    "order": node.index,
                    "attributes": [ // required
                        "attr__class": node.targetClass
                    ]
                ]
            }

            let elementsChain = event.viewHierarchy
                .map(\.description)
                .joined(separator: Self.viewHierarchyDelimiter)

            if let coordinates = event.touchCoordinates {
                properties["$touch_x"] = coordinates.x
                properties["$touch_y"] = coordinates.y
            }
            
            hedgeLog("autocaptured \"\(eventType)\" in \(elements.first!.description) with \(properties) ")

            postHogInstance.autocapture(
                eventType: eventType,
                elements: elements,
                elementsChain: elementsChain,
                properties: properties
            )
        }
    }
#endif
