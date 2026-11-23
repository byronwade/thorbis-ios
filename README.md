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

The tests run a Debug build. `Release build` compiles the app and its widgets as Release, for
the simulator and unsigned, so a debug-only symbol used in shipping code fails here and not at
archive time. It compiles without the optimiser, which is what makes it quick, so it does not
stand in for the archive. It tests nothing and is its own check.

A pull request that carries the `ci-optimized-build` label when it is pushed gets a test build
with the optimiser on (`-O`, whole module). It is still the Debug configuration, with DEBUG
defined and testability on, so it is not the build that ships. The unit tests and every UI shard
run on it. The build alone can take half an hour or more, so the build job's limit rises to 90
minutes. A notice on the run says it is not an ordinary run, and a re-run of it builds the same
way. It is evidence for BYR-1841. Add the label before the push and take it off once the run has
started. While the label is on, every push builds this way and the ordinary build goes untested.
Push nothing more until the run's UI shards have finished, because a new push cancels the run.

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
when every failed test in the shard failed on the wait right after a tap, that error was logged at
that tap by XCTest's own clock, no failure speaks of a crash or a launch, there are at most three
of them, and the run is otherwise fully accounted for (xcodebuild exited 65, its counts match the
log, no unexpected failure). The same rule covers one more thing the simulator does by itself
(BYR-1843): it hands a keyboard chord to the app as a command only once the app has registered its
key commands with the input server, and on the iPad that registration now and then comes only after
a test has pressed twice. The script follows backboardd's lines about that too, and a test that
failed on the wait right after a chord counts only when every chord of the test went to the app's
pid as a bare key, no key command was matched against the app during the test, the app had
registered nothing before its last chord, and its first registration after it lists that chord.
Every failed test in the shard must qualify under one of the two rules. The shard passes only if
each re-run shows that one test passing.
Every such run is a warning on the job and is listed in its summary with the reasons, and its
evidence is uploaded as `ios-ui-test-reruns-<shard>`, or `ios-ipad-ui-test-reruns-<shard>` for
the iPad shards (BYR-1835). A failure without that evidence is never run again.

Every UI shard, iPhone and iPad, also carries a temporary probe for BYR-1841, the first opening of
Customer view on Estimates that holds the app's main thread for seconds at a time.
`scripts/ci_hold_sampler.py` follows the app's own log of each request XCTest makes of the main
thread, and when one has waited 5 s without being served it takes a 3 second stack sample of the
app, and one more if the same hold is still going at 15 s, at most eight in a shard. Its log
stream starts at the default level. If 300 s pass with no request line, it moves to info, and
after 300 s more to debug, and it stays at the first level that delivers one. It does not change
how a test passes or fails, or which test is run once more. It does add some load while it runs:
a filtered log stream for the shard's first run, and, during a hold that has already lasted 5 s,
a 3 s stack sample. It does not watch a test that is run once more by itself. The samples, a
note beside each and a one-line summary (also printed in the job's log) are uploaded as
`ios-ui-hold-samples-<shard>`, or `ios-ipad-ui-hold-samples-<shard>` for the iPad shards. It
comes out again once BYR-1841 has its stack.
