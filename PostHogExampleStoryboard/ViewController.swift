//
//  ViewController.swift
//  PostHogExampleStoryboard
//
//  Created by Manoel Aranda Neto on 21.03.24.
//

import UIKit

class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.

        let view = UITextView(frame: CGRect(x: 50, y: 50, width: 100, height: 100))
        view.text = "test"
        self.view.addSubview(view)
    }
}
