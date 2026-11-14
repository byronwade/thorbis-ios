# Customer records accumulator verification

The initial regression was a compile-time red: `build-for-testing` exited 65 because the accumulator and denial signal did not exist. This is not a behavioral reproduction.

The first green attempt, `/private/tmp/thorbis-customer-accumulator-green-1114.xcresult`, ran zero tests because the compiler rejected an inaccessible synthesized initializer. After adding an explicit initializer, `/private/tmp/thorbis-customer-accumulator-green2-1114.xcresult` passed 6 of 6 tests with no failures or skips. A later duplicate-job 403 fix and additional retry assertions changed the tested code; green2 does not verify those changes.

Per-job notes remain unpaged on the server. Customer Records UI integration, session/authority binding, and real interaction tests for cursor and permission cases remain required before a release claim. The caller must track whole-page errors, prevent concurrent stale completions, and reset state on session or authority changes.

The strengthened run `/private/tmp/thorbis-customer-accumulator-green3-1114.xcresult` passed 6 of 6 tests, zero failures and skips. These include in-memory state checks and an API-fixture 403 check; they do not establish UI interaction behavior.

A subsequent review found that an older successful job read could overwrite a later 403, and that a same-scope reset needed its own identity. The test-first build `/tmp/thorbis-accumulator-epoch-red-1114.log` failed at compilation because the request-token APIs did not exist; this is compile-time red, not a runtime reproduction. The state now uses owner and request tokens, supports token-bound whole-section denial, and distinguishes job 404 unavailable from temporary failure. `/private/tmp/thorbis-customer-accumulator-epoch-green-1114.xcresult` passed 8 of 8 focused tests, with no failures or skips. Its out-of-order completion check applies state responses deterministically; it does not replace UI interaction coverage.
