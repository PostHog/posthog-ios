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

        // Will read 16 chars per iteration. Can use bigger buffer if needed
        let bufferSize = 16

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)

        var dat = Data()

        while bodyStream.hasBytesAvailable {
            let readDat = bodyStream.read(buffer, maxLength: bufferSize)
            dat.append(buffer, count: readDat)
        }

        buffer.deallocate()

        bodyStream.close()

        return dat
    }
}
