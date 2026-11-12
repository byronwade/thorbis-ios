#!/usr/bin/env python3
"""Exercise the actual authority primitive on macOS without Simulator.

This does not exercise SwiftUI, document-read publication, or navigation.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / "Thorbis/Sources/JobEstimateHandoffState.swift").read_text()
start = source.index("struct CustomerHandoffExitAuthority {")
end = source.index("\n@MainActor\nfinal class JobEstimateHandoffPresenter", start)
template = (root / "scripts/tests/overview_authority_host.swift").read_text()
marker = "// OVERVIEW_AUTHORITY_SOURCE"
assert template.count(marker) == 1
with tempfile.TemporaryDirectory(prefix="thorbis-overview-authority-") as directory:
    swift = Path(directory) / "probe.swift"
    binary = Path(directory) / "probe"
    swift.write_text(template.replace(marker, source[start:end]))
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(swift), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
