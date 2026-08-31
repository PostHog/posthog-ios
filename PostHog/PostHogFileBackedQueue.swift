//
//  PostHogFileBackedQueue.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 13.10.23.
//

import Foundation

class PostHogFileBackedQueue {
    struct Entry {
        let id: String
        let data: Data
    }

    let queue: URL
    private let maxSize: Int?
    private var items = [String]()
    private let itemsLock = NSLock()

    var depth: Int {
        itemsLock.withLock { items.count }
    }

    init(queue: URL, oldQueues: [URL] = [], maxSize: Int? = nil) {
        self.queue = queue
        self.maxSize = maxSize.map { max(1, $0) }
        setup(oldQueues: oldQueues)
    }

    private func setup(oldQueues: [URL]) {
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
            replaceItemsWithBounded(sortedItems)
        } catch {
            hedgeLog("Failed to load files for queue \(error)")
            // failed to read directory – bad permissions, perhaps?
        }
    }

    func peek(_ count: Int) -> [Data] {
        peekEntries(count).map(\.data)
    }

    func peekEntries(_ count: Int) -> [Entry] {
        loadEntries(count)
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

    func remove(ids: [String]) {
        let ids = Set(ids)
        let removed: [String] = itemsLock.withLock {
            let removed = items.filter { ids.contains($0) }
            items.removeAll { ids.contains($0) }
            return removed
        }

        for item in removed {
            deleteSafely(queue.appendingPathComponent(item))
        }
    }

    /// Persists one entry and optionally enforces a FIFO capacity in the same
    /// critical section. Returning an evicted id lets the queue report
    /// backpressure without racing a separate depth check against other adds.
    @discardableResult
    func add(_ contents: Data, maxSize: Int? = nil) -> String? {
        do {
            let filename = UUID.v7String()
            let effectiveMaxSize = maxSize.map { max(1, $0) } ?? self.maxSize
            var evicted: String?

            try itemsLock.withLock {
                if let effectiveMaxSize, items.count >= effectiveMaxSize {
                    evicted = items.removeFirst()
                    if let evicted {
                        deleteSafely(queue.appendingPathComponent(evicted))
                    }
                }

                try contents.write(to: queue.appendingPathComponent(filename))
                items.append(filename)
            }

            return evicted
        } catch {
            hedgeLog("Could not write file \(error)")
            return nil
        }
    }

    /// Internal, used for testing
    func clear() {
        deleteSafely(queue)
        setup(oldQueues: [])
    }

    /// Reloads items from disk and sorts by creation date.
    /// Use after externally adding files to the queue directory.
    func reloadFromDisk() {
        do {
            let sortedItems = try FileManager.default.contentsOfDirectory(at: queue, sortedBy: .creationDateKey)
            replaceItemsWithBounded(sortedItems)
        } catch {
            hedgeLog("Failed to reload files for queue \(error)")
        }
    }

    private func replaceItemsWithBounded(_ sortedItems: [String]) {
        let overflow = maxSize.map { max(0, sortedItems.count - $0) } ?? 0
        let dropped = sortedItems.prefix(overflow)
        itemsLock.withLock { items = Array(sortedItems.dropFirst(overflow)) }

        for item in dropped {
            deleteSafely(queue.appendingPathComponent(item))
        }
        if overflow > 0 {
            hedgeLog("Dropped \(overflow) oldest cached records to enforce queue capacity")
        }
    }

    private func loadEntries(_ count: Int) -> [Entry] {
        var results = [Entry]()
        var skipped = Set<String>()

        let itemsCopy = itemsLock.withLock { items }

        for item in itemsCopy {
            let itemURL = queue.appendingPathComponent(item)
            do {
                if !FileManager.default.fileExists(atPath: itemURL.path) {
                    hedgeLog("File \(itemURL) does not exist")
                    skipped.insert(item)
                    continue
                }
                let contents = try Data(contentsOf: itemURL)

                results.append(Entry(id: item, data: contents))
            } catch {
                if isTemporarilyUnavailable(error) {
                    hedgeLog("File \(itemURL) is temporarily unavailable, will retry \(error)")
                    break
                }

                hedgeLog("File \(itemURL) is corrupted \(error)")

                deleteSafely(itemURL)
                skipped.insert(item)
            }

            if results.count == count {
                break
            }
        }

        if !skipped.isEmpty {
            itemsLock.withLock { items.removeAll { skipped.contains($0) } }
        }

        return results
    }

    /// True when a read failed because the file is temporarily unreadable (iOS data protection on a
    /// locked device) rather than corrupt, so it must be kept rather than deleted.
    private func isTemporarilyUnavailable(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoPermissionError {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain,
           underlying.code == Int(EACCES) || underlying.code == Int(EPERM)
        {
            return true
        }
        return false
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
