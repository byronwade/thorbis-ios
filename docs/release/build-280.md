# Build 280

Uploaded to TestFlight from `paper-v2-tokens` at 47468bd1 on 2026-11-19 (PR #563).

- Sheets (owner's phone screenshot of Settings: the top-left button crowded the corner): page sheets place their top button 14 under the sheet's edge, as form sheets do (was 2). Settings, Edit invoice, the job checklist and one payment screen close with × instead of a back chevron.
- Estimate names (owner: "the names are usually after the price the most looked at thing"): an estimate's name is its headline, with the customer under it (Paper 35C drew the customer as the headline). The field is labelled "Name · Your customer sees this" in New estimate and Edit estimate. On the customer's "Choose your fix" cards the option's name is as large as its price.

Checks: unit tests and stock-control lint pass; menu, tab bar, invoice and estimate UI classes pass (see /private/tmp/ut-280.log and ut-280b.log at upload time). 24 sheets were swept in the simulator with the device corner mask. Still inconsistent: New estimate closes with a chevron, and only some sheets show the grab handle.
