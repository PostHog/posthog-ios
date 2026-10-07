//
//  PostHogCallbackIsolationTests.swift
//  PostHogSwift6Tests
//

import Foundation
import PostHog
import Testing

/// Calls the public callback APIs from main-actor code, as a Swift 6 app would.
///
/// In Swift 6 mode, a closure written in main-actor code and passed as a non-`Sendable`
/// parameter is main-actor isolated, and the runtime traps if the SDK calls it off the main thread.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PostHogCallbackIsolationTests {
    @MainActor final class AppState {
        var reloadResult: PostHogFeatureFlagsLoaded?
        var loaded: PostHogFeatureFlagsLoaded?
        var deliveredOnMain = false
    }

    /// Nothing listens on this port, so requests fail fast without leaving the machine.
    private func makeSDK(bootstrapFlags: [String: Any]? = nil) -> PostHogSDK {
        let config = PostHogConfig(projectToken: "phc_swift6_\(UUID().uuidString)", host: "http://127.0.0.1:9")
        config.captureApplicationLifecycleEvents = false
        config.preloadFeatureFlags = false
        if let bootstrapFlags {
            let bootstrap = PostHogBootstrapConfig()
            bootstrap.featureFlags = bootstrapFlags
            config.bootstrap = bootstrap
        }
        return PostHogSDK.with(config)
    }

    @Test("reloadFeatureFlags callback written in main-actor code runs without an isolation trap")
    func reloadCallbackFromMainActorCode() async {
        let sdk = makeSDK()
        defer { sdk.close() }
        let state = AppState()

        // The SDK invokes this from its network completion, off the main thread.
        await withCheckedContinuation { continuation in
            sdk.reloadFeatureFlags { result in
                // Sending the result into the hop requires it to be Sendable.
                Task { @MainActor in
                    state.reloadResult = result
                    continuation.resume()
                }
            }
        }

        #expect(state.reloadResult != nil)
    }

    @Test("onFeatureFlags callback written in main-actor code runs on main with a Sendable payload")
    func onFeatureFlagsDeliversOnMainActor() async {
        let sdk = makeSDK(bootstrapFlags: ["swift6-flag": true])
        defer { sdk.close() }
        let state = AppState()

        var subscription: PostHogFeatureFlagsSubscription?
        await withCheckedContinuation { continuation in
            subscription = sdk.onFeatureFlags { loaded in
                // Touches main-actor state directly, with no hop.
                guard state.loaded == nil else { return }
                state.loaded = loaded
                state.deliveredOnMain = Thread.isMainThread
                continuation.resume()
            }
        }
        subscription?.unsubscribe()

        #expect(state.deliveredOnMain)
        // Sending the payload to another task requires it to be Sendable.
        let loaded = state.loaded
        let flags = await Task.detached { loaded?.flags ?? [] }.value
        #expect(flags == ["swift6-flag"])
    }

    @Test("onFeatureFlags payload keeps its variant values when a mutable bootstrap value changes")
    func onFeatureFlagsPayloadIsImmutable() async {
        let source = NSMutableString(string: "original")
        let sdk = makeSDK(bootstrapFlags: ["swift6-variant": source])
        defer { sdk.close() }
        let state = AppState()

        var subscription: PostHogFeatureFlagsSubscription?
        await withCheckedContinuation { continuation in
            subscription = sdk.onFeatureFlags { loaded in
                guard state.loaded == nil else { return }
                state.loaded = loaded
                continuation.resume()
            }
        }
        subscription?.unsubscribe()

        source.setString("changed")
        let loaded = state.loaded
        let variant = await Task.detached { loaded?.variants["swift6-variant"] as? String }.value
        #expect(variant == "original")
    }
}
