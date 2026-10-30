# Job overview clarity — in review

Base: build 85 source, branch `codex/pricebook-show-more` at `0396781`. Paper source: Thorbis Mobile, “21 · Job details” (`PPL-0`, direct JSX): compact customer/job heading, status and tabs, descriptive job text, grouped details. The native adaptation retains its semantic tokens and existing system navigation while placing customer name ahead of the job ID and bringing visit shortcuts forward. A real job site is still not inferred from account locations.

## Feature inventory

The primary job step, status, schedule, customer link, Call, Text, Directions, all tabs, full office note, booking call, contacts, account locations, equipment, membership, visit notes/photos/follow-ups, past visits, booked time, visit time, job ID, and Job actions remain reachable. The technical ID, booked date, and time live in More job details; Copy job ID remains in the toolbar menu. Scheduled time remains in its existing header control, with the full date available in More job details. The progress track remains on Overview; document/activity headers keep identity, balance and quick actions, without repeating that track. Photos retains its previous compact treatment.

## Evidence

- Before/after images: `docs/design/evidence/2026-10-29-job-glance/`. The first after-overview screenshot taken after a fixed five-second wait was captured before the asynchronous footer load; it is not used as proof of the action. The saved after-overview image comes from the existing test after it waits for the Collect action to be hittable.
- Pre-change UI red: `/private/tmp/thorbis-job-glance-red.log` recorded visit actions below customer locations. Its result bundle is incomplete because Xcode hung during cleanup and was stopped after the test result was logged.
- Pre-fix singular option red: `/private/tmp/thorbis-job-singular-red.log` showed the old “1 options” label did not match “1 option”; Xcode was stopped after test output during cleanup.
- Final focused simulator run: **15 passed, 0 failed** at `/private/tmp/thorbis-job-glance-final3.xcresult` on iPhone 17 Pro (iOS 26). It covers visit ordering and detail disclosure, actions on document tabs, long-title wrapping, singular estimate option, actual Collect/Wrap-up access, explicit Directions location choice, and release-note rules.
- The intermediate `final2` run failed its Job ID assertion after the full scheduled-date row was restored; the test was corrected to scroll through expanded details and its focused retry passed. The failed log is `/private/tmp/thorbis-job-glance-final2.log`; Xcode cleanup was stopped after its result was recorded.
- Screens were inspected in the simulator for overview and Estimates. Full VoiceOver, largest Dynamic Type, iPad, real-device performance and offline journey verification were not performed; this is not full-app or Paper parity certification.

No TestFlight upload or independent review has occurred for this change. The separate activity-selection/offline branch is not included.

Follow-up review improved customer-link discoverability and tap size: the customer name has a chevron, wraps rather than being truncated, and its hit target is at least 44 points. The test tapped it and verified the customer profile opened. The targeted regression was red before the change (`/private/tmp/thorbis-job-customer-link-red.log`; Xcode stopped during cleanup after recording failure), then the navigation, long-job-title, Collect/Wrap-up, location-choice and release-note suite passed **13/13** in `/private/tmp/thorbis-job-customer-link-green.xcresult`. The updated after-overview image was captured after Collect became tappable. Long customer names, VoiceOver and physical-device behavior remain unverified.

The customer-link frame now also has an explicit 44-point minimum width. A DEBUG-only single-character customer fixture and the normal customer navigation and long-job-title tests passed **3/3** in `/private/tmp/thorbis-job-customer-width-final.xcresult`. The short-name width case also passed before the explicit minimum because its icon and chevron already made the fixture wide enough; it was not a demonstrated red regression. Release audits must exclude the new `--paper-preview-short-customer-name` fixture flag.
