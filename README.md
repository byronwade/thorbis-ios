# Thorbis iOS (SwiftUI)

Native field app for technicians, owners and office staff: schedule, jobs and the job screen,
customers, estimates, invoices and payments, messages, search, reports, team and settings.
Design source: Paper → "Thorbis Mobile".

The app is a client of the Thorbis API, which lives in the `byronwade/Thorbis-TanStack`
repository (`services/api`). No business rules live here.

All iOS work follows the [app-wide golden rules](docs/design/ios-golden-rules.md)
and [implementation/review process](docs/design/ios-implementation-process.md).
The full user-supplied field-management design guidelines are retained as context;
existing implementation gaps remain explicit in [design coverage](docs/design/README.md).

```sh
xcodegen generate
xcodebuild -project Thorbis.xcodeproj -scheme Thorbis -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath build build
```

A release build talks only to `https://app.thorbis.com`. A debug build can be pointed at an API
running on this Mac: set `THORBIS_API_URL` in the scheme's environment to a loopback address such
as `http://localhost:8799` (where `pnpm dev` serves it), then sign in with an account on that
API. Running the API locally is covered by `docs/runbooks/local-development.md` in
`Thorbis-TanStack`.

## TestFlight

On a Mac signed in to Xcode with team T677262U5B, pick the next build number after the latest one
in App Store Connect and run:

```sh
BUILD_NUMBER=<n> scripts/testflight.sh             # test, archive, upload
BUILD_NUMBER=<n> scripts/testflight.sh --no-upload # stop after exporting the .ipa
```

Record each upload in `docs/release/build-<n>.md`.

## CI

`.github/workflows/ios.yml` runs on every pull request. It builds the app once, runs the unit
tests, and then runs the UI tests from that build in parallel shards
(`scripts/ui_test_shards.py --shards 6 --list` shows the split). `UI tests` is the one check that
says every shard passed. The planner counts tests a class inherits or declares in an extension, and
stops with an error for any `func test…` it cannot place in a class it names, so a test never
drops out of the split unnoticed.

The shards run on an iPhone simulator. The iPad layout has its own run, `iPad UI tests`, on an
iPad simulator: the test classes with an iPad path (`scripts/ui_test_shards.py --tablet --shards 2
--list`), in two shards. It starts only for a pull request that changes the iPad layout, a test
with an iPad path, or the workflow and scripts that plan it (`scripts/ci-ipad-scope.sh` holds the
rule). It is its own check and not yet part of `UI tests` (BYR-1843).

A failed UI test is a failure. There is one exception, and it is narrow. XCTest taps through a
virtual touchscreen, and on a busy runner the simulator sometimes cancels such a tap by itself:
its input server logs `*** unknown digitizer`, the app sees a cancelled touch and rightly does
nothing, and the test fails on a tap nobody made. `scripts/ci-run-ui-tests.sh` runs each shard and
follows the simulator's log for that one error. A failed test is run once more, by itself, only
when every failed test in the shard has that error inside the time it ran, there are at most three
of them, and the run is otherwise fully accounted for. The shard passes only if each then passes.
Every such run is a warning on the job and is listed in its summary, and its evidence is uploaded
as `ios-ui-test-reruns-<shard>` (BYR-1835). A failure without the error is never run again.

One shard also carries a temporary probe, `scripts/ci-freeze-sampler.sh`. It takes a few stack
samples of the app when the simulator reports a frozen animation, and uploads them as
`ios-ui-freeze-samples-<shard>`. It is evidence for BYR-1841 and goes when that issue has its
answer.
