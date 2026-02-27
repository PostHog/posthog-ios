//
//  PostHogContextTest.swift
//  PostHogTests
//
//  Created by Manoel Aranda Neto on 30.10.23.
//

import Foundation
@testable import PostHog
import Testing

@Suite("PostHogContext Tests")
struct PostHogContextTest {
    func getSut() -> PostHogContext {
        #if !os(watchOS)
            var reachability: Reachability?
            do {
                reachability = try Reachability()
            } catch {
                // ignored
            }
            return PostHogContext(reachability)
        #else
            return PostHogContext()
        #endif
    }

    @Test("returns static context")
    func returnsStaticContext() {
        let sut = getSut()

        let context = sut.staticContext()
        // Bundle.main.infoDictionary is empty when running via `swift test` (SPM)
        // so app_name, app_version, app_build may not be present
        let hasBundleInfo = Bundle.main.infoDictionary?.isEmpty == false
        if hasBundleInfo {
            #expect(context["$app_name"] as? String != nil)
            #expect(context["$app_version"] as? String != nil)
            #expect(context["$app_build"] != nil)
            #expect(context["$app_namespace"] as? String != nil)
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
        #expect(context["$network_wifi"] as? Bool != nil)
        #expect(context["$network_cellular"] as? Bool != nil)
    }

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

        // Bundle.main.infoDictionary is empty when running via `swift test` (SPM)
        let hasBundleInfo = Bundle.main.infoDictionary?.isEmpty == false
        if hasBundleInfo {
            #expect(context["$app_version"] as? String != nil)
            #expect(context["$app_build"] != nil)
            #expect(context["$app_namespace"] as? String != nil)
        }

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
