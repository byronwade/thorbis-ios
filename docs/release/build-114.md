# Build 114 — faster photos and estimates

Runtime source: `87efbeb` (`release/104-integration`).

- **Photos** (PR #184): one selector (All · Before · After · Documents); square thumbnails with Waiting / Sending / Failed and retry; ink Take photo plus Burst, Scan, Measure, Video, Import; a tag step after each shot (56pt Before / After / Skip, spoken caption, Markup, Retake, Take another); burst mode; uploads no longer block the camera; full-screen viewer (Markup, Stage, Share, Remove with confirm); Before/After compare (slider or side by side); multi-select tag/share/remove; Measure in ft-in or metric with Save to job.
- **Estimate and invoice builder** (PR #183): one builder screen with lines expanding in place (big ± stepper, price, full description); price book as a cart (favourites and recent first, member prices, multi-add, "Done · N items", custom item); Add/Copy option where options are allowed; Add discount where the account has it; the invoice line editor shares the same pieces.

**No tests were run, at the owner's request.** The stock-control lint passed (0), the Release archive succeeded, and Xcode reported **Upload succeeded** at 03:09 EDT on 31 October 2026.

Backend gaps: options on new estimates, estimate description, deposit and discounts at create (BYR-1598); photo author names, caption edits, discarding unsent photos. Not verified: camera, burst, AR measure, scan, video, dictation, real uploads and estimate saves.

**Processing, tester groups and What to Test are not verified.**
