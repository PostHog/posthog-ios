//
//  PostHogFileBackedQueue.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 13.10.23.
//

import Foundation

class PostHogFileBackedQueue {
    private let url: URL
    @ReadWriteLock
    private var items = [String]()

    var depth: Int {
        items.count
    }

    init(url: URL) {
        self.url = url
        setup()
    }

    private func setup() {
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.createDirectory(atPath: url.path, withIntermediateDirectories: true)
            } catch {
                hedgeLog("Error trying to create caching folder \(error)")
            }
        }

        do {
            items = try FileManager.default.contentsOfDirectory(atPath: url.path)
            items.sort { Double($0)! < Double($1)! }
        } catch {
            hedgeLog("Failed to load files for queue \(error)")
            // failed to read directory – bad permissions, perhaps?
        }
    }

    func peek(_ count: Int) -> [Data] {
        loadFiles(count)
    }

    func delete(index: Int) {
        if items.isEmpty { return }
        let removed = items.remove(at: index)

        deleteSafely(url.appendingPathComponent(removed))
    }

    func pop(_ count: Int) -> [Data] {
        let result = loadFiles(count)
        deleteFiles(count)
        return result
    }

    func add(_ contents: Data) {
        do {
            let filename = "\(Date().timeIntervalSince1970)"
            try contents.write(to: url.appendingPathComponent(filename))
            items.append(filename)
        } catch {
            hedgeLog("Could not write file \(error)")
        }
    }

    func clear() {
        deleteSafely(url)

        setup()
    }

    private func loadFiles(_ count: Int) -> [Data] {
        var results = [Data]()

        for item in items {
            let itemURL = url.appendingPathComponent(item)
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
            if items.isEmpty { return }
            let removed = items.remove(at: 0) // We always remove from the top of the queue

            deleteSafely(url.appendingPathComponent(removed))
        }
    }
}
