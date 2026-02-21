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
            var loadedItems = try FileManager.default.contentsOfDirectory(atPath: queue.path)
            loadedItems.sort { Double($0)! < Double($1)! }
            itemsLock.withLock { items = loadedItems }
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
            let filename = "\(Date().timeIntervalSince1970)"
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

    private func loadFiles(_ count: Int) -> [Data] {
        let currentItems = itemsLock.withLock { items }
        var results = [Data]()

        for item in currentItems {
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
                if items.isEmpty {
                    return nil
                }
                return items.remove(at: 0) // We always remove from the top of the queue
            }
            if let removed {
                deleteSafely(queue.appendingPathComponent(removed))
            }
        }
    }
}
