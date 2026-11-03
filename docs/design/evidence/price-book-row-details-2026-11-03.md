# Price-book row details — 3 November 2026

Status: staged, not released. Based on build 154 record `4ceb2fd`.

The standalone price book lets a technician scan grouped names, supporting details, units and sell prices before opening an item. Paper's Thorbis Mobile price-book artboard `VSA-0` uses grouped rows with a title, supporting line and price. This adapts that hierarchy to the existing native list and retains the unit, rather than inventing catalog images that the list API does not supply.

The original description and stored text are unchanged. A supporting detail is extracted only when the existing presentation title has a known boundary (a demo import's first sentence or a first line); otherwise the entire single-line text stays the title. Long previews use two lines even at accessibility sizes; the complete description remains in the existing item detail. Stale rows retain their existing complete inline descriptions. Search, filters, group disclosures, detail routes, add/edit capabilities, copy actions, page requests and explicit Load more are unchanged. Search still covers loaded records, and a matching term deeper than the preview can remain hidden until details are opened.

| Check | Evidence and limits |
| --- | --- |
| Formatting red | `/tmp/thorbis-catalog-visual-red-xcode.log` failed the new supporting-details test against the placeholder implementation. |
| Large-text red | `/tmp/thorbis-catalog-large-summary-red-retry.log` reached the intended assertion: unbounded summary was 919.7 points, exceeding 155.7. Initial run `/tmp/thorbis-catalog-large-summary-red.log` was interrupted before an assertion. |
| Final focused verification | `/tmp/thorbis-catalog-visual-final.log`: 6 presentation tests and 6 UI tests passed on simulator 3031C9BB. Tests include normal and largest text, long summary/full details, extreme price, grouped dark catalog and partial loaded scope. Source fingerprint: `/tmp/thorbis-catalog-visual-final-manifest.txt`. |
| Render | `/tmp/thorbis-catalog-visual-attachments/05629187-E890-41E2-AE4F-703A2AD3EA0F.png` (dark grouped catalog), `/tmp/thorbis-catalog-visual-attachments/4CC8FE71-6C97-44D9-A858-DD161D690457.png` (largest text), `/tmp/thorbis-catalog-visual-attachments/AF79C67B-4788-4C4D-82A7-1881B6C9D798.png` (full detail). Inspected grouped and largest text; the latter stacks the amount and truncates the preview with an ellipsis. Preview uses sample data. |
| Not verified | VoiceOver, iPad, real customer catalog and performance measurements; this is not a full app or TestFlight qualification. Existing search remains limited to loaded data. No claim of product photos or end-to-end catalog search. |
