# Job photo accessibility reflow

At accessibility text sizes, the filter uses a labelled menu instead of four clipped pills, capture controls appear in the scroll content above the pending queue and grid rather than covering them, and photo tiles use one column with wrapping captions and space for the tag control. The normal-size filter, two-column grid, and bottom capture bar remain unchanged. Pending rows and Retry remain visible after the capture controls.

The iPhone 16 Pro simulator verified date grouping, filter selection, full-width photo and library/document control access. After independent review identified that capture still followed a potentially long pending queue, a 20-item fixture reproduced the ordering problem; the corrected layout passed the ordering test. A separate test verified that an empty filter says “No matching photos” and returns to All. The saved-scan navigation/relaunch UI case and 12 date/release-note unit cases passed in that same run.

The combined run failed when the large-text stage test's runner exited during menu selection; a separate retry of that exact test passed after the pending-queue reordering. Earlier stage-selection testing had also passed before that reordering. Previous screenshots show the complete sample photo tile and caption, but use sample image downloads that intentionally fail, not real photographs.

Real photo opening, retag success, camera/library selection, rotation, VoiceOver, RTL, iPad, physical device and high-count performance remain unverified. Independent review is required before release. DEBUG `--paper-preview-media-dates`, `--paper-preview-many-pending` and sample fixture literals must be excluded from release packaging.
