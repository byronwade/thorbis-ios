#!/usr/bin/env python3
"""Exercise the production receipt validator with a small host-side model stub."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
source = (root / 'Thorbis/Sources/CustomerEstimateReview.swift').read_text()
start = source.index('struct CustomerEstimateAcceptanceReceipt:')
end = source.index('private struct CustomerReviewPaper:', start)
template = (root / 'scripts/tests/customer_estimate_receipt_host.swift').read_text()
with tempfile.TemporaryDirectory(prefix='thorbis-receipt-') as tmp:
    swift = Path(tmp) / 'probe.swift'
    binary = Path(tmp) / 'probe'
    swift.write_text(template.replace('// ACTUAL_RECEIPT', source[start:end]))
    subprocess.run(['swiftc', '-swift-version', '6', '-parse-as-library', str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
