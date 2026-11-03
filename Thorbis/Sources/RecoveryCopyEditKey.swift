import Foundation

/// A volatile edit belongs to both the original scoped job and its source copy.
struct RecoveryCopyEditKey<Scope: Hashable>: Hashable {
    let scope: Scope
    let sourceID: UUID
}

/// Session identity survives view recreation while the process-local edit exists.
struct RecoveryCopyEditState<Draft> {
    let draft: Draft
    let sessionID: UUID
}
