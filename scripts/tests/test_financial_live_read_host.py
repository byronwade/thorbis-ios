#!/usr/bin/env python3
"""Exercise actual live-read wrappers with a host stub, not URLSession or iOS."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / "Thorbis/Sources/SavedCopies.swift").read_text()
start = source.index("    func liveFieldEstimate(_ id: String)")
end = source.index("    /// The job's estimate links", start)
template = (root / "scripts/tests/financial_live_read_host.swift").read_text()
marker = "// LIVE_READ_WRAPPERS"
assert template.count(marker) == 1
api = (root / "Thorbis/Sources/API.swift").read_text()
policy_start = api.index("        let freshRead = requireFresh ||")
policy_end = api.index("        req.httpMethod = method", policy_start)
policy_marker = "// REQUEST_POLICY"
assert template.count(policy_marker) == 1
with tempfile.TemporaryDirectory(prefix="thorbis-financial-live-") as directory:
    swift = Path(directory) / "probe.swift"
    binary = Path(directory) / "probe"
    swift.write_text(template.replace(marker, source[start:end]).replace(policy_marker, api[policy_start:policy_end]))
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(swift), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
