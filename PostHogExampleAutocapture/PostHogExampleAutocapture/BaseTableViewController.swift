/*
 See LICENSE folder for this sample’s licensing information.

 Abstract:
 A base class used for all UITableViewControllers in this sample app.
 */

import UIKit

class BaseTableViewController: UITableViewController {
    // List of table view cell test cases.
    var testCells = [CaseElement]()

    func centeredHeaderView(_ title: String) -> UITableViewHeaderFooterView {
        // Set the header title and make it centered.
        let headerView = UITableViewHeaderFooterView()
        var content = UIListContentConfiguration.groupedHeader()
        content.text = title
        content.textProperties.alignment = .center
        headerView.contentConfiguration = content
        return headerView
    }

    // MARK: - UITableViewDataSource

    override func tableView(_: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        centeredHeaderView(testCells[section].title)
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        testCells[section].title
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        1
    }

    override func numberOfSections(in _: UITableView) -> Int {
        testCells.count
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell
    {
        let cellTest = testCells[indexPath.section]
        let cell = tableView.dequeueReusableCell(withIdentifier: cellTest.cellID, for: indexPath)
        if let view = cellTest.targetView(cell) {
            cellTest.configHandler(view)
        }
        return cell
    }
}
