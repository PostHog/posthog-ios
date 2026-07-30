import Foundation
@testable import PostHog
import Testing

// Swizzling mutates class-level state for the process lifetime, so every test uses its own fixture
// class and the suite is serialized.
private enum SwizzlerLog {
    static var invocations: [String] = []
}

private class FixtureImplementing: NSObject {
    @objc dynamic func ph_test_fixtureCallback(_ value: NSNumber) {
        SwizzlerLog.invocations.append("original:\(value)")
    }
}

private class FixtureImplementingCycle: NSObject {
    @objc dynamic func ph_test_fixtureCallback(_ value: NSNumber) {
        SwizzlerLog.invocations.append("original:\(value)")
    }
}

private class FixtureMissing: NSObject {}
private class FixtureMissingCycle: NSObject {}
private class FixtureMissingPostCycle: NSObject {}

private extension NSObject {
    @objc func ph_test_swizzled_fixtureCallback(_ value: NSNumber) {
        SwizzlerLog.invocations.append("swizzled:\(value)")
        ph_test_swizzled_fixtureCallback(value)
    }

    @objc func ph_test_noop_fixtureCallback(_ value: NSNumber) {
        SwizzlerLog.invocations.append("noop:\(value)")
    }
}

@Suite("Test swizzleAddingIfNeeded", .serialized)
class PostHogSwizzlerTest {
    private let originalSelector = #selector(FixtureImplementing.ph_test_fixtureCallback(_:))
    private let swizzledSelector = #selector(NSObject.ph_test_swizzled_fixtureCallback(_:))
    private let noopSelector = #selector(NSObject.ph_test_noop_fixtureCallback(_:))

    init() {
        SwizzlerLog.invocations = []
    }

    private func invoke(_ target: NSObject, _ value: Int) {
        _ = target.perform(originalSelector, with: NSNumber(value: value))
    }

    @Test("adds the method and routes the call-through to the noop when the class doesn't implement it")
    func addsMethodWhenMissing() {
        swizzleAddingIfNeeded(on: FixtureMissing.self, original: originalSelector, swizzled: swizzledSelector, noop: noopSelector)

        invoke(FixtureMissing(), 1)

        #expect(SwizzlerLog.invocations == ["swizzled:1", "noop:1"])
    }

    @Test("exchanges implementations and calls through to the original when the class implements it")
    func exchangesWhenImplemented() {
        swizzleAddingIfNeeded(on: FixtureImplementing.self, original: originalSelector, swizzled: swizzledSelector)

        invoke(FixtureImplementing(), 2)

        #expect(SwizzlerLog.invocations == ["swizzled:2", "original:2"])
    }

    @Test("re-install after unswizzle restores the exchange without corrupting NSObject or recursing")
    func reinstallAfterUnswizzleOnImplementingClass() {
        let sut = FixtureImplementingCycle()

        swizzleAddingIfNeeded(on: FixtureImplementingCycle.self, original: originalSelector, swizzled: swizzledSelector)
        swizzle(forClass: FixtureImplementingCycle.self, original: originalSelector, new: swizzledSelector)

        invoke(sut, 3)
        #expect(SwizzlerLog.invocations == ["original:3"])

        SwizzlerLog.invocations = []
        swizzleAddingIfNeeded(on: FixtureImplementingCycle.self, original: originalSelector, swizzled: swizzledSelector)

        invoke(sut, 4)
        #expect(SwizzlerLog.invocations == ["swizzled:4", "original:4"])

        // NSObject's shared swizzled implementation must survive the cycle: a fresh class swizzled
        // afterwards still gets the real implementation, not a leaked original.
        SwizzlerLog.invocations = []
        swizzleAddingIfNeeded(on: FixtureMissingPostCycle.self, original: originalSelector, swizzled: swizzledSelector, noop: noopSelector)
        invoke(FixtureMissingPostCycle(), 5)
        #expect(SwizzlerLog.invocations == ["swizzled:5", "noop:5"])
    }

    @Test("re-install after unswizzle works when the first install added the missing method")
    func reinstallAfterUnswizzleOnAddedClass() {
        let sut = FixtureMissingCycle()

        swizzleAddingIfNeeded(on: FixtureMissingCycle.self, original: originalSelector, swizzled: swizzledSelector, noop: noopSelector)
        swizzle(forClass: FixtureMissingCycle.self, original: originalSelector, new: swizzledSelector)

        SwizzlerLog.invocations = []
        swizzleAddingIfNeeded(on: FixtureMissingCycle.self, original: originalSelector, swizzled: swizzledSelector, noop: noopSelector)

        invoke(sut, 6)
        #expect(SwizzlerLog.invocations == ["swizzled:6", "noop:6"])
    }
}
