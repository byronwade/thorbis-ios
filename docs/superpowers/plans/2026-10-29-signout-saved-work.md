# Protect saved work during sign-out — design required

Status: **blocked; no runtime fix implemented or qualified**. Do not release the activity/outbox branch while this regression fails.

## Observed failure

`SessionController.signOut()` awaits `onWillUnbindDevice` and then calls `onSignedOut` to delete the outbox and media. A note or photo saved while that await is in progress was not in the confirmation the user accepted, yet is deleted. `SessionControllerTests.testSignOutDoesNotEraseNewSavedWorkWhileDeviceUnbindIsAwaiting` reproduces both losses using real temporary files. `/private/tmp/thorbis-signout-race-red.log` records four expected assertions; the test is intentionally failing in this draft branch.

## Required behavior

1. At each sign-out prompt, show a warning derived from a specific, verified inventory of all device outbox and media work, including other identities, origins, legacy files, interrupted saves and unreadable scopes. Do not represent unknown work as empty.
2. If that inventory changes before the user chooses Sign out, or while device unbinding is in progress, preserve the work and return to an updated warning requiring explicit reconfirmation. Cancellation must preserve work and restore normal operation.
3. Immediately before deletion, perform a final valid check with no suspension between that check and clearing. Do not use counts as identity: same-count replacement and unknown files must be detected or fail closed.
4. If sign-out is aborted after push device unbind, restore registration for the still-authorized identity or show actionable recovery if restoration fails. Do not claim push registration from a fire-and-forget request.
5. Respect the existing policy of deleting local copies on confirmed sign-out. Retaining files instead requires a separately reviewed retention and privacy contract: outbox filenames currently omit API origin and filter identities; legacy media is unscoped.

## Design work and seams

- Define a single confirmation coordinator used by `SettingsView.swift`, `Screens.swift`, `WorkspaceGateView` and `CreateCompanyForm` in `Onboarding.swift`. It must capture the warning and its corresponding proof together, guard reentrancy, and re-present on mismatch instead of merely setting a generic error.
- Define a shared inventory/proof abstraction owned by `FieldOutbox.swift` and `PendingMediaStore.swift`, covering their private `Outbox`, `PendingMedia`, and `PendingPhotos` roots. Establish explicit behavior for missing versus inaccessible directories, corrupt files, symlinks, interrupted staging, and files changing while inspected. A proof must not leak file contents or credentials in logs.
- Establish how a potentially large inventory is inspected without synchronously reading every photo on the main actor. An off-main scan must be paired with file coordination or complete mutation tracking plus revalidation so no change can slip between scanning and final deletion. In-memory epochs alone do not prove protection against external changes; directory counts alone do not identify replacements. If exact inspection is unavailable, fail closed and preserve data with a clear recovery path.
- Do not assume that coordinating an ordinary directory automatically excludes child writes: [Apple's NSFileCoordinator documentation](https://developer.apple.com/documentation/foundation/nsfilecoordinator/coordinate%28writingitemat%3Aoptions%3Aerror%3Abyaccessor%3A%29) says a normal directory write does not wait for operations on its contents. Any coordinator-based design must prove how every writer and the deletion participate, including the specific deletion or moving options and any uncoordinated POSIX access.
- Modify `SessionController.signOut()` to validate the accepted proof before and after `onWillUnbindDevice`, without suspension between the final check and `onSignedOut`. Ensure all callers supply the proof. Design an explicit result for changed or unavailable inventory and cancellation. Reconcile any session/actor switch during the awaited call.
- `PushNotifications.unbind()` currently ignores server errors and `identityChanged` re-registers asynchronously; add a testable restoration contract for aborted sign-out without exposing device tokens in logs. Scope the outcome to actual provider evidence.
- Preserve durable queue/media files on all abort paths; distinguish confirmed removal from local deletion failure. Existing note REST replay, outbox dismissal/sync persistence and cold-offline authorization are separate release holds.

## Verification before release

- Make the existing delayed-unbind regression pass with both note and photo retained and a renewed confirmation. Add a same-count replacement, changed existing payload, work added before confirmation, work added during unbind, foreign workspace/origin, legacy and interrupted staging cases.
- Test unreadable and missing roots, unreadable files, directory traversal/symlink refusal, interrupted inventory reads, storage changing during scanning, cancellation, duplicate sign-out taps, session switch, and a failed deletion. Confirm never treating a failed probe as proof of absence.
- Exercise all four actual sign-out entry points, including cancelling and reconfirming, with native UI tests at large text. Validate push unregister/re-register success and failure with gated requests.
- Measure representative media inventories and responsiveness without loading all payloads into memory. Run independent correctness and privacy review and exact-source tests. Update release notes and only then consider an archive and TestFlight upload.
