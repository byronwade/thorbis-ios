# Customer job document book

This batch gives each verified job estimate/invoice a stable page in one customer
handoff. Previous/Next, native swipes, the all-documents menu and the original
overview remain available. Canonical review and signature are separate destinations
so drawing cannot change documents; Back retains the selected page. Payment still
requires technician authentication and a fresh exact invoice/job check.

Charges, original discount/credit descriptions, total, paid and due use checked
integer minor units. Each invoice has its own dated payment/refund disclosure.
Original received amount, refund and remaining received amount are separate;
foreign/duplicate/inconsistent history is rejected, never shown as complete.
Cancellation/workspace changes cannot publish the former invoice's history.
Discounted owed invoices retain priority over newer paid deposits, and estimate
status totals retain valid discounts without combining package choices.

## Design and retained behavior

Paper Thorbis Mobile Q6N-0/R5C-0/R7U-0, token2803f4aa, shared Theme/CustomerType and
CustomerPresentation are the reference. Native PageTabViewStyle provides scrolling;
[Apple documentation](https://developer.apple.com/documentation/swiftui/pagetabviewstyle).
Linear Mobile's quiet header/disclosure was adapted; list/settings examples were
rejected for this task. The user chose existing Paper directly after12ui required
a separate sign-in and produced no candidates. No generated design replaces Paper.

Large text uses named56pt arrow controls, compact position with a full accessibility
label, and a separate document menu; intermediate widths use ViewThatFits. Body
text and financial totals retain the stronger customer size rules. Draft/declined
estimates and void paper stay read-only. Paid invoices retain signing when unsigned
and current-revision signer evidence when signed; paid invoices offer no collection.
Stale→fresh unchanged estimates reload issued terms without losing their page.
Invalid estimate amounts display an explicit unavailable state and cannot be reviewed.

## Verification and review

Initial important qualification passed104/104:85affected units and19native journeys,
zero failures/skips. All170Swift fingerprints matched. Evidence and the one fresh
whole-branch review are in [job-document-book](../../design/evidence/job-document-book).
The12release-script boundary tests passed. This is focused qualification under the
user's explicit important-tests/skip-repetitive-CI preference, not a full scheme.

Review returned0Critical,2Important,2Minor. Both Important findings were accepted:
stale estimate task identity and paid signing retention. Root regraded both Minors
Important under the explicit checked-money and no-feature-removal requirements:
invalid-money rendering and missing signer label. All four enter one fix pass.
Regressions first reproduced missing signing/signer/error states. The reconnect
setup initially missed the pull threshold; tapping the actual estimate entry
reloaded it as stale, then the final same-page refresh assertion reproduced the
real lifecycle defect. Fixture failure is explicit and persistent until restored,
not a timer or one-shot response consumed by SwiftUI lifecycle.

A new-class filtered Xcode run executed0tests despite compiling sources; it is
recorded as discovery failure, not a pass. Installed/built UIbinary hashes matched;
actual enumeration listed all new methods, which then ran using exact identifiers.

Final release qualification passed95/95 (85units+10native journeys), zero failures
or skips. All172Swift source/test/widget fingerprints match. Initial iPad mini
(iOS18.2) smoke passed3/3: money history, swiping and large text. After the shared
large-type card refinement, the iPad large-text regression passed1/1 again on the
final source. Six selected phone screenshots and the iPad screenshot were visually
inspected; metadata identifies synthetic read-only previews, not live approvals.

Visual review caught one further shared-card issue: a fixed price left87.33pt for
the description at maximum type size. Native RED failed the meaningful readable
column threshold (241.2pt). Accessibility line and total rows now stack, preserving
ordinary Paper geometry and combined reading order. Individual amounts reuse the
checked total helper. The final95-run and iPad1-run include that fix.

Signed archive and upload succeeded for **1.0 (76)** on October28 at22:58EDT.
Apple processing completed; build76 is assigned to Internal Testers(2), and What
to Test shows Saved. [Delivery record](../../release/build-76.md) and
[dashboard proof](../../design/evidence/build-76/testflight-confirmation.png).
Runtime source956a22f and172frozen Swift files match the archive. App+widget76,
strict signature/team, preview/control exclusion and disabled Tap audit passed.
This closes the document-book delivery batch; the overall continuous goal stays active.

## Decisions and limits

- Continue the established isolated branch under the user's continuous implementation
  and upload authorization; do not repeat design/permission menus. Cost if wrong:
  local reviewable changes need revision before release; no merge is authorized here.
- Use disjoint focused agents for fixtures, routing, native capability research and
  one fresh final review. Important financial/identity/consent/native/release checks
  replace repetitive basic full-CI loops at the user's request. Cost if wrong:
  an unrelated unexercised regression may need a subsequent fix; list actual coverage.
- Reuse the pinned Stripe Terminal5.8.1 package cache after stack sampling proved a
  redundant binary download stall. No dependency upgrade or vendor policy change.
- Preserve canonical positive-quantity/USD contracts; no compatibility claim for
  unsupported zero quantities or non-USD collection.
- Test fixtures/control menu are DEBUG-only opt-ins with a network sink; Release
  boundary audit must prove their absence. No customer/payment/provider data was
  written to a live service by native journeys.
- Physical VoiceOver/biometrics, older physical-device performance and live provider
  collection are not certified by simulator/source evidence.

C1–C3 customer catalog offers, server quotes/immutable acceptance, approved additions
and bill-once billing remain required separate work. Tap to Pay remains disabled
until distribution qualification. No guessed-tenant bulk import was performed.
The [native capability roadmap](../../design/native-field-capability-roadmap-2026-10-28.md)
prioritizes durable scoped media, performance and native conveniences; it activates
no capability. The overall continuous improvement goal remains active.
