//
//  PostHogStorageMergeTest.swift
//  PostHog
//
//  Created by Marcel Hoppe on 13.06.25.
//

import Foundation
@testable import PostHog
import Testing

@Suite("PostHogStorage app group merge tests", .serialized)
class PostHogStorageMergeTest {
    let testApiKey = "test_merge_api_key"
    var baseUrl: URL!
    var fileManager: FileManager!

    init() {
        // Set up base URL
        baseUrl = applicationSupportDirectoryURL()

        // Clean up any existing test directories
        fileManager = FileManager.default
        cleanUpTestDirectories()
    }

    deinit {
        // Clean up after tests
        cleanUpTestDirectories()
    }

    private func cleanUpTestDirectories() {
        // Clean up both potential locations using the test constants
        let legacyUrl = baseUrl.appendingPathComponent(testBundleIdentifier)
        let appGroupUrl = baseUrl.appendingPathComponent(testAppGroupIdentifier)

        try? fileManager.removeItem(at: legacyUrl)
        try? fileManager.removeItem(at: appGroupUrl)
        try? fileManager.removeItem(at: baseUrl.appendingPathComponent(testApiKey))
    }

    private func calculateFileHash(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        var hasher = Hasher()
        hasher.combine(data)
        return String(hasher.finalize())
    }

    private func createFile(at directory: URL, fileName: String, content: Data) throws -> String {
        // Ensure directory exists
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }

        // Create the file
        let fileUrl = directory.appendingPathComponent(fileName)
        // Check if file exists first
        if !fileManager.fileExists(atPath: fileUrl.path) {
            try content.write(to: fileUrl, options: .atomic)
        }

        // Verify file was created
        guard fileManager.fileExists(atPath: fileUrl.path) else {
            throw NSError(domain: "PostHogTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create file"])
        }

        return try calculateFileHash(fileUrl)
    }

    private func createLegacyFile(bundleId: String, apiKey: String, fileName: String, content: Data) throws -> String {
        let bundleDir = baseUrl.appendingPathComponent(bundleId)
        let apiKeyDir = bundleDir.appendingPathComponent(apiKey)
        return try createFile(at: apiKeyDir, fileName: fileName, content: content)
    }

    private func createAppGroupFile(appGroupId: String, apiKey: String, fileName: String, content: Data) throws -> String {
        let appGroupDir = baseUrl.appendingPathComponent(appGroupId)
        let apiKeyDir = appGroupDir.appendingPathComponent(apiKey)
        return try createFile(at: apiKeyDir, fileName: fileName, content: content)
    }

    @Test("test app group container merge detection")
    func appGroupContainerMergeDetection() throws {
        // This test verifies that the merge detection logic works correctly
        // by setting up files in the legacy location and checking if they would be detected

        // Create a file in the legacy bundle identifier location
        let fileContent = "test_content".data(using: .utf8)!
        _ = try createLegacyFile(
            bundleId: testBundleIdentifier,
            apiKey: testApiKey,
            fileName: "test_file.txt",
            content: fileContent
        )

        // Verify legacy file exists
        let legacyFileUrl = baseUrl
            .appendingPathComponent(testBundleIdentifier)
            .appendingPathComponent(testApiKey)
            .appendingPathComponent("test_file.txt")
        #expect(fileManager.fileExists(atPath: legacyFileUrl.path))

        // Note: We can't fully test the app group container URL creation without proper entitlements,
        // but we've verified that files in the legacy location are set up correctly for migration
    }

    @Test("test merge legacy container function")
    func mergeLegacyContainerFunction() throws {
        // Test the actual mergeLegacyContainerIfNeeded function

        // Create legacy files
        let fileContent = "test_user_123".data(using: .utf8)!
        _ = try createLegacyFile(
            bundleId: testBundleIdentifier,
            apiKey: testApiKey,
            fileName: PostHogStorage.StorageKey.distinctId.rawValue,
            content: fileContent
        )

        // Create destination URL
        let destinationUrl = baseUrl.appendingPathComponent(testAppGroupIdentifier)

        // Call the actual function
        mergeLegacyContainerIfNeeded(within: baseUrl, to: destinationUrl)

        // Verify file was migrated
        let migratedFileUrl = destinationUrl
            .appendingPathComponent(testApiKey)
            .appendingPathComponent(PostHogStorage.StorageKey.distinctId.rawValue)
        #expect(fileManager.fileExists(atPath: migratedFileUrl.path))

        // Verify legacy file was removed
        let legacyFileUrl = baseUrl
            .appendingPathComponent(testBundleIdentifier)
            .appendingPathComponent(testApiKey)
            .appendingPathComponent(PostHogStorage.StorageKey.distinctId.rawValue)
        #expect(!fileManager.fileExists(atPath: legacyFileUrl.path))
    }

    @Test("test file migration with existing files")
    func fileMigrationWithExistingFiles() throws {
        let sourceDir = baseUrl.appendingPathComponent(testBundleIdentifier).appendingPathComponent(testApiKey)
        let destDir = baseUrl.appendingPathComponent(testAppGroupIdentifier).appendingPathComponent(testApiKey)

        // Create test files in source
        let file1Content = "file1_content".data(using: .utf8)!
        let file1Hash = try createFile(at: sourceDir, fileName: "file1.txt", content: file1Content)

        let file2Content = "file2_content".data(using: .utf8)!
        _ = try createFile(at: sourceDir, fileName: "file2.txt", content: file2Content)

        // Create existing file in destination (should not be overwritten)
        let existingContent = "existing_content".data(using: .utf8)!
        let existingHash = try createFile(at: destDir, fileName: "file2.txt", content: existingContent)

        // Use the actual migrateDirectoryContents function
        migrateDirectoryContents(from: sourceDir, to: destDir)

        // Verify file1 was migrated
        let migratedFile1 = destDir.appendingPathComponent("file1.txt")
        #expect(fileManager.fileExists(atPath: migratedFile1.path))
        let migratedFile1Hash = try calculateFileHash(migratedFile1)
        #expect(migratedFile1Hash == file1Hash)

        // Verify file2 was not overwritten
        let existingFile2 = destDir.appendingPathComponent("file2.txt")
        let currentFile2Hash = try calculateFileHash(existingFile2)
        #expect(currentFile2Hash == existingHash)

        // Verify source files were removed
        #expect(!fileManager.fileExists(atPath: sourceDir.appendingPathComponent("file1.txt").path))
        #expect(!fileManager.fileExists(atPath: sourceDir.appendingPathComponent("file2.txt").path))
    }

    @Test("test nested directory migration")
    func nestedDirectoryMigration() throws {
        let sourceDir = baseUrl.appendingPathComponent(testBundleIdentifier).appendingPathComponent(testApiKey)
        let destDir = baseUrl.appendingPathComponent(testAppGroupIdentifier).appendingPathComponent(testApiKey)

        // Create nested structure
        let queueDir = sourceDir.appendingPathComponent(PostHogStorage.StorageKey.queue.rawValue)
        let event1 = try JSONSerialization.data(withJSONObject: ["event": "test1"])
        let event1Hash = try createFile(at: queueDir, fileName: "event1.json", content: event1)

        let replayDir = sourceDir.appendingPathComponent(PostHogStorage.StorageKey.replayQeueue.rawValue)
        let replay1 = try JSONSerialization.data(withJSONObject: ["snapshot": "data1"])
        let replay1Hash = try createFile(at: replayDir, fileName: "replay1.json", content: replay1)

        // Use the actual migrateDirectoryContents function
        migrateDirectoryContents(from: sourceDir, to: destDir)

        // Verify nested structure was preserved
        let migratedQueueFile = destDir
            .appendingPathComponent(PostHogStorage.StorageKey.queue.rawValue)
            .appendingPathComponent("event1.json")
        #expect(fileManager.fileExists(atPath: migratedQueueFile.path))
        let migratedQueueHash = try calculateFileHash(migratedQueueFile)
        #expect(migratedQueueHash == event1Hash)

        let migratedReplayFile = destDir
            .appendingPathComponent(PostHogStorage.StorageKey.replayQeueue.rawValue)
            .appendingPathComponent("replay1.json")
        #expect(fileManager.fileExists(atPath: migratedReplayFile.path))
        let migratedReplayHash = try calculateFileHash(migratedReplayFile)
        #expect(migratedReplayHash == replay1Hash)

        // Verify source was cleaned up
        #expect(!fileManager.fileExists(atPath: queueDir.path))
        #expect(!fileManager.fileExists(atPath: replayDir.path))
    }

    @Test("test anonymous ID preservation")
    func anonymousIdPreservation() throws {
        let sourceDir = baseUrl.appendingPathComponent(testBundleIdentifier).appendingPathComponent(testApiKey)
        let destDir = baseUrl.appendingPathComponent(testAppGroupIdentifier).appendingPathComponent(testApiKey)

        // Create anonymous ID in destination (should be preserved)
        let existingAnonymousId = "existing_anonymous_123".data(using: .utf8)!
        let existingHash = try createFile(
            at: destDir,
            fileName: PostHogStorage.StorageKey.anonymousId.rawValue,
            content: existingAnonymousId
        )

        // Create different anonymous ID in source (should be skipped)
        let legacyAnonymousId = "legacy_anonymous_456".data(using: .utf8)!
        _ = try createFile(
            at: sourceDir,
            fileName: PostHogStorage.StorageKey.anonymousId.rawValue,
            content: legacyAnonymousId
        )

        // Create other files that should be migrated
        let distinctId = "user_789".data(using: .utf8)!
        let distinctIdHash = try createFile(
            at: sourceDir,
            fileName: PostHogStorage.StorageKey.distinctId.rawValue,
            content: distinctId
        )

        // Use the actual migrateDirectoryContents function
        migrateDirectoryContents(from: sourceDir, to: destDir)

        // Verify anonymous ID was preserved
        let anonymousIdFile = destDir.appendingPathComponent(PostHogStorage.StorageKey.anonymousId.rawValue)
        let currentHash = try calculateFileHash(anonymousIdFile)
        #expect(currentHash == existingHash)

        // Verify distinct ID was migrated
        let distinctIdFile = destDir.appendingPathComponent(PostHogStorage.StorageKey.distinctId.rawValue)
        #expect(fileManager.fileExists(atPath: distinctIdFile.path))
        let migratedDistinctIdHash = try calculateFileHash(distinctIdFile)
        #expect(migratedDistinctIdHash == distinctIdHash)

        // Verify source files were removed
        #expect(!fileManager.fileExists(atPath: sourceDir.appendingPathComponent(PostHogStorage.StorageKey.anonymousId.rawValue).path))
        #expect(!fileManager.fileExists(atPath: sourceDir.appendingPathComponent(PostHogStorage.StorageKey.distinctId.rawValue).path))
    }

    @Test("test removeIfEmpty function")
    func removeIfEmptyFunction() throws {
        // Test empty directory removal
        let emptyDir = baseUrl.appendingPathComponent("test_empty_dir")
        try fileManager.createDirectory(at: emptyDir, withIntermediateDirectories: true)

        let removed = removeIfEmpty(emptyDir)
        #expect(removed == true)
        #expect(!fileManager.fileExists(atPath: emptyDir.path))

        // Test non-empty directory (should not be removed)
        let nonEmptyDir = baseUrl.appendingPathComponent("test_non_empty_dir")
        try fileManager.createDirectory(at: nonEmptyDir, withIntermediateDirectories: true)
        let fileUrl = nonEmptyDir.appendingPathComponent("file.txt")
        try "content".data(using: .utf8)!.write(to: fileUrl)

        let notRemoved = removeIfEmpty(nonEmptyDir)
        #expect(notRemoved == false)
        #expect(fileManager.fileExists(atPath: nonEmptyDir.path))

        // Clean up
        try fileManager.removeItem(at: nonEmptyDir)
    }
}
