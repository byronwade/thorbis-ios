# Build 130

- Commit: c31c7b1 (`release/104-integration`)
- Uploaded: 2026-10-31

## What's in it
- Consistency sweep (#221): one time format (lowercase a.m./p.m.), money stays with its word, rows wrap instead of truncating, leftover separators removed, disabled buttons say why, dead code removed, iPad Schedule time column narrowed.
- Row swipes (#222): Jobs/Today swipe right for Call and Directions, swipe left for the next allowed status move (full swipe commits for roles with job.edit); Inbox swipe right opens the linked job. Every action is also on the job screen and a VoiceOver custom action.
- Large-text job test fixed (wrong Directions match), no layout change.
