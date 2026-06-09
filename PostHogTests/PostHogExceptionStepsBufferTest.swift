import Foundation
@testable import PostHog
import Testing

@Suite("PostHogExceptionStepsBuffer Tests")
struct PostHogExceptionStepsBufferTest {
    // Fixed timestamp keeps serialized step sizes deterministic across steps.
    private static let fixedTimestamp = "2026-06-09T10:00:00.000Z"

    private func makeStep(_ message: String, pad: String? = nil) -> [String: Any] {
        var step: [String: Any] = [
            PostHogExceptionStepFields.message: message,
            PostHogExceptionStepFields.timestamp: Self.fixedTimestamp,
        ]
        if let pad {
            step["pad"] = pad
        }
        return step
    }

    private func messages(_ steps: [[String: Any]]) -> [String] {
        steps.compactMap { $0[PostHogExceptionStepFields.message] as? String }
    }

    @Test("keeps steps in order, oldest first")
    func keepsOrder() {
        let buffer = PostHogExceptionStepsBuffer(maxBytes: 32768)
        buffer.add(makeStep("one"))
        buffer.add(makeStep("two"))
        buffer.add(makeStep("three"))

        #expect(messages(buffer.getAttachable()) == ["one", "two", "three"])
    }

    @Test("evicts the oldest steps when over the byte budget")
    func evictsOldest() {
        // Two equally-sized steps fit; adding a third evicts the oldest.
        let sample = makeStep("s1")
        let size = toJSONData(sample)!.count
        let buffer = PostHogExceptionStepsBuffer(maxBytes: size * 2)

        buffer.add(makeStep("s1"))
        buffer.add(makeStep("s2"))
        buffer.add(makeStep("s3"))

        #expect(messages(buffer.getAttachable()) == ["s2", "s3"])
    }

    @Test("rejects a single step larger than the whole budget and retains prior steps")
    func rejectsOversized() {
        let small = makeStep("small")
        let smallSize = toJSONData(small)!.count
        let buffer = PostHogExceptionStepsBuffer(maxBytes: smallSize + 8)

        #expect(buffer.add(makeStep("small")) == true)

        let oversized = makeStep("big", pad: String(repeating: "x", count: smallSize + 100))
        #expect(buffer.add(oversized) == false)

        // The oversized step is rejected outright; the earlier step is retained.
        #expect(messages(buffer.getAttachable()) == ["small"])
    }

    @Test("rejects steps with an empty or missing message")
    func rejectsInvalidMessage() {
        let buffer = PostHogExceptionStepsBuffer(maxBytes: 32768)

        #expect(buffer.add(makeStep("")) == false)
        #expect(buffer.add([PostHogExceptionStepFields.timestamp: Self.fixedTimestamp]) == false)
        #expect(buffer.isEmpty)
    }

    @Test("rejects steps with an invalid timestamp but accepts string or number")
    func validatesTimestamp() {
        let buffer = PostHogExceptionStepsBuffer(maxBytes: 32768)

        // Missing timestamp
        #expect(buffer.add([PostHogExceptionStepFields.message: "x"]) == false)
        // Non-string / non-number timestamp
        #expect(buffer.add([
            PostHogExceptionStepFields.message: "x",
            PostHogExceptionStepFields.timestamp: ["nested"],
        ]) == false)
        // Numeric timestamp is accepted
        #expect(buffer.add([
            PostHogExceptionStepFields.message: "x",
            PostHogExceptionStepFields.timestamp: 1_749_463_200_000,
        ]) == true)
    }

    @Test("clear empties the buffer and resets the byte total")
    func clearEmpties() {
        let buffer = PostHogExceptionStepsBuffer(maxBytes: 32768)
        buffer.add(makeStep("one"))
        buffer.add(makeStep("two"))

        buffer.clear()

        #expect(buffer.isEmpty)
        #expect(buffer.getAttachable().isEmpty)

        // Buffer is usable again after clear.
        buffer.add(makeStep("three"))
        #expect(messages(buffer.getAttachable()) == ["three"])
    }

    @Test("byte counting uses serialized UTF-8 byte length, not character count")
    func countsUtf8Bytes() {
        // A multi-byte emoji message is larger in bytes than in characters.
        let multibyte = makeStep("🚀🚀🚀🚀🚀")
        let asciiSized = makeStep("a")
        let asciiSize = toJSONData(asciiSized)!.count

        // Budget that fits the small ASCII step but not the larger multi-byte one.
        let buffer = PostHogExceptionStepsBuffer(maxBytes: asciiSize + 4)
        #expect(buffer.add(multibyte) == false)
        #expect(buffer.add(asciiSized) == true)
    }

    @Test("never throws on an unserializable value; drops it but keeps the step")
    func handlesUnserializableValue() {
        let buffer = PostHogExceptionStepsBuffer(maxBytes: 32768)
        var step = makeStep("ok")
        step["data"] = Data([0x01, 0x02, 0x03]) // not JSON-serializable

        // Recording must not throw; the bad value is dropped and the step is still buffered.
        #expect(buffer.add(step) == true)
        let stored = buffer.getAttachable().first
        #expect(stored?[PostHogExceptionStepFields.message] as? String == "ok")
        #expect(stored?["data"] == nil)
    }

    @Test("normalizes values once so the stored step matches the wire form")
    func normalizesStoredStep() {
        let buffer = PostHogExceptionStepsBuffer(maxBytes: 32768)
        let date = Date(timeIntervalSince1970: 1_749_463_200)
        var step = makeStep("ok")
        step["when"] = date

        #expect(buffer.add(step) == true)
        let stored = buffer.getAttachable().first
        // The Date is normalized to an ISO-8601 string (same as event-property handling), not stored as a Date.
        #expect(stored?["when"] as? String == ISO8601DateFormatter().string(from: date))
    }

    @Test("concurrent adds and reads are thread-safe")
    func concurrentAccessIsSafe() {
        // Large budget so nothing is evicted and the final count is deterministic.
        let buffer = PostHogExceptionStepsBuffer(maxBytes: 5_000_000)
        let iterations = 500

        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            buffer.add(makeStep("s\(i)"))
            _ = buffer.getAttachable()
        }

        #expect(buffer.getAttachable().count == iterations)
    }
}
