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

        // TODO: sessionRecording config such as networkPayloadCapture, captureConsoleLogs, sampleRate, etc
    }
#endif
