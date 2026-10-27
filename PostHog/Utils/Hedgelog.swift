//
//  Hedgelog.swift
//  PostHog
//
//  Created by Ben White on 07.02.23.
//

import Foundation

var hedgeLogEnabled = false

func toggleHedgeLog(_ enabled: Bool) {
    hedgeLogEnabled = enabled
}

// Meant for internally logging PostHog related things
func hedgeLog(_ message: String) {
    if !hedgeLogEnabled { return }
    print("[PostHog] \(message)")
}

/// Prints even when debug is off, for a problem the app can't see any other way.
func hedgeLogWarning(_ message: String) {
    print("[PostHog] \(message)")
}
