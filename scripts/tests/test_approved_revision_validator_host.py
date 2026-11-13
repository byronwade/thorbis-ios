#!/usr/bin/env python3
"""Compile the actual production revision validator; this is not an iOS test."""
from pathlib import Path
import subprocess, tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'Thorbis/Sources/CustomerEstimateReview.swift').read_text()
start = source.index('    func validate(for expected: EstimateRecord')
end = source.index('    /// Retained reader content', start)
template = (root / 'scripts/tests/approved_revision_validator_host.swift').read_text()
with tempfile.TemporaryDirectory(prefix='thorbis-approved-validator-') as tmp:
    swift = Path(tmp) / 'probe.swift'
    binary = Path(tmp) / 'probe'
    swift.write_text(template.replace('    // ACTUAL_VALIDATOR', source[start:end]))
    subprocess.run(['swiftc', '-swift-version', '6', '-parse-as-library', str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
