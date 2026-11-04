# Invoice transport preflight experiment

This worktree is based on merged response-provenance work and carries the held read fence from 3fffee4. No app transport, screen, cache, payment intent, or outbox is connected to this fence.

The standalone macOS harness injects failure while syncing the preflight hold for an existing verified invoice. It checks that begin throws before the caller can start transport, a separate process sees the hold, and unrelated authorized data stays readable. A child process also exits immediately after the failed preflight; a new observer sees the hold. The harness passes. The failed hold itself is not proven durable when its directory sync fails: power loss could remove it, but the guarded contract prevents a live request from having been started in that case.

Existing API provenance reports URLSession/cache policy and saved-copy scope, not fresh authorization or collision-free identity. The fence needs immutable response bytes and verified scope, terminal denial handling even during cancellation, serialized asynchronous cache writers, invalidation of mounted and list consumers, and a tested offline migration before it can be enabled. The held file is not an implementation of those requirements. iOS filesystem protection, device crashes, power loss, extensions, and independently changing assignment authority remain unqualified.
