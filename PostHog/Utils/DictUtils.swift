//
//  DictUtils.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 27.10.23.
//

import CoreGraphics
import Foundation

func toJSONData(_ dict: [String: Any]?, options: JSONSerialization.WritingOptions = []) -> Data? {
    guard let sanitized = sanitizeDictionary(dict) else {
        return nil
    }
    do {
        return try JSONSerialization.data(withJSONObject: sanitized, options: options)
    } catch {
        hedgeLog("Failed to serialize dictionary to JSON: \(error)")
        return nil
    }
}

func toJSONData(_ dicts: [[String: Any]?], options: JSONSerialization.WritingOptions = []) -> Data? {
    let sanitized = dicts.compactMap { sanitizeDictionary($0) }
    do {
        return try JSONSerialization.data(withJSONObject: sanitized, options: options)
    } catch {
        hedgeLog("Failed to serialize array to JSON: \(error)")
        return nil
    }
}

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
    if object is String || object is Bool {
        return true
    }
    // Check for invalid floating point values (.infinity, NaN)
    if let double = object as? Double {
        return double.isFinite
    }
    if let float = object as? Float {
        return float.isFinite
    }
    if let cgFloat = object as? CGFloat {
        return cgFloat.isFinite
    }
    if object is any Numeric || object is NSNumber {
        return true
    }
    if object is [Any?] || object is [String: Any?] {
        return JSONSerialization.isValidJSONObject(object)
    }
    // workaround [object] since isValidJSONObject only accepts an Array or Dict
    return JSONSerialization.isValidJSONObject([object])
}
