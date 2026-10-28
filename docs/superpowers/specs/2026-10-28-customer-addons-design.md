# Customer choices, exact review and approved additions — BYR-1580

The user wants a catalog/cart for technicians and customers, every estimate and
invoice for the current job, and Apple-simple presentation without losing features.
Stages A and B are delivered in TestFlight 73/74. This document preserves the full
remaining scope; the first implementation plan addresses the review boundary below.
Customer-selected add-ons are not complete until their server, billing and native
flows are verified together.

## Full customer add-on outcome

Technicians prepare included work and optional offered extras from the catalog or
custom descriptions. Customers can browse the published offers, choose quantities
within the offer's policy, see the exact resulting work and price, go back freely,
and explicitly approve. Nothing optional is selected for them. Internal costs,
margins, source records and unoffered catalog entries stay out of customer mode.
Complete mutually exclusive estimate options remain a separate feature.

Estimates owns immutable offers and their source snapshots, allowed quantities,
option applicability, normalized selections and server quote. A quote binds the
tenant/customer/estimate, issued revision and paper hash, choices, final lines and
minor-unit total. Reading/quoting does not consume the approval nonce. The existing
signed decision recomputes and verifies that exact quote under its source/token
locks, then commits nonce, acceptance, lifecycle, audit and outbox atomically.
Changed selections invalidate review and consent. Plain/staff approval cannot
bypass selection acceptance for an offer-bearing revision.

Database acceptance guards, immutable accepted scope, API schemas/projections,
feature admission and compatibility ship with the domain contract. The existing
guard in migration 0128 only admits base scope or one complete option; a client-only
cart cannot meet this requirement. Job-related creation must pass the new offers
through the Jobs-owned port while deriving customer/location and membership.

Extras after the original approval also require explicit change-order and bill-once
source authority. Linking a second approved estimate preserves the job's original
estimate/revision; today's invoice-birth guard accepts only that original scope.
Preserve origin provenance and extend canonical accepted additions and billing
admission under the shared job lock, including schedule/deposit interactions.
Do not represent a second estimate or manual line copy as completed billing support.

The implementation sequence is: C0 exact native review; C1 domain/API/database
offer and quote acceptance; C2 postapproval additions and bill-once billing; C3
technician offer preparation and customer selection/review/signing in Swift. These
are delivery stages of the full outcome, not reduced definitions of completion.

## C0: review the canonical issued estimate before signing

Current native customer mode reviews an EstimateRecord supplied by the caller.
For options, startSigning later opens a public action without checking that it
matches the reviewed terms. The immutable revision endpoint already exists:
GET /v1/estimates/{estimateId}/revisions/{revisionNumber}. It returns a direct
EstimateRevision DTO, with a distinct revision UUID, aggregate estimateId,
organization/customer/location, revisionNumber, issued lifecycle, title, full
lines/options, totalAmount and currency. Money is integer minor units; public
action numbers also represent minor units despite Swift's Double decoding.

Add a read-only native DTO for that endpoint; never manufacture an EstimateRecord
from revision data. Before showing a new decision, read the current aggregate
on its existing GET endpoint and require the captured identity, sent status and
requested current revision. Then load that exact immutable revision and validate
aggregate/job-captured organization, customer and location, requested revision and
issued status. These reads prove currentness at opening; final server guards
refuse revisions replaced while the customer reads. Initial opening shows a named loading state instead
of actionable caller-supplied terms. Failure offers Try again and explains when
the technician must reopen current paper. Existing approved confirmation remains
read-only. Customer display uses the immutable title, full lines/options, currency
and server total. Preserve option selection only when its identity still exists;
never select a replacement or recommended option automatically.

For the signed public path, POST commercial-documents returns the existing
tenant/source-bound paper envelope. Retain its contentHash and validate
source.type == estimate, source.id == the aggregate and snapshot.content.revision.number
== the reviewed revision. The immutable DTO itself has no hash. The minting and
signing server ports rebuild the issued content from that revision and verify
the hash. Retain the issued paper's hash and known source;
mint on that exact aggregate with the reviewed revision/hash. Require the returned
public action to match the issued hash, revision, title, currency, base total and
complete option identity/title/description/currency/total metadata. Its base scope
must match the immutable lines when no options exist. Refuse mismatches instead
of signing unseen terms. Only a sent, signing-enabled action may enter signing.
The final decision keeps that nonce/hash and the reviewed chosen option. The
drawn single-scope staff path remains supported against the reviewed revision.

Capture API generation for opening and signing. Cancellation or a workspace/session
change cannot publish old paper or continue approval from the old context. Preserve
signature drawing/upload, typed name, consent, decline, Back, Not today, technician
hand-back and the existing complete-option flow. Clear signature/consent readiness
when a different review is loaded. Do not add an endpoint, provider, schema migration
or live financial action in C0.

## Design and verification

Guided CustomerPresentation is the canonical pattern, with Paper's customer cards
and native system navigation. The current Paper token hash is 2803f4aa; the source
is Thorbis Mobile in file 01KY0S86CYXENWSH216F3ZB058. Use the existing CustomerType
20pt/22pt body, 34pt/40pt total, 56pt targets, ink totals, one bottom commit, full
description wrapping, explicit back/no and full-screen confirmation. Secondary
details use existing sheets/disclosures. No new visual pattern is introduced by
C0's loading/retry and canonical-data substitution.

C0 tests must prove canonical title/lines/amount replace a contradictory local
record before review; foreign identity, historical/superseded revision, malformed
money and changed API context cannot enable signing; public hash/revision/option
mismatches stop approval; unchanged exact terms retain all working paths. Add native
loading/error/retry and canonical-price journeys, then run the full native scheme.
Use one fresh whole-branch review, fix Important findings with RED/GREEN tests,
archive/sign/upload and verify the existing TestFlight group's availability.

C1/C2 require R3 domain/API/PostgreSQL adversarial concurrency, RLS, immutable
evidence, bill-once and migration compatibility verification plus full pnpm check.
C3 requires server-quote-driven native decisions, choice invalidation, unknown
contract preservation/refusal, job/session boundaries, accessibility and release
evidence. Keep exposure held until the complete contract is deployed and qualified.
The local bulk demo kit stays pending destination and governed import/roster/photo
interfaces; it is independent of approval authority.

Authoritative recon: backend e96908e4, native d834fa9; Estimates schema/commands/
document-actions/queries, Jobs related-estimate and origin rules, Invoicing
ensureCompletionBilling, migration0128, contracts/api/http.md and
contracts/design/customer-presentation.md. Fresh guarded-start accepted BYR-1580
at /private/tmp/thorbis-addons-start-8tu__p_l/receipt.json without tracker transition
or credentials. The connected shared-notes operation was unavailable after a
bounded retry; current issue and repository contracts supplied the authority.

Builder check asked how immutable historical paper proves currentness and hash
identity. The existing aggregate GET, source-bound issued envelope and final
mint/approval guards above answer it; no new server endpoint is needed. Those
are implementation decisions grounded in current contracts, not new user choices.
