#!/usr/bin/env python3
"""Compile the real review method with a host API stub; not a URLSession test."""
from pathlib import Path
import subprocess, sys, tempfile
root = Path(__file__).resolve().parents[2]
source = subprocess.check_output(['git', 'show', 'HEAD:Thorbis/Sources/CustomerEstimateReview.swift'], cwd=root, text=True) if '--baseline' in sys.argv else (root / 'Thorbis/Sources/CustomerEstimateReview.swift').read_text()
start = source.index('    func customerIssuedEstimateRevision(')
end = source.index('    /// The customer reviewed', start)
template = (root / 'scripts/tests/customer_issued_revision_fresh_host.swift').read_text()
with tempfile.TemporaryDirectory(prefix='thorbis-issued-fresh-') as tmp:
    swift = Path(tmp) / 'probe.swift'; binary = Path(tmp) / 'probe'
    swift.write_text(template.replace('    // ACTUAL_READER', source[start:end]))
    subprocess.run(['swiftc', '-swift-version', '6', '-parse-as-library', str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
