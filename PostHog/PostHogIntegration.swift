//
//  PostHogIntegration.swift
//  PostHog
//
//  Created by Ioannis Josephides on 25/02/2025.
//
import Foundation

protocol PostHogIntegration {
    /**
     * Installs and initializes the integration with a PostHogSDK instance.
     *
     * This method should:
     * 1. Run checks if needed to ensure that the integration is only installed once
     * 2. Initialize any required resources
     * 3. Start the integration's functionality
     *
     * - Parameter postHog: The PostHogSDK instance to integrate with
     * - Throws: InternalPostHogError if installation fails (e.g., already installed)
     */
    func install(_ postHog: PostHogSDK) throws

    /**
     * Uninstalls the integration from a specific PostHogSDK instance.
     *
     * This method should:
     * 1. Stop all integration functionality
     * 2. Clean up any resources
     * 3. Remove references to the PostHog instance
     *
     * - Parameter postHog: The PostHog SDK instance to uninstall from
     */
    func uninstall(_ postHog: PostHogSDK)

    /**
     * Starts the integration's functionality.
     *
     * Note: This is typically called automatically during installation
     * but may be called manually to restart a stopped integration.
     */
    func start()

    /**
     * Stops the integration's functionality without uninstalling.
     *
     * Note: This is typically called automatically during uninstallation
     * but may be called manually to temporarily suspend the integration
     * while maintaining its installation status (e.g manual start/stop for session recording)
     */
    func stop()
}
