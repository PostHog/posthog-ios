//
//  PostHogStorageMigrationTest.swift
//  PostHog
//
//  Created by Yiannis Josephides on 04/02/2025.
//

import Foundation
@testable import PostHog
import Testing

@Suite("PostHogStorage migration tests", .serialized)
class PostHogStorageMigrationTest {
    let testApiKey = "test_migration_key"
    var legacyUrl: URL!
    var newBaseUrl: URL!
    var fileManager: FileManager!

    init() {
        // Set up base URLs
        legacyUrl = applicationSupportDirectoryURL()
        newBaseUrl = legacyUrl.appendingPathComponent(testApiKey)

        // Clean up any existing test directories
        fileManager = FileManager.default
        try? fileManager.removeItem(at: legacyUrl)
        try? fileManager.removeItem(at: newBaseUrl)
    }

    private func calculateFileHash(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        var hasher = Hasher()
        hasher.combine(data)
        return String(hasher.finalize())
    }

    private func createLegacyFile(_ fileName: String, content: Data) throws -> String {
        // Ensure legacy directory exists
        if !fileManager.fileExists(atPath: legacyUrl.path) {
            try fileManager.createDirectory(at: legacyUrl, withIntermediateDirectories: true, attributes: nil)
        }

        // Create the file
        let fileUrl = legacyUrl.appendingPathComponent(fileName)
        // Check if file exists first
        if !fileManager.fileExists(atPath: fileUrl.path) {
            try content.write(to: fileUrl, options: .atomic)
        }

        // Verify file was created
        guard fileManager.fileExists(atPath: fileUrl.path) else {
            throw NSError(domain: "PostHogTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create legacy file"])
        }

        return try calculateFileHash(fileUrl)
    }

    private func testMigratesSingleFile(forKey key: PostHogStorage.StorageKey, value: Any) throws {
        // Clean up any existing files first
        try? fileManager.removeItem(at: legacyUrl)
        try? fileManager.removeItem(at: newBaseUrl)

        var jsonObject: Any?

        if let dictionary = value as? [AnyHashable: Any] {
            jsonObject = dictionary
        } else if let array = value as? [Any] {
            jsonObject = array
        } else {
            jsonObject = [key.rawValue: value]
        }

        let data = try JSONSerialization.data(withJSONObject: jsonObject!)

        // Create the file in the legacy file location
        let originalHash = try createLegacyFile(key.rawValue, content: data)

        // Verify legacy file exists before migration
        let legacyFileUrl = legacyUrl.appendingPathComponent(key.rawValue)
        guard fileManager.fileExists(atPath: legacyFileUrl.path) else {
            throw NSError(domain: "PostHogTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Legacy file not found before migration"])
        }

        // Initialize storage which should trigger migration
        _ = PostHogStorage(PostHogConfig(apiKey: testApiKey))

        // Verify legacy file was removed
        #expect(!fileManager.fileExists(atPath: legacyFileUrl.path))

        // Verify file was migrated
        let newFileUrl = newBaseUrl.appendingPathComponent(key.rawValue)
        #expect(fileManager.fileExists(atPath: newFileUrl.path))

        let newFileHash = try calculateFileHash(newFileUrl)
        #expect(newFileHash == originalHash)
    }

    private func testMigratesQueue(forKey key: PostHogStorage.StorageKey, entries events: [PostHogEvent]) throws {
        // Create legacy queue directory with event files
        let queueDir = legacyUrl.appendingPathComponent(key.rawValue)
        try fileManager.createDirectory(at: queueDir, withIntermediateDirectories: true)

        // Save events to files and calculate their hashes
        var originalHashes: [(name: String, hash: String)] = []
        for (index, event) in events.enumerated() {
            let eventJson = event.toJSON()
            let eventData = try JSONSerialization.data(withJSONObject: eventJson)
            let eventFile = queueDir.appendingPathComponent("event_\(index + 1).json")
            try eventData.write(to: eventFile)
            try originalHashes.append((
                name: eventFile.lastPathComponent,
                hash: calculateFileHash(eventFile)
            ))
        }

        // Initialize storage which should trigger migration
        _ = PostHogStorage(PostHogConfig(apiKey: testApiKey))

        // Verify events were migrated correctly
        let newQueueUrl = newBaseUrl.appendingPathComponent(key.rawValue)
        let migratedFiles = try fileManager.contentsOfDirectory(at: newQueueUrl, includingPropertiesForKeys: nil)
        #expect(migratedFiles.count == events.count)

        // Verify file contents are identical by comparing hashes
        let migratedHashes = try migratedFiles
            .map { try (name: $0.lastPathComponent, hash: calculateFileHash($0)) }
            .sorted(by: { $0.name < $1.name })

        for (migratedHash, originalHash) in zip(migratedHashes, originalHashes) {
            #expect(migratedHash.name == originalHash.name)
            #expect(migratedHash.hash == originalHash.hash)
        }

        // Verify legacy queue directory was removed
        #expect(!fileManager.fileExists(atPath: queueDir.path))
    }

    @Test("migrates distinctId from legacy location")
    func migratesDistinctIdFileFromLegacyLocation() throws {
        try testMigratesSingleFile(forKey: .distinctId, value: "test_user_id")
    }

    @Test("migrates anonymousId from legacy location")
    func migratesAnonymousIdFileFromLegacyLocation() throws {
        try testMigratesSingleFile(forKey: .anonymousId, value: UUID().uuidString)
    }

    @Test("migrates optOut from legacy location")
    func migratesOptOutFileFromLegacyLocation() throws {
        try testMigratesSingleFile(forKey: .optOut, value: false)
    }

    @Test("migrates isIdentified from legacy location")
    func migratesIsIdentifiedFileFromLegacyLocation() throws {
        try testMigratesSingleFile(forKey: .isIdentified, value: true)
    }

    @Test("migrates personProcessingEnabled from legacy location")
    func migratesPersonProcessingEnabledFromLegacyLocation() throws {
        try testMigratesSingleFile(forKey: .personProcessingEnabled, value: true)
    }

    @Test("migrates registerProperties from legacy location")
    func migratesRegisterPropertiesFromLegacyLocation() throws {
        let value: [String: Any] = ["prop": true, "prop2": false, "prop4": "hello"]
        try testMigratesSingleFile(forKey: .registerProperties, value: value)
    }

    @Test("migrates groups from legacy location")
    func migratesGroupsFromLegacyLocation() throws {
        try testMigratesSingleFile(forKey: .groups, value: ["groupProp": "value1"])
    }

    @Test("migrates session replay key from legacy location")
    func migratesSessionReplayKeyFromLegacyLocation() throws {
        let value: [String: String] = [
            "endpoint": "/newS",
            "linkedFalg": "myRecordingFlag",
        ]

        try testMigratesSingleFile(forKey: .sessionReplay, value: value)
    }

    @Test("migrates enabledFeatureFlags from legacy location")
    func migratesEnabledFeatureFlagsFromLegacyLocation() throws {
        let value: [String: Bool] = [
            "fflag1": true,
            "fflag2": true,
        ]

        try testMigratesSingleFile(forKey: .enabledFeatureFlags, value: value)
    }

    @Test("migrates enabledFeatureFlagsPayloads from legacy location")
    func migratesEnabledFeatureFlagsPayloadFromLegacyLocation() throws {
        let value: [String: String] = [
            "fflag1": "{\"payload\": true}",
            "fflag2": "{\"payload\": false}",
        ]

        try testMigratesSingleFile(forKey: .enabledFeatureFlagPayloads, value: value)
    }

    @Test("migrates event queue files and preserves event data")
    func migratesEventQueueFilesAndPreservesEventData() async throws {
        // Create test events
        let originalEvents = [
            PostHogEvent(
                event: "test_event_1",
                distinctId: "user_123",
                properties: ["key1": "value1", "key2": 42],
                timestamp: Date(timeIntervalSince1970: 1707221234),
                uuid: UUID()
            ),
            PostHogEvent(
                event: "test_event_2",
                distinctId: "user_456",
                properties: ["key3": "value3", "$set": ["company": "PostHog"]],
                timestamp: Date(timeIntervalSince1970: 1707221235),
                uuid: UUID()
            ),
        ]

        try testMigratesQueue(forKey: .queue, entries: originalEvents)
    }

    @Test("migrates replay queue files and preserves snapshot data")
    func migratesReplayQueueFilesAndPreservesSnapshotData() async throws {
        // Create test snapshot events
        let sessionId = "test_session_123"
        let events = [
            PostHogEvent(
                event: "$snapshot",
                distinctId: "user_123",
                properties: [
                    "$snapshot_source": "mobile",
                    "$snapshot_data": [
                        [
                            "type": 6,
                            "data": [
                                "plugin": "rrweb/network@1",
                                "payload": [
                                    "requests": [
                                        [
                                            "url": "https://api.example.com/data",
                                            "method": "GET",
                                            "status": 200,
                                        ],
                                    ],
                                ],
                            ],
                            "timestamp": 1707221234000,
                        ],
                    ],
                    "$session_id": sessionId,
                ],
                timestamp: Date(timeIntervalSince1970: 1707221234000),
                uuid: UUID(),
                apiKey: "test_api_key_1"
            ),
            PostHogEvent(
                event: "$snapshot",
                distinctId: "user_123",
                properties: [
                    "$snapshot_source": "mobile",
                    "$snapshot_data": [
                        [
                            "type": 6,
                            "data": [
                                "plugin": "rrweb/network@1",
                                "payload": [
                                    "requests": [
                                        [
                                            "url": "https://api.example.com/users",
                                            "method": "POST",
                                            "status": 400,
                                        ],
                                    ],
                                ],
                            ],
                            "timestamp": 1707221235000,
                        ],
                    ],
                    "$session_id": sessionId,
                ],
                timestamp: Date(timeIntervalSince1970: 1707221235),
                uuid: UUID(),
                apiKey: "test_api_key_1"
            ),
        ]

        try testMigratesQueue(forKey: .replayQeueue, entries: events)
    }

    @Test("preserves non-posthog files in legacy directory")
    func preservesNonPostHogFilesInLegacyDirectory() async throws {
        // Create a legacy storage file and a non-posthog file
        let postHogFileContent = "test_user_id".data(using: .utf8)!
        let postHogFileHash = try createLegacyFile(PostHogStorage.StorageKey.distinctId.rawValue, content: postHogFileContent)
        let myAppData = "custom content".data(using: .utf8)!
        _ = try createLegacyFile("my.application.data", content: myAppData)

        // Initialize storage which should trigger migration
        _ = PostHogStorage(PostHogConfig(apiKey: testApiKey))

        // Verify storage file was migrated
        let newFileUrl = newBaseUrl.appendingPathComponent(PostHogStorage.StorageKey.distinctId.rawValue)
        let newFileHash = try calculateFileHash(newFileUrl)
        #expect(newFileHash == postHogFileHash)

        // Verify non-storage file remains in legacy location
        let customFileUrl = legacyUrl.appendingPathComponent("my.application.data")
        let customContent = try String(contentsOf: customFileUrl, encoding: .utf8)
        #expect(customContent == "custom content")

        // Verify legacy directory contains new posthog api dir + one non-posthog file
        #expect(fileManager.fileExists(atPath: legacyUrl.path))
        let legacyDirContents = try fileManager.contentsOfDirectory(atPath: legacyUrl.path).sorted()
        #expect(legacyDirContents.count == 2)
        #expect(legacyDirContents[0] == "my.application.data")
        #expect(legacyDirContents[1] == "test_migration_key")
    }
}
