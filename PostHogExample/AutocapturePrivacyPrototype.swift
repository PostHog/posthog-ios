#if DEBUG && os(iOS)
    import Foundation
    @_spi(PostHogInternal) @testable import PostHog
    import SwiftUI
    import UIKit

    /// Debug-only synthetic controls. Credentials are supplied only by the launch environment.
    final class AutocapturePrivacyPrototype {
        static let shared = AutocapturePrivacyPrototype()
        static var isEnabled: Bool { ProcessInfo.processInfo.environment["POSTHOG_PROTOTYPE"] == "1" }

        private let lock = NSLock()
        private var eventCount = 0
        private(set) var status = "Waiting for setup"
        private(set) var capturesText = true
        var onStatus: ((String) -> Void)?

        func setup() {
            let environment = ProcessInfo.processInfo.environment
            guard let token = environment["POSTHOG_API_KEY"], !token.isEmpty,
                  let host = environment["POSTHOG_HOST"], !host.isEmpty
            else {
                status = "Missing POSTHOG_API_KEY or POSTHOG_HOST"
                return
            }
            let run = environment["POSTHOG_PROTOTYPE_RUN"] ?? UUID().uuidString
            let logURL = eventsURL.deletingLastPathComponent().appendingPathComponent("prototype-sdk.log")
            freopen(logURL.path, "w", stdout)
            setbuf(stdout, nil)
            let config = PostHogConfig(projectToken: token, host: host)
            config.debug = true
            if environment["POSTHOG_CAPTURE_ELEMENT_TEXT"] == "0" {
                config.captureElementText = false
            }
            capturesText = config.captureElementText
            config.captureElementInteractions = true
            config.captureScreenViews = false
            config.captureApplicationLifecycleEvents = false
            config.preloadFeatureFlags = false
            config.sendFeatureFlagEvent = false
            config.sessionReplay = false
            config.surveys = false
            config.rageClickConfig.enabled = false
            config.errorTrackingConfig.autoCapture = false
            config.personProfiles = .never
            config.persistOptOut = false
            config.flushAt = 1
            config.flushIntervalSeconds = 1
            let capturesText = config.captureElementText
            config.setBeforeSend { [weak self] event in
                event.properties["sdk_prototype"] = "autocapture-text-privacy"
                event.properties["sdk_prototype_run"] = run
                event.properties["sdk_prototype_capture_element_text"] = capturesText
                self?.record(event)
                return event
            }
            do {
                try Data().write(to: eventsURL)
            } catch {
                status = "Evidence file error: \(error.localizedDescription)"
                return
            }
            PostHogSDK.shared.setup(config)
            status = "Ready: text \(capturesText ? "ON (default)" : "OFF")"
        }

        private var eventsURL: URL {
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("prototype-events.jsonl")
        }

        private func record(_ event: PostHogEvent) {
            lock.lock()
            defer { lock.unlock() }
            do {
                // Analytics events contain no project token. Never serialize the configuration.
                let json: [String: Any] = [
                    "event": event.event,
                    "properties": event.properties,
                    "uuid": event.uuid.uuidString,
                ]
                var data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
                data.append(0x0A)
                let file = try FileHandle(forWritingTo: eventsURL)
                defer { file.closeFile() }
                file.seekToEndOfFile()
                file.write(data)
                eventCount += 1
                let message = "Recorded \(eventCount): \(event.event)"
                DispatchQueue.main.async { [weak self] in
                    self?.status = message
                    self?.onStatus?(message)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    let message = "Evidence file error: \(error.localizedDescription)"
                    self?.status = message
                    self?.onStatus?(message)
                }
            }
        }
    }

    struct AutocapturePrivacyPrototypeView: UIViewControllerRepresentable {
        func makeUIViewController(context _: Context) -> AutocapturePrivacyPrototypeController {
            AutocapturePrivacyPrototypeController()
        }

        func updateUIViewController(_: AutocapturePrivacyPrototypeController, context _: Context) {}
    }

    final class AutocapturePrivacyPrototypeController: UIViewController {
        private let statusLabel = UILabel()

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
            let stack = UIStackView()
            stack.axis = .vertical
            stack.spacing = 10
            stack.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
                stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
                stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            ])

            let title = UILabel()
            title.text = "Synthetic privacy prototype"
            title.font = .preferredFont(forTextStyle: .headline)
            stack.addArrangedSubview(title)
            let mode = UILabel()
            mode.text = "Control text: \(AutocapturePrivacyPrototype.shared.capturesText ? "ON (default)" : "OFF")"
            mode.accessibilityIdentifier = "prototype-mode"
            stack.addArrangedSubview(mode)
            let syntheticLabel = UILabel()
            syntheticLabel.text = "SYNTHETIC_LABEL — use synthetic data only"
            syntheticLabel.font = .preferredFont(forTextStyle: .caption1)
            stack.addArrangedSubview(syntheticLabel)

            stack.addArrangedSubview(button("SYNTHETIC_BUTTON", id: "prototype-button", action: #selector(tapped)))

            let field = UITextField()
            field.borderStyle = .roundedRect
            field.text = "SYNTHETIC_FIELD"
            field.accessibilityIdentifier = "prototype-field"
            field.postHogLabel = "synthetic-field"
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
            stack.addArrangedSubview(field)

            let editor = UITextView()
            editor.text = "SYNTHETIC_TEXT_VIEW"
            editor.accessibilityIdentifier = "prototype-editor"
            editor.postHogLabel = "synthetic-editor"
            editor.autocorrectionType = .no
            editor.autocapitalizationType = .none
            editor.layer.borderWidth = 1
            editor.layer.borderColor = UIColor.separator.cgColor
            editor.heightAnchor.constraint(equalToConstant: 65).isActive = true
            stack.addArrangedSubview(editor)
            stack.addArrangedSubview(button("Finish editing", id: "prototype-end-editing", action: #selector(finishEditing)))

            let segments = UISegmentedControl(items: ["SYNTHETIC_A", "SYNTHETIC_B"])
            segments.selectedSegmentIndex = 0
            segments.accessibilityIdentifier = "prototype-segments"
            segments.postHogLabel = "synthetic-selection"
            segments.addTarget(self, action: #selector(changed), for: .valueChanged)
            stack.addArrangedSubview(segments)

            let toggle = UISwitch()
            toggle.accessibilityIdentifier = "prototype-switch"
            toggle.postHogLabel = "synthetic-switch"
            toggle.addTarget(self, action: #selector(changed), for: .valueChanged)
            stack.addArrangedSubview(toggle)
            stack.addArrangedSubview(button("Manual synthetic event", id: "prototype-manual", action: #selector(manual)))
            stack.addArrangedSubview(button("Excluded synthetic button", id: "prototype-excluded-ph-no-capture", action: #selector(tapped)))

            let lifecycle = UIStackView()
            lifecycle.distribution = .fillEqually
            lifecycle.addArrangedSubview(button("Opt out", id: "prototype-opt-out", action: #selector(optOut)))
            lifecycle.addArrangedSubview(button("Opt in", id: "prototype-opt-in", action: #selector(optIn)))
            lifecycle.addArrangedSubview(button("Close", id: "prototype-close", action: #selector(closeSDK)))
            // These are test harness controls, not analytics subjects.
            lifecycle.accessibilityIdentifier = "ph-no-capture"
            stack.addArrangedSubview(lifecycle)
            statusLabel.numberOfLines = 0
            statusLabel.font = .preferredFont(forTextStyle: .caption1)
            statusLabel.text = AutocapturePrivacyPrototype.shared.status
            statusLabel.accessibilityIdentifier = "prototype-status"
            stack.addArrangedSubview(statusLabel)
            AutocapturePrivacyPrototype.shared.onStatus = { [weak self] text in
                self?.statusLabel.text = text
            }
        }

        private func button(_ title: String, id: String, action: Selector) -> UIButton {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.accessibilityIdentifier = id
            button.postHogLabel = id
            button.addTarget(self, action: action, for: .touchUpInside)
            return button
        }

        @objc private func tapped() {
            statusLabel.text = "Synthetic button activated"
        }
        @objc private func changed() {
            statusLabel.text = "Synthetic selection changed"
        }
        @objc private func finishEditing() {
            view.endEditing(true)
        }
        @objc private func manual() {
            PostHogSDK.shared.capture("prototype_manual", properties: ["text": "SYNTHETIC_MANUAL"])
        }

        @objc private func optOut() {
            PostHogSDK.shared.optOut()
            statusLabel.text = "Opted out"
        }

        @objc private func optIn() {
            PostHogSDK.shared.optIn()
            statusLabel.text = "Opted in"
        }

        @objc private func closeSDK() {
            PostHogSDK.shared.flush()
            PostHogSDK.shared.close()
            statusLabel.text = "Closed"
        }
    }
#endif
