//
//  PostHogFileBackedQueueTest.swift
//  PostHogTests
//
//  Created by Manoel Aranda Neto on 30.10.23.
//

import Foundation
import Nimble
@testable import PostHog
import Quick

class PostHogFileBackedQueueTest: QuickSpec {
    let eventJson =
        """
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
        """

    func getSut() -> PostHogFileBackedQueue {
        let baseUrl = applicationSupportDirectoryURL()
        let oldURL = baseUrl.appendingPathComponent("oldQueue")
        let newURL = baseUrl.appendingPathComponent("queue")

        return PostHogFileBackedQueue(queue: newURL, oldQueues: [oldURL])
    }

    override func spec() {
        it("create folder and init queue") {
            let sut = self.getSut()

            expect(sut.depth) == 0
            expect(FileManager.default.fileExists(atPath: sut.queue.path)) == true

            sut.clear()
        }

        it("load cached files into memory") {
            let baseUrl = applicationSupportDirectoryURL()
            let newURL = baseUrl.appendingPathComponent("queue")
            try FileManager.default.createDirectory(atPath: newURL.path, withIntermediateDirectories: true)

            let eventURL = newURL.appendingPathComponent("1698236044.407")
            let eventsData = self.eventJson.data(using: .utf8)!
            try eventsData.write(to: eventURL)

            expect(FileManager.default.fileExists(atPath: eventURL.path)) == true

            let sut = self.getSut()

            expect(sut.depth) == 1
            let items = sut.peek(1)
            expect(items.first) != nil

            sut.clear()
        }

        it("delete from queue and disk") {
            let baseUrl = applicationSupportDirectoryURL()
            let newURL = baseUrl.appendingPathComponent("queue")
            try FileManager.default.createDirectory(atPath: newURL.path, withIntermediateDirectories: true)

            let eventURL = newURL.appendingPathComponent("1698236044.407")
            let eventsData = self.eventJson.data(using: .utf8)!
            try eventsData.write(to: eventURL)

            expect(FileManager.default.fileExists(atPath: eventURL.path)) == true

            let sut = self.getSut()

            sut.delete(index: 0)

            expect(sut.depth) == 0
            expect(FileManager.default.fileExists(atPath: eventURL.path)) == false

            sut.clear()
        }

        it("pop from queue and disk") {
            let baseUrl = applicationSupportDirectoryURL()
            let newURL = baseUrl.appendingPathComponent("queue")
            try FileManager.default.createDirectory(atPath: newURL.path, withIntermediateDirectories: true)

            let eventURL = newURL.appendingPathComponent("1698236044.407")
            let eventsData = self.eventJson.data(using: .utf8)!
            try eventsData.write(to: eventURL)

            expect(FileManager.default.fileExists(atPath: eventURL.path)) == true

            let sut = self.getSut()

            sut.pop(1)

            expect(sut.depth) == 0
            expect(FileManager.default.fileExists(atPath: eventURL.path)) == false

            sut.clear()
        }

        it("add to queue and disk") {
            let baseUrl = applicationSupportDirectoryURL()
            let newURL = baseUrl.appendingPathComponent("queue")
            try FileManager.default.createDirectory(atPath: newURL.path, withIntermediateDirectories: true)

            let eventsData = self.eventJson.data(using: .utf8)!

            let sut = self.getSut()

            sut.add(eventsData)

            let items = try FileManager.default.contentsOfDirectory(atPath: newURL.path)
            expect(sut.depth) == 1
            expect(items.count) == 1

            sut.clear()
        }

        it("clear queue and disk") {
            let baseUrl = applicationSupportDirectoryURL()
            let newURL = baseUrl.appendingPathComponent("queue")
            try FileManager.default.createDirectory(atPath: newURL.path, withIntermediateDirectories: true)

            let eventsData = self.eventJson.data(using: .utf8)!

            let sut = self.getSut()

            sut.add(eventsData)
            sut.clear()

            let items = try FileManager.default.contentsOfDirectory(atPath: newURL.path)
            expect(sut.depth) == 0
            expect(items.count) == 0
        }

        it("loads and sorts files in chronological order") {
            let baseUrl = applicationSupportDirectoryURL()
            let newURL = baseUrl.appendingPathComponent("queue")
            try FileManager.default.createDirectory(atPath: newURL.path, withIntermediateDirectories: true)

            // Create files in expected order with delays to ensure distinct modification dates
            let file1 = newURL.appendingPathComponent("1698236044.407")
            try "event-1".data(using: .utf8)!.write(to: file1)
            Thread.sleep(forTimeInterval: 0.01)

            let file2 = newURL.appendingPathComponent("A1B2C3D4-E5F6-7890-ABCD-EF1234567890")
            try "event-2".data(using: .utf8)!.write(to: file2)
            Thread.sleep(forTimeInterval: 0.01)

            let file3 = newURL.appendingPathComponent("1698236046.789")
            try "event-3".data(using: .utf8)!.write(to: file3)
            Thread.sleep(forTimeInterval: 0.01)

            let file4 = newURL.appendingPathComponent("F1E2D3C4-B5A6-7890-1234-567890ABCDEF")
            try "event-4".data(using: .utf8)!.write(to: file4)
            Thread.sleep(forTimeInterval: 0.01)

            let file5 = newURL.appendingPathComponent("1698236045.123")
            try "event-5".data(using: .utf8)!.write(to: file5)
            Thread.sleep(forTimeInterval: 0.01)

            let file6 = newURL.appendingPathComponent("G1H2I3J4-K5L6-7890-1234-567890ABCDEF")
            try "event-6".data(using: .utf8)!.write(to: file6)

            // Initialize queue - should load and sort all files correctly
            let sut = self.getSut()

            // Verify FIFO order - sorted by modification date (oldest first)
            let items = sut.peek(6)
            expect(items.count) == 6
            expect(String(data: items[0], encoding: .utf8)) == "event-1"
            expect(String(data: items[1], encoding: .utf8)) == "event-2"
            expect(String(data: items[2], encoding: .utf8)) == "event-3"
            expect(String(data: items[3], encoding: .utf8)) == "event-4"
            expect(String(data: items[4], encoding: .utf8)) == "event-5"
            expect(String(data: items[5], encoding: .utf8)) == "event-6"

            sut.clear()
        }

        it("migrates files from old queue folder to new queue folder") {
            let baseUrl = applicationSupportDirectoryURL()
            let oldQueueFolder = baseUrl.appendingPathComponent("posthog.queueFolder")
            let newQueueFolder = baseUrl.appendingPathComponent("posthog.queueFolder.uuid")

            // Clean up any existing folders
            try? FileManager.default.removeItem(at: oldQueueFolder)
            try? FileManager.default.removeItem(at: newQueueFolder)

            // Create old queue folder with some files (simulating pre-3.49.0 SDK)
            try FileManager.default.createDirectory(at: oldQueueFolder, withIntermediateDirectories: true)

            let file1 = oldQueueFolder.appendingPathComponent("1698236044.407")
            try "event-1".data(using: .utf8)!.write(to: file1)

            let file2 = oldQueueFolder.appendingPathComponent("1698236045.123")
            try "event-2".data(using: .utf8)!.write(to: file2)

            let file3 = oldQueueFolder.appendingPathComponent("A1B2C3D4-E5F6-7890-ABCD-EF1234567890")
            try "event-3".data(using: .utf8)!.write(to: file3)

            expect(FileManager.default.fileExists(atPath: oldQueueFolder.path)) == true
            expect(FileManager.default.fileExists(atPath: newQueueFolder.path)) == false

            // Initialize queue with old folder as migration source
            let sut = PostHogFileBackedQueue(queue: newQueueFolder, oldQueues: [oldQueueFolder])

            // Verify migration happened
            expect(FileManager.default.fileExists(atPath: oldQueueFolder.path)) == false
            expect(FileManager.default.fileExists(atPath: newQueueFolder.path)) == true

            // Verify all files were migrated and are readable
            expect(sut.depth) == 3
            let items = sut.peek(3)
            expect(items.count) == 3

            // Verify content (order may vary based on modification date)
            let contents = items.map { String(data: $0, encoding: .utf8) }
            expect(contents).to(contain("event-1"))
            expect(contents).to(contain("event-2"))
            expect(contents).to(contain("event-3"))

            sut.clear()
        }
    }
}
