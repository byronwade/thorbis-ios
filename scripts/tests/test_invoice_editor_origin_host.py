#!/usr/bin/env python3
"""Exercise the production invoice edit gate against an API-origin change.

This host check isolates canEdit; it does not prove SwiftUI masking, saving,
session restoration, or network request cancellation.
"""
from pathlib import Path
import re
import subprocess
import tempfile

source = Path("Thorbis/Sources/InvoiceLineEditorView.swift").read_text()
match = re.search(r"    private var canEdit: Bool \{\n(.*?)\n    \}", source, re.S)
assert match, "production canEdit gate not found"
gate = match.group(1)
swift = f'''import Foundation
struct Invoice {{ var status = "draft" }}
struct Editor {{ var invoice = Invoice() }}
struct Session {{ func can(_ capability: String, feature: String? = nil) -> Bool {{ true }} }}
struct Probe {{
    var editor = Editor()
    var session = Session()
    var editorTransportIsCurrent = true
    var canEdit: Bool {{
{gate}
    }}
}}
@main struct Main {{
    static func main() {{
        var probe = Probe()
        precondition(probe.canEdit, "authorized original origin should remain editable")
        probe.editorTransportIsCurrent = false
        precondition(!probe.canEdit, "a retired API scope must not allow invoice edits")
    }}
}}
'''
with tempfile.TemporaryDirectory(prefix="thorbis-invoice-origin-probe-") as directory:
    path = Path(directory) / "Probe.swift"
    binary = Path(directory) / "probe"
    path.write_text(swift)
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(path), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print("invoice editor origin gate probe passed")
