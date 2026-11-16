#!/usr/bin/env python3
"""Test pure production page-state checks with note model doubles; not an iOS mounted test."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
source = (root / 'Thorbis/Sources/JobNotesPageState.swift').read_text()
template = (root / 'scripts/tests/job_notes_page_host.swift').read_text()
with tempfile.TemporaryDirectory(prefix='thorbis-notes-page-') as d:
    path = Path(d) / 'probe.swift'
    binary = Path(d) / 'probe'
    path.write_text(template.replace('// NOTES_STATE_SOURCE', source))
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
