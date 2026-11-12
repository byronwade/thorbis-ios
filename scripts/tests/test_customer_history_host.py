#!/usr/bin/env python3
"""Exercise production history batching/indexing on the host, without Simulator.

Does not measure SwiftUI layout, network requests, or runtime performance.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / "Thorbis/Sources/PaperCustomerViews.swift").read_text()
start = source.index("enum CustomerJobHistory {")
end = source.index("\n/// Native translation", start)
template = (root / "scripts/tests/customer_history_host.swift").read_text()
marker = "// CUSTOMER_HISTORY_SOURCE"
assert template.count(marker) == 1
with tempfile.TemporaryDirectory(prefix="thorbis-history-") as directory:
    swift = Path(directory) / "probe.swift"
    binary = Path(directory) / "probe"
    swift.write_text(template.replace(marker, source[start:end]))
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(swift), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
