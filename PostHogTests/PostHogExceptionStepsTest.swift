import Foundation
@testable import PostHog
import Testing

@Suite("PostHog exception steps capture", .serialized)
class PostHogExceptionStepsTest {
    let server: MockPostHogServer

    init() {
        server = MockPostHogServer(version: 4)
        server.start()
    }

    deinit {
        server.stop()
    }

    private enum TestError: Error {
        case boom
    }

    /// Reference box so a `beforeSend` closure can be toggled mid-test (the closure runs synchronously
    /// on the capturing thread).
    private final class DropToggle {
        var dropExceptions: Bool
        init(_ dropExceptions: Bool) {
            self.dropExceptions = dropExceptions
        }
    }

    private func getSut(
        stepsEnabled: Bool = true,
        maxBytes: Int = 32768,
        flushAt: Int = 1,
        token: String = testProjectToken,
        beforeSend: BeforeSendBlock? = nil
    ) -> PostHogSDK {
        let config = PostHogConfig(projectToken: token, host: "http://localhost:9001")
        config.flushAt = flushAt
        config.captureApplicationLifecycleEvents = false
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true
        config.errorTrackingConfig.exceptionSteps.enabled = stepsEnabled
        config.errorTrackingConfig.exceptionSteps.maxBytes = maxBytes
        if let beforeSend {
            config.setBeforeSend(beforeSend)
        }

        let storage = PostHogStorage(config)
        storage.reset()

        return PostHogSDK.with(config)
    }

    private func exceptionSteps(_ event: PostHogEvent) -> [[String: Any]]? {
        event.properties[PostHogExceptionStepFields.stepsKey] as? [[String: Any]]
    }

    private func messages(_ steps: [[String: Any]]?) -> [String] {
        steps?.compactMap { $0[PostHogExceptionStepFields.message] as? String } ?? []
    }

    @Test("attaches buffered steps to the next exception in order")
    func attachesInOrder() {
        let sut = getSut()
        sut.addExceptionStep("first")
        sut.addExceptionStep("second")
        sut.captureException(TestError.boom)

        let events = getBatchedEvents(server).filter { $0.event == "$exception" }
        #expect(events.count == 1)
        #expect(messages(exceptionSteps(events.first!)) == ["first", "second"])

        sut.reset()
        sut.close()
    }

    @Test("does not overwrite caller-provided $exception_steps")
    func respectsManualOverride() {
        let sut = getSut()
        sut.addExceptionStep("buffered")

        let manual: [[String: Any]] = [["$message": "manual", "$timestamp": "2026-06-09T10:00:00.000Z"]]
        sut.captureException(TestError.boom, properties: ["$exception_steps": manual])

        let events = getBatchedEvents(server).filter { $0.event == "$exception" }
        #expect(events.count == 1)
        #expect(messages(exceptionSteps(events.first!)) == ["manual"])

        sut.reset()
        sut.close()
    }

    @Test("preserves buffered steps when the caller supplies their own $exception_steps")
    func preservesBufferOnManualOverride() {
        let sut = getSut()
        server.reset(batchCount: 2)

        sut.addExceptionStep("buffered")

        // Caller supplies their own steps: the SDK must neither attach nor discard its buffer.
        let manual: [[String: Any]] = [["$message": "manual", "$timestamp": "2026-06-09T10:00:00.000Z"]]
        sut.captureException(TestError.boom, properties: ["$exception_steps": manual]) // batch 1
        sut.captureException(TestError.boom) // batch 2 — the preserved buffered step attaches here

        let events = getBatchedEvents(server).filter { $0.event == "$exception" }
        #expect(events.count == 2)
        #expect(events.contains { messages(exceptionSteps($0)) == ["manual"] })
        // The buffered step was preserved across the manual-override capture, not silently cleared.
        #expect(events.contains { messages(exceptionSteps($0)) == ["buffered"] })

        sut.reset()
        sut.close()
    }

    @Test("recording steps concurrently with integration churn does not crash")
    func concurrentStepsDuringIntegrationChurn() {
        let sut = getSut()

        // Concurrent recording while opt-out/opt-in churn installs and uninstalls integrations must
        // not crash.
        DispatchQueue.concurrentPerform(iterations: 150) { i in
            switch i % 3 {
            case 0: sut.addExceptionStep("s\(i)")
            case 1: sut.optOut()
            default: sut.optIn()
            }
        }

        sut.optIn()
        sut.reset()
        sut.close()
    }

    @Test("strips reserved keys from step properties and sets canonical values")
    func stripsReservedKeys() {
        let sut = getSut()
        sut.addExceptionStep("real-message", properties: [
            "$message": "should-be-ignored",
            "$timestamp": "should-be-ignored",
            "ok": 1,
        ])
        sut.captureException(TestError.boom)

        let events = getBatchedEvents(server).filter { $0.event == "$exception" }
        let step = exceptionSteps(events.first!)?.first
        #expect(step?["$message"] as? String == "real-message")
        #expect(step?["ok"] as? Int == 1)
        // The SDK-set timestamp is an ISO-8601 string, not the caller's bogus value.
        #expect((step?["$timestamp"] as? String) != "should-be-ignored")
        #expect(step?["$timestamp"] as? String != nil)

        sut.reset()
        sut.close()
    }

    @Test("steps persist across captures (session-scoped buffer)")
    func persistsAcrossCaptures() {
        // flushAt 2 so both exceptions land in a single deterministic batch.
        let sut = getSut(flushAt: 2)
        server.reset(batchCount: 1)

        sut.addExceptionStep("a")
        sut.addExceptionStep("b")
        sut.captureException(TestError.boom) // → [a, b]
        sut.addExceptionStep("c")
        sut.captureException(TestError.boom) // → [a, b, c] (buffer not cleared by capture)

        let events = getBatchedEvents(server).filter { $0.event == "$exception" }
        #expect(events.count == 2)
        guard events.count == 2 else {
            sut.reset()
            sut.close()
            return
        }
        // Batch order isn't guaranteed; the later capture carries the extra step.
        let stepLists = events.map { messages(exceptionSteps($0)) }.sorted { $0.count < $1.count }
        #expect(stepLists[0] == ["a", "b"])
        #expect(stepLists[1] == ["a", "b", "c"])

        sut.reset()
        sut.close()
    }

    @Test("steps persist across an identity change (reset / identify)")
    func persistsAcrossIdentityChange() {
        let sut = getSut()

        sut.addExceptionStep("recorded-before-identity-change")
        sut.reset() // identity change must NOT clear the step buffer
        sut.captureException(TestError.boom)

        let events = getBatchedEvents(server).filter { $0.event == "$exception" }
        #expect(events.count == 1)
        #expect(messages(exceptionSteps(events.first!)) == ["recorded-before-identity-change"])

        sut.close()
    }

    @Test("preserves buffered steps when an exception is dropped, attaching them to the next accepted one")
    func preservesStepsOnDrop() {
        let toggle = DropToggle(true)
        let sut = getSut(beforeSend: { event in
            if event.event == "$exception", toggle.dropExceptions { return nil }
            return event
        })

        sut.addExceptionStep("kept-across-drop")
        sut.captureException(TestError.boom) // dropped by beforeSend → buffer preserved

        toggle.dropExceptions = false
        sut.captureException(TestError.boom) // accepted → preserved steps attached

        let events = getBatchedEvents(server).filter { $0.event == "$exception" }
        #expect(events.count == 1) // the first exception was dropped, only the second is delivered
        #expect(messages(exceptionSteps(events.first!)) == ["kept-across-drop"])

        sut.reset()
        sut.close()
    }

    @Test("ignores empty messages")
    func ignoresEmptyMessage() {
        let sut = getSut()
        sut.addExceptionStep("")
        sut.captureException(TestError.boom)

        let events = getBatchedEvents(server).filter { $0.event == "$exception" }
        #expect(exceptionSteps(events.first!) == nil)

        sut.reset()
        sut.close()
    }

    @Test("each SDK instance carries only its own steps")
    func oneBufferPerInstance() {
        let sutA = getSut(token: "steps_A_\(UUID().uuidString)")
        let sutB = getSut(token: "steps_B_\(UUID().uuidString)")
        server.reset(batchCount: 2)

        sutA.addExceptionStep("from-A")
        sutA.captureException(TestError.boom, properties: ["which": "A"])
        sutB.captureException(TestError.boom, properties: ["which": "B"]) // B recorded no steps

        let events = getBatchedEvents(server).filter { $0.event == "$exception" }
        let eventA = events.first { $0.properties["which"] as? String == "A" }
        let eventB = events.first { $0.properties["which"] as? String == "B" }
        #expect(messages(exceptionSteps(eventA!)) == ["from-A"])
        #expect(exceptionSteps(eventB!) == nil) // A's steps did not leak into B

        sutA.reset()
        sutA.close()
        sutB.reset()
        sutB.close()
    }

    @Test("timestamp reflects call time, not serialization time")
    func timestampReflectsCallTime() {
        let callTime = Date(timeIntervalSince1970: 1_700_000_000)
        now = { callTime }
        defer { now = { Date() } }

        let sut = getSut()
        sut.addExceptionStep("at-call-time")

        // Advance the clock after recording — the step must keep the call-time timestamp.
        now = { Date(timeIntervalSince1970: 1_800_000_000) }
        sut.captureException(TestError.boom)

        let events = getBatchedEvents(server).filter { $0.event == "$exception" }
        let step = exceptionSteps(events.first!)?.first
        #expect(step?["$timestamp"] as? String == toISO8601String(callTime))

        sut.reset()
        sut.close()
    }

    @Test("does nothing when exception steps are disabled")
    func disabledIsNoOp() {
        let sut = getSut(stepsEnabled: false)
        sut.addExceptionStep("ignored")
        sut.captureException(TestError.boom)

        let events = getBatchedEvents(server).filter { $0.event == "$exception" }
        #expect(events.count == 1)
        #expect(exceptionSteps(events.first!) == nil)

        sut.reset()
        sut.close()
    }

    @Test("replays buffered steps to subscribers on opt-in (buffer survives opt-out)")
    func replaysStepsOnOptIn() {
        let sut = getSut()

        var received: [[[String: Any]]] = []
        let token = sut.onExceptionStepsChanged.subscribe { received.append($0) }

        sut.addExceptionStep("a")
        sut.addExceptionStep("b")

        sut.optOut()
        let countBeforeOptIn = received.count
        sut.optIn() // a freshly installed crash writer must be replayed the surviving buffer

        #expect(received.count == countBeforeOptIn + 1)
        #expect(messages(received.last) == ["a", "b"])

        withExtendedLifetime(token) {}
        sut.reset()
        sut.close()
    }

    @Test("does not replay on opt-in when the buffer is empty")
    func noReplayWhenBufferEmptyOnOptIn() {
        let sut = getSut()

        var received: [[[String: Any]]] = []
        let token = sut.onExceptionStepsChanged.subscribe { received.append($0) }

        sut.optOut()
        sut.optIn() // empty buffer → nothing to replay

        #expect(received.isEmpty)

        withExtendedLifetime(token) {}
        sut.reset()
        sut.close()
    }
}
