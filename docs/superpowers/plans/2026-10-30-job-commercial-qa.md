# Job document visual QA — 2026-10-30

Scope: compact the job's estimate/invoice header, distinguish document cards, and avoid showing base-line amounts as accepted option prices. This is a focused change, not a complete redesign.

## Evidence

- iPhone 17 Pro simulator, iOS 18.2: `JobCommercialDocumentsTests/testApprovedOptionEstimateDoesNotShowBaseLinesAsAcceptedAmount`, `JobDocumentsSafetyUITests/testEstimateTotalsRemainAvailableInADisclosure`, and `JobDocumentsUITests/testTechnicianEstimateCardsKeepBothDocumentsOpenable` passed in `/private/tmp/thorbis-compact-verified.xcresult`.
- The final estimate-card test additionally checks that both cards are above the tappable Present estimates control; it passed in `/private/tmp/thorbis-present-hittable.xcresult`. It opens the first estimate; it does not test the second estimate's navigation.
- Before: `/private/tmp/thorbis-commercial-card-attachments/21A7B461-C4EC-4FF8-9CA8-25D659D9EC5E.png`. After: `/private/tmp/thorbis-compact-header-attachments/94519294-3F60-4FFA-AFFA-BCAB1333ED7E.png`. Those files and result bundles are local evidence, not repository artifacts.
- iPhone SE (third generation), iOS 18.2: default and largest standard text checks for Call, Text and Directions frame size, screen bounds and overlap passed in `/private/tmp/thorbis-narrow-header.xcresult`; the same bundle contains a separate failed accessibility test. At the large standard size, the action row remains readable in `/private/tmp/thorbis-narrow-header-attachments/5471E187-45BC-41B3-A61A-D657439848AC.png`. On this small phone only one full estimate card fits initially.

## Remaining verification

- Invoice navigation stalled after tapping an invoice in `/private/tmp/thorbis-commercial-card-final.xcresult`; it is not verified by these tests.
- The first largest-accessibility-size test incorrectly searched for a tab instead of the accessibility section chooser. Its corrected rerun `/private/tmp/thorbis-narrow-accessibility-menu.xcresult` exited in the XCTest automation session before interaction. Largest accessibility size is therefore not verified.
- Real longer localized labels are not tested because these labels are hard-coded English. The larger standard-text check is not a substitute for localization testing.
- An option-bearing estimate's accepted scope is held separately by the server; the estimate row does not receive a canonical accepted total. Amounts for those estimates are intentionally withheld. The server currently omits `options` for a no-option estimate; its iOS model cannot distinguish this valid omission from an unexpectedly incomplete response.

## Narrow-screen follow-up

- On the iPhone SE, the original visual change still left the second estimate behind the fixed action. The compact follow-up retains both full estimate cards above the action and adds an explicit 44-point control for offscreen job sections. Both the two-card/footer test and a tap through the control to Activity passed in `/private/tmp/thorbis-se-explicit-final.xcresult`. Screenshot: `/private/tmp/thorbis-se-explicit-final-attachments/DAFA71C1-376D-4616-BDD2-8CEC52AAB865.png`. The next tab label is partially faded beside the explicit control; this remains a visual limitation.
- On the unchanged base `68a7aa7`, the invoice-navigation test reproduced the idle stall after a tap at (201.0, 614.83) points on a fully visible Deposit card. Evidence: `/private/tmp/thorbis-invoice-base-qa.xcresult` and `/private/tmp/thorbis-invoice-base-attachments/BB7534B2-7989-4011-A992-AB8ED49F38F1.png`. It does not establish that the handler executed; navigation remains unverified.
- On a separate SE at the largest accessibility size, the corrected section-chooser test opened the chooser and selected Estimates in `/private/tmp/thorbis-access-invoice-qa.log`, but its subsequent reachability assertions used the wrong scroll direction. A corrected rerun `/private/tmp/thorbis-access-final.xcresult` exited in the XCTest automation session before completing. The largest-accessibility flow remains unverified.
