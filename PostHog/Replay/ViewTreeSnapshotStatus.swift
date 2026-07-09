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
    // Hash of the last screenshot sent for this window, used to skip unchanged frames.
    var lastImageHash: Int?
}
