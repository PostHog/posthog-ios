//
//  PostHogLegacyQueueTest.swift
//  PostHogTests
//
//  Created by Manoel Aranda Neto on 30.10.23.
//

import Foundation
import Nimble
@testable import PostHog
import Quick

class PostHogLegacyQueueTest: QuickSpec {
    override func spec() {
        it("migrate old queue to new queue") {
            let baseUrl = applicationSupportDirectoryURL()
            try FileManager.default.createDirectory(atPath: baseUrl.path, withIntermediateDirectories: true)

            let newURL = baseUrl.appendingPathComponent("queue")
            try FileManager.default.createDirectory(atPath: newURL.path, withIntermediateDirectories: true)

            let oldURL = baseUrl.appendingPathComponent("oldQueue")

            let eventsArray =
                """
                [
                  {
                    "properties": {
                      "$network_cellular": false,
                      "$groups": {
                        "some-group": "id:4"
                      },
                      "$app_build": 1,
                      "$os_name": "iOS",
                      "$feature/multivariant": "payload",
                      "$screen_width": 852,
                      "$app_version": "1.0",
                      "$device_type": "Mobile",
                      "$active_feature_flags__0": "multivariant",
                      "$feature/4535-funnel-bar-viz": true,
                      "$network_wifi": true,
                      "$timezone": "Europe/Vienna",
                      "$device_id": "48DA3429-495A-4903-B347-F096FC31C3AB",
                      "$active_feature_flags": [
                        "$feature/multivariant",
                        "$feature/testJson",
                        "$feature/4535-funnel-bar-viz",
                        "$feature/disabledFlag"
                      ],
                      "$active_feature_flags__3": "disabledFlag",
                      "$device_name": "iPhone",
                      "$app_name": "",
                      "$app_namespace": "com.posthog.CocoapodsExample",
                      "$locale": "en-US",
                      "$feature/disabledFlag": true,
                      "$active_feature_flags__1": "testJson",
                      "$screen_height": 393,
                      "$device_model": "arm64",
                      "$device_manufacturer": "Apple",
                      "$feature/testJson": "theInteger",
                      "$lib_version": "2.1.0",
                      "$os_version": "17.0.1",
                      "$lib": "posthog-ios",
                      "$active_feature_flags__2": "4535-funnel-bar-viz"
                    },
                    "timestamp": "2023-10-25T14:14:04.407Z",
                    "message_id": "5CE069F8-E967-4B47-9D89-207EF7519453",
                    "event": "Cocoapods Example Button",
                    "distinct_id": "Prateek"
                  }
                ]
                """

            let eventsData = eventsArray.data(using: .utf8)!
            try eventsData.write(to: oldURL)

            expect(FileManager.default.fileExists(atPath: oldURL.path)) == true

            migrateOldQueue(queue: newURL, oldQueue: oldURL)

            expect(FileManager.default.fileExists(atPath: oldURL.path)) == false

            let items = try FileManager.default.contentsOfDirectory(atPath: newURL.path)

            let eventURL = newURL.appendingPathComponent(items[0])
            expect(FileManager.default.fileExists(atPath: eventURL.path)) == true

            let eventData = try Data(contentsOf: eventURL)
            let eventObject = try JSONSerialization.jsonObject(with: eventData, options: .allowFragments) as? [String: Any]

            expect(eventObject!["distinct_id"] as? String) == "Prateek"
            expect(eventObject!["event"] as? String) == "Cocoapods Example Button"
            expect(eventObject!["message_id"] as? String) == "5CE069F8-E967-4B47-9D89-207EF7519453"
            expect(eventObject!["timestamp"] as? String) == "2023-10-25T14:14:04.407Z"
            expect(eventObject!["properties"] as? [String: Any]) != nil

            deleteSafely(oldURL)
            deleteSafely(newURL)
        }

        it("ignore and delete corrupted file") {
            let baseUrl = applicationSupportDirectoryURL()
            try FileManager.default.createDirectory(atPath: baseUrl.path, withIntermediateDirectories: true)

            let newURL = baseUrl.appendingPathComponent("queue")
            try FileManager.default.createDirectory(atPath: newURL.path, withIntermediateDirectories: true)

            let oldURL = baseUrl.appendingPathComponent("oldQueue")

            let eventsArray =
                """
                [
                  i am broken
                ]
                """

            let eventsData = eventsArray.data(using: .utf8)!
            try eventsData.write(to: oldURL)

            expect(FileManager.default.fileExists(atPath: oldURL.path)) == true

            migrateOldQueue(queue: newURL, oldQueue: oldURL)

            expect(FileManager.default.fileExists(atPath: oldURL.path)) == false

            let items = try FileManager.default.contentsOfDirectory(atPath: newURL.path)
            expect(items.isEmpty) == true

            deleteSafely(oldURL)
            deleteSafely(newURL)
        }
    }
}
