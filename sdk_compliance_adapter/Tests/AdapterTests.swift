import Foundation
@testable import PostHogIOSComplianceAdapter
import Testing

struct AdapterTests {
    @Test func captureTimestampPreservesInstant() throws {
        let offset = try parseCaptureTimestamp("2025-01-02T08:34:05+05:30")
        #expect(offset == (try parseCaptureTimestamp("2025-01-02T03:04:05Z")))
        #expect(try parseCaptureTimestamp("2025-01-02T03:04:05.123Z") != offset)
        #expect(try parseCaptureTimestamp(nil) == nil)
        #expect(throws: (any Error).self) { try parseCaptureTimestamp("not-a-timestamp") }
    }

    @Test func unobservedCaptureDoesNotSettle() async throws {
        let tracker = RequestTracker()
        #expect(tracker.trackCapture {} == nil)
        #expect(tracker.snapshot().pending == 1)
        #expect(try await !tracker.waitForAcknowledgments(timeout: 0.04))
    }

    @Test func idleNetworkIsNotDeliveryOrRetryExhaustion() async throws {
        let tracker = RequestTracker()
        tracker.observeCapture(uuid: "ABC")
        for attempt in 0 ..< 4 {
            tracker.observeResponse(status: 503, uuids: ["abc"], timestampMs: Int64(attempt))
        }
        #expect(tracker.snapshot().pending == 1)
        #expect(tracker.snapshot().retries == 3)
        #expect(tracker.snapshot().requests.map(\.retryAttempt) == [0, 1, 2, 3])
        #expect(try await !tracker.waitForAcknowledgments(timeout: 0.04))
        tracker.observeResponse(status: 200, uuids: ["abc"], timestampMs: 4)
        #expect(try await tracker.waitForAcknowledgments(timeout: 0.04))
        #expect(tracker.snapshot().sent == 1)
    }

    @Test func acknowledgmentWaitsForTransportCompletion() async throws {
        let tracker = RequestTracker()
        tracker.observeCapture(uuid: "a")
        tracker.beginRequest()
        tracker.observeResponse(status: 200, uuids: ["a"], timestampMs: 0)
        #expect(try await !tracker.waitForAcknowledgments(timeout: 0.04))
        tracker.endRequest()
        #expect(try await tracker.waitForAcknowledgments(timeout: 0.04))
    }

    @Test func terminalResponseAndBatchSplitObservations() {
        let tracker = RequestTracker()
        tracker.observeCapture(uuid: "a")
        tracker.observeCapture(uuid: "b")
        tracker.observeResponse(status: 413, uuids: ["a", "b"], timestampMs: 0)
        #expect(tracker.snapshot().pending == 2)
        tracker.observeResponse(status: 413, uuids: ["a"], timestampMs: 1)
        tracker.observeResponse(status: 400, uuids: ["b"], timestampMs: 2)
        #expect(tracker.snapshot().pending == 0)
        #expect(tracker.snapshot().sent == 0)
    }

    @Test func overlappingCapturesKeepTheirOwnUUIDs() {
        let tracker = RequestTracker()
        let firstEntered = DispatchSemaphore(value: 0)
        let secondStarted = DispatchSemaphore(value: 0)
        let secondEntered = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)
        let completed = DispatchGroup()

        completed.enter()
        DispatchQueue.global().async {
            let uuid = tracker.trackCapture {
                firstEntered.signal()
                #expect(releaseFirst.wait(timeout: .now() + 5) == .success)
                tracker.observeCapture(uuid: "FIRST")
            }
            #expect(uuid == "first")
            completed.leave()
        }
        #expect(firstEntered.wait(timeout: .now() + 5) == .success)

        completed.enter()
        DispatchQueue.global().async {
            secondStarted.signal()
            let uuid = tracker.trackCapture {
                secondEntered.signal()
                tracker.observeCapture(uuid: "SECOND")
            }
            #expect(uuid == "second")
            completed.leave()
        }
        #expect(secondStarted.wait(timeout: .now() + 5) == .success)
        // The second public call cannot run while the first observation is outstanding.
        #expect(secondEntered.wait(timeout: .now() + 0.1) == .timedOut)
        releaseFirst.signal()
        #expect(completed.wait(timeout: .now() + 5) == .success)
        #expect(tracker.snapshot().captured == 2)
        #expect(tracker.snapshot().pending == 2)
    }

    @Test func captureReturnsObservedSDKUUID() {
        let tracker = RequestTracker()
        let uuid = tracker.trackCapture { tracker.observeCapture(uuid: "ABC") }
        #expect(uuid == "abc")
        #expect(tracker.snapshot().captured == 1)
        #expect(tracker.snapshot().pending == 1)
    }
}
