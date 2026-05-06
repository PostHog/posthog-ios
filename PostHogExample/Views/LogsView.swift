//
//  LogsView.swift
//  PostHogExample
//

#if os(iOS)
    import PostHog
    import SwiftUI

    struct LogsView: View {
        @State private var lastAction: String = ""

        var body: some View {
            List {
                Section("Levels") {
                    ForEach(Self.levelButtons, id: \.0) { label, level in
                        Button(label) {
                            PostHogSDK.shared.logger.callMethodFor(level: level, body: "test \(label) at \(Date())", attributes: ["source": "example"])
                            lastAction = "Sent \(label)"
                        }
                    }
                }

                Section("Capture variants") {
                    Button("captureLog with traceId") {
                        PostHogSDK.shared.captureLog(
                            "trace-context-demo",
                            level: .info,
                            attributes: ["sample": true],
                            traceId: "0af7651916cd43dd8448eb211c80319c",
                            spanId: "b7ad6b7169203331",
                            traceFlags: 1
                        )
                        lastAction = "Sent traced log"
                    }
                    Button("Flood 1000 (rate-cap demo)") {
                        for i in 0 ..< 1000 {
                            PostHogSDK.shared.logger.info("flood \(i)")
                        }
                        lastAction = "Submitted 1000 — rate cap will drop most"
                    }
                }

                Section("Flush") {
                    Button("Flush all queues") {
                        PostHogSDK.shared.flush()
                        lastAction = "flush() called"
                    }
                }

                if !lastAction.isEmpty {
                    Section("Last action") {
                        Text(lastAction)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Logs")
        }

        private static let levelButtons: [(String, PostHogLogLevel)] = [
            ("trace", .trace),
            ("debug", .debug),
            ("info", .info),
            ("warn", .warn),
            ("error", .error),
            ("fatal", .fatal),
        ]
    }

    private extension PostHogLogger {
        // Avoids a 6-way switch in the View body — same body and attributes for
        // every level button.
        func callMethodFor(level: PostHogLogLevel, body: String, attributes: [String: Any]? = nil) {
            switch level {
            case .trace: trace(body, attributes: attributes)
            case .debug: debug(body, attributes: attributes)
            case .info: info(body, attributes: attributes)
            case .warn: warn(body, attributes: attributes)
            case .error: error(body, attributes: attributes)
            case .fatal: fatal(body, attributes: attributes)
            @unknown default: info(body, attributes: attributes)
            }
        }
    }
#endif
