import Foundation

/// Yields to the main queue once, so work the SUT hopped onto main has run before the test asserts.
@MainActor
func drainMain() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}
