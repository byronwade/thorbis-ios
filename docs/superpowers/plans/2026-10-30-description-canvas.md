# Description canvas — scoped plan

A technician editing an estimate or draft invoice should be able to keep working inline and open a full-height canvas for a line's complete description. The canvas edits a local copy; Apply returns it to the existing document draft and never claims a server save. Cancel preserves the original. Existing document permission, draft/revision and save guards remain the authority. Customer presentation is unchanged in this increment.

The API currently caps estimate lines at 200 UTF-16 units, invoice lines at 211 Unicode scalars, and option descriptions at 500 UTF-16 units. The canvas must show the applicable count, retain over-limit input without truncation and disable Apply until it fits. These limits require separate server work to support the requested paragraphs; this UI does not solve that contract gap. Existing long values stay visible, with no automatic truncation.

Verify a red-to-green native journey, cancellation, local apply, validation and permission behavior, full-size and accessibility layout, and existing related editor paths. Reuse native sheets and the existing Thorbis tokens; keep the inline editor direct. Add a What's New entry and keep preview-only fixtures outside Release.
