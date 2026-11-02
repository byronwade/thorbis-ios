# Job estimate creation: recovery contract proposal

Status: proposed, not implemented or deployed. This describes a required joint API, database and iOS change; it does not certify the running backend.

## Observed release behavior and risk

Build 144's `NewEstimateView.save` calls `POST /v1/estimates` with the selected customer, title and lines, but without the job location, then calls the job link endpoint. The backend `linkEstimate` requires the customer and location to exactly match the job. Therefore the request can create an unattached estimate for a job with a location. A failed link can be retried using the returned estimate ID, but a lost or undecodable creation response has no ID to retain and retrying creation can make a duplicate. The Swift form's draft and returned estimate ID are only in view state, and do not survive dismissal or process termination.

The checked-in backend's `estimates.create` allocates a new ID and has no client operation key in its input. `jobs.createRelatedEstimate` copies job facts but its input schema lacks price-book source and customer-presentation fields. It also lacks an operation key. Its implementation invokes creation and link insertion in sequence; its documentation's atomicity wording is not evidence that the deployed adapter provides one transaction. Using that command as-is could lose line provenance and presentation settings and would not resolve ambiguous retries. The manifest inspected exposes the existing job-link route; the command's presence alone is not proof of an available mobile create route.

## Proposed operation

Provide a job-scoped create operation, with a client-generated persistent operation UUID, title and the full canonical estimate line request (including price-book item/revision provenance, group and visibility). The server must derive customer and location from the authorized current job rather than trust client-supplied ownership. It must check the job's current facts and the caller's `job.edit`, `estimate.create`, applicable price-book, discount, entitlement and resource scope checks using existing policy. An optional expected job version or equivalent must detect a location/customer change after the technician reviewed the job and return a recoverable conflict before creation. Existing feature gates and validation remain in force.

Persist the operation key, canonical request fingerprint, authoritative estimate ID and job link under tenant scope with a database uniqueness constraint. Create the estimate, its link, idempotency result, outbox and audit atomically in the same transaction. Concurrent identical requests and a retry after an interrupted response return the same authoritative result. Reuse of a key with different job or material request content returns a conflict, never a second estimate. Reauthorization is required for every replay and result lookup; the operation key is not an access credential. Provide an authorized operation status lookup if needed to reconcile an uncertain response without creating again. Define retention and replay behavior before deployment; do not infer an operation failed from a timeout.

## iOS recovery

Before issuing the request, persist the complete editable draft and operation UUID in the existing protected local-work mechanism, scoped to verified actor, organization, API origin and job. Persist an immutable submitted snapshot separately from subsequent editable work; a changed submission requires a new operation only after the prior outcome is resolved. On timeout, cancellation, malformed success, sign-out, workspace switch, app termination or relaunch, retain the pending operation. Never silently create a second estimate. On verified return to its original scope, reconcile or retry with the same operation key and show the true pending, linked, rejected or conflict state. Do not expose a former tenant's draft or response to a new identity. Explain where to find the estimate and how to recover when the status is unknown; do not claim it was saved, linked or failed without evidence.

If the job changed while the draft was open, show the changed location/customer and let the technician review before submitting; preserve all draft content. If a permission is revoked or the original scope is unavailable, keep the protected draft without submitting under another actor or tenant. On a definitive validation failure, retain the editable draft and show actionable field feedback. A completed link opens the resulting estimate only after confirming current authority and job identity.

## Required tests before exposure

- A job with a location produces an estimate and link with exactly the server's current customer and location; a job without one remains unlocated.
- Price-book provenance, source revision, group, visibility, quantities, money and customer-facing descriptions round-trip without loss; unauthorized lines are rejected.
- Two concurrent identical requests and a committed response lost before delivery produce one estimate, one link and one set of audit/outbox effects. A retry returns the same result; the same key with changed job or payload conflicts.
- Inject failure after each write and verify transaction rollback or stable replay. Exercise real database transactions, not just in-memory stubs.
- Change job customer/location before and during submission; verify conflict or atomic serialization with no orphan and preserved draft.
- Switch actor, tenant, origin, capability or job while requests are delayed; no stale result or cross-scope request is applied. Revalidation without a material identity change must not erase work.
- Kill and relaunch after local persistence, before send, after server commit, and before acknowledgement; reconcile the original operation without duplication. Cover offline and definitive validation recovery.
- Verify actual deployed endpoint, production adapter, permission and feature gates, then exercise the technician journey on device. Separate these results from simulator fixture evidence.
