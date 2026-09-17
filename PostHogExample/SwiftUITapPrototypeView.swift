#if DEBUG && os(iOS)
    @_spi(PostHogInternal) import PostHog
    import SwiftUI

    /// Synthetic controls only. Launch with POSTHOG_PROTOTYPE=1 to opt into this demo.
    final class SwiftUITapPrototypeModel: ObservableObject {
        static let shared = SwiftUITapPrototypeModel()
        @Published var status = "Not configured"
        @Published var events = 0
        @Published var lastEvent = "None"
        private let fileLock = NSLock()
        private let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("prototype-events.jsonl")

        func configure() {
            let environment = ProcessInfo.processInfo.environment
            guard let key = environment["POSTHOG_API_KEY"], !key.isEmpty,
                  let host = environment["POSTHOG_HOST"], !host.isEmpty
            else { status = "Missing POSTHOG_API_KEY or POSTHOG_HOST"
                return
            }
            let run = environment["POSTHOG_PROTOTYPE_RUN"] ?? UUID().uuidString
            try? Data().write(to: fileURL, options: .atomic)
            let logURL = fileURL.deletingLastPathComponent().appendingPathComponent("prototype-sdk.log")
            freopen(logURL.path, "w", stdout)
            setbuf(stdout, nil)
            let config = PostHogConfig(projectToken: key, host: host)
            config.debug = true
            config.captureElementInteractions = true
            config.captureApplicationLifecycleEvents = false
            config.captureScreenViews = false
            config.sessionReplay = false
            config.preloadFeatureFlags = false
            config.sendFeatureFlagEvent = false
            config.surveys = false
            config.errorTrackingConfig.autoCapture = false
            config.personProfiles = .never
            config.optOut = false
            config.persistOptOut = false
            config.flushAt = 1
            config.flushIntervalSeconds = 2
            config.setBeforeSend { [weak self] event in
                event.properties["sdk_prototype"] = "swiftui-taps"
                event.properties["sdk_prototype_run"] = run
                self?.record(event)
                return event
            }
            PostHogSDK.shared.setup(config)
            status = "Active"
        }

        private func record(_ event: PostHogEvent) {
            let evidence: [String: Any] = [
                "event": event.event, "properties": event.properties,
                "uuid": event.uuid.uuidString,
                "timestamp": ISO8601DateFormatter().string(from: event.timestamp),
            ]
            do {
                var data = try JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys])
                data.append(0x0A)
                fileLock.lock()
                defer { fileLock.unlock() }
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                DispatchQueue.main.async { self.status = "Evidence write failed: \(error.localizedDescription)" }
            }
            guard event.event == "$autocapture" else { return }
            let chain = event.properties["$elements_chain"] as? String ?? ""
            DispatchQueue.main.async {
                self.events += 1
                self.lastEvent = chain
            }
        }
    }

    struct SwiftUITapPrototypeView: View {
        @ObservedObject private var model = SwiftUITapPrototypeModel.shared
        @State private var count = 0
        @State private var nestedCount = 0
        @State private var gestureCount = 0
        @State private var uiCount = 0
        @State private var maskedCount = 0
        @State private var sheet = false

        var body: some View {
            NavigationView {
                VStack(spacing: 10) {
                    Text("SwiftUI tap prototype").font(.headline)
                    Text("Status: \(model.status)").accessibilityIdentifier("prototype.status")
                    Text("Autocapture events: \(model.events)").accessibilityIdentifier("prototype.events")
                    Text("Button: \(count) Nested: \(nestedCount) Gesture: \(gestureCount) UIKit: \(uiCount) Masked: \(maskedCount)")
                        .font(.caption).accessibilityIdentifier("prototype.counters")
                    Button("Increment SwiftUI") { count += 1 }
                        .postHogLabel("prototype.swiftui.button")
                        .accessibilityIdentifier("prototype.swiftui.button")
                    Button { nestedCount += 1 } label: {
                        HStack { Image(systemName: "plus.circle")
                            Text("Nested child button")
                        }.padding(8)
                    }
                    .postHogLabel("prototype.swiftui.nested")
                    .accessibilityIdentifier("prototype.swiftui.nested")
                    Text("Tap gesture target").padding(8).background(Color.blue.opacity(0.15))
                        .onTapGesture { gestureCount += 1 }
                        .postHogLabel("prototype.swiftui.gesture")
                        .accessibilityIdentifier("prototype.swiftui.gesture")
                    PrototypeUIKitButton(count: $uiCount).frame(height: 36)
                    HStack {
                        Button("Open sheet") { sheet = true }
                            .postHogLabel("prototype.sheet.open")
                            .accessibilityIdentifier("prototype.sheet.open")
                        NavigationLink("Navigate") {
                            VStack {
                                Text("Navigation destination").accessibilityIdentifier("prototype.destination")
                                Button("Destination button") { count += 1 }
                                    .postHogLabel("prototype.destination.button")
                                    .accessibilityIdentifier("prototype.destination.button")
                            }
                        }
                        .postHogLabel("prototype.navigate")
                        .accessibilityIdentifier("prototype.navigate")
                    }
                    HStack {
                        Button("Masked button") { maskedCount += 1 }
                            .postHogLabel("prototype.masked").postHogMask()
                            .accessibilityIdentifier("prototype.masked")
                        Button("No capture") { maskedCount += 1 }
                            .accessibilityIdentifier("prototype.ph-no-capture")
                    }
                    ScrollView {
                        VStack {
                            ForEach(0 ..< 40) { row in
                                Text("Synthetic scroll row \(row)").frame(maxWidth: .infinity).padding(10)
                            }
                        }
                    }
                    .frame(height: 140).accessibilityIdentifier("prototype.scroll")
                    HStack {
                        Button("Opt out") { PostHogSDK.shared.optOut()
                            model.status = "Opted out"
                        }
                        .accessibilityIdentifier("prototype.optout")
                        Button("Opt in") { PostHogSDK.shared.optIn()
                            model.status = "Active"
                        }
                        .accessibilityIdentifier("prototype.optin")
                        Button("Close SDK") { PostHogSDK.shared.close()
                            model.status = "Closed"
                        }
                        .accessibilityIdentifier("prototype.close")
                    }
                    .font(.caption)
                    Text(model.lastEvent).font(.system(size: 9)).lineLimit(3)
                        .accessibilityIdentifier("prototype.last-event")
                }
                .padding()
                .sheet(isPresented: $sheet) {
                    VStack {
                        Text("Synthetic sheet").accessibilityIdentifier("prototype.sheet")
                        Button("Sheet button") { count += 1 }
                            .postHogLabel("prototype.sheet.button")
                            .accessibilityIdentifier("prototype.sheet.button")
                        Button("Dismiss sheet") { sheet = false }
                            .postHogLabel("prototype.sheet.dismiss")
                            .accessibilityIdentifier("prototype.sheet.dismiss")
                    }
                }
            }
            .navigationViewStyle(.stack)
        }
    }

    private struct PrototypeUIKitButton: UIViewRepresentable {
        @Binding var count: Int

        func makeCoordinator() -> Coordinator {
            Coordinator(count: $count)
        }

        func makeUIView(context: Context) -> UIButton {
            let button = UIButton(type: .system)
            button.setTitle("UIKit duplicate control", for: .normal)
            button.accessibilityIdentifier = "prototype.uikit.button"
            button.postHogLabel = "prototype.uikit.button"
            button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
            return button
        }

        func updateUIView(_: UIButton, context _: Context) {}

        final class Coordinator: NSObject {
            @Binding var count: Int
            init(count: Binding<Int>) {
                _count = count
            }
            @objc func tap() {
                count += 1
            }
        }
    }
#endif
