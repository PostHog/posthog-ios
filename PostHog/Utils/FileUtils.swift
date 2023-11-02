//
//  FileUtils.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 30.10.23.
//

import Foundation

public func deleteSafely(_ file: URL) {
    if FileManager.default.fileExists(atPath: file.path) {
        do {
            try FileManager.default.removeItem(at: file)
        } catch {
            hedgeLog("Error trying to delete file \(file.path) \(error)")
        }
    }
}
