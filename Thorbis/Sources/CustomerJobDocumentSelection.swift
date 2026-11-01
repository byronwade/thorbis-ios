import Foundation

enum CustomerJobDocumentID: Hashable, Identifiable {
    case estimate(String)
    case invoice(String)

    var id: String {
        switch self {
        case .estimate(let id): "estimate:\(id)"
        case .invoice(let id): "invoice:\(id)"
        }
    }

    var reference: String {
        switch self {
        case .estimate(let id): "EST-\(id.suffix(4).uppercased())"
        case .invoice(let id): "INV-\(id.suffix(4).uppercased())"
        }
    }
}

struct CustomerJobDocumentSelection {
    private(set) var ids: [CustomerJobDocumentID] = []
    private(set) var selected: CustomerJobDocumentID?
    init(ids: [CustomerJobDocumentID], selected: CustomerJobDocumentID) {
        reconcile(ids)
        select(selected)
    }
    var previous: CustomerJobDocumentID? { neighbor(-1) }
    var next: CustomerJobDocumentID? { neighbor(1) }
    var position: String {
        guard let selected, let index = ids.firstIndex(of: selected) else { return "Choose a document" }
        return "\(index + 1) of \(ids.count) \(ids.count == 1 ? "document" : "documents")"
    }
    mutating func select(_ id: CustomerJobDocumentID) {
        if ids.contains(id) { selected = id }
    }
    mutating func reconcile(_ incoming: [CustomerJobDocumentID]) {
        var seen = Set<CustomerJobDocumentID>()
        ids = incoming.filter { seen.insert($0).inserted }
        if let selected, !ids.contains(selected) { self.selected = nil }
    }
    private func neighbor(_ offset: Int) -> CustomerJobDocumentID? {
        guard let selected, let index = ids.firstIndex(of: selected), ids.indices.contains(index + offset) else { return nil }
        return ids[index + offset]
    }
}
