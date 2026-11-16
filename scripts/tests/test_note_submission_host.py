#!/usr/bin/env python3
"""Exercise production note-submission snapshot with a delayed host task, not mounted SwiftUI."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
source = (root / 'Thorbis/Sources/NoteSubmissionSnapshot.swift').read_text()
template = (root / 'scripts/tests/note_submission_host.swift').read_text()
with tempfile.TemporaryDirectory(prefix='thorbis-note-submit-') as d:
    path = Path(d) / 'probe.swift'
    binary = Path(d) / 'probe'
    path.write_text(template.replace('// NOTE_SUBMISSION_SOURCE', source))
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
