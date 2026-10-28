# Paper-aligned new-job composer

## Outcome

Expand `NewJobSheet` to follow the Paper job composer while submitting only fields supported by the canonical jobs API. The form will collect title, description/notes, and customer. After creation it will open the new job so its existing schedule and assignment actions are one step away.

## Contract and design constraints

- Use the 390 × 844 Paper composer in `docs/design/paper-3Z8B-0.json` as the layout reference and `paper-40RU-0.json` for shared controls and tokens.
- Create through `APIClient.createFieldJob(FieldJobCreate)` at `POST /v1/jobs`; send customer, trimmed title, and optional trimmed notes.
- Do not map a customer service address to `FieldJobCreate.locationId`: the canonical API uses that field for organization branch scope, in a separate ID space.
- Do not send priority, schedule, or individual assignee values: the create DTO and verified endpoint do not accept them. Reuse the job detail's existing schedule and assignment flows after creation.
- Preserve the draft after request failure and prevent duplicate submission.
- Preserve authorization gating for `job.create` and the existing customer preselection behavior.

## Implementation sequence

1. Add tests for a testable job draft/request builder and for request encoding with notes and location.
2. Implement draft normalization and validation, then wire the existing composer to those fields.
3. Match the Paper title, notes, customer chip, and composer toolbar; explain that schedule and technician assignment follow creation.
4. Use the canonical create endpoint, retain input on failure, and navigate to the created job after success.
5. Run focused tests and the iPhone simulator suite, then compare the composer with the Paper export and update beta coverage.

## Acceptance evidence

- Draft/request tests prove the payload contains supported fields only and trims blank optional notes.
- API tests keep organization branch scope separate from customer service-address IDs.
- Simulator preview matches the Paper title, description, and metadata hierarchy, remains usable with a keyboard, and opens the new job after a successful create.
- Test failures preserve the user's entered draft; rapid repeated taps make only one request.
