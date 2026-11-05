# Held invoice terminal-owner experiment

This is an unwired macOS prototype, not an app implementation. Run:

    swiftc tools/invoice-terminal-harness/InvoiceReadFence.swift tools/invoice-terminal-harness/InvoiceTerminalOwner.swift tools/invoice-terminal-harness/main.swift -o /private/tmp/thorbis-invoice-terminal-harness
    /private/tmp/thorbis-invoice-terminal-harness

The fence copy comes from held commit `5c67b40`; its `terminalUncertain` case allows retry only after the owner receives its final callback, keeping the pending disk state that blocks a prior copy. The earlier `uncertain` remains conservative when callback quiescence is not known.

The harness exercises denial before/after cancellation, mismatched response URL, terminal uncertainty followed by retry, denial-persistence rename failure, and reopening in another process. One additional test uses a real URLSession delegate with a custom URLProtocol delivering a 403; the delegate cancels after observing the response and waits for `didCompleteWithError`. An earlier diagnostic run timed out when the protocol never finished; the current fixture completes its response. This does not prove redirect behavior, real network callback delivery, actor/workspace authority, iOS device or power-loss durability, cache migration, scope isolation in all consumers, nor any screen or outbox behavior. No success or connectivity authorization is implemented here; all non-denial terminal outcomes remain held.
