# Customer document descriptions implementation plan

**Goal:** Make long descriptions easy to scan and read without changing customer document contents or consent.

**Architecture:** Add a scoped, read-only description sheet in the customer job-document browsing surface. Preserve full inline terms in signature and approval destinations. Dismiss the sheet when the selected document or session authority changes.

**Tech stack:** SwiftUI and XCTest.

**Spec:** docs/design/ios-golden-rules.md and docs/design/ios-implementation-process.md.

**Review focus:** Large text; long multiline descriptions; navigation and job isolation; authority changes; unchanged money and consent.

- Add a UI regression fixture with multiple paragraphs and check opening, complete text, read-only state, and return to the same job document.
- Run the test before the implementation and verify it fails because Show more is absent.
- Add a shared read-only sheet and enable it only in job-document browsing. Keep consent destinations unchanged.
- Run the test and relevant document, money, and release-note checks; inspect the diff and report any verification gaps.
