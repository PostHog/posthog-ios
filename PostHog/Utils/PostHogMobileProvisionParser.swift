//
//  PostHogMobileProvisionParser.swift
//  PostHog
//
//  Created by Ioannis Josephides on 20/01/25.
//
//  see: https://github.com/Shopify/tophat/blob/201b914b6a38eab142cbd926a50492e192aceeef/Tophat/Models/ProvisioningProfile.swift

import Foundation

enum PostHogMobileProvisionParser {
    /// Parses the embedded provisioning profile and returns its contents as a dictionary.
    /// Returns nil if no profile exists (App Store/TestFlight builds are re-signed by Apple and have no embedded profile).
    static func parse() -> [String: Any]? {
        guard let profilePath = defaultProfilePath(),
              let binaryString = try? String(contentsOfFile: profilePath, encoding: .isoLatin1)
        else {
            return nil
        }

        let scanner = Scanner(string: binaryString)
        guard scanner.scanUpToString("<plist") != nil,
              let plistString = scanner.scanUpToString("</plist>")
        else {
            return nil
        }

        let fullPlistString = "\(plistString)</plist>"

        guard let plistData = fullPlistString.data(using: .isoLatin1) else {
            return nil
        }

        return try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
    }

    private static func defaultProfilePath() -> String? {
        #if targetEnvironment(macCatalyst)
            let ext = "provisionprofile"
        #else
            let ext = "mobileprovision"
        #endif
        return Bundle.main.path(forResource: "embedded", ofType: ext)
    }
}
