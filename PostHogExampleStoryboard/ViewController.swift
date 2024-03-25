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

        let view = UITextView(frame: CGRect(x: 100, y: 100, width: 100, height: 100))
        view.text = "test"
        self.view.addSubview(view)
    }
}
