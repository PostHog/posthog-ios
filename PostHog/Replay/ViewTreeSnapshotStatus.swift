//
//  ViewTreeSnapshotStatus.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 20.03.24.
//

import Foundation

class ViewTreeSnapshotStatus {
    var sentFullSnapshot: Bool = false
    var sentMetaEvent: Bool = false
    var keyboardVisible: Bool = false
    var lastSnapshot: Bool = false
    // Hash of the last screenshot enqueued for this window, so an unchanged
    // screenshot (a static screen captured on the throttle cadence) is not
    // re-sent. Nil until the first screenshot.
    var lastImageHash: Int?
}
