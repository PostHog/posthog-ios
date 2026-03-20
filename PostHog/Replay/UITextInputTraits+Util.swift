//
//  UITextInputTraits+Util.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 21.03.24.
//

#if os(iOS)
    import Foundation
    import UIKit

    private let sensibleTypes: [UITextContentType] = [
        .newPassword, .oneTimeCode, .creditCardNumber,
        .telephoneNumber, .emailAddress, .password,
        .username, .URL, .name, .nickname,
        .middleName, .familyName, .nameSuffix,
        .namePrefix, .organizationName, .location,
        .fullStreetAddress, .streetAddressLine1,
        .streetAddressLine2, .addressCity, .addressState,
        .addressCityAndState, .postalCode,
    ]

    extension UITextInputTraits {
        func isSensitiveText() -> Bool {
            if isSecureTextEntry ?? false {
                return true
            }

            if let contentType = textContentType, let contentType = contentType {
                return sensibleTypes.contains(contentType)
            }

            return false
        }
    }

#elseif os(macOS)
    import AppKit
    import Foundation

    @available(macOS 14.0, *)
    private let sensibleContentTypes: [NSTextContentType] = [
        .newPassword, .oneTimeCode,
        .telephoneNumber, .emailAddress, .password,
        .username, .URL, .name, .familyName,
        .namePrefix, .organizationName,
        .fullStreetAddress, .streetAddressLine1,
        .streetAddressLine2, .addressCity, .addressState,
        .addressCityAndState, .postalCode,
    ]

    extension NSTextField {
        func isSensitiveText() -> Bool {
            if self is NSSecureTextField {
                return true
            }

            if #available(macOS 14.0, *) {
                if let contentType = contentType {
                    return sensibleContentTypes.contains(contentType)
                }
            }

            return false
        }
    }

    extension NSTextView {
        func isSensitiveText() -> Bool {
            if #available(macOS 14.0, *) {
                if let contentType = contentType {
                    return sensibleContentTypes.contains(contentType)
                }
            }

            return false
        }
    }

#endif
