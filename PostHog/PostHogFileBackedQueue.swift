//
//  PostHogFileBackedQueue.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 13.10.23.
//

import Foundation

class PostHogFileBackedQueue {
    let queue: URL
    private var items = [String]()
    private let itemsLock = NSLock()

    var depth: Int {
        itemsLock.withLock { items.count }
    }

    init(queue: URL, oldQueue: URL? = nil) {
        self.queue = queue
        setup(oldQueue: oldQueue)
    }

    private func setup(oldQueue: URL?) {
        do {
            try FileManager.default.createDirectory(atPath: queue.path, withIntermediateDirectories: true)
        } catch {
            hedgeLog("Error trying to create caching folder \(error)")
        }

        if oldQueue != nil {
            migrateOldQueue(queue: queue, oldQueue: oldQueue!)
        }

        do {
            // when copying over buffered snapshots, content modification date will change, so we work off creation date instead.
            let sortedItems = try FileManager.default.contentsOfDirectory(at: queue, sortedBy: .creationDateKey)
            itemsLock.withLock { items = sortedItems }
        } catch {
            hedgeLog("Failed to load files for queue \(error)")
            // failed to read directory – bad permissions, perhaps?
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
        setup(oldQueue: nil)
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
