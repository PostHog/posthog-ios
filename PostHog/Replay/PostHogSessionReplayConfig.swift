//
//  PostHogSessionReplayConfig.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 19.03.24.
//
#if os(iOS)
    import Foundation

    @objc(PostHogSessionReplayConfig) public class PostHogSessionReplayConfig: NSObject {
        /// Enable masking of all text input fields
        /// Experimental support
        /// Default: true
        @objc public var maskAllTextInputs: Bool = true

        /// Enable masking of all images to a placeholder
        /// Experimental support
        /// Default: true
        @objc public var maskAllImages: Bool = true

        /// Enable capturing network telemetry
        /// Experimental support
        /// Default: true
        @objc public var captureNetworkTelemetry: Bool = true

        /// By default Session replay will capture all the views on the screen as a wireframe,
        /// By enabling this option, PostHog will capture the screenshot of the screen.
        /// The screenshot may contain sensitive information, use with caution.
        /// Experimental support
        /// Default: false
        @objc public var screenshotMode: Bool = false

        // TODO: sessionRecording config such as networkPayloadCapture, captureConsoleLogs, sampleRate, etc
    }
#endif
