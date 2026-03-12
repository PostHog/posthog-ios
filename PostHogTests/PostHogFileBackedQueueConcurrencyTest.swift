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
    }

    @Test("Concurrent add operations")
    func concurrentAddOperations() async throws {
        let queue = createTestQueue()
        defer { queue.clear() }

        let operationCount = 1000

        await Task.detached {
            DispatchQueue.concurrentPerform(iterations: operationCount) { i in
                let uniqueData = "event-\(i)-\(UUID().uuidString)".data(using: .utf8)!
                queue.add(uniqueData)
            }
        }.value

        let finalDepth = queue.depth
        #expect(finalDepth == operationCount,
                "Expected \(operationCount) events but got \(finalDepth). Lost \(operationCount - finalDepth) events due to race condition.")
    }

    @Test("Concurrent adds with duplicate timestamp detection")
    func concurrentAddsDetectDuplicateFilenames() async throws {
        let queue = createTestQueue()
        defer { queue.clear() }

        let operationCount = 2_000

        let expectedData = (0 ..< operationCount).map { i in
            "unique-event-\(i)-\(UUID().uuidString)"
        }

        await Task.detached {
            DispatchQueue.concurrentPerform(iterations: operationCount) { i in
                queue.add(expectedData[i].data(using: .utf8)!)
            }
        }.value

        let retrievedData = queue.peek(operationCount)
        let retrievedStrings = Set(retrievedData.compactMap { String(data: $0, encoding: .utf8) })

        #expect(queue.depth == operationCount,
                "Expected \(operationCount) events but got \(queue.depth)")

        #expect(retrievedStrings.count == operationCount,
                "Expected \(operationCount) unique events but got \(retrievedStrings.count). Possible duplicate filename collision.")
    }

    @Test("Concurrent reads and writes don't cause crashes or corruption")
    func concurrentReadsAndWrites() async throws {
        let queue = createTestQueue()
        defer { queue.clear() }

        for i in 0 ..< 50 {
            queue.add("initial-\(i)".data(using: .utf8)!)
        }

        let writeCount = 200
        let readCount = 200
        let totalOps = writeCount + readCount

        await Task.detached {
            DispatchQueue.concurrentPerform(iterations: totalOps) { i in
                if i < writeCount {
                    queue.add("write-\(i)".data(using: .utf8)!)
                } else {
                    _ = queue.peek(10)
                    _ = queue.depth
                }
            }
        }.value

        let finalDepth = queue.depth
        #expect(finalDepth >= 50,
                "Queue should have at least initial 50 items, got \(finalDepth)")
        #expect(finalDepth <= 50 + writeCount,
                "Queue should have at most 250 items, got \(finalDepth)")
    }

    @Test("Concurrent deletes at various indices")
    func concurrentDeletesAtVariousIndices() async throws {
        let queue = createTestQueue()
        defer { queue.clear() }

        let initialCount = 100
        for i in 0 ..< initialCount {
            queue.add("item-\(i)".data(using: .utf8)!)
        }

        let deleteCount = 150

        await Task.detached {
            DispatchQueue.concurrentPerform(iterations: deleteCount) { i in
                queue.delete(index: i % 10)
            }
        }.value

        let finalDepth = queue.depth
        #expect(finalDepth >= 0, "Depth should never be negative")
        #expect(finalDepth <= initialCount, "Depth should not exceed initial count")
    }

    @Test("Chaotic mix of all operations")
    func chaoticMixOfAllOperations() async throws {
        let queue = createTestQueue()
        defer { queue.clear() }

        for i in 0 ..< 50 {
            queue.add("initial-\(i)".data(using: .utf8)!)
        }

        let operationCount = 500

        await Task.detached {
            DispatchQueue.concurrentPerform(iterations: operationCount) { i in
                let operation = i % 5
                switch operation {
                case 0, 1:
                    queue.add("event-\(i)".data(using: .utf8)!)
                case 2:
                    queue.delete(index: 0)
                case 3:
                    _ = queue.peek(5)
                case 4:
                    _ = queue.depth
                default:
                    break
                }
            }
        }.value

        let finalDepth = queue.depth
        let peekedData = queue.peek(finalDepth)

        #expect(finalDepth >= 0, "Depth should never be negative")
        #expect(peekedData.count == finalDepth,
                "Peek should return exactly depth items, got \(peekedData.count) vs \(finalDepth)")
    }

    @Test("Maximum contention stress test for TSan")
    func maximumContentionStressTest() async throws {
        let queue = createTestQueue()
        defer { queue.clear() }

        let iterations = 100
        let threadsPerIteration = 20

        for iteration in 0 ..< iterations {
            await Task.detached {
                DispatchQueue.concurrentPerform(iterations: threadsPerIteration) { threadId in
                    queue.add("iter-\(iteration)-thread-\(threadId)".data(using: .utf8)!)
                }
            }.value
        }

        let expectedTotal = iterations * threadsPerIteration
        #expect(queue.depth == expectedTotal,
                "Expected \(expectedTotal) events but got \(queue.depth)")
    }
}
