#if os(iOS)
    @testable import PostHog
    import Testing
    import Foundation

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

        @Test("pruneOlderThan removes items older than duration from head")
        func pruneRemovesOldItemsFromHead() async throws {
            let queue = createQueue()

            // Add items with small delays to ensure different timestamps and creation date file meta
            queue.add(createTestData("item1"))
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            queue.add(createTestData("item2"))
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            queue.add(createTestData("item3"))
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            queue.add(createTestData("item4"))

            #expect(queue.depth == 4)

            // Get the buffer duration before pruning
            let bufferDuration = queue.bufferDuration ?? 0
            #expect(bufferDuration > 0)

            // Prune items older than half the buffer duration
            // This should remove the oldest items (from head)
            let pruneDuration = bufferDuration / 2
            queue.pruneOlderThan(duration: pruneDuration)

            // Should have fewer items now
            #expect(queue.depth < 4)
            #expect(queue.depth > 0)

            // The remaining buffer duration should be <= pruneDuration
            let remainingDuration = queue.bufferDuration ?? 0
            #expect(remainingDuration <= pruneDuration + 0.01) // small tolerance
        }

        @Test("pruneOlderThan keeps items within duration window")
        func pruneKeepsRecentItems() async throws {
            let queue = createQueue()

            // Add items
            queue.add(createTestData("item1"))
            queue.add(createTestData("item2"))
            queue.add(createTestData("item3"))

            #expect(queue.depth == 3)

            // Prune with a very large duration - should keep all items
            queue.pruneOlderThan(duration: 3600) // 1 hour

            #expect(queue.depth == 3)
        }

        @Test("pruneOlderThan removes all items when duration is zero")
        func pruneWithZeroDurationRemovesAll() async throws {
            let queue = createQueue()

            queue.add(createTestData("item1"))
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            queue.add(createTestData("item2"))

            #expect(queue.depth == 2)

            // Prune with zero duration - should remove all but the newest
            queue.pruneOlderThan(duration: 0)

            // Only the newest item should remain (cutoff = newestTs - 0 = newestTs)
            // Items with ts < newestTs are removed, so only the last one stays
            #expect(queue.depth == 1)
        }

        @Test("pruneOlderThan does nothing on empty queue")
        func pruneEmptyQueue() {
            let queue = createQueue()

            #expect(queue.depth == 0)

            queue.pruneOlderThan(duration: 1.0)

            #expect(queue.depth == 0)
        }

        @Test("pruneOlderThan preserves order")
        func prunePreservesOrder() async throws {
            let queue = createQueue()

            // Add items with delays
            queue.add(createTestData("oldest"))
            try await Task.sleep(nanoseconds: 30_000_000) // 30ms
            queue.add(createTestData("middle"))
            try await Task.sleep(nanoseconds: 30_000_000) // 30ms
            queue.add(createTestData("newest"))

            let oldestBefore = queue.oldestTimestamp
            let newestBefore = queue.newestTimestamp

            #expect(oldestBefore != nil)
            #expect(newestBefore != nil)
            #expect(oldestBefore! < newestBefore!)

            // Prune should remove from head (oldest)
            let bufferDuration = queue.bufferDuration ?? 0
            queue.pruneOlderThan(duration: bufferDuration / 2)

            let oldestAfter = queue.oldestTimestamp
            let newestAfter = queue.newestTimestamp

            // Newest should be unchanged (we remove from head)
            #expect(newestAfter == newestBefore)

            // Oldest should be newer than before (we removed old items)
            #expect(oldestAfter! > oldestBefore!)
        }

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
    }
#endif
