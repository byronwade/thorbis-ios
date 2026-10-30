# Job photo accessibility reflow

At accessibility text sizes, the filter uses a labelled menu instead of four clipped pills, capture controls live in the scroll content instead of covering the grid, and photo tiles become a single column with wrapping captions and space for the tag control. The normal-size filter, two-column grid, and bottom capture bar remain. Moving capture controls below the grid means reaching them may take more scrolling for jobs with many photos; the discoverability tradeoff needs field evaluation.

Focused iPhone 16 Pro simulator UI run passed three cases: dated grouping/filter, undated grouping/filter, and largest-text filter selection, full-width photo and access to library/document controls. The screenshot shows the sample caption fully; it is scrolled partway past the picture, so it is not proof that a full image fits in the viewport. Separate test-first failures demonstrated the absent filter menu and cramped 178-point tile before these changes.

No real photo opening, retag success, camera/library selection, device rotation, VoiceOver, RTL, iPad, physical device or large-photo-count performance was verified. The preview data is read-only and its images intentionally fail to download. Independent review is required before release. The DEBUG preview flag and sample fixtures added by the parent commit must be excluded from release packaging.
