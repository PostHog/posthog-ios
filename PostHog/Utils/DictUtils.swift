//
//  DictUtils.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 27.10.23.
//

import Foundation

public func sanitizeDictionary(_ dict: [String: Any]?) -> [String: Any]? {
    if dict == nil || dict!.isEmpty {
        return nil
    }

    var newDict = dict!

    for (key, value) in newDict where !isValidObject(value) {
        if value is URL {
            newDict[key] = (value as! URL).absoluteString
            continue
        }
        if value is Date {
            newDict[key] = ISO8601DateFormatter().string(from: (value as! Date))
            continue
        }

        newDict.removeValue(forKey: key)
        hedgeLog("property: \(key) isn't serializable, dropping the item")
    }

    return newDict
}

private func isValidObject(_ object: Any) -> Bool {
    if object is String || object is Bool || object is any Numeric || object is NSNumber {
        return true
    }
    if object is [Any?] || object is [String: Any?] {
        return JSONSerialization.isValidJSONObject(object)
    }
    // workaround [object] since isValidJSONObject only accepts an Array or Dict
    return JSONSerialization.isValidJSONObject([object])
}
