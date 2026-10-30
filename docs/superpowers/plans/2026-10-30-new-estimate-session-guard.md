# New estimate owner and job lifetime plan

**Goal:** Keep a job-launched estimate editor alive through a temporary job refresh, and never publish or link a created estimate under a changed owner or job.

**Architecture:** Capture the opening job identity and owner in the parent presentation. The editor observes the live job and suspends its description canvas if the job is absent, resuming only for the captured job and owner. Before and after each async create or link, check the captured owner, job, capability and API identity; if create may already have succeeded, tell the user to check before retrying rather than implying a rollback.

**Tech stack:** SwiftUI, XCTest, preview-only intercepted network requests.

**Spec:** docs/design/ios-golden-rules.md and docs/design/ios-implementation-process.md.

**Review focus:** transient loss, different job with same customer, account/workspace replacement, permission loss while create is in flight, ambiguous create or link outcome, duplicate retry.

- Exercise job parent disappearance while an unapplied canvas is open, then restore the same job and verify the text remains; a different job or changed owner must retire it.
- Exercise authority loss between create request and response and verify no callback or link occurs and the UI reports a potentially created estimate.
- Guard live state at each asynchronous boundary and validate returned estimate identity before adoption. Never claim to undo a server-accepted create.
- Run focused tests and request independent review; record unsupported process-death recovery and any failed or unrun cases.
