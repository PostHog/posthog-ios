import Foundation
@testable import PostHog
import Testing

@Suite("PostHog file-backed queue peek/pop alignment", .serialized)
struct PostHogFileBackedQueueAlignmentTest {
    private func makeQueue() -> (queue: PostHogFileBackedQueue, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ph-queue-align-\(UUID().uuidString)")
        return (PostHogFileBackedQueue(queue: dir, oldQueues: []), dir)
    }

    private func sortedFiles(in dir: URL) throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey])
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return a < b
            }
    }

    private func enqueue(_ values: [String], into queue: PostHogFileBackedQueue) {
        for value in values {
            queue.add(value.data(using: .utf8)!)
            Thread.sleep(forTimeInterval: 0.005) // distinct creation dates for sortedFiles
        }
    }

    private func decode(_ data: [Data]) -> [String] {
        data.map { String(data: $0, encoding: .utf8)! }
    }

    @Test("delivers every record once in FIFO order on the happy path")
    func happyPath() throws {
        let (queue, dir) = makeQueue()
        defer { queue.clear()
            try? FileManager.default.removeItem(at: dir)
        }

        enqueue(["A", "B", "C", "D"], into: queue)

        #expect(queue.depth == 4)
        let first = decode(queue.peek(2))
        #expect(first == ["A", "B"])
        queue.pop(first.count)

        let second = decode(queue.peek(2))
        #expect(second == ["C", "D"])
        queue.pop(second.count)

        #expect(queue.depth == 0)
    }

    @Test("does not re-deliver a record when a missing file precedes returned items")
    func missingFilePrecedingReturnedItems() throws {
        let (queue, dir) = makeQueue()
        defer { queue.clear()
            try? FileManager.default.removeItem(at: dir)
        }

        enqueue(["A", "B", "C", "D"], into: queue)
        try FileManager.default.removeItem(at: sortedFiles(in: dir)[0])

        let batch1 = decode(queue.peek(2))
        #expect(batch1 == ["B", "C"])
        queue.pop(batch1.count)

        let batch2 = decode(queue.peek(2))
        #expect(Set(batch1).isDisjoint(with: Set(batch2)))
        #expect(batch2 == ["D"])
    }

    @Test("does not re-deliver a record when a corrupt file precedes returned items")
    func corruptFilePrecedingReturnedItems() throws {
        let (queue, dir) = makeQueue()
        defer { queue.clear()
            try? FileManager.default.removeItem(at: dir)
        }

        enqueue(["A", "B", "C", "D"], into: queue)

        // present but unreadable: fileExists true, Data(contentsOf:) throws
        let head = try sortedFiles(in: dir)[0]
        try FileManager.default.removeItem(at: head)
        try FileManager.default.createDirectory(at: head, withIntermediateDirectories: false)

        let batch1 = decode(queue.peek(2))
        #expect(batch1 == ["B", "C"])
        queue.pop(batch1.count)

        let batch2 = decode(queue.peek(2))
        #expect(Set(batch1).isDisjoint(with: Set(batch2)))
        #expect(batch2 == ["D"])
    }

    @Test("prunes unreadable entries so depth reflects deliverable records")
    func depthReflectsPrunedEntries() throws {
        let (queue, dir) = makeQueue()
        defer { queue.clear()
            try? FileManager.default.removeItem(at: dir)
        }

        enqueue(["A", "B", "C"], into: queue)
        try FileManager.default.removeItem(at: sortedFiles(in: dir)[0])

        #expect(queue.depth == 3)
        _ = queue.peek(10)
        #expect(queue.depth == 2)
    }

    @Test("deletes and scans past a run of corrupt files without accumulating them")
    func deletesRunOfCorruptFiles() throws {
        let (queue, dir) = makeQueue()
        defer { queue.clear()
            try? FileManager.default.removeItem(at: dir)
        }

        enqueue(["A", "B", "C", "D", "E"], into: queue)
        let corrupt = Array(try sortedFiles(in: dir).prefix(3))
        for url in corrupt {
            try FileManager.default.removeItem(at: url)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        }

        #expect(decode(queue.peek(10)) == ["D", "E"])
        for url in corrupt {
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
        #expect(queue.depth == 2)
    }

    @Test("delete(index:) removes a stuck unreadable head so eviction can unblock the queue")
    func deleteRemovesStuckHead() throws {
        guard geteuid() != 0 else { return } // chmod read-denial is a no-op for root
        let (queue, dir) = makeQueue()
        defer {
            for file in (try? sortedFiles(in: dir)) ?? [] {
                try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
            }
            queue.clear()
            try? FileManager.default.removeItem(at: dir)
        }

        enqueue(["A", "B", "C"], into: queue)
        let head = try sortedFiles(in: dir)[0]
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: head.path)

        #expect(queue.peek(10).isEmpty)
        queue.delete(index: 0)
        #expect(decode(queue.peek(10)) == ["B", "C"])
    }

    @Test("keeps a temporarily unreadable file instead of deleting it, then delivers once readable")
    func keepsTemporarilyUnreadableFile() throws {
        guard geteuid() != 0 else { return } // chmod read-denial is a no-op for root
        let (queue, dir) = makeQueue()
        defer {
            for file in (try? sortedFiles(in: dir)) ?? [] {
                try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
            }
            queue.clear()
            try? FileManager.default.removeItem(at: dir)
        }

        enqueue(["A", "B"], into: queue)
        let head = try sortedFiles(in: dir)[0]
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: head.path)

        #expect(queue.peek(10).isEmpty)
        #expect(FileManager.default.fileExists(atPath: head.path))
        #expect(queue.depth == 2)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: head.path)
        #expect(decode(queue.peek(10)) == ["A", "B"])
    }

    @Test("randomized add/vanish/flush interleavings never duplicate a delivered record")
    func randomizedNoDuplicateDelivery() throws {
        var rng = SeededGenerator(seed: 0x00C0_FFEE)
        let (queue, dir) = makeQueue()
        defer { queue.clear()
            try? FileManager.default.removeItem(at: dir)
        }

        var nextId = 0
        var vanished: Set<Int> = []
        var delivered: [Int] = []

        func flush(upTo count: Int) {
            let batch = queue.peek(count).map { Int(String(data: $0, encoding: .utf8)!)! }
            queue.pop(batch.count)
            delivered.append(contentsOf: batch)
        }

        for _ in 0 ..< 400 {
            switch Int.random(in: 0 ... 2, using: &rng) {
            case 0:
                queue.add("\(nextId)".data(using: .utf8)!)
                nextId += 1
            case 1:
                let files = try FileManager.default.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: nil
                )
                guard let victim = files.randomElement(using: &rng) else { break }
                let id = Int(try String(decoding: Data(contentsOf: victim), as: UTF8.self))!
                try FileManager.default.removeItem(at: victim)
                vanished.insert(id)
            default:
                flush(upTo: Int.random(in: 1 ... 3, using: &rng))
            }
        }

        while queue.depth > 0 {
            let before = queue.depth
            flush(upTo: queue.depth)
            if queue.depth == before { break }
        }

        #expect(Set(delivered).count == delivered.count)
        let expected = Set(0 ..< nextId).subtracting(vanished)
        #expect(Set(delivered) == expected)
    }

    @Test("concurrent add/vanish/flush stays consistent and never double-delivers")
    func concurrentPruneIsThreadSafe() throws {
        let (queue, dir) = makeQueue()
        defer { queue.clear()
            try? FileManager.default.removeItem(at: dir)
        }

        let deliveredLock = NSLock()
        var delivered: [String] = []
        let group = DispatchGroup()
        let concurrent = DispatchQueue(label: "ph.queue.align.test", attributes: .concurrent)

        for i in 0 ..< 500 {
            concurrent.async(group: group) {
                queue.add("\(i)".data(using: .utf8)!)
            }
        }
        for _ in 0 ..< 120 {
            concurrent.async(group: group) {
                let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                if let victim = files?.randomElement() {
                    try? FileManager.default.removeItem(at: victim)
                }
            }
        }
        concurrent.async(group: group) {
            for _ in 0 ..< 200 {
                let batch = queue.peek(5).map { String(data: $0, encoding: .utf8)! }
                queue.pop(batch.count)
                deliveredLock.withLock { delivered.append(contentsOf: batch) }
            }
        }

        group.wait()

        while queue.depth > 0 {
            let before = queue.depth
            let batch = queue.peek(queue.depth).map { String(data: $0, encoding: .utf8)! }
            queue.pop(batch.count)
            delivered.append(contentsOf: batch)
            if queue.depth == before { break }
        }

        #expect(Set(delivered).count == delivered.count)
        #expect(queue.depth == 0)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) {
        state = seed
    }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
