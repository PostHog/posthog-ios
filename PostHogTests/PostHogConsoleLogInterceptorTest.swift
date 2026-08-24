//
//  PostHogConsoleLogInterceptorTest.swift
//  PostHogTests
//
//  Regression coverage for https://github.com/PostHog/posthog-ios/issues/780
//

#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing

    @Suite("Console Log Interceptor Tests", .serialized)
    class PostHogConsoleLogInterceptorTest {
        private func getConfig() -> PostHogConfig {
            PostHogConfig(apiKey: "test-api-key")
        }

        /// A broken pipe on a descriptor the SDK owns has to surface as `EPIPE`, not as a
        /// fatal `SIGPIPE` that the host app has no way to catch.
        @Test("stdout and stderr are marked NOSIGPIPE while capturing")
        func stdioIsMarkedNoSigPipeWhileCapturing() {
            let interceptor = PostHogConsoleLogInterceptor.shared
            interceptor.startCapturing(config: getConfig()) { _ in }
            defer { interceptor.stopCapturing() }

            #expect(fcntl(STDOUT_FILENO, F_GETNOSIGPIPE) == 1)
            #expect(fcntl(STDERR_FILENO, F_GETNOSIGPIPE) == 1)
        }

        /// `stopCapturing` has to hand the real console back, otherwise every later `print`
        /// disappears into a pipe nobody is reading.
        @Test("stopCapturing restores the original stdout and stderr")
        func stopCapturingRestoresOriginalDescriptors() throws {
            let marker = "posthog-interceptor-test-\(UUID().uuidString)\n"
            let path = NSTemporaryDirectory() + "posthog-stdout-\(UUID().uuidString).txt"
            FileManager.default.createFile(atPath: path, contents: nil)
            defer { try? FileManager.default.removeItem(atPath: path) }

            let file = try #require(FileHandle(forWritingAtPath: path))
            defer { file.closeFile() }

            // Stand in for the real console so we can read back what landed on fd 1
            let savedStdout = dup(STDOUT_FILENO)
            dup2(file.fileDescriptor, STDOUT_FILENO)
            defer {
                dup2(savedStdout, STDOUT_FILENO)
                close(savedStdout)
            }

            let interceptor = PostHogConsoleLogInterceptor.shared
            interceptor.startCapturing(config: getConfig()) { _ in }
            interceptor.stopCapturing()

            _ = Array(marker.utf8).withUnsafeBytes { ptr in
                write(STDOUT_FILENO, ptr.baseAddress, ptr.count)
            }

            let written = try #require(try? String(contentsOfFile: path, encoding: .utf8))
            #expect(written.contains(marker.trimmingCharacters(in: .newlines)))
        }

        /// The rest of the suite passes `{ _ in }`, so nothing else proves the interceptor
        /// delivers anything at all. This is what makes the handler's
        /// `fileHandleForReading === handle` identity check falsifiable: if that assumption were
        /// wrong, console capture would be silently dead and every other test would still pass.
        @Test("captured stdout reaches the callback")
        func capturedStdoutReachesTheCallback() throws {
            // Plain hex and dashes, so the default sanitizer classifies it as `.info`, and it
            // cannot be mistaken for one of the SDK's own logs
            let marker = "posthog-interceptor-capture-\(UUID().uuidString)"
            try #require(!marker.contains("[PostHog]"))

            let watcher = MarkerWatcher(marker: marker)

            let config = getConfig()
            // Defaults to `.error`, which would drop the marker
            config.sessionReplayConfig.captureLogsConfig.minLogLevel = .info

            let interceptor = PostHogConsoleLogInterceptor.shared
            interceptor.startCapturing(config: config) { output in
                watcher.record(output.text)
            }
            defer { interceptor.stopCapturing() }

            print(marker)

            #expect(watcher.waitForMarker(timeout: 10))
            #expect(watcher.capturedText.contains { $0.contains(marker) })
        }

        /// The crash in #780: teardown used to close the descriptors the readability handlers
        /// write to while those handlers were still in flight, so a handler could write into a
        /// descriptor number the process had already recycled. Churning start/stop against a
        /// thread that never stops logging is what surfaced it.
        @Test("concurrent start/stop while logging does not crash")
        func concurrentStartStopWhileLoggingIsSafe() throws {
            // Point fd 1 at a temp file for the duration. The churn prints on a tight loop and
            // the interceptor echoes every line, which would otherwise dump megabytes into the
            // CI log
            let path = NSTemporaryDirectory() + "posthog-churn-\(UUID().uuidString).txt"
            FileManager.default.createFile(atPath: path, contents: nil)
            defer { try? FileManager.default.removeItem(atPath: path) }

            let file = try #require(FileHandle(forWritingAtPath: path))
            defer { file.closeFile() }

            let savedStdout = dup(STDOUT_FILENO)
            dup2(file.fileDescriptor, STDOUT_FILENO)
            defer {
                dup2(savedStdout, STDOUT_FILENO)
                close(savedStdout)
            }

            // Identity of the descriptor the churn has to hand back untouched
            var beforeChurn = stat()
            #expect(fstat(STDOUT_FILENO, &beforeChurn) == 0)

            let interceptor = PostHogConsoleLogInterceptor.shared
            let config = getConfig()

            let keepLogging = TestFlag()
            let loggerFinished = DispatchSemaphore(value: 0)
            let logger = Thread {
                while keepLogging.isSet {
                    print("posthog interceptor test chatter")
                }
                loggerFinished.signal()
            }
            logger.stackSize = 512 * 1024
            logger.start()

            for _ in 0 ..< 200 {
                interceptor.startCapturing(config: config) { _ in }
                // Stress knob, not synchronization: it widens the window in which a readability
                // handler is in flight against teardown, which is what reproduces #780
                usleep(200)
                interceptor.stopCapturing()
            }

            keepLogging.clear()
            // Join the logging thread rather than sleeping, so it cannot still be printing into
            // whatever fd 1 has become once the suite moves on
            #expect(loggerFinished.wait(timeout: .now() + 30) == .success)

            // `fcntl(F_GETFD)` would only prove fd 1 is open, which it always is. Comparing the
            // device/inode pins that the *original* stdout came back, rather than a leftover
            // pipe end from a mixed-up start/stop pair
            var afterChurn = stat()
            #expect(fstat(STDOUT_FILENO, &afterChurn) == 0)
            #expect(beforeChurn.st_dev == afterChurn.st_dev)
            #expect(beforeChurn.st_ino == afterChurn.st_ino)
        }
    }

    /// Collects interceptor output off the reader queue and lets a test wait for a specific
    /// marker without polling on a fixed sleep.
    private final class MarkerWatcher {
        private let marker: String
        private let lock = NSLock()
        private let signalled = DispatchSemaphore(value: 0)
        private var captured: [String] = []

        init(marker: String) {
            self.marker = marker
        }

        var capturedText: [String] {
            lock.lock()
            defer { lock.unlock() }
            return captured
        }

        func record(_ text: String) {
            lock.lock()
            captured.append(text)
            lock.unlock()

            if text.contains(marker) {
                signalled.signal()
            }
        }

        func waitForMarker(timeout: TimeInterval) -> Bool {
            signalled.wait(timeout: .now() + timeout) == .success
        }
    }

    /// Minimal flag so the logging thread can be stopped without pulling in a dependency.
    private final class TestFlag {
        private let lock = NSLock()
        private var value = true

        var isSet: Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func clear() {
            lock.lock()
            value = false
            lock.unlock()
        }
    }
#endif
