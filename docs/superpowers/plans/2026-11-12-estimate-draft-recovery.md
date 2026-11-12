# Estimate Draft Recovery Implementation Plan

**Goal:** Preserve unsent estimate intent locally without enabling submission.

**Architecture:** A protected local store isolates origin, organization, actor and estimate, saves immutable operation envelopes, and refuses conflicting reuse. Current authority is rechecked before any read; feature or policy holds do not delete intent. No UI or transport integration is provided.

**Tech Stack:** Swift, Foundation, XCTest.

- [ ] Test persistence, identity isolation, operation collision and unavailable authority.
- [ ] Implement protected, atomic local storage and fail-closed reads.
- [ ] Test and obtain independent review before integration.
