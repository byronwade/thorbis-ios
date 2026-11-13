#!/usr/bin/env python3
"""Exercise the production customer load body against a mid-request authority change."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'Thorbis/Sources/PaperCustomerViews.swift').read_text()
start = source.index('    private func load(currentAuthority:')
end = source.index('\n}\n\nprivate struct CustomerContactIcon', start)
body = source[start:end].replace('    private func load(', '    func load(', 1)
harness = '''import Foundation
struct Customer { let id: String }
struct LocationState {
    var values: [Int] = []
    mutating func beginLoad() -> Int { 1 }
    mutating func receive(_ v: [Int], generation: Int) -> Bool { values = v; return true }
}
struct ContactState {
    var values: [Int] = []
    mutating func beginLoading() -> Int { 1 }
    mutating func receive(_ v: [Int], generation: Int) { values = v }
}
@MainActor final class FakeAPI {
    var onCustomer: (() -> Void)?
    var onContacts: (() -> Void)?
    var onLocations: (() -> Void)?
    var calls = 0
    func fieldCustomer(_ id: String) async throws -> Int { calls += 1; onCustomer?(); return 10 }
    func fieldContacts(_ id: String) async throws -> [Int] { calls += 1; onContacts?(); return [20] }
    func fieldLocations(_ id: String) async throws -> [Int] { calls += 1; onLocations?(); return [30] }
}
@MainActor final class Subject {
    var customer = Customer(id: "one")
    var api = FakeAPI()
    var locationNoteAuthority: Int? = 1
    var locationNotesSource: Int?
    var loadGeneration = 0
    var locationState = LocationState()
    var contactState = ContactState()
    var record: Int?
    var locationError: String?
    var error: String?
BODY
}
@main struct Probe {
    @MainActor static func main() async {
        let subject = Subject()
        subject.api.onCustomer = { subject.locationNoteAuthority = 2 }
        await subject.load()
        guard subject.record == nil && subject.contactState.values.isEmpty && subject.locationState.values.isEmpty else {
            fputs("FAIL: stale customer load published after authority changed\\n", stderr); exit(1)
        }
        let contacts = Subject()
        contacts.api.onContacts = { contacts.locationNoteAuthority = 2 }
        await contacts.load()
        guard contacts.record == 10 && contacts.contactState.values.isEmpty && contacts.locationState.values.isEmpty else {
            fputs("FAIL: stale contacts published after authority changed\\n", stderr); exit(1)
        }
        let locations = Subject()
        locations.api.onLocations = { locations.locationNoteAuthority = 2 }
        await locations.load()
        guard locations.record == 10 && locations.contactState.values == [20] && locations.locationState.values.isEmpty else {
            fputs("FAIL: stale locations published after authority changed\\n", stderr); exit(1)
        }
        let denied = Subject()
        denied.locationNoteAuthority = nil
        await denied.load()
        guard denied.api.calls == 0 else { fputs("FAIL: load started without authority\\n", stderr); exit(1) }
        let current = Subject()
        await current.load()
        guard current.record == 10 && current.contactState.values == [20] && current.locationState.values == [30] && current.locationNotesSource == 1 else {
            fputs("FAIL: current customer load failed to publish\\n", stderr); exit(1)
        }
        print("PASS: stale load withheld; current load published")
    }
}
'''.replace('BODY', body)
with tempfile.TemporaryDirectory(prefix='thorbis-customer-load-probe-') as tmp:
    swift = Path(tmp) / 'probe.swift'
    binary = Path(tmp) / 'probe'
    swift.write_text(harness)
    subprocess.run(['swiftc', '-parse-as-library', str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
