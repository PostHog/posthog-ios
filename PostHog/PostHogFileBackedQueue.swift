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
    /// FIFO limit on the total size of the stored files, on top of `maxSize`.
    /// The newest entry is always kept, even when it's larger on its own.
    private let maxBytes: Int?
    private var items = [String]()
    /// File sizes by id, tracked only when `maxBytes` is set. Guarded by `itemsLock`.
    private var sizes = [String: Int]()
    private var totalBytes = 0
    private let itemsLock = NSLock()

    var depth: Int {
        itemsLock.withLock { items.count }
    }

    init(queue: URL, oldQueues: [URL] = [], maxSize: Int? = nil, maxBytes: Int? = nil) {
        self.queue = queue
        self.maxSize = maxSize.map { max(1, $0) }
        self.maxBytes = maxBytes.map { max(1, $0) }
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
                    deleteSafely(oldQueue)
                }
            }
        }

        do {
            try reindexFromDisk()
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
            return untrack(items.remove(at: index))
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
            removed.forEach { untrack($0) }
            return removed
        }

        for item in removed {
            deleteSafely(queue.appendingPathComponent(item))
        }
    }

    /// Persists one entry and optionally enforces a FIFO capacity in the same
    /// critical section. Returning the evicted ids lets the queue report
    /// backpressure without racing a separate depth check against other adds.
    @discardableResult
    func add(_ contents: Data, maxSize: Int? = nil) -> (success: Bool, evicted: [String]) {
        do {
            let filename = UUID.v7String()
            let effectiveMaxSize = maxSize.map { max(1, $0) } ?? self.maxSize
            var evicted = [String]()

            try itemsLock.withLock {
                try contents.write(to: queue.appendingPathComponent(filename))

                if let effectiveMaxSize, items.count >= effectiveMaxSize {
                    evicted.append(untrack(items.removeFirst()))
                }

                items.append(filename)
                track(filename, size: contents.count)
                evicted += evictOverByteLimit()
            }

            for id in evicted {
                deleteSafely(queue.appendingPathComponent(id))
            }
            return (true, evicted)
        } catch {
            hedgeLog("Could not write file \(error)")
            return (false, [])
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
            try reindexFromDisk()
        } catch {
            hedgeLog("Failed to reload files for queue \(error)")
        }
    }

    /// Re-reads the queue directory and replaces the in-memory index with it,
    /// enforcing the FIFO capacity. The enumeration runs inside `itemsLock` so a
    /// filename appended by a concurrent `add` can't be dropped from the index by
    /// the replacement while its file stays on disk.
    private func reindexFromDisk() throws {
        let dropped: [String] = try itemsLock.withLock {
            // when copying over buffered snapshots, content modification date will change, so we work off creation date instead.
            let sortedItems = try FileManager.default.contentsOfDirectory(at: queue, sortedBy: .creationDateKey)
            let overflow = maxSize.map { max(0, sortedItems.count - $0) } ?? 0
            items = Array(sortedItems.dropFirst(overflow))
            sizes = [:]
            totalBytes = 0
            if maxBytes != nil {
                for item in items {
                    let attributes = try? FileManager.default.attributesOfItem(atPath: queue.appendingPathComponent(item).path)
                    track(item, size: (attributes?[.size] as? NSNumber)?.intValue ?? 0)
                }
            }
            return Array(sortedItems.prefix(overflow)) + evictOverByteLimit()
        }

        for item in dropped {
            deleteSafely(queue.appendingPathComponent(item))
        }
        if !dropped.isEmpty {
            hedgeLog("Dropped \(dropped.count) oldest cached records to enforce queue capacity")
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
            itemsLock.withLock {
                items.removeAll { skipped.contains($0) }
                skipped.forEach { untrack($0) }
            }
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

    /// Caller must hold `itemsLock`.
    private func track(_ id: String, size: Int) {
        guard maxBytes != nil else { return }
        sizes[id] = size
        totalBytes += size
    }

    /// Caller must hold `itemsLock`. Returns `id` for chaining.
    @discardableResult
    private func untrack(_ id: String) -> String {
        if let size = sizes.removeValue(forKey: id) {
            totalBytes -= size
        }
        return id
    }

    /// Drops the oldest items until the total fits `maxBytes`, keeping the
    /// newest. Caller must hold `itemsLock` and delete the returned files.
    private func evictOverByteLimit() -> [String] {
        guard let maxBytes else { return [] }
        var evicted = [String]()
        while totalBytes > maxBytes, items.count > 1 {
            evicted.append(untrack(items.removeFirst()))
        }
        return evicted
    }

    private func deleteFiles(_ count: Int) {
        for _ in 0 ..< count {
            let removed: String? = itemsLock.withLock {
                guard !items.isEmpty else { return nil }
                return untrack(items.remove(at: 0)) // We always remove from the top of the queue
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
    /// Returns filenames in a total order: by resource key, then by filename.
    /// `reindexFromDisk` deletes the head of this order to enforce capacity, so a file
    /// whose date can't be read must not sort oldest, and equal dates need a tie-breaker
    /// because `sorted` isn't stable. UUID v7 names sort by their embedded timestamp.
    func contentsOfDirectory(at url: URL, sortedBy key: URLResourceKey) throws -> [String] {
        let urls = try contentsOfDirectory(at: url, includingPropertiesForKeys: [key])
        return urls.sorted { lhs, rhs in
            let date1 = (try? lhs.resourceValues(forKeys: [key]).allValues[key] as? Date) ?? .distantFuture
            let date2 = (try? rhs.resourceValues(forKeys: [key]).allValues[key] as? Date) ?? .distantFuture
            if date1 == date2 {
                return lhs.lastPathComponent < rhs.lastPathComponent
            }
            return date1 < date2
        }.map(\.lastPathComponent)
    }
}
