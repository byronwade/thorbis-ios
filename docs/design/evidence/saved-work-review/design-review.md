# Saved-work review design check

Independent read-only builder check requested changes before implementation:

- Add live command-drain authority/binding/generation guards across batches,
  REST fallback, conflict reads and post-await state changes.
- Add a read-only exact matching-context accessor to the media store; opaque
  private scope fields cannot otherwise be verified by a new view.
- Use one sheet-local navigation owner so nested job banners return to that
  review rather than presenting another review sheet.

All two Important findings and the Minor clarification were addressed in the
revised spec/plan. Scoped re-review approved, with no new findings.
Same-identity revalidation preserves generation and existing published expiry
handling remains authoritative; no extra timer is introduced.

Approved spec SHA256:
dbb0d246f0372a1a0fbca0cdbea60d4ff4f170d9ec8b29697d937b866613e546
Approved plan SHA256:
81008bfea6e62637b7f0e636742adcd197d3e6126937146de4cdb058207dfc00

This approves implementation instructions, not runtime or delivery. The live
capability callback applies to review-triggered drains; broader legacy-call-site
capability behavior is not certified merely by this design.
