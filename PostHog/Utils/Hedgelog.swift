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
