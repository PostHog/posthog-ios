//
//  PostHogFileBackedQueueTest.swift
//  PostHogTests
//
//  Created by Manoel Aranda Neto on 30.10.23.
//

import Foundation
@testable import PostHog
import Testing

@Suite("PostHogFileBackedQueue Tests")
struct PostHogFileBackedQueueTest {
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

    func getBaseUrl() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent(UUID().uuidString)
    }

    func getSut(baseUrl: URL) -> PostHogFileBackedQueue {
        let oldURL = baseUrl.appendingPathComponent("oldQueue")
        let newURL = baseUrl.appendingPathComponent("queue")
        return PostHogFileBackedQueue(queue: newURL, oldQueue: oldURL)
    }

    @Test("create folder and init queue")
    func createFolderAndInitQueue() throws {
        let baseUrl = getBaseUrl()
        let sut = getSut(baseUrl: baseUrl)

        #expect(sut.depth == 0)
        #expect(FileManager.default.fileExists(atPath: sut.queue.path) == true)

        sut.clear()
        deleteSafely(baseUrl)
    }

    @Test("load cached files into memory")
    func loadCachedFilesIntoMemory() throws {
        let baseUrl = getBaseUrl()
        let newURL = baseUrl.appendingPathComponent("queue")
        try FileManager.default.createDirectory(atPath: newURL.path, withIntermediateDirectories: true)

        let eventURL = newURL.appendingPathComponent("1698236044.407")
        let eventsData = eventJson.data(using: .utf8)!
        try eventsData.write(to: eventURL)

        #expect(FileManager.default.fileExists(atPath: eventURL.path) == true)

        let sut = getSut(baseUrl: baseUrl)

        #expect(sut.depth == 1)
        let items = sut.peek(1)
        #expect(items.first != nil)

        sut.clear()
        deleteSafely(baseUrl)
    }

    @Test("delete from queue and disk")
    func deleteFromQueueAndDisk() throws {
        let baseUrl = getBaseUrl()
        let newURL = baseUrl.appendingPathComponent("queue")
        try FileManager.default.createDirectory(atPath: newURL.path, withIntermediateDirectories: true)

        let eventURL = newURL.appendingPathComponent("1698236044.407")
        let eventsData = eventJson.data(using: .utf8)!
        try eventsData.write(to: eventURL)

        #expect(FileManager.default.fileExists(atPath: eventURL.path) == true)

        let sut = getSut(baseUrl: baseUrl)

        sut.delete(index: 0)

        #expect(sut.depth == 0)
        #expect(FileManager.default.fileExists(atPath: eventURL.path) == false)

        sut.clear()
        deleteSafely(baseUrl)
    }

    @Test("pop from queue and disk")
    func popFromQueueAndDisk() throws {
        let baseUrl = getBaseUrl()
        let newURL = baseUrl.appendingPathComponent("queue")
        try FileManager.default.createDirectory(atPath: newURL.path, withIntermediateDirectories: true)

        let eventURL = newURL.appendingPathComponent("1698236044.407")
        let eventsData = eventJson.data(using: .utf8)!
        try eventsData.write(to: eventURL)

        #expect(FileManager.default.fileExists(atPath: eventURL.path) == true)

        let sut = getSut(baseUrl: baseUrl)

        sut.pop(1)

        #expect(sut.depth == 0)
        #expect(FileManager.default.fileExists(atPath: eventURL.path) == false)

        sut.clear()
        deleteSafely(baseUrl)
    }

    @Test("add to queue and disk")
    func addToQueueAndDisk() throws {
        let baseUrl = getBaseUrl()
        let newURL = baseUrl.appendingPathComponent("queue")
        try FileManager.default.createDirectory(atPath: newURL.path, withIntermediateDirectories: true)

        let eventsData = eventJson.data(using: .utf8)!

        let sut = getSut(baseUrl: baseUrl)

        sut.add(eventsData)

        let items = try FileManager.default.contentsOfDirectory(atPath: newURL.path)
        #expect(sut.depth == 1)
        #expect(items.count == 1)

        sut.clear()
        deleteSafely(baseUrl)
    }

    @Test("clear queue and disk")
    func clearQueueAndDisk() throws {
        let baseUrl = getBaseUrl()
        let newURL = baseUrl.appendingPathComponent("queue")
        try FileManager.default.createDirectory(atPath: newURL.path, withIntermediateDirectories: true)

        let eventsData = eventJson.data(using: .utf8)!

        let sut = getSut(baseUrl: baseUrl)

        sut.add(eventsData)
        sut.clear()

        let items = try FileManager.default.contentsOfDirectory(atPath: newURL.path)
        #expect(sut.depth == 0)
        #expect(items.count == 0)

        deleteSafely(baseUrl)
    }
}
