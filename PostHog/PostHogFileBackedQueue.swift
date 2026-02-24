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
        itemsLock.lock()
        defer { itemsLock.unlock() }
        return items.count
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
            itemsLock.lock()
            items = try FileManager.default.contentsOfDirectory(atPath: queue.path)
            items.sort { Double($0)! < Double($1)! }
            itemsLock.unlock()
        } catch {
            itemsLock.unlock()
            hedgeLog("Failed to load files for queue \(error)")
            // failed to read directory – bad permissions, perhaps?
        }
    }

    func peek(_ count: Int) -> [Data] {
        loadFiles(count)
    }

    func delete(index: Int) {
        itemsLock.lock()
        guard index < items.count else {
            itemsLock.unlock()
            return
        }
        let removed = items.remove(at: index)
        itemsLock.unlock()

        deleteSafely(queue.appendingPathComponent(removed))
    }

    func pop(_ count: Int) {
        deleteFiles(count)
    }

    func add(_ contents: Data) {
        do {
            let filename = "\(Date().timeIntervalSince1970)"
            try contents.write(to: queue.appendingPathComponent(filename))

            itemsLock.lock()
            items.append(filename)
            itemsLock.unlock()
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
        var results = [Data]()

        itemsLock.lock()
        let itemsCopy = items
        itemsLock.unlock()

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
            itemsLock.lock()
            if items.isEmpty {
                itemsLock.unlock()
                return
            }
            let removed = items.remove(at: 0) // We always remove from the top of the queue
            itemsLock.unlock()

            deleteSafely(queue.appendingPathComponent(removed))
        }
    }
}
