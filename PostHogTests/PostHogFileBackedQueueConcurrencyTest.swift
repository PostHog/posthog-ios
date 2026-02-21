//
//  PostHogFileBackedQueueConcurrencyTest.swift
//  PostHogTests
//

import Foundation
@testable import PostHog
import Testing

@Suite("FileBackedQueue Concurrency Tests")
struct PostHogFileBackedQueueConcurrencyTest {
    func createTestQueue() -> PostHogFileBackedQueue {
        let baseUrl = applicationSupportDirectoryURL()
        let testId = UUID().uuidString
        let queueURL = baseUrl.appendingPathComponent("concurrency-test-\(testId)")
        return PostHogFileBackedQueue(queue: queueURL)
    }

    @Test("Concurrent add operations preserve all events")
    func concurrentAddPreservesAllEvents() async throws {
        let queue = createTestQueue()
        defer { queue.clear() }

        let threadCount = 10
        let eventsPerThread = 100
        let expectedTotal = threadCount * eventsPerThread

        let group = DispatchGroup()
        let concurrentQueue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

        for threadIndex in 0 ..< threadCount {
            for eventIndex in 0 ..< eventsPerThread {
                group.enter()
                concurrentQueue.async {
                    let eventData = "thread-\(threadIndex)-event-\(eventIndex)".data(using: .utf8)!
                    queue.add(eventData)
                    group.leave()
                }
            }
        }

        group.wait()

        #expect(queue.depth == expectedTotal,
                "Expected \(expectedTotal) events but got \(queue.depth). Events were lost due to race condition.")
    }

    @Test("Highly concurrent add operations preserve all events")
    func highlyConcurrentAddPreservesAllEvents() async throws {
        let queue = createTestQueue()
        defer { queue.clear() }

        let operationCount = 500
        let group = DispatchGroup()
        let concurrentQueue = DispatchQueue(label: "test.highly-concurrent", attributes: .concurrent)

        let startSemaphore = DispatchSemaphore(value: 0)

        for i in 0 ..< operationCount {
            group.enter()
            concurrentQueue.async {
                startSemaphore.wait()

                let eventData = "event-\(i)".data(using: .utf8)!
                queue.add(eventData)
                group.leave()
            }
        }

        for _ in 0 ..< operationCount {
            startSemaphore.signal()
        }

        group.wait()

        #expect(queue.depth == operationCount,
                "Expected \(operationCount) events but got \(queue.depth). Race condition caused event loss.")
    }

    @Test("Concurrent delete operations don't crash with invalid indices")
    func concurrentDeleteDoesNotCrash() async throws {
        let queue = createTestQueue()
        defer { queue.clear() }

        for i in 0 ..< 10 {
            queue.add("item-\(i)".data(using: .utf8)!)
        }

        let group = DispatchGroup()
        let concurrentQueue = DispatchQueue(label: "test.delete-concurrent", attributes: .concurrent)

        for _ in 0 ..< 50 {
            group.enter()
            concurrentQueue.async {
                queue.delete(index: 0)
                group.leave()
            }
        }

        group.wait()

        #expect(queue.depth == 0)
    }

    @Test("Mixed concurrent add and delete operations maintain consistency")
    func mixedConcurrentOperations() async throws {
        let queue = createTestQueue()
        defer { queue.clear() }

        let group = DispatchGroup()
        let concurrentQueue = DispatchQueue(label: "test.mixed-concurrent", attributes: .concurrent)

        let addCount = 200
        let deleteCount = 50

        for i in 0 ..< addCount {
            group.enter()
            concurrentQueue.async {
                queue.add("event-\(i)".data(using: .utf8)!)
                group.leave()
            }
        }

        for _ in 0 ..< deleteCount {
            group.enter()
            concurrentQueue.async {
                queue.delete(index: 0)
                group.leave()
            }
        }

        group.wait()

        #expect(queue.depth >= addCount - deleteCount,
                "Queue depth \(queue.depth) is less than minimum expected \(addCount - deleteCount)")
        #expect(queue.depth <= addCount,
                "Queue depth \(queue.depth) exceeds maximum expected \(addCount)")
    }
}
