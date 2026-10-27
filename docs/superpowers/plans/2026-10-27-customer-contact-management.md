# Customer contact management plan

## Goal

Bring the Paper customer detail contacts section closer to TanStack behavior by supporting create, edit, primary promotion, and confirmed removal through the existing customer API. Keep permission checks and server responses authoritative.

## Acceptance criteria

- Add and edit contact name, role, phone, and email using the existing Paper contact-sheet styling.
- The first contact remains primary by the existing server default; a user can promote another contact through the canonical update contract.
- Blank optional edit fields clear their value using the API's documented null semantics.
- Contact removal requires confirmation and only updates the visible list after API success.
- Failed mutations keep the existing row and preserve unsaved editor values while showing an error.
- Contact actions remain hidden or unavailable unless the current session has `customer.edit` in `core_crm`.
- Regression tests cover request paths and bodies, null clearing, no-body removal responses, primary promotion, and local state updates.

## Implementation sequence

1. Confirm the TanStack/API update, primary, and remove contracts against the current source. **Done.**
2. Add typed contact update and remove API methods with UUID path validation and explicit nullable-field encoding. **Done.**
3. Extend contact collection state to replace/promote/remove records only after successful API responses and invalidate stale loads. **Done.**
4. Reuse the Paper contact sheet for add/edit, add per-contact actions, primary promotion, and a removal confirmation. **Done.**
5. Add contract/state regression tests first, then implement and run focused plus full simulator suites. **Done; 136 tests pass.**
6. Review the diff, inspect the Paper customer preview, and update beta coverage documentation. **Done.**

## Out of scope

This slice does not add company-wide contact search, bulk import, or contact activity history.
