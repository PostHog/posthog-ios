//
//  PostHogExceptionProcessor.swift
//  PostHog
//
//  Created by Ioannis Josephides on 14/11/2025.
//

import Darwin
import Foundation

/// Processes errors and exceptions into PostHog's $exception event format
///
/// This class converts Swift Error and NSException instances into PostHog exception event properties.
/// It automatically attaches binary image metadata (`$debug_images`) needed for server-side symbolication.
///
enum PostHogExceptionProcessor {
    // MARK: - Public API

    /// Convert Error/NSError to properties
    ///
    /// - Parameters:
    ///   - error: The error to convert
    ///   - handled: Whether the error was caught/handled
    ///   - mechanismType: The mechanism that captured the error (e.g., "generic", "onunhandledexception")
    ///   - config: Error tracking configuration for in-app detection
    /// - Returns: Dictionary of properties in PostHog's $exception event format
    static func errorToProperties(
        _ error: Error,
        handled: Bool,
        mechanismType: String = "generic",
        config: PostHogErrorTrackingConfig
    ) -> [String: Any] {
        var properties: [String: Any] = [:]

        properties["$exception_level"] = "error" // TODO: figure if error or fatal based on wrapper error type when

        let exceptions = buildExceptionList(
            from: error,
            handled: handled,
            mechanismType: mechanismType,
            config: config
        )

        attachExceptionsAndDebugImages(exceptions, to: &properties)

        return properties
    }

    /// Convert NSException to properties
    ///
    /// Note: Uses the exception's own stack trace (`callStackReturnAddresses`) if available,
    /// otherwise falls back to capturing the current thread's stack (synthetic).
    ///
    /// - Parameters:
    ///   - exception: The NSException to convert
    ///   - handled: Whether the exception was caught/handled
    ///   - mechanismType: The mechanism type for categorizing the exception
    ///   - config: Error tracking configuration for in-app detection
    /// - Returns: Dictionary of properties in PostHog's $exception event format
    static func exceptionToProperties(
        _ exception: NSException,
        handled: Bool,
        mechanismType: String = "generic",
        config: PostHogErrorTrackingConfig
    ) -> [String: Any] {
        var properties: [String: Any] = [:]
        properties["$exception_level"] = "error" // TODO: figure this out from error wrapped type

        let exceptions = buildExceptionList(
            from: exception,
            handled: handled,
            mechanismType: mechanismType,
            config: config
        )

        attachExceptionsAndDebugImages(exceptions, to: &properties)

        return properties
    }

    /// Convert a message string to properties
    ///
    /// - Parameters:
    ///   - message: The error message to convert
    ///   - type: Optional exception type name (defaults to "String")
    ///   - config: Error tracking configuration for in-app detection
    /// - Returns: Dictionary of properties in PostHog's $exception event format
    static func messageToProperties(
        _ message: String,
        mechanismType: String = "generic",
        config: PostHogErrorTrackingConfig
    ) -> [String: Any] {
        var properties: [String: Any] = [:]

        properties["$exception_level"] = "error"

        var exception: [String: Any] = [:]
        exception["type"] = "Message"
        exception["value"] = message
        exception["thread_id"] = Thread.current.threadId

        exception["mechanism"] = [
            "type": mechanismType,
            "handled": true,
            "synthetic": true, // always true for message exceptions - we capture current stack
        ]

        if let stacktrace = buildStacktrace(config: config) {
            exception["stacktrace"] = stacktrace
        }

        let exceptions = [exception]
        attachExceptionsAndDebugImages(exceptions, to: &properties)

        return properties
    }

    // MARK: - Internal Exception Building

    /// Build list of exceptions from NSException chain
    ///
    /// Walks the NSException chain via NSUnderlyingErrorKey to capture all related exceptions.
    /// The list is ordered root-first, matching iOS console output format where the outermost
    /// exception is displayed first with underlying exceptions nested inside.
    ///
    /// Example iOS console output:
    /// ```
    /// Error Domain=OuterErrorDomain Code=300 "Outer wrapper" UserInfo={
    ///     NSUnderlyingError=0x... {Error Domain=InnerErrorDomain Code=100 "Root cause" ...}
    /// }
    /// ```
    private static func buildExceptionList(
        from exception: NSException,
        handled: Bool,
        mechanismType: String,
        config: PostHogErrorTrackingConfig
    ) -> [[String: Any]] {
        var exceptions: [[String: Any]] = []
        var nsExceptions: [NSException] = []

        // Walk exception chain via NSUnderlyingErrorKey
        nsExceptions.append(exception)

        var current = exception
        while let underlying = current.userInfo?[NSUnderlyingErrorKey] as? NSException {
            nsExceptions.append(underlying)
            current = underlying
        }

        // Build exceptions in order: root first, deepest underlying last
        // This matches iOS console output format
        for exc in nsExceptions {
            if let exceptionDict = buildException(
                from: exc,
                handled: handled,
                mechanismType: mechanismType,
                config: config
            ) {
                exceptions.append(exceptionDict)
            }
        }

        return exceptions
    }

    /// Build list of exceptions from error chain
    ///
    /// Walks the error chain via NSUnderlyingErrorKey to capture all related errors.
    /// The list is ordered root-first, matching iOS console output format where the outermost
    /// error is displayed first with underlying errors nested inside.
    ///
    /// Example iOS console output:
    /// ```
    /// Error Domain=OuterErrorDomain Code=300 "Outer wrapper" UserInfo={
    ///     NSUnderlyingError=0x... {Error Domain=InnerErrorDomain Code=100 "Root cause" ...}
    /// }
    /// ```
    private static func buildExceptionList(
        from error: Error,
        handled: Bool,
        mechanismType: String,
        config: PostHogErrorTrackingConfig
    ) -> [[String: Any]] {
        var exceptions: [[String: Any]] = []
        var errors: [NSError] = []

        // Walk error chain via NSUnderlyingErrorKey
        let nsError = error as NSError
        errors.append(nsError)

        var current = nsError
        while let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError {
            errors.append(underlying)
            current = underlying
        }

        // Build exceptions in order: root first, deepest underlying last
        // This matches iOS console output format
        for err in errors {
            if let exception = buildException(
                from: err,
                handled: handled,
                mechanismType: mechanismType,
                config: config
            ) {
                exceptions.append(exception)
            }
        }

        return exceptions
    }

    /// Build a single exception dictionary from an NSError
    private static func buildException(
        from error: NSError,
        handled: Bool,
        mechanismType: String,
        config: PostHogErrorTrackingConfig
    ) -> [String: Any]? {
        var exception: [String: Any] = [:]

        exception["type"] = extractTypeName(from: error)

        if let message = extractErrorMessage(from: error) {
            exception["value"] = message
        }

        if let moduleName = extractModule(from: error) {
            exception["module"] = moduleName
        }

        exception["thread_id"] = Thread.current.threadId

        exception["mechanism"] = [
            "type": mechanismType,
            "handled": handled,
            "synthetic": true, // Always true for NSError - we capture current stack
        ]

        if let stacktrace = buildStacktrace(config: config) {
            exception["stacktrace"] = stacktrace
        }

        return exception
    }

    /// Build a single exception dictionary from an NSException
    private static func buildException(
        from exception: NSException,
        handled: Bool,
        mechanismType: String,
        config: PostHogErrorTrackingConfig
    ) -> [String: Any]? {
        var exceptionDict: [String: Any] = [:]

        exceptionDict["type"] = exception.name.rawValue
        exceptionDict["thread_id"] = Thread.current.threadId
        if let reason = exception.reason {
            exceptionDict["value"] = reason
        }

        // Use exception's real stack if available, otherwise capture current (synthetic)
        let exceptionAddresses = exception.callStackReturnAddresses
        let isSynthetic: Bool
        let stacktrace: [String: Any]?

        if !exceptionAddresses.isEmpty {
            // Use exception's actual stack trace (captured when exception was raised)
            stacktrace = buildStacktraceFromAddresses(exceptionAddresses, config: config)
            isSynthetic = false
        } else {
            // Fall back to current stack (synthetic - captured at reporting site)
            stacktrace = buildStacktrace(config: config)
            isSynthetic = true
        }

        exceptionDict["mechanism"] = [
            "type": mechanismType,
            "handled": handled,
            "synthetic": isSynthetic,
        ]

        if let stacktrace = stacktrace {
            exceptionDict["stacktrace"] = stacktrace
        }

        return exceptionDict
    }

    // MARK: - Error Message Extraction

    /// Extract user-friendly error message
    ///
    /// Priority:
    /// 1. Debug description (NSDebugDescriptionErrorKey)
    /// 2. Localized description (NSLocalizedDescriptionKey)
    private static func extractErrorMessage(from error: NSError) -> String? {
        if let debugDesc = error.userInfo[NSDebugDescriptionErrorKey] as? String {
            return "\(debugDesc) (Code: \(error.code))"
        }

        return "\(error.localizedDescription) (Code: \(error.code))"
    }

    /// Extract clean type name from error
    ///
    /// Uses Swift's type reflection to get the actual type name.
    /// Falls back to error domain for Objective-C errors.
    private static func extractTypeName(from error: NSError) -> String {
        // Get the actual Swift type name using reflection
        let typeName = String(describing: type(of: error as Error))

        // If it's a plain NSError (not a Swift error bridged to NSError),
        // the type will just be "NSError" - use domain instead
        if typeName == "NSError" {
            return error.domain
        }

        return typeName
    }

    /// Extract module name from error domain
    ///
    /// For Swift errors, the domain contains the full module path (e.g., "MyApp.Networking.APIError").
    /// We extract everything except the type name at the end.
    private static func extractModule(from error: NSError) -> String? {
        let domain = error.domain

        // For domains without dots (e.g., NSCocoaErrorDomain), return nil
        guard let lastDot = domain.lastIndex(of: ".") else {
            return nil
        }

        // For dotted domains, extract everything before the last component (the type name)
        let module = String(domain[..<lastDot])

        return module.isEmpty ? nil : module
    }

    // MARK: - Helpers

    /// Attach exceptions and debug images to properties dictionary
    private static func attachExceptionsAndDebugImages(
        _ exceptions: [[String: Any]],
        to properties: inout [String: Any]
    ) {
        guard !exceptions.isEmpty else { return }
        properties["$exception_list"] = exceptions

        let debugImages = PostHogDebugImageProvider.getDebugImages(fromExceptions: exceptions)
        if !debugImages.isEmpty {
            properties["$debug_images"] = debugImages
        }
    }

    // MARK: - Stack Trace Capture

    /// Build stacktrace dictionary from current thread (synthetic)
    private static func buildStacktrace(config: PostHogErrorTrackingConfig) -> [String: Any]? {
        let frames = PostHogStackTraceProcessor.captureCurrentStackTraceWithMetadata(config: config)

        guard !frames.isEmpty else { return nil }

        return [
            "frames": frames.map(\.toDictionary),
            "type": "raw",
        ]
    }

    /// Build stacktrace dictionary from raw addresses (e.g., NSException.callStackReturnAddresses)
    private static func buildStacktraceFromAddresses(
        _ addresses: [NSNumber],
        config: PostHogErrorTrackingConfig
    ) -> [String: Any]? {
        // Don't strip PostHog frames for NSException - the addresses are from the exception itself
        let frames = PostHogStackTraceProcessor.symbolicateAddresses(addresses, config: config, stripTopPostHogFrames: false)

        guard !frames.isEmpty else { return nil }

        return [
            "frames": frames.map(\.toDictionary),
            "type": "raw",
        ]
    }
}

private extension Thread {
    /// Get the current thread's Mach thread ID
    var threadId: Int {
        Int(pthread_mach_thread_np(pthread_self()))
    }
}
