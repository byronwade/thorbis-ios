# Description canvas parent lifetime implementation plan

**Goal:** Keep unapplied text safe during a transient source-record refresh without replaying it across an actor, authority, document revision or editor replacement.

**Architecture:** Capture the document when the editor is opened so a parent refresh cannot tear down its SwiftUI sheet. The nested canvas retains its local working text, suspends while the source record is unavailable, and resumes only when the exact original record and authority return. A changed document or authority permanently retires that canvas. Track unapplied canvas changes in the enclosing dismiss guard.

**Tech stack:** SwiftUI, XCTest, Xcode.

**Spec:** docs/design/ios-golden-rules.md and docs/design/ios-implementation-process.md.

**Review focus:** Failed refresh; same-revision return; changed revision; permission loss; unsafe reconstruction or session teardown; nested sheet dismissal.

- Exercise actual parent record loss while an estimate canvas contains unapplied text; observe the existing editor teardown.
- Present estimate and invoice editors from captured documents while comparing the live parent record with the captured document; never authorize a changed record.
- Preserve local working text through transient same-session absence and require explicit discard for a replaced record or lost authority. Propagate dirty state to the enclosing dismissal guard.
- Exercise estimate and invoice source loss, safe return, replacement and authority transitions; build and document any untested or unsupported recovery.
