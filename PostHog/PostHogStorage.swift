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

    let bundleIdentifier = getBundleIdentifier()

    #if os(tvOS)
        // tvOS: Due to stricter sandbox rules, creating "Application Support" directory is not possible on tvOS
        let librarySubPath = "Library/Caches/"
    #else
        let librarySubPath = "Library/Application Support/"
    #endif

    let url = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
        .appendingPathComponent(librarySubPath)
        .appendingPathComponent(bundleIdentifier)

    if let url {
        createDirectoryAtURLIfNeeded(url: url)
        return directoryExists(url) ? url : nil
    }

    return nil
}

func getBundleIdentifier() -> String {
    #if TESTING // only visible to test targets
        return Bundle.main.bundleIdentifier ?? "com.posthog.test"
    #else
        return Bundle.main.bundleIdentifier!
    #endif
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
        case groups = "posthog.groups"
        case registerProperties = "posthog.registerProperties"
        case optOut = "posthog.optOut"
        case sessionReplay = "posthog.sessionReplay"
        case isIdentified = "posthog.isIdentified"
        case personProcessingEnabled = "posthog.enabledPersonProcessing"
    }

    // The location for storing data that we always want to keep
    let appFolderUrl: URL

    init(_ config: PostHogConfig) {
        appFolderUrl = Self.getAppFolderUrl(from: config)

        // migrate legacy storage if needed
        Self.migrateLegacyStorage(from: config, to: appFolderUrl)
    }

    public func url(forKey key: StorageKey) -> URL {
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

    public func reset() {
        // sadly the StorageKey.allCases does not work here
        deleteSafely(url(forKey: .distinctId))
        deleteSafely(url(forKey: .anonymousId))
        // .queue, .replayQeueue not needed since it'll be deleted by the queue.clear()
        deleteSafely(url(forKey: .oldQeueue))
        deleteSafely(url(forKey: .enabledFeatureFlags))
        deleteSafely(url(forKey: .enabledFeatureFlagPayloads))
        deleteSafely(url(forKey: .groups))
        deleteSafely(url(forKey: .registerProperties))
        deleteSafely(url(forKey: .optOut))
        deleteSafely(url(forKey: .sessionReplay))
        deleteSafely(url(forKey: .isIdentified))
        deleteSafely(url(forKey: .personProcessingEnabled))
    }

    public func remove(key: StorageKey) {
        let url = url(forKey: key)

        deleteSafely(url)
    }

    public func getString(forKey key: StorageKey) -> String? {
        let value = getJson(forKey: key)
        if let stringValue = value as? String {
            return stringValue
        } else if let dictValue = value as? [String: String] {
            return dictValue[key.rawValue]
        }
        return nil
    }

    public func setString(forKey key: StorageKey, contents: String) {
        setJson(forKey: key, json: contents)
    }

    public func getDictionary(forKey key: StorageKey) -> [AnyHashable: Any]? {
        getJson(forKey: key) as? [AnyHashable: Any]
    }

    public func setDictionary(forKey key: StorageKey, contents: [AnyHashable: Any]) {
        setJson(forKey: key, json: contents)
    }

    public func getBool(forKey key: StorageKey) -> Bool? {
        let value = getJson(forKey: key)
        if let boolValue = value as? Bool {
            return boolValue
        } else if let dictValue = value as? [String: Bool] {
            return dictValue[key.rawValue]
        }
        return nil
    }

    public func setBool(forKey key: StorageKey, contents: Bool) {
        setJson(forKey: key, json: contents)
    }
}
