//
//  PostHogSessionReplayPlugin.swift
//  PostHog
//
//  Created by Ioannis Josephides on 12/05/2025.
//

#if os(iOS)
    import Foundation

    /// Session replay plugins are used to capture specific types of meta data during a session,
    /// such as console logs, network requests and user interactions. Each plugin is responsible
    /// for managing its own capture lifecycle and sending data to PostHog.
    ///
    /// Plugins are installed automatically based on the session replay configuration.
    protocol PostHogSessionReplayPlugin {
        /// Starts the plugin and begins data capture.
        ///
        /// Called when session replay is started. The plugin should set up any required
        /// resources and begin capturing data.
        ///
        /// - Parameter postHog: The PostHog SDK instance to use for sending data
        func start(postHog: PostHogSDK)

        /// Stops the plugin and cleans up resources.
        ///
        /// Called when session replay is stopped. The plugin should clean up any resources
        /// and stop capturing data.
        func stop()

        /// Temporarily pauses data capture.
        ///
        /// Called by session replay integration when plugin is requested to temporarily pause capturing data
        /// The plugin should pause data capture but maintain its state.
        func pause()

        /// Resumes data capture after being paused.
        ///
        /// Called by session replay integration when plugin is requested to resume normal capturing data
        /// The plugin should resume data capture from its previous state.
        func resume()
    }
#endif
