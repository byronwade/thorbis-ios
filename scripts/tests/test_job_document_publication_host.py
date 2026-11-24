#!/usr/bin/env python3
"""Exercise production document publication and identity with a gated loader double.

This does not test the real network loader or a mounted SwiftUI journey.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / "Thorbis/Sources/JobCommercialDocuments.swift").read_text()
start = source.index("final class JobDocumentCollections:")
end = source.index("\nenum JobEstimateCreation", start)
template = (root / "scripts/tests/job_document_publication_host.swift").read_text()
marker = "// JOB_DOCUMENT_PUBLICATION_SOURCE"
assert template.count(marker) == 1
with tempfile.TemporaryDirectory(prefix="thorbis-doc-publication-") as directory:
    swift = Path(directory) / "probe.swift"
    binary = Path(directory) / "probe"
    swift.write_text(template.replace(marker, "@MainActor\n" + source[start:end]))
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(swift), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
