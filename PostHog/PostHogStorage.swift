//
//  PostHogStorage.swift
//  PostHog
//
//  Created by Ben White on 08.02.23.
//

import Foundation

/**
 # Storage

 Note for tvOS:
 As tvOS restricts access to persisted Application Support directory, we use Library/Caches instead for storage

 If needed, we can use UserDefaults for lightweight data - according to Apple, you can use UserDefaults to persist up to 500KB of data on tvOS
 see: https://developer.apple.com/forums/thread/16967?answerId=50696022#50696022
 */
func applicationSupportDirectoryURL() -> URL {
    #if os(tvOS)
        // tvOS restricts access to Application Support directory on physical devices
        // Use Library/Caches directory which may have less frequent eviction behavior than temp (which is purged when the app quits)
        let searchPath: FileManager.SearchPathDirectory = .cachesDirectory
    #else
        let searchPath: FileManager.SearchPathDirectory = .applicationSupportDirectory
    #endif

    let url = FileManager.default.urls(for: searchPath, in: .userDomainMask).first!
    let bundleIdentifier = getBundleIdentifier()

    return url.appendingPathComponent(bundleIdentifier)
}

/**

 From Apple Docs:
 In iOS, the value is nil when the group identifier is invalid. In macOS, a URL of the expected form is always
 returned, even if the app group is invalid, so be sure to test that you can access the underlying directory
 before attempting to use it.

 MacOS: The system also creates the Library/Application Support, Library/Caches, and Library/Preferences
 subdirectories inside the group directory the first time you use it
 iOS: The system creates only the Library/Caches subdirectory automatically

  see: https://developer.apple.com/documentation/foundation/filemanager/1412643-containerurl/
  */
func appGroupContainerUrl(config: PostHogConfig) -> URL? {
    guard let appGroupIdentifier = config.appGroupIdentifier else { return nil }

    #if os(tvOS)
        // tvOS: Due to stricter sandbox rules, creating "Application Support" directory is not possible on tvOS
        let librarySubPath = "Library/Caches/"
    #else
        let librarySubPath = "Library/Application Support/"
    #endif

    let libraryUrl = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
        .appendingPathComponent(librarySubPath)

    guard let url = libraryUrl?.appendingPathComponent(appGroupIdentifier) else { return nil }

    createDirectoryAtURLIfNeeded(url: url)

    // Merges a legacy container (using bundleIdentifier) into the new container using appGroupIdentifier
    mergeLegacyContainerIfNeeded(within: libraryUrl, to: url)

    return directoryExists(url) ? url : nil
}

func getBundleIdentifier() -> String {
    #if TESTING // only visible to test targets
        return Bundle.main.bundleIdentifier ?? "com.posthog.test"
    #else
        return Bundle.main.bundleIdentifier!
    #endif
}

/**
 Merges content from a legacy container directory into the current app group container.

 This function handles the migration of PostHog data from the old storage location (using `bundleIdentifier`)
 to the new app group shared container location (using `appGroupIdentifier`).

 Migration rules:
 - Files that already exist at the destination are skipped (no overwrite)
 - The anonymousId from the first processed container (legacy or current) is preserved to maintain user identity
 - Successfully migrated files are deleted from the source
 - Empty directories are cleaned up after migration
 - The entire folder structure is preserved during migration

 - Parameters:
   - libraryUrl: The base library URL where both legacy and new containers might exist
   - destinationUrl: The target app group container URL where files should be migrated
 */
func mergeLegacyContainerIfNeeded(within libraryUrl: URL?, to destinationUrl: URL) {
    let bundleIdentifier = getBundleIdentifier()
    guard let sourceUrl = libraryUrl?.appendingPathComponent(bundleIdentifier), directoryExists(sourceUrl) else {
        return
    }

    hedgeLog("Legacy folder found at \(sourceUrl), merging...")

    // Migrate all contents from the legacy container
    migrateDirectoryContents(from: sourceUrl, to: destinationUrl)

    // Try to remove the source directory if it's empty
    if removeIfEmpty(sourceUrl) {
        hedgeLog("Successfully migrated and removed legacy folder at \(sourceUrl)")
    }
}

/**
 Removes a directory if it's empty.

 - Parameters:
   - url: The directory URL to potentially remove
 - Returns: `true` if the directory was removed, `false` otherwise
 */
@discardableResult
func removeIfEmpty(_ url: URL) -> Bool {
    let remainingItems = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
    if remainingItems?.isEmpty == true {
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            hedgeLog("Failed to remove empty directory at \(url.path): \(error)")
        }
    }
    return false
}

/**
 Migrates a single file from source to destination.

 Migration rules:
 - If the file doesn't exist at destination, it's copied and then deleted from source
 - If the file already exists at destination, only the source file is deleted

 - Parameters:
   - sourceFile: The source file URL
   - destinationFile: The destination file URL
 - Throws: Any errors that occur during file operations
 */
func migrateFile(from sourceFile: URL, to destinationFile: URL) throws {
    if !FileManager.default.fileExists(atPath: destinationFile.path) {
        try FileManager.default.copyItem(at: sourceFile, to: destinationFile)
    }
    // Always delete source file after processing (whether copied or skipped)
    try FileManager.default.removeItem(at: sourceFile)
}

/**
 Recursively migrates all contents from a source directory to a destination directory.

 - Parameters:
   - sourceDir: The source directory URL
   - destinationDir: The destination directory URL
 */
func migrateDirectoryContents(from sourceDir: URL, to destinationDir: URL) {
    do {
        // Create destination directory if it doesn't exist (we need to call this here again as the function is recursive)
        createDirectoryAtURLIfNeeded(url: destinationDir)

        // Get all items in source directory
        let items = try FileManager.default.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil, options: [])

        for item in items {
            let destinationItem = destinationDir.appendingPathComponent(item.lastPathComponent)

            // Check if it's a directory
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    // Recursively migrate subdirectory (preserving the folder structure)
                    migrateDirectoryContents(from: item, to: destinationItem)
                    // Remove empty directory after migration
                    removeIfEmpty(item)
                } else {
                    // Migrate file
                    do {
                        try migrateFile(from: item, to: destinationItem)
                    } catch {
                        hedgeLog("Failed to migrate file from \(item.path) to \(destinationItem.path): \(error)")
                    }
                }
            }
        }
    } catch {
        hedgeLog("Error reading directory contents at \(sourceDir.path): \(error)")
    }
}

class PostHogStorage {
    // when adding or removing items here, make sure to update the reset method
    enum StorageKey: String, CaseIterable {
        case distinctId = "posthog.distinctId"
        case anonymousId = "posthog.anonymousId"
        case queue = "posthog.queueFolder" // NOTE: This is different to posthog-ios v2
        case oldQeueue = "posthog.queue.plist"
        case replayQeueue = "posthog.replayFolder"
        case enabledFeatureFlags = "posthog.enabledFeatureFlags"
        case enabledFeatureFlagPayloads = "posthog.enabledFeatureFlagPayloads"
        case flags = "posthog.flags"
        case groups = "posthog.groups"
        case registerProperties = "posthog.registerProperties"
        case optOut = "posthog.optOut"
        case sessionReplay = "posthog.sessionReplay"
        case isIdentified = "posthog.isIdentified"
        case personProcessingEnabled = "posthog.enabledPersonProcessing"
        case remoteConfig = "posthog.remoteConfig"
        case surveySeen = "posthog.surveySeen"
        case requestId = "posthog.requestId"
        case personPropertiesForFlags = "posthog.personPropertiesForFlags"
        case groupPropertiesForFlags = "posthog.groupPropertiesForFlags"
    }

    // The location for storing data that we always want to keep
    let appFolderUrl: URL

    init(_ config: PostHogConfig) {
        appFolderUrl = Self.getAppFolderUrl(from: config)

        // migrate legacy storage if needed
        Self.migrateLegacyStorage(from: config, to: appFolderUrl)
    }

    func url(forKey key: StorageKey) -> URL {
        appFolderUrl.appendingPathComponent(key.rawValue)
    }

    // The "data" methods are the core for storing data and differ between Modes
    // All other typed storage methods call these
    private func getData(forKey: StorageKey) -> Data? {
        let url = url(forKey: forKey)

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                return try Data(contentsOf: url)
            }
        } catch {
            hedgeLog("Error reading data from key \(forKey): \(error)")
        }
        return nil
    }

    private func setData(forKey: StorageKey, contents: Data?) {
        var url = url(forKey: forKey)

        do {
            if contents == nil {
                deleteSafely(url)
                return
            }

            try contents?.write(to: url)

            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try url.setResourceValues(resourceValues)
        } catch {
            hedgeLog("Failed to write data for key '\(forKey)' error: \(error)")
        }
    }

    private func getJson(forKey key: StorageKey) -> Any? {
        guard let data = getData(forKey: key) else { return nil }

        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            hedgeLog("Failed to serialize key '\(key)' error: \(error)")
        }
        return nil
    }

    private func setJson(forKey key: StorageKey, json: Any) {
        var jsonObject: Any?

        if let dictionary = json as? [AnyHashable: Any] {
            jsonObject = dictionary
        } else if let array = json as? [Any] {
            jsonObject = array
        } else {
            // TRICKY: This is weird legacy behaviour storing the data as a dictionary
            jsonObject = [key.rawValue: json]
        }

        var data: Data?
        do {
            data = try JSONSerialization.data(withJSONObject: jsonObject!)
        } catch {
            hedgeLog("Failed to serialize key '\(key)' error: \(error)")
        }
        setData(forKey: key, contents: data)
    }

    /**
     There are cases where applications using posthog-ios want to share analytics data between host app and
     an app extension, Widget or App Clip. If there's a defined `appGroupIdentifier` in configuration,
     we want to use a shared container for storing data so that extensions correctly identify a user (and batch process events)
     */
    private static func getBaseAppFolderUrl(from configuration: PostHogConfig) -> URL {
        appGroupContainerUrl(config: configuration) ?? applicationSupportDirectoryURL()
    }

    private static func migrateItem(at sourceUrl: URL, to destinationUrl: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: sourceUrl.path) else { return }
        // Copy file or directory over (if it doesn't exist)
        if !fileManager.fileExists(atPath: destinationUrl.path) {
            try fileManager.copyItem(at: sourceUrl, to: destinationUrl)
        }
    }

    private static func migrateLegacyStorage(from configuration: PostHogConfig, to apiDir: URL) {
        let legacyUrl = getBaseAppFolderUrl(from: configuration)
        if directoryExists(legacyUrl) {
            let fileManager = FileManager.default

            // Migrate old files that correspond to StorageKey values
            for storageKey in StorageKey.allCases {
                let legacyFileUrl = legacyUrl.appendingPathComponent(storageKey.rawValue)
                let newFileUrl = apiDir.appendingPathComponent(storageKey.rawValue)

                do {
                    // Migrate the item and its contents if it exists
                    try migrateItem(at: legacyFileUrl, to: newFileUrl, fileManager: fileManager)
                } catch {
                    hedgeLog("Error during storage migration for file \(storageKey.rawValue) at path \(legacyFileUrl.path): \(error)")
                }

                // Remove the legacy item after successful migration
                if fileManager.fileExists(atPath: legacyFileUrl.path) {
                    do {
                        try fileManager.removeItem(at: legacyFileUrl)
                    } catch {
                        hedgeLog("Could not delete file \(storageKey.rawValue) at path \(legacyFileUrl.path): \(error)")
                    }
                }
            }
        }
    }

    private static func getAppFolderUrl(from configuration: PostHogConfig) -> URL {
        let apiDir = getBaseAppFolderUrl(from: configuration)
            .appendingPathComponent(configuration.apiKey)

        createDirectoryAtURLIfNeeded(url: apiDir)

        return apiDir
    }

    func reset(keepAnonymousId: Bool = false) {
        // sadly the StorageKey.allCases does not work here
        deleteSafely(url(forKey: .distinctId))
        if !keepAnonymousId {
            deleteSafely(url(forKey: .anonymousId))
        }
        // .queue, .replayQeueue not needed since it'll be deleted by the queue.clear()
        deleteSafely(url(forKey: .oldQeueue))
        deleteSafely(url(forKey: .flags))
        deleteSafely(url(forKey: .enabledFeatureFlags))
        deleteSafely(url(forKey: .enabledFeatureFlagPayloads))
        deleteSafely(url(forKey: .groups))
        deleteSafely(url(forKey: .registerProperties))
        deleteSafely(url(forKey: .optOut))
        deleteSafely(url(forKey: .sessionReplay))
        deleteSafely(url(forKey: .isIdentified))
        deleteSafely(url(forKey: .personProcessingEnabled))
        deleteSafely(url(forKey: .remoteConfig))
        deleteSafely(url(forKey: .surveySeen))
        deleteSafely(url(forKey: .requestId))
        deleteSafely(url(forKey: .personPropertiesForFlags))
        deleteSafely(url(forKey: .groupPropertiesForFlags))
    }

    func remove(key: StorageKey) {
        let url = url(forKey: key)

        deleteSafely(url)
    }

    func getString(forKey key: StorageKey) -> String? {
        let value = getJson(forKey: key)
        if let stringValue = value as? String {
            return stringValue
        } else if let dictValue = value as? [String: String] {
            return dictValue[key.rawValue]
        }
        return nil
    }

    func setString(forKey key: StorageKey, contents: String) {
        setJson(forKey: key, json: contents)
    }

    func getDictionary(forKey key: StorageKey) -> [AnyHashable: Any]? {
        getJson(forKey: key) as? [AnyHashable: Any]
    }

    func setDictionary(forKey key: StorageKey, contents: [AnyHashable: Any]) {
        setJson(forKey: key, json: contents)
    }

    func getBool(forKey key: StorageKey) -> Bool? {
        let value = getJson(forKey: key)
        if let boolValue = value as? Bool {
            return boolValue
        } else if let dictValue = value as? [String: Bool] {
            return dictValue[key.rawValue]
        }
        return nil
    }

    func setBool(forKey key: StorageKey, contents: Bool) {
        setJson(forKey: key, json: contents)
    }
}
