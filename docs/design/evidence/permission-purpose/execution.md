# Permission purpose metadata — qualification

Base `a6f7dbabafaaedd56ff482c2268769bd0a55eeab`, branch `codex/ios-permission-purpose`. Build79/PR83 evidence and delivered binary remain immutable. Coordinator authorized this bounded metadata/validation fix; no approval menu, subagents, staging, commits, pushes, archive or upload by implementation agent.

## Cause and bounded change

Actual signed archive79 omitted both NSBluetoothAlwaysUsageDescription and NSLocationWhenInUseUsageDescription, matching observed Apple90683 warnings. The existing ScheduleMapView already contains UserAnnotation/MapUserLocationButton; linked StripeTerminal5.8.1 requires these declarations independently of the disabled Tap gate. Exact primary-document/source recon is retained in `.superpowers/sdd/2026-10-29-job-estimate-handoff/root-review/permission-purpose-recon.md`.

Canonical `Thorbis/Resources/Info.plist` now contains the two approved accurate strings. The audit validates both as nonempty strings on the actual signed app Info.plist outside its enabled-reader branch. Existing disabled-reader entitlement/profile skip remains. No Always location, background mode, authorization manager, permission request, entitlement, SDK upgrade, payment enablement, Swift/UI or provider behavior changes.

## RED / GREEN and actual artifact checks

| Check | Result / evidence |
| --- | --- |
| Actual signed-bundle CLI fixtures, before guard | 12 tests,8 expected assertions: each key missing or empty/whitespace/nontext incorrectly passed while Tapfalse; `red.log`. Initial fixture copy preserving protected system-file flags errored and was corrected before this meaningful RED; it is not behavioral evidence. |
| Focused Python scripts suite | `python3 -m unittest discover -s scripts/tests -v`:15 tests,0 failures, exit0; `green.log`. Includes12 build-audit tests and3 upload-boundary tests. |
| Legacy disabled-reader behavior | Actual ad-hoc signed valid-purpose fixture with no embedded provisioning profile/reader grant passes; missing policy and enabled entitlement/binding regressions remain green. |
| Immutable real archive79 | New CLI audit exit1 with exactly both missing-key errors, `archive79-rejection.log`; no archive mutation. |
| Generated simulator app | Ad-hoc signing build exit0, BUILD SUCCEEDED; log `/private/tmp/thorbis-purpose-simulator-build.log`. Actual CLI codesign+purpose audit exit0, `built-app-audit.log`; compiled Info evidence `built-app-proof.json`. |
| Source plist / patch | `plutil -lint Thorbis/Resources/Info.plist` and `git diff --check` pass. Three changed implementation/test files fingerprinted in `source-manifest.sha256`. |

Build command:

```sh
xcodebuild -project Thorbis.xcodeproj -scheme Thorbis -destination 'platform=iOS Simulator,id=FA43B63E-98C9-4336-B1F7-A55E9D4B4B0A' -derivedDataPath /private/tmp/thorbis-job-book-derived -clonedSourcePackagesDirPath /private/tmp/thorbis-ios-payment-derived/SourcePackages -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
```

Actual application audit:

```sh
python3 scripts/audit_tap_to_pay_build.py /private/tmp/thorbis-job-book-derived/Build/Products/Debug-iphonesimulator/Thorbis.app
```

Compiled Info SHA-256 `25c238e30c4e6e1e3c5c5611dadb81e7ccec905246a1e7b3bc489334a0a90b74`; exact strings in the proof. Tap policy remains Booleanfalse, camera/FaceID purposes equal baseline, Always/background keys absent, linked framework version5.8.1. Package.resolved SHA-256 remains `9efa8e6a1368735524818fb99e805543db1633cd65843816a439f7c56edb5fc6`.

## Limits and release boundary

No simulator/device permission was granted or real location/payment/provider data accessed. Native map permission prompt/denial timing was not exercised; this batch verifies declarations and audit behavior, not runtime permission recovery or payment readiness. No broad Swift/native suite was repeated for metadata/Python validation. A new signed archive and Apple upload processing are coordinator-owned; absence of90683 on a future build is not yet verified and cannot repair build79 retrospectively.

No new DEBUG fixture flags/controls/strings were added to the app. Existing187-Swift source fingerprints and Release fixture-exclusion inventory remain applicable unchanged; these two production purpose descriptions must remain in Release and must NOT be treated as fixture strings to strip. Existing What’s new notes were not edited because task scope forbids extra Swift changes; coordinator owns any combined-build user note.

All native/Xcode handles were terminal and ownership returned to coordinator after simulator build handle12841 exit0. No further source or Xcode work planned for this task.
