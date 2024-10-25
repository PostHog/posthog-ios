//
//  PostHogAutocaptureConfig.swift
//  PostHog
//
//  Created by Yiannis Josephides on 23/10/2024.
//

#if os(iOS) || targetEnvironment(macCatalyst)
    import Foundation

    @objc(PostHogAutocaptureConfig)
    public class PostHogAutocaptureConfig: NSObject {
        /**
         Capture text input changes and edits
         Experimental support
         Default: true
         */
        @objc public var captureTextEdits: Bool = true

        /**
         Capture gestures such as swipes and taps.
         Experimental support
         Default: true
         */
        @objc public var captureGestures: Bool = true

        /**
         Capture action events such as button presses
         Experimental support
         Default: true
         */
        @objc public var captureControlActions: Bool = true

        /**
         Captures values or text from controls such as text views and buttons
         Experimental support
         Default: true
         */
        @objc public var captureValues: Bool = true
    }
#endif
