//
//  PostHogContextTest.swift
//  PostHogTests
//
//  Created by Manoel Aranda Neto on 30.10.23.
//

import Foundation
import Nimble
@testable import PostHog
import Quick

class PostHogContextTest: QuickSpec {
    func getSut() -> PostHogContext {
        var reachability: Reachability?
        do {
            reachability = try Reachability()
        } catch {
            // ignored
        }
        return PostHogContext(reachability)
    }

    override func spec() {
        it("returns static context") {
            let sut = self.getSut()

            let context = sut.staticContext()
            expect(context["$app_name"] as? String) == "xctest"
            expect(context["$app_version"] as? String) != nil
            expect(context["$app_build"] as? String) != nil
            expect(context["$app_namespace"] as? String) == "com.apple.dt.xctest.tool"
            #if os(iOS) || os(tvOS)
                expect(context["$device_name"] as? String) != nil
                expect(context["$os_name"] as? String) != nil
                expect(context["$os_version"] as? String) != nil
                expect(context["$device_type"] as? String) != nil
                expect(context["$device_model"] as? String) != nil
                expect(context["$device_manufacturer"] as? String) == "Apple"
            #endif
        }

        it("returns dynamic context") {
            let sut = self.getSut()

            let context = sut.dynamicContext()

            #if os(iOS) || os(tvOS)
                expect(context["$screen_width"] as? Float) != nil
                expect(context["$screen_height"] as? Float) != nil
            #endif
            expect(context["$lib"] as? String) == "posthog-ios"
            expect(context["$lib_version"] as? String) == postHogVersion
            expect(context["$locale"] as? String) != nil
            expect(context["$timezone"] as? String) != nil
            expect(context["$network_wifi"] as? Bool) != nil
            expect(context["$network_cellular"] as? Bool) != nil
        }
    }
}
