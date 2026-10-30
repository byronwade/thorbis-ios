# Job Overview Clarity Implementation Plan

**Goal:** Make the job easier to understand at a glance while keeping its actions and information available.

**Architecture:** Retain the existing Paper layout, job tab navigation, authority checks and direct contact/directions actions. Bring visit shortcuts ahead of long customer-account sections, show the customer name ahead of the job identifier, and group secondary job details behind a labeled disclosure. Use a compact header on document/activity tabs so their content begins sooner, without truncating the job title.

**Tech Stack:** SwiftUI, XCTest/XCUITest, iOS 18+.

**Source:** Paper Thorbis Mobile “21 · Job details”; `docs/design/ios-golden-rules.md` and the user's request for plain language and less repetition.

## Constraints and checks

- No feature removal; call, text, directions, job actions, notes, photos, follow-ups, customer profile and all job tabs remain available. Never imply a customer account location is the verified job site.
- Preserve balance, permission, offline, financial and navigation behavior. Long titles must wrap, including in compact state.
- Test visit actions before long account sections, detail disclosure access, compact-tab return to direct contact actions and directions selection; record accessibility and device gaps.
- Add a user-facing release note and run focused job overview, location and release-note tests. Capture simulator evidence and request independent review.
