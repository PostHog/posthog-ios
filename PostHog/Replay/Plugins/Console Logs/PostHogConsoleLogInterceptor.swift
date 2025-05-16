//
//  PostHogConsoleLogInterceptor.swift
//  PostHog
//
//  Created by Ioannis Josephides on 05/05/2025.
//

#if os(iOS)
    import Foundation

    final class PostHogConsoleLogInterceptor {
        private let maxLogStringSize = 2000 // Maximum number of characters allowed in a string

        struct ConsoleOutput {
            let timestamp: Date
            let text: String
            let level: PostHogLogLevel
        }

        static let shared = PostHogConsoleLogInterceptor()

        // Pipe redirection properties
        private var stdoutPipe: Pipe?
        private var stderrPipe: Pipe?
        private var originalStdout: Int32 = -1
        private var originalStderr: Int32 = -1

        private init() { /* Singleton */ }

        func startCapturing(config: PostHogConfig, callback: @escaping (ConsoleOutput) -> Void) {
            stopCapturing() // cleanup
            setupPipeRedirection(config: config, callback: callback)
        }

        private func setupPipeRedirection(config: PostHogConfig, callback: @escaping (ConsoleOutput) -> Void) {
            // Set stdout/stderr to unbuffered mode (_IONBF) to ensure real-time output capture.
            // Without this, output might be buffered and only flushed when the buffer is full or
            // when explicitly flushed, which is especially problematic without an attached debugger
            setvbuf(stdout, nil, _IONBF, 0)
            setvbuf(stderr, nil, _IONBF, 0)

            // Save original file descriptors
            originalStdout = dup(STDOUT_FILENO)
            originalStderr = dup(STDERR_FILENO)

            stdoutPipe = Pipe()
            stderrPipe = Pipe()

            guard let stdoutPipe = stdoutPipe, let stderrPipe = stderrPipe else { return }

            // Redirect stdout and stderr to our pipes
            dup2(stdoutPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
            dup2(stderrPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

            // Setup and handle pipe output
            setupPipeSource(for: originalStdout, fileHandle: stdoutPipe.fileHandleForReading, config: config, callback: callback)
            setupPipeSource(for: originalStderr, fileHandle: stderrPipe.fileHandleForReading, config: config, callback: callback)
        }

        private func setupPipeSource(for originalFd: Int32, fileHandle: FileHandle, config: PostHogConfig, callback: @escaping (ConsoleOutput) -> Void) {
            fileHandle.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty,
                      let output = String(data: data, encoding: .utf8),
                      let self = self else { return }

                // Write to original file descriptor, so logs appear normally
                if originalFd != -1 {
                    if let data = output.data(using: .utf8) {
                        _ = data.withUnsafeBytes { ptr in
                            write(originalFd, ptr.baseAddress, ptr.count)
                        }
                    }
                }

                self.processOutput(output, config: config, callback: callback)
            }
        }

        private func processOutput(_ output: String, config: PostHogConfig, callback: @escaping (ConsoleOutput) -> Void) {
            // Skip internal logs and empty lines
            // Note: Need to skip internal logs because `config.debug` may be enabled. If that's the case, then
            // the process of capturing logs, will generate more logs, leading to an infinite loop. This relies on hedgeLog() format which should
            // be okay, even not ideal
            guard !output.contains("[PostHog]"), !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }

            // Process log entries from config
            let entries = output
                .components(separatedBy: CharacterSet.newlines) // split by line
                .lazy
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } // Skip empty strings and new lines
                .compactMap(config.sessionReplayConfig.captureLogsConfig.logSanitizer)

            for entry in entries where shouldCaptureLog(entry: entry, config: config) {
                callback(ConsoleOutput(timestamp: Date(), text: truncatedOutput(entry.message), level: entry.level))
            }
        }

        /// Determines if the log message should be captured, based on config
        private func shouldCaptureLog(entry: PostHogLogEntry, config: PostHogConfig) -> Bool {
            entry.level.rawValue >= config.sessionReplayConfig.captureLogsConfig.minLogLevel.rawValue
        }

        /// Console logs can be really large.
        /// This function returns a truncated version of the console output if it exceeds `maxLogStringSize`
        private func truncatedOutput(_ output: String) -> String {
            guard output.count > maxLogStringSize else { return output }
            return "\(output.prefix(maxLogStringSize))...[truncated]"
        }

        func stopCapturing() {
            // Restore original file descriptors
            if originalStdout != -1 {
                dup2(originalStdout, STDOUT_FILENO)
                close(originalStdout)
                originalStdout = -1
            }

            if originalStderr != -1 {
                dup2(originalStderr, STDERR_FILENO)
                close(originalStderr)
                originalStderr = -1
            }

            // remove pipes
            stdoutPipe?.fileHandleForReading.readabilityHandler = nil
            stderrPipe?.fileHandleForReading.readabilityHandler = nil
            stdoutPipe?.fileHandleForReading.closeFile()
            stderrPipe?.fileHandleForReading.closeFile()
            stdoutPipe = nil
            stderrPipe = nil
        }
    }
#endif
