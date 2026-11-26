#if os(iOS) && (!SWIFT_PACKAGE || SessionReplay)
    import Foundation
    @_spi(PostHogInternal) @testable import PostHog
    import Testing

    @Suite("Remote Masking")
    struct PostHogRemoteMaskingTest {
        private func config(masking: Any?) -> [String: Any] {
            guard let masking else { return ["sessionRecording": ["endpoint": "/s/"]] }
            return ["sessionRecording": ["masking": masking]]
        }

        private func mobile(_ values: [String: Any]) -> [String: Any] {
            config(masking: ["mobile": values])
        }

        private func resolve(local: (text: Bool, images: Bool), remoteConfig: [String: Any]?) -> PostHogRemoteMasking {
            PostHogRemoteMasking.resolve(local: local, remote: PostHogRemoteMasking.parse(from: remoteConfig))
        }

        @Test("local false and server true resolves to true for each flag")
        func serverTurnsFlagOn() {
            let both = resolve(local: (false, false), remoteConfig: mobile(["maskAllText": true, "maskAllImages": true]))
            #expect(both == PostHogRemoteMasking(maskAllTextInputs: true, maskAllImages: true))

            let textOnly = resolve(local: (false, false), remoteConfig: mobile(["maskAllText": true]))
            #expect(textOnly == PostHogRemoteMasking(maskAllTextInputs: true, maskAllImages: false))

            let imagesOnly = resolve(local: (false, false), remoteConfig: mobile(["maskAllImages": true]))
            #expect(imagesOnly == PostHogRemoteMasking(maskAllTextInputs: false, maskAllImages: true))
        }

        @Test("local true stays true when the server is false or missing")
        func localTrueNeverTurnedOff() {
            let serverFalse = resolve(local: (true, true), remoteConfig: mobile(["maskAllText": false, "maskAllImages": false]))
            #expect(serverFalse == PostHogRemoteMasking(maskAllTextInputs: true, maskAllImages: true))

            let serverMissing = resolve(local: (true, true), remoteConfig: mobile([:]))
            #expect(serverMissing == PostHogRemoteMasking(maskAllTextInputs: true, maskAllImages: true))
        }

        @Test("false, null, string and number server values stay false")
        func nonBooleanTrueValuesAreRejected() {
            let values: [Any] = [false, NSNull(), "true", 1, 1.0, 0, NSNumber(value: 1)]
            for value in values {
                let resolved = resolve(local: (false, false), remoteConfig: mobile(["maskAllText": value, "maskAllImages": value]))
                #expect(resolved == PostHogRemoteMasking(maskAllTextInputs: false, maskAllImages: false), "value: \(value)")
            }
        }

        @Test("a JSON boolean true parses to true")
        func jsonBooleanTrue() throws {
            let data = Data(#"{"sessionRecording":{"masking":{"mobile":{"maskAllText":true,"maskAllImages":1}}}}"#.utf8)
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let parsed = PostHogRemoteMasking.parse(from: json)
            #expect(parsed.maskAllTextInputs == true)
            #expect(parsed.maskAllImages == false)
        }

        @Test("missing or malformed paths keep the local value")
        func missingPathsKeepLocal() {
            let configs: [[String: Any]?] = [
                nil,
                [:],
                ["sessionRecording": false],
                config(masking: nil),
                config(masking: "not a dictionary"),
                config(masking: ["mobile": "not a dictionary"]),
                config(masking: ["web": ["maskAllText": true]]),
            ]
            for remoteConfig in configs {
                #expect(resolve(local: (false, false), remoteConfig: remoteConfig) == PostHogRemoteMasking(maskAllTextInputs: false, maskAllImages: false))
                #expect(resolve(local: (true, false), remoteConfig: remoteConfig) == PostHogRemoteMasking(maskAllTextInputs: true, maskAllImages: false))
                #expect(resolve(local: (false, true), remoteConfig: remoteConfig) == PostHogRemoteMasking(maskAllTextInputs: false, maskAllImages: true))
            }
        }

        @Test("web keys alone change nothing")
        func webKeysAreIgnored() {
            let remoteConfig = config(masking: [
                "maskAllInputs": true,
                "maskTextSelector": "*",
                "blockSelector": "img",
                "maskAllText": true,
                "maskAllImages": true,
            ])
            #expect(resolve(local: (false, false), remoteConfig: remoteConfig) == PostHogRemoteMasking(maskAllTextInputs: false, maskAllImages: false))
        }

        @Test("the two flags resolve independently")
        func flagsAreIndependent() {
            let resolved = resolve(local: (true, false), remoteConfig: mobile(["maskAllText": false, "maskAllImages": true]))
            #expect(resolved == PostHogRemoteMasking(maskAllTextInputs: true, maskAllImages: true))

            let other = resolve(local: (false, true), remoteConfig: mobile(["maskAllText": true, "maskAllImages": false]))
            #expect(other == PostHogRemoteMasking(maskAllTextInputs: true, maskAllImages: true))
        }
    }
#endif
