# Release exclusion inventory

The entire `JobEstimateHandoffPreview.swift` fixture and its App/preview/Container wiring are conditional on DEBUG. The coordinator must verify the signed Release binary excludes the following fixture types, flags, controls, sample host and receipt strings. Production accessibility identifiers and the existing `Storage upload failed` error are intentionally retained.

- Types: `JobEstimateHandoffPreview`, `JobEstimateHandoffReceiptMetadata`.
- Receipt: `handoff-canonical-receipt`, `Anonymized sample approval receipt`.
- Controls/copy: `Sample testing controls`, `Interrupt next membership read`, `Interrupt next signature upload`, `Change sample workspace shortly`, `End sample session shortly`, `Choose sample workspace shortly`, `Allow sample unlock`, `Refresh sample receipt`, `LOCAL TEST · SAMPLE APPROVALS ONLY`.
- Host: `sample-upload.thorbis.invalid`.
- Flags: `--paper-preview-job-estimate-handoff`, `--paper-preview-handoff-third-sent`, `--paper-preview-handoff-public-patch-no-acceptance`, `--paper-preview-handoff-options`, `--paper-preview-handoff-duplicate-titles`, `--paper-preview-handoff-lose-second`, `--paper-preview-handoff-fail-before-second`, `--paper-preview-handoff-denied-unlock`, `--paper-preview-handoff-hide-controls`, `--paper-preview-handoff-mixed`, `--paper-preview-handoff-all-statuses`, `--paper-preview-handoff-discount`.

Temporary `THORBIS_UI_DIAG`, `--paper-preview-ui-diagnostics` and guard/tap logging were removed from source rather than left dormant. The isolated receipt seam is zero-layout and noninteractive, exposes only anonymized fixture transport state and performs no timer/network/mutation. Final production-look screenshots hide fixture controls; interruption/scope tests deliberately expose those DEBUG controls to exercise real production operations.

No signed archive or Release qualification was performed by the implementation agent. Release signing, exclusion inspection, upload and App Store Connect availability remain coordinator-owned.
