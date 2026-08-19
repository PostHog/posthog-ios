//
//  ReplayMaskScrollReproducer.swift
//  PostHogExample
//
//  Manual screenshot-replay mask reproduction.
//
//  In a local copy of the PostHogExample scheme, set these launch variables:
//  POSTHOG_REPLAY_MASK_REPRO=1
//  POSTHOG_TEST_PROJECT_TOKEN=<test project token>
//  POSTHOG_TEST_HOST=https://us.i.posthog.com
//  POSTHOG_TEST_RUN_ID=<unique run ID>
//
//  Run the app for at least one minute. Tap Flush. Find the replay by its
//  test_run_id event property. Red SECRET pixels in the replay show a leak.
//  Do not commit the local scheme or its credentials.
//

import PostHog
import SwiftUI
import UIKit

enum ReplayMaskReproducerEnvironment {
    private static let environment = ProcessInfo.processInfo.environment

    static var isEnabled: Bool {
        environment["POSTHOG_REPLAY_MASK_REPRO"] == "1"
    }

    static var projectToken: String? {
        environment["POSTHOG_TEST_PROJECT_TOKEN"]
    }

    static var host: String {
        environment["POSTHOG_TEST_HOST"] ?? "https://us.i.posthog.com"
    }

    static var runID: String? {
        environment["POSTHOG_TEST_RUN_ID"]
    }
}

struct ReplayMaskScrollReproducer: View {
    @State private var isAutoScrolling = true
    @State private var statusRefreshID = UUID()

    private var runID: String {
        ReplayMaskReproducerEnvironment.runID ?? "missing"
    }

    private var recordingStatus: String {
        PostHogSDK.shared.isSessionReplayActive() ? "Recording" : "Not recording"
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Screenshot mask scroll reproduction")
                    .font(.headline)
                Text(recordingStatus)
                    .foregroundStyle(PostHogSDK.shared.isSessionReplayActive() ? .green : .red)
                Text("Run: \(runID)")
                    .font(.caption2.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Red SECRET regions use the React Native ph-no-capture marker. Replay masks must stay aligned with them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .id(statusRefreshID)
            .frame(maxWidth: .infinity, alignment: .leading)

            ReplayMaskFastScrollView(isAutoScrolling: isAutoScrolling)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.secondary, lineWidth: 1)
                }

            HStack {
                Button(isAutoScrolling ? "Pause fast scroll" : "Resume fast scroll") {
                    isAutoScrolling.toggle()
                    PostHogSDK.shared.capture("replay_mask_scroll_repro_toggled", properties: [
                        "test_run_id": runID,
                        "auto_scrolling": isAutoScrolling,
                        "synthetic": true,
                        "$process_person_profile": false,
                    ])
                }
                .buttonStyle(.borderedProminent)

                Button("Flush") {
                    statusRefreshID = UUID()
                    PostHogSDK.shared.flush()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                statusRefreshID = UUID()
            }
        }
    }
}

private struct ReplayMaskFastScrollView: UIViewRepresentable {
    let isAutoScrolling: Bool

    func makeUIView(context _: Context) -> ReplayMaskUIScrollView {
        let scrollView = ReplayMaskUIScrollView()
        scrollView.isAutoScrolling = isAutoScrolling
        return scrollView
    }

    func updateUIView(_ scrollView: ReplayMaskUIScrollView, context _: Context) {
        scrollView.isAutoScrolling = isAutoScrolling
    }
}

private final class ReplayMaskUIScrollView: UIScrollView {
    var isAutoScrolling = true {
        didSet {
            if isAutoScrolling {
                startTimerIfNeeded()
            } else {
                timer?.invalidate()
                timer = nil
                setContentOffset(contentOffset, animated: false)
            }
        }
    }

    private var timer: Timer?
    private var targetIndex = 0
    private let rowHeight: CGFloat = 112
    private let rowCount = 36

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, isAutoScrolling {
            startTimerIfNeeded()
        } else if window == nil {
            timer?.invalidate()
            timer = nil
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentSize = CGSize(width: bounds.width, height: CGFloat(rowCount) * rowHeight)
    }

    private func configure() {
        backgroundColor = .systemGroupedBackground
        alwaysBounceVertical = true
        showsVerticalScrollIndicator = true
        decelerationRate = .fast

        for index in 0 ..< rowCount {
            let y = CGFloat(index) * rowHeight

            let row = UIView(frame: CGRect(x: 12, y: y + 8, width: 342, height: 96))
            row.backgroundColor = index.isMultiple(of: 2) ? UIColor.systemBlue.withAlphaComponent(0.14) : UIColor.systemPurple.withAlphaComponent(0.14)
            row.layer.cornerRadius = 10

            let rowLabel = UILabel(frame: CGRect(x: 12, y: 10, width: 130, height: 24))
            rowLabel.text = "Public row \(index + 1)"
            rowLabel.font = .systemFont(ofSize: 15, weight: .semibold)
            row.addSubview(rowLabel)

            let marker = UILabel(frame: CGRect(x: 12, y: 52, width: 130, height: 22))
            marker.text = "Marker \(index + 1)"
            marker.textColor = .secondaryLabel
            marker.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            row.addSubview(marker)

            let maskedContainer = UIView(frame: CGRect(x: 156, y: 18, width: 172, height: 60))
            maskedContainer.accessibilityLabel = "ph-no-capture"
            maskedContainer.backgroundColor = .systemRed
            maskedContainer.layer.cornerRadius = 8

            let secret = UILabel(frame: maskedContainer.bounds.insetBy(dx: 8, dy: 8))
            secret.text = "SECRET \(index + 1)"
            secret.textAlignment = .center
            secret.textColor = .white
            secret.font = .monospacedSystemFont(ofSize: 17, weight: .bold)
            maskedContainer.addSubview(secret)
            row.addSubview(maskedContainer)
            addSubview(row)
        }
    }

    private func startTimerIfNeeded() {
        guard timer == nil, window != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.34, repeats: true) { [weak self] _ in
            self?.advanceScrollAnimation()
        }
        timer?.tolerance = 0.01
        advanceScrollAnimation()
    }

    private func advanceScrollAnimation() {
        guard isAutoScrolling, bounds.height > 0 else { return }

        let maximumOffset = max(0, contentSize.height - bounds.height)
        let targets: [CGFloat] = [
            maximumOffset + 90,
            maximumOffset * 0.22,
            maximumOffset * 0.78,
            -80,
            maximumOffset * 0.55,
            maximumOffset * 0.08,
        ]
        let target = targets[targetIndex % targets.count]
        targetIndex += 1

        // Each target changes direction before the prior animation settles. The
        // out-of-range targets also exercise the top and bottom rubber-band areas.
        setContentOffset(CGPoint(x: 0, y: target), animated: true)
    }
}
