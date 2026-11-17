#!/usr/bin/env python3
"""Exercise the actual live-membership wrapper with a simulated paged host client."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'Thorbis/Sources/SavedCopies.swift').read_text()
start = source.index('    func liveFieldJobEstimateLinks(_ jobID: String)')
end = source.index('    private func requireLive(', start)
template = (root / 'scripts/tests/job_membership_live_host.swift').read_text()
with tempfile.TemporaryDirectory(prefix='thorbis-membership-live-') as directory:
    swift = Path(directory) / 'probe.swift'
    binary = Path(directory) / 'probe'
    swift.write_text(template.replace('// LIVE_MEMBERSHIP_WRAPPER', source[start:end]))
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
