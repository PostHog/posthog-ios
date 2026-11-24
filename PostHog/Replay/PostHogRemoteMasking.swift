#if os(iOS) && (!SWIFT_PACKAGE || SessionReplay)
    import Foundation

    /// The project's mobile masking setting from remote config, and how it combines with the local flags.
    struct PostHogRemoteMasking: Equatable {
        var maskAllTextInputs: Bool
        var maskAllImages: Bool

        /// Reads `sessionRecording.masking.mobile`. A flag is on only for a real JSON boolean `true`.
        static func parse(from remoteConfig: [String: Any]?) -> PostHogRemoteMasking {
            let mobile = ((remoteConfig?["sessionRecording"] as? [String: Any])?["masking"] as? [String: Any])?["mobile"] as? [String: Any]
            return PostHogRemoteMasking(
                maskAllTextInputs: isTrue(mobile?["maskAllText"]),
                maskAllImages: isTrue(mobile?["maskAllImages"])
            )
        }

        /// The remote setting can only add masking, never remove it.
        static func resolve(local: (text: Bool, images: Bool), remote: PostHogRemoteMasking) -> PostHogRemoteMasking {
            PostHogRemoteMasking(
                maskAllTextInputs: local.text || remote.maskAllTextInputs,
                maskAllImages: local.images || remote.maskAllImages
            )
        }

        // `as? Bool` bridges a JSON `1` to true, so check the CFBoolean type.
        private static func isTrue(_ value: Any?) -> Bool {
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
            return number.boolValue
        }
    }
#endif
