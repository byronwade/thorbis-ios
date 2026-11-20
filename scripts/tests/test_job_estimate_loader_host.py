#!/usr/bin/env python3
"""Compile the actual estimate loader and scheduler against a deterministic host API."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
source = (subprocess.check_output(["git", "show", "HEAD:Thorbis/Sources/JobCommercialDocuments.swift"], cwd=root, text=True)
          if "--baseline" in sys.argv else (root / "Thorbis/Sources/JobCommercialDocuments.swift").read_text())
start = source.index("@MainActor\nenum JobDocumentsLoader {")
end = source.index("    static func invoices(", start)
helpers = source[source.index("    private static func unique(", end):source.rindex("\n}")]
actual = source[start:end] + helpers + "\n}\n"
with tempfile.TemporaryDirectory(prefix="thorbis-estimate-host-") as temp:
    extracted = Path(temp) / "loader.swift"
    extracted.write_text("import Foundation\n" + actual)
    binary = Path(temp) / "probe"
    subprocess.run(["swiftc", "-swift-version", "6", "-parse-as-library", str(extracted),
                    str(root / "Thorbis/Sources/BoundedMainActorOperations.swift"),
                    str(root / "scripts/tests/job_estimate_loader_host.swift"), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
