import unittest

from verify_report import verify_report


def report(passed=32, total=47):
    return (
        f"**{passed}/{total}** tests passed\n"
        "## Capture Tests\n**29/30** tests passed\n"
        "## Feature_Flags Tests\n**3/17** tests passed\n"
        + "| test | ✅ | 1ms |\n" * total
    )


class ReportInventoryTests(unittest.TestCase):
    def test_assertion_failures_remain_advisory(self):
        verify_report(report())

    def test_empty_report_rejected(self):
        with self.assertRaises(ValueError):
            verify_report("")

    def test_zero_test_report_rejected(self):
        with self.assertRaises(ValueError):
            verify_report(report(passed=0, total=0))

    def test_missing_case_rejected(self):
        with self.assertRaises(ValueError):
            verify_report(report(total=46))

    def test_missing_detail_rows_rejected(self):
        with self.assertRaises(ValueError):
            verify_report(report().replace("| test | ✅ | 1ms |\n", "", 1))


if __name__ == "__main__":
    unittest.main()
