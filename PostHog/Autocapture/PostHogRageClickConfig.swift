import Foundation

@objc(PostHogRageClickConfig) public class PostHogRageClickConfig: NSObject {
    /// Manhattan distance threshold in logical points.
    ///
    /// Taps within this distance from the previous tap are considered "in the same area".
    /// Uses Manhattan distance: `|x1 - x2| + |y1 - y2|`.
    ///
    /// Default: 30
    @objc public var thresholdPoints: CGFloat = 30

    /// Maximum time interval between consecutive taps to count as part of the same sequence.
    ///
    /// If more than this interval passes between two taps, the sequence resets.
    ///
    /// Default: 1.0 (seconds)
    @objc public var timeoutInterval: TimeInterval = 1.0

    /// Number of consecutive taps within the threshold to qualify as a rage click.
    ///
    /// Default: 3
    @objc public var minimumTapCount: Int = 3
}
