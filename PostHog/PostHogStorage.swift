//
//  PostHogStorage.swift
//  PostHog
//
//  Created by Ben White on 08.02.23.
//

import Foundation

/**
 # Storage

 posthog-ios stores data either to file or to UserDefaults in order to support tvOS. As recordings won't work on tvOS anyways and we have no tvOS users so far,
 we are opting to only support iOS via File storage.
 */

func applicationSupportDirectoryURL() -> URL {
    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return url.appendingPathComponent(Bundle.main.bundleIdentifier!)
}

class PostHogStorage {
    // when adding or removing items here, make sure to update the reset method
    enum StorageKey: String {
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
    }

    private let config: PostHogConfig

    // The location for storing data that we always want to keep
    let appFolderUrl: URL

    init(_ config: PostHogConfig) {
        self.config = config

        appFolderUrl = applicationSupportDirectoryURL() // .appendingPathComponent(config.apiKey)

        createDirectoryAtURLIfNeeded(url: appFolderUrl)
    }

    private func createDirectoryAtURLIfNeeded(url: URL) {
        if FileManager.default.fileExists(atPath: url.path) { return }
        do {
            try FileManager.default.createDirectory(atPath: url.path, withIntermediateDirectories: true)
        } catch {
            hedgeLog("Error creating storage directory: \(error)")
        }
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
