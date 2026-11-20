#!/usr/bin/env python3
"""Compile actual page adapter body against a host API stub; not URLSession or iOS."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
source = (root / 'Thorbis/Sources/FieldAPI.swift').read_text()
start = source.index('    func fieldJobEstimateLinkPage(')
end = source.index('    /// Links an existing estimate', start)
template = (root / 'scripts/tests/job_estimate_page_adapter_host.swift').read_text()
with tempfile.TemporaryDirectory(prefix='thorbis-estimate-page-') as directory:
    swift = Path(directory) / 'probe.swift'
    binary = Path(directory) / 'probe'
    swift.write_text(template.replace('// PAGE_ADAPTER', source[start:end]))
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library', str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
