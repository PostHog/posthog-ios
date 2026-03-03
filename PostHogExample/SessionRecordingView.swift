//
//  SessionRecordingView.swift
//  PostHogExample
//

import PostHog
import SwiftUI

struct SessionRecordingView: View {
    @State private var refreshStatusID = UUID()

    private func refreshStatus() {
        Task { @MainActor in
            refreshStatusID = UUID()
        }
    }

    private var sessionRecordingStatus: String {
        if PostHogSDK.shared.isSessionReplayActive() {
            return "🟢 Recording"
        } else {
            return "🔴 Not Recording"
        }
    }

    var body: some View {
        Form {
            Section("Manual Controls") {
                Group {
                    Text("\(sessionRecordingStatus)")
                    Text("SID: \(PostHogSDK.shared.getSessionId() ?? "NA")")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.leading)
                }
                .id(refreshStatusID)

                Button("Stop") {
                    PostHogSDK.shared.stopSessionRecording()
                    refreshStatus()
                }
                Button("Resume") {
                    PostHogSDK.shared.startSessionRecording()
                    refreshStatus()
                }
                Button("Start New Session") {
                    PostHogSDK.shared.startSessionRecording(resumeCurrent: false)
                    refreshStatus()
                }
            }

            Section("Event Trigger") {
                Button {
                    PostHogSDK.shared.stopSessionRecording()
                    PostHogSDK.shared.startSessionRecording()
                    PostHogSessionManager.shared.setSessionId(UUID().uuidString)
                    refreshStatus()
                } label: {
                    Text("Restart & Rotate Session Id")
                }

                Button {
                    PostHogSDK.shared.capture("start_replay_trigger_1")
                    refreshStatus()
                } label: {
                    Text("Capture 'start_replay_trigger_1'")
                }

                Button {
                    PostHogSDK.shared.capture("start_replay_trigger_2")
                    refreshStatus()
                } label: {
                    Text("Capture 'start_replay_trigger_2'")
                }
            }
        }
        .navigationTitle("Session Recording")
    }
}
