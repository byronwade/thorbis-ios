# Every job's commercial documents — BYR-1580

User intent: show every estimate and invoice for the current job, including
customer presentation, and support cart-like add-ons with optional catalog or
custom items. The user explicitly selected BOTH technician preparation and
customer selection. Continue Apple-like simplicity without removing features;
ship useful verified TestFlight batches. Baseline488fb5e / TestFlight72.

## Delivery sequence

A. Fix job-only document completeness, visible lists and customer handoff.
B. Share the complete, multi-add catalog/cart interaction across technician
estimate and invoice editors; preserve custom items and their different source
contracts. C. Implement explicit customer add-on offer/quote authority in the
backend, then customer selection/review/acceptance. Current package options are
complete mutually exclusive alternatives and remain a separate feature. This
plan implements A; B/C remain active work under the same user goal.

## Stage A behavior

- Validate job, organization and customer identity. Invoice.jobId must exactly
  match. Estimates use validated JobEstimateLink.jobId plus the job's immutable
  origin estimate; EstimateRecord has no jobId. Never infer membership by customer.
- Fetch all pages, deduplicate IDs, and retain valid successful detail reads if
  another detail fails. Keep prior verified same-scope rows visibly stale on a
  transient failure. Failed or incomplete reads cannot become successful empty
  states, duplicate-create prompts or automatic next steps.
- An authoritative empty job-invoice response is empty. Use organization/cache
  compatibility only for404/405, validate every recovered record, and report that
  completeness is unknown. Recheck session generation after every fallback await.
- Show all invoice summaries directly, each opening its existing detail screen.
  Keep payments, PDF, signature, draft editing and creation. Prefer an outstanding
  issued invoice over a newer paid deposit for the job-tab footer; preserve the
  existing TechJobFlow across all documents.
- Job Show to customer opens a locked commercial-document hub for this job.
  Retain customer contact self-edit as Customer details. All job papers remain
  visible; mutable/approval actions require fresh verified association and the
  existing permissions/lifecycle. Draft/declined/void records may be read without
  silently issuing, revising or approving them.
- Reuse existing customer estimate/invoice presenters and technician hand-back.
  Refresh the selected exact record before review. Customer mode shows only
  approved descriptions, quantities, prices, totals and document status, never
  internal catalog/source metadata. Payment opens only after staff hand-back.
- Native scrolling, Dynamic Type and dark mode must keep every row reachable.

## Evidence and boundaries

The job invoice UI currently hides other records behind a small menu. A linked
estimate detail failure currently overwrites the list with the origin estimate.
The normal organization fallback already filters by job; no live cross-job leak
was proved. New endpoint/link/cache validation prevents malformed-association
leaks. Job APIs already paginate. Issued invoice lines stay immutable; approved
estimate changes require a change order. No new customer money authority is
invented in Stage A.

Fresh backend source was read through connected GitHub because Documents reads
stalled. domains/estimates/src/schemas.ts blob4cd96697707330facc83bf1216032ae5294b4403
and document-actions.ts blob6a38f9e1f2dfe2fc05ac515ffcd2f4cce5778cb6 bind acceptance
to an issued revision and one whole option. Native field contracts remain in
docs/audits/field-contracts.md and financial-actions-contract.md.

The separate bulk demo-data request is being prepared in parallel. Its target
workspace is pending user clarification; no bulk data or invitations have been
created. This does not delay Stage A.
