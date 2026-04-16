import Foundation
@testable import PostHog
import Testing

@Suite("Replay Buffer Queue tests")
class PostHogReplayBufferQueueTests {
    let testDirectory: URL

    init() {
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PostHogReplayBufferQueueTests")
            .appendingPathComponent(UUID().uuidString)
    }

    deinit {
        try? FileManager.default.removeItem(at: testDirectory)
    }

    private func createQueue() -> PostHogReplayBufferQueue {
        PostHogReplayBufferQueue(queue: testDirectory)
    }

    private func createTestData(_ content: String = "test") -> Data {
        content.data(using: .utf8)!
    }

    // MARK: - Prune Tests

    // MARK: - Buffer Duration Tests

    @Test("bufferDuration returns nil for empty queue")
    func bufferDurationEmpty() {
        let queue = createQueue()
        #expect(queue.bufferDuration == nil)
    }

    @Test("bufferDuration returns zero for single item")
    func bufferDurationSingleItem() {
        let queue = createQueue()
        queue.add(createTestData("only"))
        #expect(queue.bufferDuration == 0)
    }

    @Test("bufferDuration increases as items are added over time")
    func bufferDurationIncreases() async throws {
        let queue = createQueue()

        queue.add(createTestData("first"))
        let duration1 = queue.bufferDuration ?? 0

        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        queue.add(createTestData("second"))
        let duration2 = queue.bufferDuration ?? 0

        #expect(duration2 > duration1)
    }

    // MARK: - Migration Tests

    @Test("migrateAll moves all items to target queue")
    func migrateMovesAllItems() async throws {
        let bufferQueue = createQueue()
        let targetDirectory = testDirectory.appendingPathComponent("target")
        let targetQueue = PostHogFileBackedQueue(queue: targetDirectory)

        // Add items to buffer
        bufferQueue.add(createTestData("item1"))
        try await Task.sleep(nanoseconds: 20_000_000) // 20ms
        bufferQueue.add(createTestData("item2"))
        try await Task.sleep(nanoseconds: 20_000_000) // 20ms
        bufferQueue.add(createTestData("item3"))

        #expect(bufferQueue.depth == 3)
        #expect(targetQueue.depth == 0)

        // Migrate
        bufferQueue.migrateAll(to: targetQueue)

        // Buffer should be empty, target should have all items
        #expect(bufferQueue.depth == 0)
        #expect(targetQueue.depth == 3)
    }

    @Test("migrateAll preserves data integrity")
    func migratePreservesData() async throws {
        let bufferQueue = createQueue()
        let targetDirectory = testDirectory.appendingPathComponent("target")
        let targetQueue = PostHogFileBackedQueue(queue: targetDirectory)

        // Add items with distinct content
        let contents = ["first_item_data", "second_item_data", "third_item_data"]
        for content in contents {
            bufferQueue.add(createTestData(content))
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }

        // Migrate
        bufferQueue.migrateAll(to: targetQueue)

        // Read back from target and verify content
        let migratedData = targetQueue.peek(3)
        #expect(migratedData.count == 3)

        let migratedStrings = migratedData.compactMap { String(data: $0, encoding: .utf8) }
        for content in contents {
            #expect(migratedStrings.contains(content))
        }
    }

    @Test("migrateAll clears buffer even if target has items")
    func migrateIsAtomic() async throws {
        let bufferQueue = createQueue()
        let targetDirectory = testDirectory.appendingPathComponent("target")
        let targetQueue = PostHogFileBackedQueue(queue: targetDirectory)

        // Add existing items to target
        targetQueue.add(createTestData("existing1"))
        targetQueue.add(createTestData("existing2"))
        #expect(targetQueue.depth == 2)

        // Add items to buffer
        bufferQueue.add(createTestData("new1"))
        try await Task.sleep(nanoseconds: 20_000_000) // 20ms
        bufferQueue.add(createTestData("new2"))
        #expect(bufferQueue.depth == 2)

        // Migrate
        bufferQueue.migrateAll(to: targetQueue)

        // Buffer should be empty
        #expect(bufferQueue.depth == 0)

        // Target should have both existing and new items
        #expect(targetQueue.depth == 4)
    }

    @Test("migrateAll results in sorted target queue")
    func migrateResultsInSortedQueue() async throws {
        let bufferQueue = createQueue()
        let targetDirectory = testDirectory.appendingPathComponent("target")
        let targetQueue = PostHogFileBackedQueue(queue: targetDirectory)

        // Add existing items to target with delays
        targetQueue.add(createTestData("target_old"))
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Add items to buffer (these will have newer timestamps)
        bufferQueue.add(createTestData("buffer_1"))
        try await Task.sleep(nanoseconds: 30_000_000) // 30ms
        bufferQueue.add(createTestData("buffer_2"))
        try await Task.sleep(nanoseconds: 30_000_000) // 30ms
        bufferQueue.add(createTestData("buffer_3"))

        // Migrate
        bufferQueue.migrateAll(to: targetQueue)

        // Target should have 4 items
        #expect(targetQueue.depth == 4)

        // Peek all items - they should be in chronological order
        let allData = targetQueue.peek(4)
        #expect(allData.count == 4)

        let strings = allData.compactMap { String(data: $0, encoding: .utf8) }

        // First item should be the oldest (target_old)
        #expect(strings[0] == "target_old")

        // Buffer items should follow in order
        #expect(strings[1] == "buffer_1")
        #expect(strings[2] == "buffer_2")
        #expect(strings[3] == "buffer_3")
    }

    @Test("migrateAll handles empty buffer gracefully")
    func migrateEmptyBuffer() {
        let bufferQueue = createQueue()
        let targetDirectory = testDirectory.appendingPathComponent("target")
        let targetQueue = PostHogFileBackedQueue(queue: targetDirectory)

        // Add items to target
        targetQueue.add(createTestData("existing"))
        #expect(targetQueue.depth == 1)

        // Migrate empty buffer
        bufferQueue.migrateAll(to: targetQueue)

        // Target should be unchanged
        #expect(targetQueue.depth == 1)
        #expect(bufferQueue.depth == 0)
    }

    @Test("migrateAll does not corrupt queue on duplicate filenames")
    func migrateHandlesDuplicates() async throws {
        let bufferQueue = createQueue()
        let targetDirectory = testDirectory.appendingPathComponent("target")
        let targetQueue = PostHogFileBackedQueue(queue: targetDirectory)

        // Add items to both queues
        bufferQueue.add(createTestData("buffer_item"))
        try await Task.sleep(nanoseconds: 20_000_000)
        targetQueue.add(createTestData("target_item"))

        let bufferDepthBefore = bufferQueue.depth
        let targetDepthBefore = targetQueue.depth

        #expect(bufferDepthBefore == 1)
        #expect(targetDepthBefore == 1)

        // Migrate - should not throw or corrupt
        bufferQueue.migrateAll(to: targetQueue)

        // Buffer should be empty
        #expect(bufferQueue.depth == 0)

        // Target should have both items (no corruption)
        #expect(targetQueue.depth == 2)

        // Verify we can still read from target
        let data = targetQueue.peek(2)
        #expect(data.count == 2)
    }

    @Test("concurrent writes to target during migration do not corrupt queue")
    func concurrentWritesDuringMigration() async throws {
        let bufferQueue = createQueue()
        let targetDirectory = testDirectory.appendingPathComponent("target")
        let targetQueue = PostHogFileBackedQueue(queue: targetDirectory)

        // Add items to buffer
        for i in 0 ..< 10 {
            bufferQueue.add(createTestData("buffer_\(i)"))
            try await Task.sleep(nanoseconds: 5_000_000) // 5ms
        }

        #expect(bufferQueue.depth == 10)

        // Migrate first
        bufferQueue.migrateAll(to: targetQueue)

        // Then write concurrently to target
        for i in 0 ..< 5 {
            targetQueue.add(createTestData("concurrent_\(i)"))
        }

        // Buffer should be empty
        #expect(bufferQueue.depth == 0)

        // Target should have all migrated items + concurrent writes
        #expect(targetQueue.depth == 15)

        // Verify we can read all items without corruption
        let allData = targetQueue.peek(targetQueue.depth)
        #expect(allData.count == 15)

        // Verify all data is valid (non-empty strings)
        for data in allData {
            let str = String(data: data, encoding: .utf8)
            #expect(str != nil)
            #expect(str!.isEmpty == false)
        }
    }

    @Test("writes to target queue during migration are preserved")
    func writesPreservedDuringMigration() async throws {
        let bufferQueue = createQueue()
        let targetDirectory = testDirectory.appendingPathComponent("target")
        let targetQueue = PostHogFileBackedQueue(queue: targetDirectory)

        // Add items to buffer
        for i in 0 ..< 15 {
            bufferQueue.add(createTestData("buffer_\(i)"))
        }

        // Migrate buffer to target
        bufferQueue.migrateAll(to: targetQueue)

        // Write more items to target after migration
        for i in 0 ..< 15 {
            targetQueue.add(createTestData("snapshot_\(i)"))
        }

        // All items should be in target
        #expect(targetQueue.depth == 30)

        // Verify all items are readable
        let allData = targetQueue.peek(30)
        let strings = allData.compactMap { String(data: $0, encoding: .utf8) }

        #expect(strings.contains("buffer_14"))
        #expect(strings.contains("snapshot_14"))
    }

    // MARK: - Thread Safety Tests

    @Test("concurrent adds from multiple threads do not corrupt buffer")
    func concurrentAddsFromMultipleThreads() async throws {
        let bufferQueue = createQueue()
        let itemsPerThread = 20
        let threadCount = 4

        await withTaskGroup(of: Void.self) { group in
            for threadIndex in 0 ..< threadCount {
                group.addTask {
                    for i in 0 ..< itemsPerThread {
                        bufferQueue.add(self.createTestData("thread_\(threadIndex)_item_\(i)"))
                    }
                }
            }
        }

        // All items should be added
        #expect(bufferQueue.depth == itemsPerThread * threadCount)

        // Verify buffer duration is valid (not corrupted)
        let duration = bufferQueue.bufferDuration
        #expect(duration != nil)
        #expect(duration! >= 0)
    }

    @Test("concurrent adds to target while migrating from different threads")
    func concurrentAddsAndMigrationFromDifferentThreads() async throws {
        let bufferQueue = createQueue()
        let targetDirectory = testDirectory.appendingPathComponent("target")
        let targetQueue = PostHogFileBackedQueue(queue: targetDirectory)

        await withTaskGroup(of: Void.self) { group in
            // Thread 1: Populate and migrate buffer to target
            group.addTask {
                // Pre-populate buffer
                for i in 0 ..< 20 {
                    bufferQueue.add(self.createTestData("buffer_\(i)"))
                }

                #expect(bufferQueue.depth == 20)

                bufferQueue.migrateAll(to: targetQueue)
            }

            // Thread 2: Add items directly to target
            group.addTask {
                for i in 0 ..< 10 {
                    targetQueue.add(self.createTestData("direct_\(i)"))
                }
            }

            // Thread 3: Add more items directly to target
            group.addTask {
                for i in 0 ..< 10 {
                    targetQueue.add(self.createTestData("direct2_\(i)"))
                }
            }
        }

        // Buffer should be empty
        #expect(bufferQueue.depth == 0)

        // Target should have all items (20 migrated + 20 direct)
        #expect(targetQueue.depth == 40)

        // Verify all data is readable and not corrupted
        let allData = targetQueue.peek(40)
        #expect(allData.count == 40)

        for data in allData {
            let str = String(data: data, encoding: .utf8)
            #expect(str != nil)
            #expect(str!.isEmpty == false)
        }
    }

    @Test("migration from one thread while adding to buffer from another")
    func migrationWhileAddingToBuffer() async throws {
        let bufferQueue = createQueue()
        let targetDirectory = testDirectory.appendingPathComponent("target")
        let targetQueue = PostHogFileBackedQueue(queue: targetDirectory)

        // Add initial items
        for i in 0 ..< 10 {
            bufferQueue.add(createTestData("initial_\(i)"))
        }

        await withTaskGroup(of: Void.self) { group in
            // Thread 1: Migrate
            group.addTask {
                bufferQueue.migrateAll(to: targetQueue)
            }

            // Thread 2: Add more items to buffer (these may or may not be migrated)
            group.addTask {
                for i in 0 ..< 5 {
                    bufferQueue.add(self.createTestData("during_\(i)"))
                }
            }
        }

        // Total items across both queues should be 15
        let totalItems = bufferQueue.depth + targetQueue.depth
        #expect(totalItems == 15)

        // Verify target queue is not corrupted
        let targetData = targetQueue.peek(targetQueue.depth)
        #expect(targetData.count == targetQueue.depth)

        for data in targetData {
            let str = String(data: data, encoding: .utf8)
            #expect(str != nil)
        }
    }
}
