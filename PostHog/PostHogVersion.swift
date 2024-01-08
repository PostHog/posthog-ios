//
//  PostHogVersion.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 13.10.23.
//

import Foundation

// This class is internal only
public class PostHogVersion {
    // if you change this, make sure to also change it in the podspec and check if the script scripts/bump-version.sh still works
    public static var postHogVersion = "3.0.0-beta.1"

    public static var postHogSdkName = "posthog-ios"
}
