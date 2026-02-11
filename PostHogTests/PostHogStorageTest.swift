//
//  PostHogStorageTest.swift
//  PostHogTests
//
//  Created by Ben White on 08.02.23.
//

import Foundation
@testable import PostHog
import Testing

@Suite("PostHogStorage Tests", .serialized)
class PostHogStorageTest {
    let storageTracker = TestStorageTracker()

    deinit {
        storageTracker.cleanup()
    }

    func getSut(config: PostHogConfig = PostHogConfig(apiKey: uniqueApiKey())) -> PostHogStorage {
        storageTracker.track(config)
        return PostHogStorage(config)
    }

    @Test("returns the application support dir URL")
    func returnsTheApplicationSupportDirURL() {
        let url = applicationSupportDirectoryURL()
        let expectedSuffix = ["Library", "Application Support", testBundleIdentifier]
        let actualSuffix = Array(url.pathComponents.suffix(expectedSuffix.count))
        #expect(actualSuffix == expectedSuffix)
    }

    @Test("returns the app group container dir URL")
    func returnsTheAppGroupContainerDirURL() {
        let config = PostHogConfig(apiKey: "123")
        config.appGroupIdentifier = testAppGroupIdentifier
        let url = appGroupContainerUrl(config: config)!

        let expectedSuffix = ["Library", "Application Support", testAppGroupIdentifier]
        let actualSuffix = Array(url.pathComponents.suffix(expectedSuffix.count))

        // positive check: must return the same url across the whole app group
        #expect(actualSuffix == expectedSuffix)

        // negative check: guard against using bundleIdentifier, prevents spawning
        // separate folders per bundle identifer within the app group folder
        #expect(!actualSuffix.contains(testBundleIdentifier))

        let groupContainerComponent = url.pathComponents[url.pathComponents.count - 5]
        #expect(["Group Containers", "AppGroup"].contains(groupContainerComponent))
    }

    @Test("creates a folder if none exists")
    func createsFolderIfNoneExists() throws {
        let fileManager = FileManager.default

        // Initialize storage which should create directory structure
        let sut = getSut()

        // Validate that folder structure was created
        #expect(fileManager.fileExists(atPath: sut.appFolderUrl.path))

        try? fileManager.removeItem(at: sut.appFolderUrl)

        // Clean up
        sut.reset()
    }

    @Test("Persists and loads string")
    func persistsAndLoadsString() {
        let sut = getSut()

        let str = "san francisco"
        sut.setString(forKey: .distinctId, contents: str)

        #expect(sut.getString(forKey: .distinctId) == str)

        sut.remove(key: .distinctId)
        #expect(sut.getString(forKey: .distinctId) == nil)

        sut.reset()
    }

    @Test("Persists and loads bool")
    func persistsAndLoadsBool() {
        let sut = getSut()

        sut.setBool(forKey: .optOut, contents: true)

        #expect(sut.getBool(forKey: .optOut) == true)

        sut.remove(key: .optOut)
        #expect(sut.getString(forKey: .optOut) == nil)

        sut.reset()
    }

    @Test("Persists and loads dictionary")
    func persistsAndLoadsDictionary() {
        let sut = getSut()

        let dict = [
            "san francisco": "tech",
            "new york": "finance",
            "paris": "fashion",
        ]
        sut.setDictionary(forKey: .distinctId, contents: dict)
        #expect(sut.getDictionary(forKey: .distinctId) as? [String: String] == dict)

        sut.remove(key: .distinctId)
        #expect(sut.getDictionary(forKey: .distinctId) == nil)

        sut.reset()
    }

    @Test("Saves file to disk and removes from disk")
    func savesFileToDiskAndRemovesFromDisk() throws {
        let sut = getSut()

        let url = sut.url(forKey: .distinctId)
        let isUrlReachable: () -> Bool = {
            (try? url.checkResourceIsReachable()) ?? false
        }

        #expect(isUrlReachable() == false)

        sut.setString(forKey: .distinctId, contents: "sloth")
        #expect(isUrlReachable() == true)

        sut.remove(key: .distinctId)
        #expect(isUrlReachable() == false)

        sut.reset()
    }

    @Test("writes to disk in an api key folder under application support directory")
    func writesToDiskInAnApiKeyFolderUnderApplicationSupportDirectory() {
        let config = PostHogConfig(apiKey: "test_key")
        storageTracker.track(config)
        let sut = PostHogStorage(config)
        let url = sut.appFolderUrl

        sut.setString(forKey: .distinctId, contents: "distinct_id_value")

        let expectedSuffix = ["Library", "Application Support", testBundleIdentifier, "test_key"]
        let actualSuffix = Array(url.pathComponents.suffix(expectedSuffix.count))
        #expect(expectedSuffix == actualSuffix)

        let fileManager = FileManager.default
        let fileUrl = url.appendingPathComponent(PostHogStorage.StorageKey.distinctId.rawValue)
        #expect(fileManager.fileExists(atPath: fileUrl.path))

        sut.remove(key: .distinctId)
        #expect(fileManager.fileExists(atPath: fileUrl.path) == false)

        sut.reset()
    }

    @Test("writes to disk in an api key folder under a group container directory")
    func writesToDiskInAnApiKeyFolderUnderGroupContainerDirectory() {
        let config = PostHogConfig(apiKey: "test_key")
        storageTracker.track(config)
        config.appGroupIdentifier = testAppGroupIdentifier
        let sut = PostHogStorage(config)
        let url = sut.appFolderUrl

        sut.setString(forKey: .distinctId, contents: "distinct_id_value")

        let expectedSuffix = ["Library", "Application Support", testAppGroupIdentifier, "test_key"]
        let actualSuffix = Array(url.pathComponents.suffix(expectedSuffix.count))
        #expect(expectedSuffix == actualSuffix)

        let groupContainerComponent = url.pathComponents[url.pathComponents.count - 6]
        #expect(["Group Containers", "AppGroup"].contains(groupContainerComponent))

        let fileManager = FileManager.default
        let fileUrl = url.appendingPathComponent(PostHogStorage.StorageKey.distinctId.rawValue)
        #expect(fileManager.fileExists(atPath: fileUrl.path))

        sut.remove(key: .distinctId)
        #expect(fileManager.fileExists(atPath: fileUrl.path) == false)

        sut.reset()
    }

    @Test("falls back to application support directory when app group identifier is not provided")
    func fallsBackToApplicationSupportDirectoryWhenAppGroupIdentifierIsNotProvided() {
        let config = PostHogConfig(apiKey: uniqueApiKey())
        storageTracker.track(config)
        config.appGroupIdentifier = nil
        let sut = PostHogStorage(config)
        let url = sut.appFolderUrl

        let expectedSuffix = ["Library", "Application Support", testBundleIdentifier, config.apiKey]
        let actualSuffix = Array(url.pathComponents.suffix(expectedSuffix.count))
        #expect(expectedSuffix == actualSuffix)

        let groupContainerComponent = url.pathComponents[url.pathComponents.count - 6]
        #expect(!["Group Containers", "AppGroup"].contains(groupContainerComponent))

        sut.reset()
    }
}
