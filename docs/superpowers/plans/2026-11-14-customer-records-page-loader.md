# Customer notes and documents page loader

**Goal:** Open job-grouped notes or documents for a customer without reading unrelated estimates, invoices, photos or history, and without loading every job or media page at once.

**Architecture:** A scope-bound loader fetches one customer-filtered jobs page (5), validates each returned job, and reads only its requested section with at most four concurrent job reads. Notes use the existing unpaged job notes endpoint; documents fetch one bounded media page per job (20 metadata rows), retaining video, document and scan while excluding photos and archived media. A group includes its own error/partial state and media cursor; job pagination remains explicit. Every request is guarded by API generation and a caller-supplied authority closure before and after I/O. UI owns state, retry and incremental merge, and must never claim a complete total until all job/media continuations are exhausted and every group is verified.

**Constraints:** Notes for a single job are unbounded on the current server. Customer history is a separate API and is not read by this loader; its 200-per-source backend cap must not be presented as complete. No endpoints, permissions, existing full loader, or offline authority rules are replaced. 401/cancellation stops the page; other per-job failures preserve successful groups with a retryable status.

- [ ] Reproduce that existing notes compilation reads unrelated endpoints.
- [ ] Implement scoped, bounded jobs-page and section reads, media continuation and validation.
- [ ] Verify unrelated failure isolation, per-job corruption/errors, pagination, stale authority and cancellation; communicate the API to the UI agent.
