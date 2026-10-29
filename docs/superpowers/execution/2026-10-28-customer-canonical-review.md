# Canonical customer estimate review — C0 of BYR-1580

Customer mode previously reviewed caller-supplied estimate terms, then opened a
fresh signing action without proving that it matched them. It now checks the
current aggregate and loads its exact immutable issued revision before offering
a new decision. The customer sees that revision's full work, options, currency
and server total. Valid choice identities survive; a removed choice returns to
an unselected picker.

Loading and recovery use the existing Guided CustomerPresentation grammar.
Opening cannot show an approval action. Try again recovers from a failed read;
Not today and owner-authenticated hand-back remain available. A changed review
clears signing readiness. Drawn staff approval uses the reviewed revision, while
the public path verifies paper source/revision/hash and matching action terms.
API-generation and cancellation guards prevent old request chains continuing.

## Verification

Task1 observed missing-API RED, then24/24 protocol/public-action tests passed.
Task2 observed three missing-model compilation failures; after model adoption,
12cases executed:9model passed and3native failed on the old presentation. Focused
confirmation initially passed64/65. Trace proved SwiftUI cancelled the first
opening task during initial presentation, consuming the one-shot preview fault.
A persistent DEBUG-only fault now has an explicit control in its own preview
safe area. The real Try again action then loads canonical terms. The banner-menu
attempts and all failed results remain in the ledger; no diagnostic logs remain.

Final focused suite65/65 passed, zero failures/skips. Full Thorbis iPhone scheme
474/474 passed, zero failures/skips, completed2026-10-28 at19:57:52EDT. All164 Swift
sources, including Widgets, match the frozen test fingerprints. The12 release
Python checks passed. Runtime evidence is iPhone17Pro / iOS26.0; no new iPad,
iOS18, physical biometrics or live financial qualification is claimed.

One fresh whole-branch review covered d834fa9..abf31de on gpt-6-astra xhigh:
0Critical,0Important,0Minor. It checked actual backend DTO/paper/action contracts
at e96908e4 and affected routing/hand-back boundaries. No code fix or re-review
was requested. The full scheme ran independently on that same frozen source.

Evidence: [canonical review](../../design/evidence/customer-canonical-review/canonical-review.png),
[opening](../../design/evidence/customer-canonical-review/opening.png),
[recovery](../../design/evidence/customer-canonical-review/recovery.png), and
[full result summary](../../design/evidence/customer-canonical-review/full-tests.json).
These are synthetic read-only previews; the recovery image includes a labelled
DEBUG fixture control. They are not screenshots of real customer approvals.

## Remaining scope and delivery gate

The full user goal remains active. C1 must implement canonical offers, bounded
choices, server quotes and immutable acceptance; C2 must admit approved additions
into bill-once job billing without rewriting origin; C3 must expose technician
preparation and customer choice/review/signing in Swift. A second estimate alone
cannot provide that billing support. Bulk import still awaits destination and
canonical import/roster/photo interfaces. Tap to Pay remains disabled pending
its separate distribution qualification.

Signed archive, upload, Apple processing, saved notes and tester-group assignment
are the separate release gate following this source verification. No next-build
availability is inferred from tests or review. Source and plan artifacts are
retained for release evidence and ongoing work.

## Decisions and practical limits

- Ruling: continue the established native implementation method under user's explicit approve-everything/keep-working instructions — no new workflow permission menu — cost if wrong: own reversible branch, one independent whole-branch review and no merge.
- Ruling: retain the old signing overload through Task1 so existing presentation compiles independently; remove it in Task2 when the checked overload is wired — sequential source compatibility — cost if wrong: task2 cannot complete with an unchecked caller remaining.
- Task1 GREEN24/24,0fail/skip:10new immutable review/signing cases +14existing public-action cases. Scope mismatches, currentness, public hash/metadata/money and context rotation proven through real APIClient/URLProtocol. No Swift source changed while Xcode ran. Ruling: task-done verifies the finished xcresult and all-source fingerprints instead of rerunning the identical suite — developer instructions avoid unchanged duplicate testing — cost if wrong: verifier refuses completion on any source/count/status difference.
- Task2 model RED: three compilation failures only for absent useIssuedRevision. Ruling: split model and native RED so missing model API cannot hide the UI failures — implement model, then run its9cases alongside3native cases before wiring presentation — cost if wrong: native RED still must execute and fail on old screen behavior. Added pure adoption, canonical-read DEBUG fixtures and3native journeys; nonGET still405. Running expected12executed/9pass/3fail.
- Task2 first GREEN65executed:64pass/1fail (retry UI first wait). Exported full AX/video/test detail; it showed canonical success instead of Try again. Scoped trace reproduced: opening starts, fixture503read1, opening task cancelled, opening starts again with same API UUID, fixture read2 succeeds. No API retry exists; initial SwiftUI lifecycle cancellation consumed the one-shot fault. Ruling: use a persistent DEBUG-only fixture fault restored explicitly through the existing preview banner context menu, independent of view mount count — tests the actual retry against a controlled server transition, without a timer, production hook or weakened assertion — cost if wrong: only the read-only preview control fails; production behavior unchanged. Removed all CUSTOMER_REVIEW_TRACE source, stopped owned logstream59195. Re-run focused suite65 after changed fixture/test.
- Task2 second GREEN65executed:64pass/1fail, now past the intended visible Try again/no-approval/error capture. Context-menu restore button absent. Exact current source App.swift130 applies allowsHitTesting(false) to the preview banner, so its new debug context menu cannot open. Ruling: enable banner hit testing only for the explicit persistent-failure DEBUG fixture; retain normal passive preview banner — provides controlled fixture recovery without product hooks or layout change — cost if wrong: only that scenario intercepts banner touches. Added App.swift to plan file map. This is a diagnosed preview harness correction; no production behavior changed.
- Task2 third GREEN65:64pass/1fail, only preview context-menu restore still absent. Stopped that gesture approach and discussed the harness architecture in commentary. Screenshot/AX show a passive banner overlapping bottom safe area; using it as a state-control surface is the wrong owner. Ruling: replace the banner gesture with a named DEBUG-only top safe-area preview connection button; restore the original passive banner. Product retry remains the action under test, fault state stays in PaperPreviewProtocol, and the control reserves its own space — cost if wrong: only explicit failure preview geometry changes. This replaces the unreliable harness interaction rather than adding another production fix. Run the single recovery journey first, then the required whole focused set after it passes.
- Task3 in progress, BASEabf31de. Freeze all164Swift sources before full scheme. Ruling: begin the one read-only whole-branch review while the frozen full scheme runs — independent evidence gathering on the same exact source, no edits until tests finish — cost if wrong: neither review nor tests alone authorizes release, accepted findings still require regressions and a green final suite.
- Final: Ruling: C1-C3 remains required active work, not completion — source/API/database/billing offers are missing and cannot be faked in Swift — cost if wrong: customers still cannot select extras until full follow-on implementation qualifies.
- Final: Ruling: StageA/B outside changed boundaries stands on its delivery evidence and inclusion in this full scheme; affected readonly routing/identity was reviewed — cost if wrong: an inherited defect needs follow-up, not an implied whole-app certification.
- Final: Ruling: optional public signature-image attachment policy stands for C0; typed-name/consent/option acceptance is canonical, drawn staff approval remains strict — cost if wrong: a failed optional upload leaves no job photo although acceptance is valid; improve evidence recovery in follow-on work.
- Final: Ruling: retaining ink when navigating Back among complete options stands as inherited explicit-confirmation behavior; reload clears ink and final sign names the current price/choice — cost if wrong: redraw intent may be unclear; new add-on quote changes must invalidate signature readiness in C3.
- Final: Ruling: approved aggregate confirmation remains read-only and is not claimed canonical accepted-scope detail; acceptance projection is follow-on work — cost if wrong: approved option detail/amount remains incomplete until that projection is integrated.
- Final: Ruling: unchanged backend protocol source proof is sufficient for this native read/binding batch, without claiming new database/concurrency qualification — cost if wrong: a backend defect requires server correction; C1/C2 still need full R3 database gates.
- Final: Ruling: full scheme, archive signing and processed tester availability remain separate mandatory gates — cost if wrong: no next-build availability claim is made before actual delivery.


## TestFlight delivery verified

After the owner completed Apple passkey sign-in, build1.0(75) was visibly processed
and assigned to Internal Testers (2). Saved What to Test contains the exact
prepared review/option/back/retry/disabled-Tap instructions. Build ID
`dd858d53-fdf2-4da1-9c77-623772969ae8`; verified dashboard and unchanged-pixel PNG
are recorded in `docs/design/evidence/build-75/upload-status.json` and
`testflight-confirmation.png`. No new group, invitation or external review was
created. The dashboard's Ready to Submit label concerns external beta review;
the existing internal tester assignment is confirmed. C1-C3 and the full ongoing
goal remain active.
