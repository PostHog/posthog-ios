//
//  PostHogFileBackedQueue.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 13.10.23.
//

import Foundation

private let maxRestoreAttempts = 3

class PostHogFileBackedQueue {
    let queue: URL
    private var items = [String]()
    private let itemsLock = NSLock()
    private let restoreAttemptsKey: String?

    var depth: Int {
        itemsLock.withLock { items.count }
    }

    init(queue: URL, oldQueues: [URL] = [], restoreAttemptsKey: String? = nil) {
        self.queue = queue
        self.restoreAttemptsKey = restoreAttemptsKey
        setup(oldQueues: oldQueues, trackAttempts: true)
    }

    private func setup(oldQueues: [URL], trackAttempts: Bool) {
        if trackAttempts, let key = restoreAttemptsKey {
            let previousAttempts = UserDefaults.standard.integer(forKey: key)

            if previousAttempts >= maxRestoreAttempts {
                hedgeLog("Queue restore failed \(previousAttempts) consecutive time(s), clearing queue directory")
                deleteSafely(queue)
                UserDefaults.standard.set(0, forKey: key)
            }

            UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
        }

        do {
            try FileManager.default.createDirectory(atPath: queue.path, withIntermediateDirectories: true)
        } catch {
            hedgeLog("Error trying to create caching folder \(error)")
        }

        for oldQueue in oldQueues {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: oldQueue.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    // old queue folder
                    migrateOldQueueFolder(queue: queue, oldQueueFolder: oldQueue)
                } else {
                    // old plist file
                    migrateOldQueue(queue: queue, oldQueue: oldQueue)
                }
            }
        }

        do {
            // when copying over buffered snapshots, content modification date will change, so we work off creation date instead.
            let sortedItems = try FileManager.default.contentsOfDirectory(at: queue, sortedBy: .creationDateKey)
            itemsLock.withLock { items = sortedItems }
        } catch {
            hedgeLog("Failed to load files for queue \(error)")
            // failed to read directory – bad permissions, perhaps?
            return
        }

        if trackAttempts, let key = restoreAttemptsKey {
            UserDefaults.standard.set(0, forKey: key)
        }
    }

    func peek(_ count: Int) -> [Data] {
        loadFiles(count)
    }

    func delete(index: Int) {
        let removed: String? = itemsLock.withLock {
            guard index < items.count else { return nil }
            return items.remove(at: index)
        }

        if let removed {
            deleteSafely(queue.appendingPathComponent(removed))
        }
    }

    func pop(_ count: Int) {
        deleteFiles(count)
    }

    func add(_ contents: Data) {
        do {
            let filename = UUID.v7().uuidString
            try contents.write(to: queue.appendingPathComponent(filename))
            itemsLock.withLock { items.append(filename) }
        } catch {
            hedgeLog("Could not write file \(error)")
        }
    }

    /// Internal, used for testing
    func clear() {
        deleteSafely(queue)
        setup(oldQueues: [], trackAttempts: false)
    }

    /// Reloads items from disk and sorts by creation date.
    /// Use after externally adding files to the queue directory.
    func reloadFromDisk() {
        do {
            let sortedItems = try FileManager.default.contentsOfDirectory(at: queue, sortedBy: .creationDateKey)
            itemsLock.withLock { items = sortedItems }
        } catch {
            hedgeLog("Failed to reload files for queue \(error)")
        }
    }

    private func loadFiles(_ count: Int) -> [Data] {
        var results = [Data]()

        let itemsCopy = itemsLock.withLock { items }

        for item in itemsCopy {
            let itemURL = queue.appendingPathComponent(item)
            do {
                if !FileManager.default.fileExists(atPath: itemURL.path) {
                    hedgeLog("File \(itemURL) does not exist")
                    continue
                }
                let contents = try Data(contentsOf: itemURL)

                results.append(contents)
            } catch {
                hedgeLog("File \(itemURL) is corrupted \(error)")

                deleteSafely(itemURL)
            }

            if results.count == count {
                return results
            }
        }

        return results
    }

    private func deleteFiles(_ count: Int) {
        for _ in 0 ..< count {
            let removed: String? = itemsLock.withLock {
                guard !items.isEmpty else { return nil }
                return items.remove(at: 0) // We always remove from the top of the queue
            }

            guard let removed else { return }
            deleteSafely(queue.appendingPathComponent(removed))
        }
    }
}

// Migrates the an Old Queue folder to a new Queue folder
// Just moves files over since the format is the same
private func migrateOldQueueFolder(queue: URL, oldQueueFolder: URL) {
    defer {
        deleteSafely(oldQueueFolder)
    }

    do {
        let files = try FileManager.default.contentsOfDirectory(atPath: oldQueueFolder.path)
        for file in files {
            let sourceURL = oldQueueFolder.appendingPathComponent(file)
            let destinationURL = queue.appendingPathComponent(file)
            do {
                try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            } catch {
                hedgeLog("Failed to migrate file \(file): \(error)")
            }
        }
    } catch {
        hedgeLog("Failed to read queue folder \(error)")
    }
}

private extension FileManager {
    /// Returns filenames sorted by resource key
    func contentsOfDirectory(at url: URL, sortedBy key: URLResourceKey) throws -> [String] {
        let urls = try contentsOfDirectory(at: url, includingPropertiesForKeys: [key])
        return urls.sorted {
            let date1 = (try? $0.resourceValues(forKeys: [key]).allValues[key] as? Date) ?? .distantPast
            let date2 = (try? $1.resourceValues(forKeys: [key]).allValues[key] as? Date) ?? .distantPast
            return date1 < date2
        }.map(\.lastPathComponent)
    }
}
