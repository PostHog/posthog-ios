//
//  ViewController.swift
//  PostHogExampleStoryboard
//
//  Created by Manoel Aranda Neto on 21.03.24.
//

import UIKit
import WebKit

class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
//        let view = UIButton(frame: CGRect(x: 100, y: 100, width: 100, height: 100))
//        view.setTitle("test", for: .normal)
//        let view = UITextChecker

//        let view = UITextView(frame: CGRect(x: 100, y: 100, width: 100, height: 100))
//        view.text = "test"
//
//        self.view.addSubview(view)

        let view = UIImageView(frame: CGRect(x: 50, y: 50, width: 100, height: 100))
        let url = URL(string: "https://1.bp.blogspot.com/-hkNkoCjc5UA/T4JTlCjhhfI/AAAAAAAAB98/XxQwZ-QPkI8/s1600/Free+Google+Wallpapers+3.jpg")!
//        if let data = try? Data(contentsOf: url) {
//            if let image = UIImage(data: data) {
//                DispatchQueue.main.async {
//                    view.image = image
//                }
//            }
//        }
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                print("Error: \(error)")
                return
            }

            guard let data = data, let image = UIImage(data: data) else {
                print("No data or couldn't create image from data")
                return
            }

            DispatchQueue.main.async {
                view.image = image
            }
        }

        task.resume()

        self.view.addSubview(view)
    }
}
