import Foundation

@MainActor @main struct Check {
    static func main() {
        let lifecycle = EstimateEditorLifecycle()
        let owner = UUID()
        var busy = true, safe = false, attempts = 0, forced = 0
        lifecycle.register(owner: owner, busy: { busy }, preserve: { attempts += 1; return safe }, forced: { forced += 1 })
        precondition(lifecycle.beginTransition())
        precondition(lifecycle.transitioning && !lifecycle.prepareTransition() && attempts == 0)
        busy = false
        precondition(!lifecycle.prepareTransition() && attempts == 1)
        safe = true
        precondition(lifecycle.prepareTransition() && attempts == 2)
        precondition(!lifecycle.beginTransition())
        lifecycle.preserveForInvalidation()
        precondition(forced == 1)
        lifecycle.endTransition()
        // An editor may become unsafe while device unbinding is suspended.
        precondition(lifecycle.beginTransition())
        precondition(lifecycle.prepareTransition())
        safe = false
        precondition(!lifecycle.prepareTransition())
        lifecycle.endTransition()
        lifecycle.unregister(owner: owner)
        precondition(lifecycle.beginTransition() && lifecycle.prepareTransition())
        lifecycle.endTransition()
        print("PASS: transition blocks busy/failed editors, repeats preservation, and forced invalidation cannot be blocked")
    }
}
