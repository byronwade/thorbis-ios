# Build 166 preparation

Source is merged release commit 3bcd587d29989997920263df5c430d529dd1687f; its Git tree is identical to tested and independently reviewed b75930d0acc8bb3710eed33e64f96d46ce461249. The source manifest is /private/tmp/thorbis-job-bounded-qualified.sha, digest 2dce60db7d8c9c925fa5006cd7a38a89909d2c0d2b6c180a12616720d22271c4; the detached release checkout passed verification.

Job payment sheets bind the requested invoice and payment model; async entry verifies selection, job scope and authority. Same-model reads wait for in-flight reads, including A→B→A. A mounted sheet retains its entered amount across unchanged authority revalidation and closes on material actor, organization, policy, capability, API origin/generation, saved-scope revision, or job/customer changes. Offline cash/check behavior remains supported by the existing model. This does not establish fresh per-invoice authorization after unchanged revalidation.

The exact source passed 37 focused unit tests and 5 mounted UI tests, total 42, in /private/tmp/thorbis-job-bounded-green.xcresult and .log. The release note passed 9 What's New tests in /private/tmp/thorbis-build166-whatsnew.xcresult, and /private/tmp/thorbis-build166-release-note-preview.png was inspected (the debug preview's Build 17 is a sample).

Known limitations: durable invoice-denial/offline cache visibility remains unresolved; a denied invoice refresh was tested to stop a new payment, not to hide or purge stale content. Cancellation of already-started payment tasks is not established, and a cancelled waiter can remain retained until a shared read finishes. Earlier intermittent customer-document navigation failures were not root-caused, though subsequent focused runs passed. Tap to Pay remains disabled. Photos navigation is not included.

Archive, upload, Apple processing and tester availability: pending.

## Archive and upload outcome

On 2026-11-04 Xcode exported and uploaded build 166 successfully; its log reported “Uploaded package is processing” and `EXPORT SUCCEEDED`. Processing completion and tester group availability were not verified. Archive app and widget both reported build 166; the app bundle was `com.thorbis.field`, version 1.0, signed by team `T677262U5B`. Both signatures verified and the Tap to Pay build audit passed with the feature disabled. The archived app executable SHA-256 was `4dc3ab30b1110bdbed5eb945d018615e0638b7990c0b778474a5eb4f6513411a`. The source manifest matched the qualified source before and after archive.

Export warned that the StripeTerminal framework dSYM for UUID `6B66F53A-307E-3AD8-AC4E-A2E5AF652AE9` was missing, which may limit symbolication of crashes in that framework. Upload log: `/private/tmp/thorbis-release-166-upload.log`.
