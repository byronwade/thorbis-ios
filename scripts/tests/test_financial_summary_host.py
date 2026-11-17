#!/usr/bin/env python3
"""Exercise production financial summary functions with small model doubles (no mounted UI)."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
source = (root / 'Thorbis/Sources/FinancialViews.swift').read_text()
amounts = (root / 'Thorbis/Sources/CustomerDocumentAmounts.swift').read_text()
lines = source[source.index('func paperLinesTotal('):source.index('\n/// Groups documents', source.index('func paperLinesTotal('))]
summary = source[source.index('func money('):source.index('\n/// Web parity:', source.index('func money('))]
helper = amounts[amounts.index('struct CustomerDocumentAmounts:'):amounts.index('\n/// Customer-facing invoice headline')]
template = (root / 'scripts/tests/financial_summary_host.swift').read_text()
with tempfile.TemporaryDirectory(prefix='thorbis-financial-summary-') as d:
    path = Path(d) / 'probe.swift'
    path.write_text(template.replace('// FINANCIAL_SOURCE', lines + '\n' + helper + '\n' + summary))
    binary = Path(d) / 'probe'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
