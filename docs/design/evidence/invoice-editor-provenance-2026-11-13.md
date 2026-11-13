# Invoice editor source provenance and uncertain writes

Status: held investigation; no app integration or release qualification.

`InvoiceLineEditorView` receives an `InvoiceRecord` without its source identity.
Capturing the currently configured origin in `onAppear` cannot establish where that record was read.
`InvoicePaymentCollectionModel.load()` can fall back to `JobDetailCache.invoice(id)`, whose disk key is only the invoice ID and whose payload carries neither actor nor origin. An ordinary `APIReadProvenance` reports transport source, but is explicitly not an authorization proof. The job path separately tracks `overviewInvoicesAuthority` after its scoped collection read; the creation path uses its own scope checks.

A safe implementation needs a source envelope bound at the original read to verified actor, tenant, API origin, invoice/customer/job identity and lines revision. Scoped cached copies must include verifiable actor/tenant/origin provenance and their offline grant must be rechecked; silently discarding existing legitimate offline work is not acceptable. A benign foreground refresh should not itself destroy a draft. Actual access revocation must hide it without dropping the local draft. A changed revision must keep the draft available for authorized conflict review while preventing replacement/issue until reconciliation.

A request sent before a transport/session transition may already have committed. A post-await guard can suppress a stale response, but cannot establish cancellation. Until server evidence reconciles that exact operation, preserve an explicit unknown-outcome state, block further replace/issue, and never claim the draft was saved or lost. The current replace path lacks an established idempotency/reconciliation contract. Root recreation can also discard local state, so in-memory gating alone is insufficient for durable recovery.

`scripts/prototypes/invoice_editor_provenance*.swift` is an isolated host-only policy sketch. It tests identity mismatch, authorization loss, conflict visibility and an uncertainty fence; its caller supplies authorization/provenance, and its state is not durable. It is not wired to production and does not prove security, offline behavior, server reconciliation or SwiftUI lifecycle safety.
