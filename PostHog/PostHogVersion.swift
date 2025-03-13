//
//  PostHogVersion.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 13.10.23.
//

import Foundation

// if you change this, make sure to also change it in the podspec and check if the script scripts/bump-version.sh still works
// This property is internal only
public var postHogVersion = "3.20.1"

public let postHogiOSSdkName = "posthog-ios"
// This property is internal only
public var postHogSdkName = postHogiOSSdkName
