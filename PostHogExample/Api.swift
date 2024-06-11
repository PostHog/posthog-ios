//
//  Api.swift
//  PostHogExample
//
//  Created by Ben White on 06.02.23.
//

import Foundation
import OSLog

struct PostHogBeerInfo: Codable, Identifiable {
    let id: Int
    var name: String
    var first_brewed: String
}

class Api: ObservableObject {
    @Published var beers = [PostHogBeerInfo]()

    var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "main")

    func listBeers(completion _: @escaping ([PostHogBeerInfo]) -> Void) {
//        guard let url = URL(string: "https://api.punkapi.com/v2/beers") else {
//            return
//        }
//
//        logger.info("Requesting beers list...")
//        URLSession.shared.dataTask(with: url) { _, _, _ in
//            let beers = try! JSONDecoder().decode([PostHogBeerInfo].self, from: data!)
//
//            DispatchQueue.main.async {
//                completion(beers)
//            }
//        }.resume()
    }

    func failingRequest() -> URLSessionDataTask? {
        guard let url = URL(string: "https://api.github.com/user") else {
            return nil
        }

        logger.info("Requesting protected endpoint...")
        let task = URLSession.shared.dataTask(with: url) { data, _, _ in
            if data == nil {
                return
            }
            print("Response", String(decoding: data!, as: UTF8.self))
        }

        task.resume()

        return task
    }
}
