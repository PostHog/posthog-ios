// Naive rage click implementation: If touch has not moved further than thresholdPoints
// over minimumTapCount taps with max timeoutInterval between taps, it's
// counted as a rage click
//
// This is a standalone utility class with no dependencies on autocapture or any integration.
// It can be reused by any future integration (e.g., heatmaps) that needs rage click detection.

import CoreGraphics
import Foundation

class RageClickDetector {
    private struct Click {
        let posX: CGFloat
        let posY: CGFloat
        let timestamp: TimeInterval
    }

    private var clicks: [Click] = []

    private let thresholdPoints: CGFloat
    private let timeoutInterval: TimeInterval
    private let minimumTapCount: Int

    init(config: PostHogRageClickConfig = .init()) {
        thresholdPoints = config.thresholdPoints
        timeoutInterval = config.timeoutInterval
        minimumTapCount = config.minimumTapCount
    }

    /// Determines whether the given tap constitutes a rage click.
    ///
    /// Call this method for each tap event with its coordinates and timestamp.
    /// Returns `true` exactly once when the rage click threshold is reached.
    /// Subsequent taps in the same area will not re-trigger until the user
    /// moves away (spatial reset) or enough time passes (temporal reset).
    ///
    /// - Parameters:
    ///   - x: The x-coordinate of the tap in logical points (window coordinates)
    ///   - y: The y-coordinate of the tap in logical points (window coordinates)
    ///   - timestamp: The timestamp of the tap (e.g., `ProcessInfo.processInfo.systemUptime` or `CACurrentMediaTime()`)
    /// - Returns: `true` if this tap completes a rage click sequence
    @discardableResult
    // swiftlint:disable:next identifier_name
    func isRageClick(x: CGFloat, y: CGFloat, timestamp: TimeInterval) -> Bool {
        let lastClick = clicks.last

        if let lastClick,
           abs(x - lastClick.posX) + abs(y - lastClick.posY) < thresholdPoints,
           timestamp - lastClick.timestamp < timeoutInterval
        {
            clicks.append(Click(posX: x, posY: y, timestamp: timestamp))

            if clicks.count == minimumTapCount {
                return true
            }
        } else {
            clicks = [Click(posX: x, posY: y, timestamp: timestamp)]
        }

        return false
    }

    /// Resets the click buffer, clearing any accumulated click history.
    ///
    /// Useful when integrations need to reset state (e.g., on session change).
    func reset() {
        clicks = []
    }
}
