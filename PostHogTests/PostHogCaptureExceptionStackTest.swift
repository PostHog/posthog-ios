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

    /// Whether a mangled symbol is the given call site: Swift mangles an identifier as its length followed
    /// by its name. The call-site names share no words with this type or module, which the mangler would
    /// otherwise abbreviate.
    private func isCallSite(_ function: String, _ name: String) -> Bool {
        function.contains("\(name.utf8.count)\(name)")
    }

    private func neverRaised() -> NSException {
        NSException(name: .genericException, reason: "never raised")
    }

    // MARK: - Swift call sites

    @inline(never) private func siteSwiftError(_ sut: PostHogSDK) {
        sut.captureException(TestError())
    }

    @inline(never) private func siteSwiftErrorWithProps(_ sut: PostHogSDK) {
        sut.captureException(TestError(), properties: ["key": "value"])
    }

    @inline(never) private func siteSwiftErrorWithOpts(_ sut: PostHogSDK) {
        sut.captureException(TestError(), properties: ["key": "value"], options: ["process_person_profile": false])
    }

    @inline(never) private func siteNeverRaised(_ sut: PostHogSDK) {
        sut.captureException(neverRaised())
    }

    @inline(never) private func siteNeverRaisedWithProps(_ sut: PostHogSDK) {
        sut.captureException(neverRaised(), properties: ["key": "value"])
    }

    @inline(never) private func siteNeverRaisedWithOpts(_ sut: PostHogSDK) {
        sut.captureException(neverRaised(), properties: ["key": "value"], options: ["process_person_profile": false])
    }

    // MARK: - Objective-C call sites

    // Calling a selector's IMP is what objc_msgSend does for an Objective-C caller: it enters the SDK
    // through the @objc thunk. `perform` can't pass three arguments or a nil dictionary to all of them.
    private typealias ObjC1 = @convention(c) (AnyObject, Selector, AnyObject) -> Void
    private typealias ObjC2 = @convention(c) (AnyObject, Selector, AnyObject, AnyObject?) -> Void
    private typealias ObjC3 = @convention(c) (AnyObject, Selector, AnyObject, AnyObject?, AnyObject?) -> Void

    private func imp<T>(_ sut: PostHogSDK, _ selector: String, as _: T.Type) -> (Selector, T) {
        let sel = NSSelectorFromString(selector)
        return (sel, unsafeBitCast(sut.method(for: sel), to: T.self))
    }

    @inline(never) private func siteObjCError(_ sut: PostHogSDK) {
        let (sel, call) = imp(sut, "captureExceptionWithError:", as: ObjC1.self)
        call(sut, sel, TestError() as NSError)
    }

    @inline(never) private func siteObjCErrorWithProps(_ sut: PostHogSDK) {
        let (sel, call) = imp(sut, "captureExceptionWithError:properties:", as: ObjC2.self)
        call(sut, sel, TestError() as NSError, ["key": "value"] as NSDictionary)
    }

    @inline(never) private func siteObjCErrorWithOpts(_ sut: PostHogSDK) {
        let (sel, call) = imp(sut, "captureExceptionWithError:properties:options:", as: ObjC3.self)
        call(sut, sel, TestError() as NSError, nil, ["process_person_profile": false] as NSDictionary)
    }

    @inline(never) private func siteObjCNeverRaised(_ sut: PostHogSDK) {
        let (sel, call) = imp(sut, "captureExceptionWithNSException:", as: ObjC1.self)
        call(sut, sel, neverRaised())
    }

    @inline(never) private func siteObjCNeverRaisedWithProps(_ sut: PostHogSDK) {
        let (sel, call) = imp(sut, "captureExceptionWithNSException:properties:", as: ObjC2.self)
        call(sut, sel, neverRaised(), ["key": "value"] as NSDictionary)
    }

    @inline(never) private func siteObjCNeverRaisedWithOpts(_ sut: PostHogSDK) {
        let (sel, call) = imp(sut, "captureExceptionWithNSException:properties:options:", as: ObjC3.self)
        call(sut, sel, neverRaised(), nil, ["process_person_profile": false] as NSDictionary)
    }

    private func callSite(_ name: String) -> (PostHogSDK) -> Void {
        switch name {
        case "siteSwiftError": return siteSwiftError
        case "siteSwiftErrorWithProps": return siteSwiftErrorWithProps
        case "siteSwiftErrorWithOpts": return siteSwiftErrorWithOpts
        case "siteNeverRaised": return siteNeverRaised
        case "siteNeverRaisedWithProps": return siteNeverRaisedWithProps
        case "siteNeverRaisedWithOpts": return siteNeverRaisedWithOpts
        case "siteObjCError": return siteObjCError
        case "siteObjCErrorWithProps": return siteObjCErrorWithProps
        case "siteObjCErrorWithOpts": return siteObjCErrorWithOpts
        case "siteObjCNeverRaised": return siteObjCNeverRaised
        case "siteObjCNeverRaisedWithProps": return siteObjCNeverRaisedWithProps
        default: return siteObjCNeverRaisedWithOpts
        }
    }

    @Test("the top frame is the caller", arguments: [
        "siteSwiftError", "siteSwiftErrorWithProps", "siteSwiftErrorWithOpts",
        "siteNeverRaised", "siteNeverRaisedWithProps", "siteNeverRaisedWithOpts",
        "siteObjCError", "siteObjCErrorWithProps", "siteObjCErrorWithOpts",
        "siteObjCNeverRaised", "siteObjCNeverRaisedWithProps", "siteObjCNeverRaisedWithOpts",
    ])
    func topFrameIsCaller(site: String) throws {
        let captured = Captured()
        let sut = getSut(captured)
        defer { sut.close() }

        callSite(site)(sut)

        let top = try #require(try functions(captured).first)
        #expect(isCallSite(top, site), "top frame: \(top)")
    }
}
