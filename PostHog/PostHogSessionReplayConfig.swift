//
//  PostHogSessionReplayConfig.swift
//  PostHog
//

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

    // TODO: sessionRecording config such as consoleLogRecordingEnabled, networkPayloadCapture, sampleRate, etc
}
