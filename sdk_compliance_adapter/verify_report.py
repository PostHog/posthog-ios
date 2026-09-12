"""Check the pinned macOS profile ran all 47 cases, independently of pass/fail."""

import re
import sys
from pathlib import Path


def verify_report(report: str) -> None:
    counts = re.findall(r"\*\*(\d+)/(\d+)\*\* tests passed", report)
    if len(counts) != 3 or [int(total) for _, total in counts] != [47, 30, 17]:
        raise ValueError(f"Expected total/capture/flags inventory 47/30/17, got {counts}")
    rows = re.findall(r"^\| .+ \| [✅❌] \| \d+ms \|$", report, re.MULTILINE)
    if len(rows) != 47:
        raise ValueError(f"Expected 47 per-test result rows, got {len(rows)}")
    print("Verified 47 results: 30 capture_v0 + 17 feature_flags (macOS shared core)")


if __name__ == "__main__":
    verify_report(Path(sys.argv[1]).read_text())
