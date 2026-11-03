import Foundation

/// Coordinates intentional identity changes with live job-estimate editors in this process.
/// Forced authorization loss is never delayed by an editor.
@MainActor final class EstimateEditorLifecycle {
    static let shared = EstimateEditorLifecycle()
    private struct Editor {
        let busy: () -> Bool
        let preserve: () -> Bool
        let forced: () -> Void
    }
    private var editors: [UUID: Editor] = [:]
    private(set) var transitioning = false

    func register(owner: UUID, busy: @escaping () -> Bool, preserve: @escaping () -> Bool, forced: @escaping () -> Void) {
        editors[owner] = Editor(busy: busy, preserve: preserve, forced: forced)
    }
    func unregister(owner: UUID) { editors.removeValue(forKey: owner) }
    func beginTransition() -> Bool {
        guard !transitioning else { return false }
        transitioning = true
        return true
    }
    func prepareTransition() -> Bool {
        let current = Array(editors.values)
        guard !current.contains(where: { $0.busy() }) else { return false }
        var safe = true
        for editor in current { if !editor.preserve() { safe = false } }
        return safe
    }
    func preserveForInvalidation() {
        for editor in Array(editors.values) { editor.forced() }
    }
    func endTransition() { transitioning = false }
}
