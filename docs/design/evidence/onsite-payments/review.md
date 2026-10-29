# Independent review and fix pass

Fresh read-only reviewer: gpt-6-astra, xhigh; base63801816903552a951d8161d90dc2920a9255ada.
Verdict: approve scoped exact-receipt reconciliation;0Critical,0Important,1Minor.
Reviewer inspected actual source, deployed backend key convention and46-test result.

Finding: unrelated-full-payment test used a different amount, so removing only key
comparison could escape it. Root regraded Important because exact-attempt identity
is the central financial guarantee. Added same-amount/different-attempt test and
removed only key comparison in a temporary mutation; assertion failed as expected.

Root also tested API invalidation after a matching receipt had been verified.
That failed independently: old model history had no request-generation binding.
Successful validated history now retains the UUID and matcher requires current
API generation. Load start clears the binding. Both review-pass tests failed first.
Restored identity comparison; final affected suite48/48, zero failures/skips.
No deferred minor, no second reviewer loop, no actual financial action.

Explicit follow-up boundaries: native keyed-card configuration, private check
evidence and deposit/clearance, new truthful tender subtypes, financing/credits,
physical Tap qualification, existing retry/relaunch and intent-expiry recovery.
Those remain required work before their respective capabilities are exposed.
Distribution Tap gate stays disabled. Existing server receipt-key convention is a
temporary compatibility choice; if it changes, native confirmation stays pending.

This is a focused important-test qualification under the user's instruction to
avoid repetitive basic CI, not a full scheme or physical-provider certification.
