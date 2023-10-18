//
//  StorageTest.swift
//  PostHogTests
//
//  Created by Ben White on 08.02.23.
//

import Nimble
import Quick

@testable import PostHog

class StorageTest: QuickSpec {
    override func spec() {
        var storage: PostHogStorage!
        beforeEach {
            let url = applicationSupportDirectoryURL()
            expect(url).toNot(beNil())
            expect(url.pathComponents[url.pathComponents.count - 2]) == "Application Support"
            expect(url.lastPathComponent) == Bundle.main.bundleIdentifier
            storage = PostHogStorage(PostHogConfig(apiKey: "test"))
        }

        it("creates folder if none exists") {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: storage.appFolderUrl.path, isDirectory: &isDir)

            expect(exists) == true
            expect(isDir.boolValue) == true
        }

        it("persists and loads string") {
            let str = "san francisco"
            storage.setString(forKey: .distinctId, contents: str)

            expect(storage.getString(forKey: .distinctId)) == str

            storage.remove(key: .distinctId)
            expect(storage.getString(forKey: .distinctId)).to(beNil())
        }

        it("persists and loads numbers") {
            storage.setNumber(forKey: .distinctId, contents: 1)
            expect(storage.getNumber(forKey: .distinctId)) == 1

            storage.setNumber(forKey: .distinctId, contents: 1.2)
            expect(storage.getNumber(forKey: .distinctId)) == 1.2

            storage.remove(key: .distinctId)
            expect(storage.getNumber(forKey: .distinctId)).to(beNil())
        }

        it("persists and loads array") {
            let array = [
                "san francisco",
                "new york",
                "tallinn",
            ]
            storage.setArray(forKey: .distinctId, contents: array)
            expect(storage.getArray(forKey: .distinctId) as? [String]) == array

            storage.remove(key: .distinctId)
            expect(storage.getArray(forKey: .distinctId)).to(beNil())
        }

        it("persists and loads dictionary") {
            let dict = [
                "san francisco": "tech",
                "new york": "finance",
                "paris": "fashion",
            ]
            storage.setDictionary(forKey: .distinctId, contents: dict)
            expect(storage.getDictionary(forKey: .distinctId) as? [String: String]) == dict

            storage.remove(key: .distinctId)
            expect(storage.getDictionary(forKey: .distinctId)).to(beNil())
        }

        it("saves file to disk and removes from disk") {
            let url = storage.url(forKey: .distinctId)
            expect(try? url.checkResourceIsReachable()).to(beNil())
            storage.setString(forKey: .distinctId, contents: "sloth")
            expect(try! url.checkResourceIsReachable()) == true
            storage.remove(key: .distinctId)
            expect(try? url.checkResourceIsReachable()).to(beNil())
        }

//        it("should work with crypto") {
//            let url = PHGFileStorage.applicationSupportDirectoryURL()
//            let crypto = PHGAES256Crypto(password: "thetrees")
//            let s = PHGFileStorage(folder: url!, crypto: crypto)
//            let dict = [
//                "san francisco": "tech",
//                "new york": "finance",
//                "paris": "fashion",
//            ]
//            s.setDictionary(dict, forKey: "cityMap")
//            expect(s.dictionary(forKey: "cityMap") as? [String: String]) == dict
//
//            s.removeKey("cityMap")
//            expect(s.dictionary(forKey: "cityMap")).to(beNil())
//        }

        afterEach {
            storage.reset()
        }
    }
}
