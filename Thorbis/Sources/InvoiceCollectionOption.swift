import Foundation

enum InvoiceCollectionOption: String, Equatable {
    case tapToPay, paymentLink, cash, check, bankTransfer, externalCard

    var recordedMethod: FieldPaymentMethod? {
        switch self {
        case .cash: .cash
        case .check: .check
        case .bankTransfer: .ach
        case .externalCard: .card
        case .tapToPay, .paymentLink: nil
        }
    }

    var isExternalReceipt: Bool { self == .bankTransfer || self == .externalCard }
    private var canRemember: Bool { self == .cash || self == .check || self == .paymentLink }

    static func initial(pendingMethod: FieldPaymentMethod?, lastUsed: Self?) -> Self {
        if let pendingMethod {
            switch pendingMethod {
            case .cash: return .cash
            case .check: return .check
            case .ach: return .bankTransfer
            case .card: return .externalCard
            }
        }
        return lastUsed.flatMap { $0.canRemember ? $0 : nil } ?? .paymentLink
    }

    /// Only direct collection choices are remembered; a retry always restores its tender.
    static var lastUsed: Self? {
        get {
            UserDefaults.standard.string(forKey: "thorbis.payment.lastOption")
                .flatMap(Self.init(rawValue:))
                .flatMap { $0.canRemember ? $0 : nil }
        }
        set { UserDefaults.standard.set(newValue?.canRemember == true ? newValue?.rawValue : nil,
                                       forKey: "thorbis.payment.lastOption") }
    }
}
