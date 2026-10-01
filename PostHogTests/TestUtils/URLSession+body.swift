//
//  URLSession+body.swift
//  PostHogTests
//
//  Created by Ben White on 10.04.23.
//

import Foundation

extension URLRequest {
    func body() -> Data? {
        if httpBody != nil {
            return httpBody
        }

        guard let bodyStream = httpBodyStream else { return nil }

        bodyStream.open()
        defer { bodyStream.close() }

        // Will read 16 chars per iteration. Can use bigger buffer if needed
        let bufferSize = 16

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var dat = Data()

        while bodyStream.hasBytesAvailable {
            let readDat = bodyStream.read(buffer, maxLength: bufferSize)
            guard readDat >= 0 else { return nil }
            guard readDat > 0 else { break }
            dat.append(buffer, count: readDat)
        }

        return dat
    }
}
