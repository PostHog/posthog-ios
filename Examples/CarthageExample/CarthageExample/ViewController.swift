import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        PostHog.capture("Carthage Main View Did Load")
        PostHog.group("some-group", groupKey: "id:4", properties: [
            "company_name": "Awesome Inc"
        ]);
        PostHog.flush()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func fireEvent(_ sender: AnyObject) {
        PostHog.capture("Carthage Button Pressed")
        PostHog.flush()
    }

}

