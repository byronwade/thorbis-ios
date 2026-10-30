# Price book visual clarity

**Goal:** Make catalog rows easier to scan without hiding descriptions, prices, or existing actions.

**Approach:** Use a restrained SF Symbol representing each real item kind and the existing Thorbis color tokens. At accessibility text sizes, place the amount below the item text so both have room. Keep existing grouping, navigation, context menus, and authority checks unchanged.

- [ ] Run the largest-text row and full-detail test against the existing layout.
- [ ] Add the category visual and adaptive row layout in `WorkspaceViews.swift`.
- [ ] Run price-book access, detail, grouping, and large-text checks; inspect screenshots in light and dark appearances.
- [ ] Report exact evidence and leave the branch unmerged until reviewed and verified.
