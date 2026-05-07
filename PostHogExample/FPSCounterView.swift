//
//  FPSCounterView.swift
//  PostHog
//
//  Created by Ioannis Josephides on 6/5/26.
//

import QuartzCore
import SwiftUI
import UIKit

struct FPSCounterView: View {
    @StateObject private var model = FPSCounterModel()

    var body: some View {
        (Text("\(model.fps)")
            .foregroundColor(model.color) + Text(" FPS")
            .foregroundColor(.white))
            .font(.custom("Menlo", size: 14))
            .minimumScaleFactor(0.8)
            .frame(width: 65, height: 20)
            .background(Color.black.opacity(0.7))
            .cornerRadius(5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .padding(.top, 8)
            .padding(.trailing, 8)
    }
}

private final class FPSCounterModel: ObservableObject {
    @Published var fps: Int = 0
    @Published var color: Color = .green

    private let fpsSampleWindow: CFTimeInterval = 1
    private let fpsUpdateInterval: CFTimeInterval = 0.25
    private var displayLink: CADisplayLink?
    private var frameIntervals: [CFTimeInterval] = []
    private var frameIntervalsDuration: CFTimeInterval = 0
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var lastFPSUpdateTimestamp: CFTimeInterval = 0

    init() {
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        configureDisplayLink(link)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    deinit {
        displayLink?.invalidate()
    }

    private var maximumFramesPerSecond: Int {
        max(UIScreen.main.maximumFramesPerSecond, 60)
    }

    private func configureDisplayLink(_ link: CADisplayLink) {
        let maximumFPS = maximumFramesPerSecond

        if #available(iOS 15.0, tvOS 15.0, *) {
            let targetFPS = Float(maximumFPS)
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: targetFPS,
                maximum: targetFPS,
                preferred: targetFPS
            )
        } else {
            link.preferredFramesPerSecond = maximumFPS
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let timestamp = link.timestamp
        if lastFrameTimestamp == 0 {
            lastFrameTimestamp = timestamp
            lastFPSUpdateTimestamp = timestamp
            return
        }

        let frameInterval = timestamp - lastFrameTimestamp
        lastFrameTimestamp = timestamp
        guard frameInterval > 0 else { return }

        frameIntervals.append(frameInterval)
        frameIntervalsDuration += frameInterval
        while frameIntervalsDuration > fpsSampleWindow, frameIntervals.count > 1 {
            frameIntervalsDuration -= frameIntervals.removeFirst()
        }

        guard timestamp - lastFPSUpdateTimestamp >= fpsUpdateInterval,
              frameIntervalsDuration > 0
        else {
            return
        }
        lastFPSUpdateTimestamp = timestamp

        let measuredFPS = min(Double(frameIntervals.count) / frameIntervalsDuration, Double(maximumFramesPerSecond))
        fps = Int(measuredFPS.rounded())
        color = fpsColor(for: measuredFPS)
    }

    private func fpsColor(for measuredFPS: Double) -> Color {
        let maximumFPS = Double(maximumFramesPerSecond)
        let progress = min(max(measuredFPS / maximumFPS, 0), 1)
        let hue = max(0, 0.27 * (progress - 0.2))
        return Color(hue: hue, saturation: 1, brightness: 0.9)
    }
}
