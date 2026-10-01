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

func fromJSONData(_ data: Data, options: JSONSerialization.ReadingOptions = []) -> [String: Any]? {
    try? JSONSerialization.jsonObject(with: data, options: options) as? [String: Any]
}

/// Removes or converts values that cannot be serialized to JSON.
///
/// `URL` values are converted to absolute strings and `Date` values to ISO-8601 strings,
/// including when they are nested inside dictionaries or arrays. Other non-serializable
/// values are dropped. A nested dictionary is kept when it still has serializable values;
/// if every nested value is dropped it becomes `{}`, matching posthog-js. On the previous
/// release the parent key was omitted instead. A nested array whose items are all dropped
/// is omitted entirely so identify does not overwrite a person property with `[]`.
///
/// - Parameter dict: Dictionary to sanitize.
/// - Returns: A sanitized dictionary, or `nil` when the input is `nil` or empty.
public func sanitizeDictionary(_ dict: [String: Any]?) -> [String: Any]? {
    if dict == nil || dict!.isEmpty {
        return nil
    }

    var newDict = dict!

    for (key, value) in newDict where !isValidObject(value) {
        if let sanitized = sanitizeInvalidValue(value) {
            newDict[key] = sanitized
            continue
        }

        newDict.removeValue(forKey: key)
        hedgeLog("property: \(key) isn't serializable, dropping the item")
    }

    return newDict
}

/// Converts one non-JSON value, or `nil` when it should be dropped.
/// Dictionaries and arrays are sanitized in place so one bad child does not discard its siblings.
private func sanitizeInvalidValue(_ value: Any) -> Any? {
    if let url = value as? URL {
        return url.absoluteString
    }
    if let date = value as? Date {
        return ISO8601DateFormatter().string(from: date)
    }
    if let nested = value as? [String: Any] {
        return sanitizeDictionary(nested) ?? [:]
    }
    if let array = value as? [Any] {
        let sanitized = sanitizeArray(array)
        return sanitized.isEmpty ? nil : sanitized
    }
    return nil
}

private func sanitizeArray(_ array: [Any]) -> [Any] {
    var sanitized: [Any] = []
    sanitized.reserveCapacity(array.count)

    for value in array {
        if isValidObject(value) {
            sanitized.append(value)
            continue
        }
        if let converted = sanitizeInvalidValue(value) {
            sanitized.append(converted)
            continue
        }
        hedgeLog("array item isn't serializable, dropping the item")
    }

    return sanitized
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
