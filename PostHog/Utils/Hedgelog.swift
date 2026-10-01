//
//  Hedgelog.swift
//  PostHog
//
//  Created by Ben White on 07.02.23.
//

import Foundation

var hedgeLogEnabled = false

// DIAGNOSTIC (do not merge): timestamped trace for CI request stalls.
private let phDiagFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let phDiagLock = NSLock()

func phDiag(_ message: String) {
    let qos = Thread.current.qualityOfService.rawValue
    let line = phDiagLock.withLock { "[PHDIAG] \(phDiagFormatter.string(from: Date())) qos=\(qos) main=\(Thread.isMainThread) \(message)" }
    print(line)
}

func toggleHedgeLog(_ enabled: Bool) {
    hedgeLogEnabled = enabled
}

// Meant for internally logging PostHog related things
func hedgeLog(_ message: String) {
    if !hedgeLogEnabled { return }
    print("[PostHog] \(message)")
}
