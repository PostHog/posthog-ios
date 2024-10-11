//
//  PostHogStorageTest.swift
//  PostHogTests
//
//  Created by Ben White on 08.02.23.
//

import Foundation
import Nimble
@testable import PostHog
import Quick

class PostHogStorageTest: QuickSpec {
    func getSut() -> PostHogStorage {
        let config = PostHogConfig(apiKey: "123")
        return PostHogStorage(config)
    }

    override func spec() {
        it("returns the support dir URL") {
            let url = applicationSupportDirectoryURL()
            expect(url).toNot(beNil())
            expect(url.pathComponents[url.pathComponents.count - 2]) == "Application Support"
            expect(url.lastPathComponent) == Bundle.main.bundleIdentifier
        }

        it("creates folder if none exists") {
            let url = applicationSupportDirectoryURL()
            try? FileManager.default.removeItem(at: url)

            expect(FileManager.default.fileExists(atPath: url.path)) == false

            let sut = self.getSut()

            expect(FileManager.default.fileExists(atPath: sut.appFolderUrl.path)) == true

            sut.reset()
        }

        it("persists and loads string") {
            let sut = self.getSut()

            let str = "san francisco"
            sut.setString(forKey: .distinctId, contents: str)

            expect(sut.getString(forKey: .distinctId)) == str

            sut.remove(key: .distinctId)
            expect(sut.getString(forKey: .distinctId)).to(beNil())

            sut.reset()
        }

        it("persists and loads bool") {
            let sut = self.getSut()

            sut.setBool(forKey: .optOut, contents: true)

            expect(sut.getBool(forKey: .optOut)) == true

            sut.remove(key: .optOut)
            expect(sut.getString(forKey: .optOut)).to(beNil())

            sut.reset()
        }

        it("persists and loads dictionary") {
            let sut = self.getSut()

            let dict = [
                "san francisco": "tech",
                "new york": "finance",
                "paris": "fashion",
            ]
            sut.setDictionary(forKey: .distinctId, contents: dict)
            expect(sut.getDictionary(forKey: .distinctId) as? [String: String]) == dict

            sut.remove(key: .distinctId)
            expect(sut.getDictionary(forKey: .distinctId)).to(beNil())

            sut.reset()
        }

        it("saves file to disk and removes from disk") {
            let sut = self.getSut()

            let url = sut.url(forKey: .distinctId)
            expect(try? url.checkResourceIsReachable()).to(beNil())
            sut.setString(forKey: .distinctId, contents: "sloth")
            expect(try! url.checkResourceIsReachable()) == true
            sut.remove(key: .distinctId)
            expect(try? url.checkResourceIsReachable()).to(beNil())

            sut.reset()
        }

        it("falls back to application support directory when app group identifier is not provided") {
            let config = PostHogConfig(apiKey: "123")
            config.appGroupIdentifier = nil
            let sut = PostHogStorage(config)
            let url = sut.appFolderUrl
            expect(url).toNot(beNil())
            expect(url.pathComponents[url.pathComponents.count - 2]) == "Application Support"
            expect(url.lastPathComponent) == Bundle.main.bundleIdentifier
        }
    }
}
