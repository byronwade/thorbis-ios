// Standalone harness only. iOS builds use the real SavedCopies transport.
enum SavedCopies {
    @TaskLocal static var liveOnly = false
    @TaskLocal static var customerNamespace: String? = nil
}
