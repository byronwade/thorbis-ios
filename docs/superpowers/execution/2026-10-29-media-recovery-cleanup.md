# Finish interrupted older-photo cleanup

Follow-up to the deferred Minor in build77. After exact stored confirmation,
PendingMediaStore previously removed the scoped media unit and recovery receipt
without reconciling an interrupted legacy cleanup. A surviving JSON/JPEG then
could retain a recovery warning after the photo was safely stored remotely.

The drain now validates the exact scoped receipt/media/hash, probes both legacy
sources with throwing file operations, validates every present metadata/payload
copy, then removes matching older sources before the scoped unit. Only genuine
absence is treated as absent; POSIX ENOENT takes precedence over outer Cocoa
classification. Access, type, content and unknown failures preserve scoped bytes,
receipt and originals. Current scope/capability/generation checks remain in force.
Normal media without recovery proof retains its existing flow. There is no
new storage format, queue, backend, SDK, bank-check path or payment enablement.

## Verification

The real store, temporary filesystem and production MediaTransfer run against
intercepted HTTP; no customer media or live service request was used.

- Initial RED:2 tests failed,10 assertions. The one thrown unbound assertion was
  the direct consequence of premature scoped-unit removal, not a network fixture
  failure. Matching JSON-only/JPEG-only remnants and changed-payload retention
  are covered.
- Initial affected run:73 cases,71pass/1skip/1fail. The failure caught an invalid
  empty-highlight release note. Corrected to concrete recovery wording; the
  later access run verifies all9 What's New cases pass.
- Access RED:10 cases,9pass/1fail. One raw JSON-byte comparison was brittle due
  to dictionary serialization order; it was corrected to retain the exact seeded
  fixture bytes. Seven other assertions directly reproduced the access bug.
- Corrected probe RED:2 cases failed with9 expected assertions and0unexpected
  errors. This separately covers an inaccessible parent and ENOTDIR. After access
  returns, retry must retain the original client ID/date, accept an already-stored
  registration and issue no second PUT/confirmation.
- Final rebuilt affected run: **75 executed,74passed,1simulator-only protection
  skip,0failures**. API21, recovery13, transfer11, store21, What's New9. Source
  fingerprints for all177 Swift files match the final run. No repeat full scheme
  or unrelated CI was required under the user's focused-testing instruction.

[Actual summaries and source fingerprints](../../design/evidence/media-recovery-cleanup).
Final bundle: /private/tmp/thorbis-media-cleanup-final.XfCtS59S/result.xcresult.
[Independent review](../../design/evidence/media-recovery-cleanup/review.md) is clear.

No new UI layout was introduced. Existing Paper rows and native recovery controls
remain unchanged; the new release note follows the existing copy contract. This
unit/transfer qualification does not certify hardware protection, physical camera,
production transfers or a new TestFlight build. Build77 remains delivered; this
change is ready for the next useful native release batch. The continuous goal,
secure keyed-card integration, unified saved-work review and C1–C3 remain active.
