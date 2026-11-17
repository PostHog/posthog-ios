import Foundation
@testable import PostHog
import Testing

/// The handled-exception stack trace must start at the code that called `captureException`.
///
/// SwiftPM links the SDK statically into the test binary, as it does into apps, so the SDK's frames
/// share a module with the caller here. That's the setup where module-name stripping can't work.
@Suite("captureException stack starts at the caller", .serialized)
final class PostHogCaptureExceptionStackTest {
    let server: MockPostHogServer

    init() {
        server = MockPostHogServer(version: 4)
        server.start()
    }

    deinit {
        server.stop()
    }

    private struct TestError: Error {}

    /// Holds the `$exception` captured by `beforeSend`, which runs synchronously on the capturing thread.
    private final class Captured {
        var properties: [String: Any]?
    }

    private func getSut(_ captured: Captured) -> PostHogSDK {
        let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
        config.captureApplicationLifecycleEvents = false
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true
        config.setBeforeSend { event in
            if event.event == "$exception" {
                captured.properties = event.properties
            }
            return nil
        }
        return PostHogSDK.with(config)
    }

    /// Innermost frame first.
    private func functions(_ captured: Captured) throws -> [String] {
        let exceptions = try #require(captured.properties?["$exception_list"] as? [[String: Any]])
        let stacktrace = try #require(exceptions.first?["stacktrace"] as? [String: Any])
        let frames = try #require(stacktrace["frames"] as? [[String: Any]])
        return frames.reversed().map { $0["function"] as? String ?? "" }
    }

    /// Swift symbols the SDK defines start with `$s7PostHog`; this test target's start with `$s12PostHogTests`.
    private func isSDKSymbol(_ function: String) -> Bool {
        function.hasPrefix("$s7PostHog")
    }

    /// Whether a mangled symbol is the given call site: Swift mangles an identifier as its length followed
    /// by its name. The call-site names share no words with this type or module, which the mangler would
    /// otherwise abbreviate.
    private func isCallSite(_ function: String, _ name: String) -> Bool {
        function.contains("\(name.utf8.count)\(name)")
    }

    @inline(never)
    private func siteSwiftError(_ sut: PostHogSDK) {
        sut.captureException(TestError())
    }

    @inline(never)
    private func siteSwiftErrorWithProps(_ sut: PostHogSDK) {
        sut.captureException(TestError(), properties: ["key": "value"])
    }

    @inline(never)
    private func siteNeverRaised(_ sut: PostHogSDK) {
        sut.captureException(NSException(name: .genericException, reason: "never raised"))
    }

    @inline(never)
    private func siteNeverRaisedWithProps(_ sut: PostHogSDK) {
        sut.captureException(NSException(name: .genericException, reason: "never raised"), properties: ["key": "value"])
    }

    @inline(never)
    private func siteObjCSelector(_ sut: PostHogSDK) {
        _ = sut.perform(NSSelectorFromString("captureExceptionWithError:properties:"), with: TestError() as NSError, with: nil)
    }

    @Test("Swift Error: the top frame is the caller", arguments: ["siteSwiftError", "siteSwiftErrorWithProps"])
    func swiftErrorTopFrameIsCaller(site: String) throws {
        let captured = Captured()
        let sut = getSut(captured)
        defer { sut.close() }

        if site == "siteSwiftError" {
            siteSwiftError(sut)
        } else {
            siteSwiftErrorWithProps(sut)
        }

        let top = try #require(try functions(captured).first)
        #expect(isCallSite(top, site), "top frame: \(top)")
    }

    @Test("unraised NSException: the top frame is the caller", arguments: ["siteNeverRaised", "siteNeverRaisedWithProps"])
    func unraisedNSExceptionTopFrameIsCaller(site: String) throws {
        let captured = Captured()
        let sut = getSut(captured)
        defer { sut.close() }

        if site == "siteNeverRaised" {
            siteNeverRaised(sut)
        } else {
            siteNeverRaisedWithProps(sut)
        }

        let top = try #require(try functions(captured).first)
        #expect(isCallSite(top, site), "top frame: \(top)")
    }

    @Test("Objective-C dispatch: no SDK frame above the caller")
    func objCDispatchHasNoSDKFrameAboveCaller() throws {
        let captured = Captured()
        let sut = getSut(captured)
        defer { sut.close() }

        siteObjCSelector(sut)

        // The call goes through the SDK's @objc thunk; a libobjc frame may sit above the caller too.
        let all = try functions(captured)
        let callerIndex = try #require(all.firstIndex { isCallSite($0, "siteObjCSelector") }, "frames: \(all)")
        let aboveCaller = all[..<callerIndex]
        #expect(!aboveCaller.contains(where: isSDKSymbol), "frames above the caller: \(Array(aboveCaller))")
    }
}
