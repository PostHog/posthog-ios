//
//  PostHogContextTest.swift
//  PostHogTests
//
//  Created by Manoel Aranda Neto on 30.10.23.
//

import Foundation
@_spi(PostHogInternal) @testable import PostHog
import Testing

@Suite("PostHogContext", .serialized, .resetsGlobalState)
struct PostHogContextTest {
    /// The `$app_*` values come from the host process's `Bundle.main`. Under Xcode (and XCTest) the
    /// host is `xctest`; `swift test` runs Swift Testing in `swiftpm-testing-helper`, which has no
    /// Info.plist, so the host-specific values below are only asserted under the `xctest` host.
    private static let isXCTestHost = Bundle.main.bundleIdentifier == "com.apple.dt.xctest.tool"

    private func getSut() -> PostHogContext {
        #if !os(watchOS)
            return PostHogContext(Reachability(notificationQueue: nil, monitorsPaths: false))
        #else
            return PostHogContext()
        #endif
    }

    @Test("returns static context")
    func returnsStaticContext() {
        let sut = getSut()

        let context = sut.staticContext()
        if Self.isXCTestHost {
            #expect(context["$app_name"] as? String == "xctest")
            #expect(context["$app_version"] as? String != nil)
            #expect(context["$app_build"] as? Int != nil)
            #expect(context["$app_namespace"] as? String == "com.apple.dt.xctest.tool")
        } else {
            #expect(context["$app_namespace"] as? String == testBundleIdentifier)
        }
        #expect(context["$is_emulator"] as? Bool != nil)
        #if os(iOS) || os(tvOS) || os(visionOS)
            #expect(context["$device_name"] as? String != nil)
            #expect(context["$os_name"] as? String != nil)
            #expect(context["$os_version"] as? String != nil)
            #expect(context["$device_type"] as? String != nil)
            #expect(context["$device_model"] as? String != nil)
            #expect(context["$device_manufacturer"] as? String == "Apple")
        #endif
    }

    @Test("returns dynamic context")
    func returnsDynamicContext() {
        let sut = getSut()

        let context = sut.dynamicContext()

        #expect(context["$locale"] as? String != nil)
        #expect(context["$timezone"] as? String != nil)
    }

    #if !os(watchOS)
        @Test("omits network properties until a path arrives")
        func omitsNetworkPropertiesWhileConnectionUnknown() {
            let sut = PostHogContext(Reachability(notificationQueue: nil, monitorsPaths: false))

            let context = sut.dynamicContext()

            #expect(context["$network_wifi"] == nil)
            #expect(context["$network_cellular"] == nil)
        }

        @Test("reports network properties from the current connection")
        func reportsNetworkPropertiesFromConnection() {
            let reachability = Reachability(notificationQueue: nil, monitorsPaths: false)
            let sut = PostHogContext(reachability)

            reachability.update(.wifi)
            var context = sut.dynamicContext()
            #expect(context["$network_wifi"] as? Bool == true)
            #expect(context["$network_cellular"] as? Bool == false)

            reachability.update(.cellular)
            context = sut.dynamicContext()
            #expect(context["$network_wifi"] as? Bool == false)
            #expect(context["$network_cellular"] as? Bool == true)
        }
    #endif

    @Test("returns sdk info")
    func returnsSdkInfo() {
        let sut = getSut()

        let context = sut.sdkInfo()

        #expect(context["$lib"] as? String == "posthog-ios")
        #expect(context["$lib_version"] as? String == postHogVersion)
    }

    @Test("returns person properties context")
    func returnsPersonPropertiesContext() {
        let sut = getSut()

        let context = sut.personPropertiesContext()

        // Check that it includes expected properties from static context
        if Self.isXCTestHost {
            #expect(context["$app_version"] as? String != nil)
            #expect(context["$app_build"] as? Int != nil)
        }
        #expect(context["$app_namespace"] as? String != nil)

        #if os(iOS) || os(tvOS) || os(visionOS)
            #expect(context["$os_name"] as? String != nil)
            #expect(context["$os_version"] as? String != nil)
            #expect(context["$device_type"] as? String != nil)
        #endif

        #expect(context["$lib"] as? String == "posthog-ios")
        #expect(context["$lib_version"] as? String == postHogVersion)

        // Verify it doesn't include non-person properties
        #expect(context["$is_emulator"] as? Bool == nil)
    }
}
