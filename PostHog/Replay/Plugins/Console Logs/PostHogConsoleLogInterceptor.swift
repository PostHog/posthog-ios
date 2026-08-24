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

        private enum Stream {
            case stdout
            case stderr
        }

        static let shared = PostHogConsoleLogInterceptor()

        // Pipe redirection properties
        // Guarded by `fdLock`, which the readability handlers also take, so that a handler
        // can never be mid-write against a file descriptor that teardown is closing
        private let fdLock = NSLock()
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

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            fdLock.lock()

            // Save original file descriptors
            originalStdout = dup(STDOUT_FILENO)
            originalStderr = dup(STDERR_FILENO)

            // A broken pipe on a descriptor we own must surface as EPIPE, not as a fatal
            // SIGPIPE that the host app cannot catch. NOSIGPIPE is a property of the open
            // file description, so the copies dup2'd onto STDOUT/STDERR inherit it too.
            setNoSigPipe(originalStdout)
            setNoSigPipe(originalStderr)
            setNoSigPipe(stdoutPipe.fileHandleForWriting.fileDescriptor)
            setNoSigPipe(stderrPipe.fileHandleForWriting.fileDescriptor)

            // Redirect stdout and stderr to our pipes
            dup2(stdoutPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
            dup2(stderrPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

            self.stdoutPipe = stdoutPipe
            self.stderrPipe = stderrPipe

            fdLock.unlock()

            // Setup and handle pipe output
            setupPipeSource(for: .stdout, fileHandle: stdoutPipe.fileHandleForReading, config: config, callback: callback)
            setupPipeSource(for: .stderr, fileHandle: stderrPipe.fileHandleForReading, config: config, callback: callback)
        }

        private func setNoSigPipe(_ descriptor: Int32) {
            guard descriptor != -1 else { return }
            _ = fcntl(descriptor, F_SETNOSIGPIPE, 1)
        }

        private func setupPipeSource(for stream: Stream, fileHandle: FileHandle, config: PostHogConfig, callback: @escaping (ConsoleOutput) -> Void) {
            fileHandle.readabilityHandler = { [weak self] handle in
                guard let self = self else { return }

                // Hold the lock for the read and the echo: `stopCapturing` takes the same lock
                // before closing these descriptors, so it cannot close one out from under us
                self.fdLock.lock()

                // Identity, not a sentinel: `stopCapturing` nils the pipes under this same lock, so
                // this is false exactly when the session that installed this handler is over. A
                // `-1` descriptor check would instead conflate that with "dup(STDOUT_FILENO)
                // failed" and skip the read, leaving the pipe to fill until every `print` blocks
                let pipe = stream == .stdout ? self.stdoutPipe : self.stderrPipe
                guard pipe?.fileHandleForReading === handle else {
                    self.fdLock.unlock()
                    return
                }

                // The read has to stay inside the lock: `stopCapturing` closes this handle while
                // holding it, so an unlocked read could hit an already closed descriptor and
                // raise `NSFileHandleOperationException` on EBADF
                let data = handle.availableData
                guard !data.isEmpty else {
                    self.fdLock.unlock()
                    return
                }

                // Duplicate the echo target rather than writing under the lock: the app's real
                // stdout is not ours, and if its reader has stalled the `write` blocks — holding
                // `fdLock` through that would hang `stopCapturing` on the main thread as the app
                // backgrounds. `dup` never blocks, and the copy keeps the open file description
                // (and its NOSIGPIPE flag) alive even if teardown closes the original
                let originalFd = stream == .stdout ? self.originalStdout : self.originalStderr
                let echoFd = originalFd != -1 ? dup(originalFd) : -1

                self.fdLock.unlock()

                // Echo before decoding, so a chunk that is not valid UTF-8 (a multi-byte sequence
                // split across a pipe buffer boundary) still reaches the console
                if echoFd != -1 {
                    _ = data.withUnsafeBytes { ptr in
                        write(echoFd, ptr.baseAddress, ptr.count)
                    }
                    close(echoFd)
                }

                guard let output = String(data: data, encoding: .utf8) else { return }

                // Deliberately outside the lock: `callback` re-enters SDK code (`handleConsoleLog`
                // -> `postHog.capture`) that can reach back into the replay lifecycle and take
                // `fdLock` again. It is non-recursive, so folding the unlock into a `defer`
                // would deadlock
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
            // Snapshot under the lock, because `setupPipeRedirection` writes these properties
            // under it. Reading a var that holds a strong class reference while another thread
            // writes it is a data race in Swift, and the failure mode is an over-release, not
            // just a stale value
            fdLock.lock()
            let stdoutReading = stdoutPipe?.fileHandleForReading
            let stderrReading = stderrPipe?.fileHandleForReading
            fdLock.unlock()

            // Detach the readability handlers first, and outside the lock, so that a handler
            // that is already running can finish and release the lock instead of deadlocking
            stdoutReading?.readabilityHandler = nil
            stderrReading?.readabilityHandler = nil

            fdLock.lock()

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
            stdoutReading?.closeFile()
            stderrReading?.closeFile()
            stdoutPipe = nil
            stderrPipe = nil

            fdLock.unlock()
        }
    }
#endif
