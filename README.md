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

Every UI shard, passing or failing, also uploads `ios-ui-cpu-load-<shard>` (`ios-ipad-ui-cpu-load-<shard>`
on the iPad) for BYR-1841: `cpu-load.txt` notes once a second the host's load and the CPU time used
so far by the app (a new pid each launch), the test runner, xcodebuild and the simulator's busiest
services, read with `ps` by pid and short name only (`scripts/ci_cpu_load.py` documents each line).
Beside it, `cpu-load-table.txt`, also printed in the job log, lists every test step of 10 s or more and
every first screen read after the Customer view tap with the share of one CPU the app used during it.
That is the CPU time of all its threads together, so it can be over 100%, and 70% of one CPU can be
two threads at 35% each. 70% or more ("working") shows that the app's threads together used at least
0.7 s of CPU per second of the step, not which threads ran nor that the main thread was one of them;
30% or less ("waiting") shows that they used at most 0.3 s of CPU per second of the step, so for most
of the step no thread of the app was running (each was waiting for a CPU or blocked), and only
together with a high "host busy" (how busy the runner's CPUs were) does it point to a CPU shortage.
It is evidence, not a test, and comes out once that question is answered. In format 2 the record also
names the simulator's other busy services and tells, for each diagnosticd and apsd, whether it runs on
the host or in the simulator; the table then starts with a budget of the runner's busy CPU by service.

For one run, the UI jobs also carry a runner load experiment (BYR-1896, `scripts/ci-load-experiment.sh`
holds the plan). Phone shards 1 and 2 and iPad shard 1 are controls and change nothing. Phone shards 3
and 6 turn the host's Spotlight indexing off before the tests (`sudo mdutil -i off` for `/` and for
`/System/Volumes/Data`). Phone shards 4
and 5 and iPad shard 2 boot the simulator's push daemon out after boot (`launchctl bootout
system/com.apple.apsd` in the simulator). A treated shard runs no failed test once more: its failure
stands, and the job log says what the rule would have run. After the tests and their evidence are
saved, every shard that has time left checks the treatment is still in place, compares the
simulator's stored log with the stream the re-run rule read (`scripts/ci_log_compare.py`), and then
stops the host's diagnosticd and kills the simulator's to see what a new log stream still gets. These
steps never fail the job, print every command with its output and exit status, and upload their files
as `ios-ui-load-experiment-<shard>` (`ios-ipad-ui-load-experiment-<shard>` on the iPad).
