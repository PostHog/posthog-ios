import Foundation
@testable import PostHog
import Testing
import XCTest

// MARK: - Mock Delegate

class MockReplayBufferDelegate: PostHogReplayBufferDelegate {
    var isBuffering: Bool = false
    var didBufferSnapshotCallCount: Int = 0
    var lastReplayQueue: PostHogReplayQueue?

    func replayQueueDidBufferSnapshot(_ replayQueue: PostHogReplayQueue) {
        didBufferSnapshotCallCount += 1
        lastReplayQueue = replayQueue
    }
}

// MARK: - Tests

@Suite("Replay Queue tests")
class PostHogReplayQueueTests {
    let mockDelegate: MockReplayBufferDelegate

    init() {
        mockDelegate = MockReplayBufferDelegate()
    }

    private func createReplayQueue() -> PostHogReplayQueue {
        // Use unique API key per test to ensure isolated storage
        let uniqueKey = UUID().uuidString
        let config = PostHogConfig(apiKey: uniqueKey, host: "http://localhost:9001")
        let storage = PostHogStorage(config)
        let api = PostHogApi(config)
        let queue = PostHogReplayQueue(config, storage, api, nil)
        // Reset delegate state for each test
        mockDelegate.isBuffering = false
        mockDelegate.didBufferSnapshotCallCount = 0
        mockDelegate.lastReplayQueue = nil
        queue.bufferDelegate = mockDelegate
        // Clear any leftover state
        queue.clear()
        queue.start(disableReachabilityForTesting: true, disableQueueTimerForTesting: true)
        return queue
    }

    private func createTestEvent(_ name: String = "test_event") -> PostHogEvent {
        PostHogEvent(
            event: name,
            distinctId: "test-user",
            properties: ["test": "value"]
        )
    }

    // MARK: - Buffering Mode Tests

    @Test("add routes to buffer when delegate.isBuffering is true")
    func addRoutesToBufferWhenBuffering() {
        let queue = createReplayQueue()
        mockDelegate.isBuffering = true

        queue.add(createTestEvent("snapshot_1"))
        queue.add(createTestEvent("snapshot_2"))

        // Events should be in buffer, not inner queue
        #expect(queue.bufferDepth == 2)
        #expect(queue.depth == 0)
    }

    @Test("add routes to inner queue when delegate.isBuffering is false")
    func addRoutesToInnerQueueWhenNotBuffering() {
        let queue = createReplayQueue()
        mockDelegate.isBuffering = false

        queue.add(createTestEvent("snapshot_1"))
        queue.add(createTestEvent("snapshot_2"))

        // Events should be in inner queue, not buffer
        #expect(queue.bufferDepth == 0)
        #expect(queue.depth == 2)
    }

    @Test("delegate is notified after each buffered snapshot")
    func delegateNotifiedAfterBuffering() {
        let queue = createReplayQueue()
        mockDelegate.isBuffering = true

        #expect(mockDelegate.didBufferSnapshotCallCount == 0)

        queue.add(createTestEvent("snapshot_1"))
        #expect(mockDelegate.didBufferSnapshotCallCount == 1)
        #expect(mockDelegate.lastReplayQueue === queue)

        queue.add(createTestEvent("snapshot_2"))
        #expect(mockDelegate.didBufferSnapshotCallCount == 2)

        queue.add(createTestEvent("snapshot_3"))
        #expect(mockDelegate.didBufferSnapshotCallCount == 3)
    }

    @Test("delegate is not notified when not buffering")
    func delegateNotNotifiedWhenNotBuffering() {
        let queue = createReplayQueue()
        mockDelegate.isBuffering = false

        queue.add(createTestEvent("snapshot_1"))
        queue.add(createTestEvent("snapshot_2"))

        #expect(mockDelegate.didBufferSnapshotCallCount == 0)
    }

    // MARK: - Flush Behavior Tests

    @Test("flush is suppressed when buffering")
    func flushSuppressedWhenBuffering() {
        let queue = createReplayQueue()
        mockDelegate.isBuffering = true

        // Add events to buffer
        queue.add(createTestEvent("snapshot_1"))
        queue.add(createTestEvent("snapshot_2"))

        // Flush should be suppressed - buffer should remain
        queue.flush()

        #expect(queue.bufferDepth == 2)
    }

    @Test("flush works when not buffering")
    func flushWorksWhenNotBuffering() async throws {
        let server = MockPostHogServer()
        server.start(snapshotCount: 1)
        defer { server.stop() }

        let config = PostHogConfig(apiKey: UUID().uuidString, host: "http://localhost:9001")
        let storage = PostHogStorage(config)
        storage.reset()
        let api = PostHogApi(config)
        let queue = PostHogReplayQueue(config, storage, api, nil)
        queue.start(disableReachabilityForTesting: true, disableQueueTimerForTesting: false)
        mockDelegate.isBuffering = false
        queue.bufferDelegate = mockDelegate

        // Add events to inner queue
        queue.add(createTestEvent("snapshot_1"))
        #expect(queue.depth == 1)

        // Flush and wait for server to receive snapshot events
        queue.flush()
        try await waitForSnapshotRequest(server)

        #expect(queue.depth == 0)
    }

    // MARK: - Migration Tests

    @Test("migrateBufferToQueue moves events from buffer to inner queue")
    func migrateBufferToQueue() {
        let queue = createReplayQueue()
        mockDelegate.isBuffering = true

        // Add events to buffer
        queue.add(createTestEvent("snapshot_1"))
        queue.add(createTestEvent("snapshot_2"))
        queue.add(createTestEvent("snapshot_3"))

        #expect(queue.bufferDepth == 3)
        #expect(queue.depth == 0)

        // Migrate
        queue.migrateBufferToQueue()

        // Buffer should be empty, inner queue should have events
        #expect(queue.bufferDepth == 0)
        #expect(queue.depth == 3)
    }

    @Test("migrateBufferToQueue does nothing when buffer is empty")
    func migrateEmptyBuffer() {
        let queue = createReplayQueue()

        #expect(queue.bufferDepth == 0)
        #expect(queue.depth == 0)

        // Migrate empty buffer - should not crash
        queue.migrateBufferToQueue()

        #expect(queue.bufferDepth == 0)
        #expect(queue.depth == 0)
    }

    // MARK: - Clear Buffer Tests

    @Test("clearBuffer removes all buffered events")
    func clearBufferRemovesAllEvents() {
        let queue = createReplayQueue()
        mockDelegate.isBuffering = true

        // Add events to buffer
        queue.add(createTestEvent("snapshot_1"))
        queue.add(createTestEvent("snapshot_2"))

        #expect(queue.bufferDepth == 2)

        // Clear buffer
        queue.clearBuffer()

        #expect(queue.bufferDepth == 0)
    }

    @Test("clearBuffer does not affect inner queue")
    func clearBufferDoesNotAffectInnerQueue() {
        let queue = createReplayQueue()

        // Add events to inner queue (not buffering)
        mockDelegate.isBuffering = false
        queue.add(createTestEvent("snapshot_1"))
        #expect(queue.depth == 1)

        // Add events to buffer
        mockDelegate.isBuffering = true
        queue.add(createTestEvent("snapshot_2"))
        #expect(queue.bufferDepth == 1)

        // Clear buffer
        queue.clearBuffer()

        // Buffer should be empty, inner queue should be unchanged
        #expect(queue.bufferDepth == 0)
        #expect(queue.depth == 1)
    }

    // MARK: - Buffer Duration Tests

    @Test("bufferDuration returns nil when buffer is empty")
    func bufferDurationEmptyBuffer() {
        let queue = createReplayQueue()
        #expect(queue.bufferDuration == nil)
    }

    @Test("bufferDuration returns duration of buffered events")
    func bufferDurationReturnsValue() async throws {
        let queue = createReplayQueue()
        mockDelegate.isBuffering = true

        queue.add(createTestEvent("snapshot_1"))
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        queue.add(createTestEvent("snapshot_2"))

        let duration = queue.bufferDuration
        #expect(duration != nil)
        #expect(duration! > 0)
    }

    // MARK: - Clear All Tests

    @Test("clear removes events from both buffer and inner queue")
    func clearRemovesAllEvents() {
        let queue = createReplayQueue()

        // Add to inner queue
        mockDelegate.isBuffering = false
        queue.add(createTestEvent("inner_1"))

        // Add to buffer
        mockDelegate.isBuffering = true
        queue.add(createTestEvent("buffer_1"))

        #expect(queue.depth == 1)
        #expect(queue.bufferDepth == 1)

        // Clear all
        queue.clear()

        #expect(queue.depth == 0)
        #expect(queue.bufferDepth == 0)
    }

    // MARK: - Buffering State Change Tests

    @Test("switching from buffering to not buffering routes new events to inner queue")
    func switchingBufferingState() {
        let queue = createReplayQueue()

        // Start buffering
        mockDelegate.isBuffering = true
        queue.add(createTestEvent("buffered_1"))
        queue.add(createTestEvent("buffered_2"))

        #expect(queue.bufferDepth == 2)
        #expect(queue.depth == 0)

        // Stop buffering
        mockDelegate.isBuffering = false
        queue.add(createTestEvent("direct_1"))

        // New event should go to inner queue
        #expect(queue.bufferDepth == 2)
        #expect(queue.depth == 1)
    }

    @Test("delegate can trigger migration from callback")
    func delegateCanTriggerMigration() {
        let queue = createReplayQueue()

        // Create a delegate that migrates after 3 events
        class MigratingDelegate: PostHogReplayBufferDelegate {
            var isBuffering: Bool = true
            var callCount = 0

            func replayQueueDidBufferSnapshot(_ replayQueue: PostHogReplayQueue) {
                callCount += 1
                if callCount >= 3 {
                    isBuffering = false
                    replayQueue.migrateBufferToQueue()
                }
            }
        }

        let migratingDelegate = MigratingDelegate()
        queue.bufferDelegate = migratingDelegate

        // Add events
        queue.add(createTestEvent("snapshot_1"))
        queue.add(createTestEvent("snapshot_2"))

        #expect(queue.bufferDepth == 2)
        #expect(queue.depth == 0)

        // Third event should trigger migration
        queue.add(createTestEvent("snapshot_3"))

        #expect(queue.bufferDepth == 0)
        #expect(queue.depth == 3)
        #expect(migratingDelegate.isBuffering == false)
    }
}
