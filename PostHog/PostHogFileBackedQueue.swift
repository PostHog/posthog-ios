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
            try? FileManager.default.createDirectory(atPath: url.path, withIntermediateDirectories: true)
        }

        do {
            items = try FileManager.default.contentsOfDirectory(atPath: url.path)
            items.sort { Double($0)! < Double($1)! }
        } catch {
            hedgeLog("Failed to load files for queue")
            // failed to read directory – bad permissions, perhaps?
        }
    }

    func peek(_ count: Int) -> [Data] {
        loadFiles(count)
    }

    func delete(index: Int) {
        if items.isEmpty { return }
        let removed = items.remove(at: index)
        try? FileManager.default.removeItem(at: url.appendingPathComponent(removed))
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
            hedgeLog("Could not write file")
        }
    }

    func clear() {
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        setup()
    }

    private func loadFiles(_ count: Int) -> [Data] {
        var results = [Data]()

        for item in items {
            let itemPath = url.appendingPathComponent(item)
            guard let contents = try? Data(contentsOf: itemPath) else {
                try? FileManager.default.removeItem(at: itemPath)
                hedgeLog("File \(itemPath) is corrupted")
                continue
            }

            results.append(contents)
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
            try? FileManager.default.removeItem(at: url.appendingPathComponent(removed))
        }
    }
}
