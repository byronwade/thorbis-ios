# GAPS: activity-feed item destinations

Goal (field roadmap item 3): every item in every activity feed is selectable and
opens its detail. This note records where the app cannot yet honor that because the
destination doesn't exist, so rows stay non-interactive instead of leading to a dead end.

## Customer activity feed (`CustomerDetailView.activitySection`)

Source: `CustomerHistoryEntry { kind, subjectId, summary, occurredAt }` from
`GET /v1/customers/{id}/history` (`APIClient.fieldCustomerHistory`).

| kind | tappable today | opens | gap |
| --- | --- | --- | --- |
| `estimate` | ✅ | `PaperRoute.estimate(subjectId)` → `EstimateDetailView` | — |
| `invoice` | ✅ | `PaperRoute.invoice(subjectId)` → `InvoiceDetailView` | — |
| `job` | ✅ | `PaperRoute.job(subjectId)` → `JobDetailView` | — |
| `payment` | ❌ | — | No standalone payment detail **route**. `InvoicePaymentDetailSheet` needs the full `FieldPaymentRecord` **and** its parent invoice; the history entry carries only the payment id, not the `invoiceId`. **API gap:** add `invoiceId` to the `payment` history entry (or a `GET /v1/payments/{id}` lookup) so we can open the invoice (or a payment detail) from the feed. |
| `contact` | ❌ | — | No standalone contact detail. Contacts render only as a section/edit-sheet on the customer screen we're already on. **App gap:** a contact detail destination, or deep-link that scrolls/highlights the contact in the customer screen. |
| `location` | ❌ | — | Same as `contact`: locations live only as a section on the customer screen. Needs a location detail destination or in-screen anchor. |
| unknown / future kinds | ❌ | — | Fall through to non-interactive. Revisit as the server adds `note`, `call`, `message`, `photo` history kinds — each will need either a detail route or an inline presentation. |

The routing table lives in `Thorbis/Sources/CustomerActivityDestination.swift`
(`CustomerHistoryEntry.destination`) — add a case there when a destination appears.

## Job activity timeline (`JobDetailView.activityContent`)

Items are **notes** (body shown inline, text-selectable) and **status changes**
(“Dispatched”, “En route”, …). These are terminal: a note's full content is already on
screen, and a status change references no other record. No detail to open, so rows are
intentionally left non-interactive. If notes gain attachments/threads later, revisit.

## Needs Attention feed (`NeedsAttentionView`)

Already fully selectable (invoice / estimate / job rows navigate via `PaperRoute`). No gap.
