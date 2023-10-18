//
//  PostHogDataMode.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 13.10.23.
//

import Foundation

@objc(PostHogDataMode) public enum PostHogDataMode: Int {
    case wifi
    case cellular
    case any
}
