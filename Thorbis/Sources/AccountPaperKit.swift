import SwiftUI

// Paper's settings grammar (main file 65 Settings, 67 Account and data, 69 Privacy and
// permissions; Navigation file 61N Business settings), with Paper's own values: a 13 Semibold
// label over one radius-20 card; rows 16 in with a 34pt glyph slot, the title in 16 Medium
// (-0.01em), one 14 muted line under it, a 14 muted value and a small chevron; hairlines start
// under the words (50 from the card's edge).

extension PaperGlyph {
    // 65 Settings (17pt box, 1.4 stroke).
    static let acctChevron = PaperGlyph.chevronRightSmall
    static let acctChevronLarge = PaperGlyph.chevronRight
    static let rowArrowOut = PaperGlyph(box: 14, [.stroke("M4.2 9.8L9.8 4.2M5.1 4.2h4.7v4.7", 1.5)])
    static let setBell = PaperGlyph(box: 17, [.stroke("M8.5 2a4.2 4.2 0 00-4.2 4.2c0 3.4-1.3 4.6-1.3 4.6h11s-1.3-1.2-1.3-4.6A4.2 4.2 0 008.5 2zM7.2 13.3a1.4 1.4 0 002.6 0", 1.4)])
    static let setBubble = PaperGlyph(box: 17, [.stroke("M8.5 2.5c3.5 0 6.2 2.4 6.2 5.4 0 3-2.7 5.4-6.2 5.4-.7 0-1.3-.1-1.9-.3l-3.4 1.5.9-2.9c-1.1-1-1.8-2.3-1.8-3.7 0-3 2.7-5.4 6.2-5.4z", 1.4)])
    static let setCalendar = PaperGlyph(box: 17, [.rect(2, 3.5, 13, 11.5, rx: 2, 1.4), .stroke("M2 7h13M5.7 1.8v3M11.3 1.8v3", 1.4)])
    static let setPencil = PaperGlyph(box: 16, [.stroke("M11.3 2.1l2.6 2.6L5.6 13H3v-2.6l8.3-8.3z", 1.4), .stroke("M9.5 4l2.5 2.5", 1.4)])
    static let setHelp = PaperGlyph(box: 17, [.circle(8.5, 8.5, 6.5, 1.4), .stroke("M6.6 6.4a2 2 0 013.9.6c0 1.3-1.9 1.6-1.9 2.7M8.5 12.2h.01", 1.4)])
    static let setSignOut = PaperGlyph(box: 16, [.stroke("M6 2H3.5A1.5 1.5 0 002 3.5v9A1.5 1.5 0 003.5 14H6M11 11l3-3-3-3M14 8H6", 1.4)])
    /// The page layout drawing Paper uses for "Sidebar"; here it marks Menu and start screen.
    static let setSidebar = PaperGlyph(box: 18, [.rect(2.25, 3.25, 13.5, 11.5, rx: 2.5, 1.5), .stroke("M7 3.25V14.75", 1.5)])
    static let setTheme = PaperGlyph(box: 17, [.circle(8.5, 8.5, 6.5, 1.4), .fill("M8.5 2a6.5 6.5 0 010 13z")])

    // 67 Account and data, 69 Privacy and permissions.
    static let acctKey = PaperGlyph(box: 17, [.circle(5.5, 8.5, 3.2, 1.4), .stroke("M8.7 8.5h6M12 8.5v2.6M14.7 8.5v1.8", 1.4)])
    static let acctShield = PaperGlyph(box: 17, [.stroke("M8.5 1.8l5.5 2v4c0 3.2-2.3 6-5.5 7.2C5.3 13.8 3 11 3 7.8v-4l5.5-2z", 1.4)])
    static let acctPerson = PaperGlyph(box: 17, [.circle(8.5, 8.5, 6.5, 1.4), .circle(8.5, 7, 2.1, 1.4),
                                                .stroke("M4.6 13.4c.8-1.6 2.2-2.4 3.9-2.4s3.1.8 3.9 2.4", 1.4)])
    static let acctTrash = PaperGlyph(box: 15, [.stroke("M2.5 4h10M5.8 4V2.8h3.4V4M4 4l.6 8.2a1.2 1.2 0 001.2 1.1h3.4a1.2 1.2 0 001.2-1.1L11 4M6.3 6.5v4M8.7 6.5v4", 1.3)])

    // 61 / 61N Business settings (20pt box drawn at 22, 1.6 stroke).
    static let bizCompany = PaperGlyph(box: 20, [.rect(5, 3, 10, 14, rx: 1.5, 1.6), .stroke("M8.5 17V14H11.5V17", 1.6)])
    static let bizDrop = PaperGlyph(box: 20, [.stroke("M10 3L14.5 9C16 11.5 14.5 16.5 10 16.5C5.5 16.5 4 11.5 5.5 9L10 3Z", 1.6)])
    static let bizTag = PaperGlyph(box: 20, [.stroke("M3.5 4.5V10L10.5 17L17 10.5L10 3.5H4.5C4 3.5 3.5 4 3.5 4.5Z", 1.6)])
    static let bizPercent = PaperGlyph(box: 20, [.stroke("M5 15L15 5", 1.6), .circle(6, 6, 1.8, 1.6), .circle(14, 14, 1.8, 1.6)])
    static let bizChecklist = PaperGlyph(box: 20, [.rect(3.5, 4, 4.5, 4.5, rx: 1, 1.6), .rect(3.5, 11.5, 4.5, 4.5, rx: 1, 1.6),
                                                  .stroke("M10.5 6.2H16.5M10.5 13.8H16.5", 1.6)])
    static let bizBell = PaperGlyph(box: 20, [.stroke("M5.5 13.5V9a4.5 4.5 0 0 1 9 0v4.5l1.2 1.5H4.3ZM8.3 16.5a1.8 1.8 0 0 0 3.4 0", 1.6)])
    static let bizWorkflows = PaperGlyph(box: 20, [.rect(3.5, 3.5, 5, 5, rx: 1, 1.6), .rect(11.5, 3.5, 5, 5, rx: 1, 1.6),
                                                  .rect(3.5, 11.5, 5, 5, rx: 1, 1.6), .stroke("M14 11.5V16.5M11.5 14H16.5", 1.6)])
    static let bizCard = PaperGlyph(box: 20, [.rect(3, 5, 14, 10, rx: 2, 1.6), .stroke("M3 8.5H17", 1.6)])
    static let bizPeople = PaperGlyph(box: 20, [.circle(8, 7.5, 2.6, 1.6), .stroke("M3 16c.6-2.8 2.6-4.2 5-4.2s4.4 1.4 5 4.2", 1.6),
                                               .stroke("M13 5.2a2.6 2.6 0 0 1 0 4.8M15 12.2c1.2.6 2 1.8 2.3 3.8", 1.6)])
    static let bizStar = PaperGlyph(box: 20, [.stroke("M10 3.2l2.1 4.3 4.7.7-3.4 3.3.8 4.7L10 14l-4.2 2.2.8-4.7L3.2 8.2l4.7-.7z", 1.6)])
    static let bizImport = PaperGlyph(box: 20, [.stroke("M10 3.5V12M6.5 8.8L10 12.3l3.5-3.5M4 15.5h12", 1.6)])
    static let bizTarget = PaperGlyph(box: 20, [.circle(10, 10, 6.5, 1.6), .circle(10, 10, 2.5, 1.6)])
}

/// Which mark ends a settings row.
enum AccountRowEnd { case none, chevron, chevronLarge, arrowOut }

/// One settings row. Give it a `WellDivider(leading: AccountRow.dividerInset)` between rows.
struct AccountRow<Trailing: View>: View {
    static var dividerInset: CGFloat { 50 }

    var glyph: PaperGlyph? = nil
    /// An SF Symbol where Paper's own drawing has not been brought over yet.
    var symbol: String? = nil
    /// Paper draws 65's glyphs at their own size (16–18) and 61N's at 22.
    var glyphSize: CGFloat? = nil
    var glyphColor: Color = Theme.muted
    let title: String
    var titleColor: Color = Theme.foreground
    var subtitle: String? = nil
    var value: String? = nil
    var end: AccountRowEnd = .chevron
    /// False on a card whose rows carry no glyphs (65A, 65C): the words start 16 in.
    var slot = true
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            if slot {
                Group {
                    if let glyph {
                        PaperIcon(glyph, size: glyphSize ?? glyph.box, color: glyphColor)
                    } else if let symbol {
                        Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(glyphColor)
                            .frame(width: 18).accessibilityHidden(true)
                    }
                }
                .frame(width: 34, alignment: .leading)
            }
            HStack(alignment: .center, spacing: value == nil ? 12 : 8) {
                let stacked = typeSize.isAccessibilitySize && value != nil
                let words = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                                    : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
                words {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).font(Theme.font(16, weight: .medium)).tracking(-0.16)
                            .foregroundStyle(titleColor)
                            .fixedSize(horizontal: false, vertical: true)
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle).font(Theme.font(14)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let value, !value.isEmpty {
                        Text(value).font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(stacked ? .leading : .trailing)
                            .lineLimit(2)
                    }
                }
                trailing
                switch end {
                case .none: EmptyView()
                case .chevron: PaperIcon(.acctChevron, size: 14, color: Theme.muted)
                case .chevronLarge: PaperIcon(.acctChevronLarge, size: 16, color: Theme.muted)
                case .arrowOut: PaperIcon(.rowArrowOut, size: 14, color: Theme.muted)
                }
            }
            .padding(.vertical, 8)
            .padding(.trailing, 16)
            .frame(minHeight: subtitle == nil ? 56 : 64)
        }
        .padding(.leading, 16)
        .multilineTextAlignment(.leading)
        .contentShape(Rectangle())
    }
}

extension AccountRow where Trailing == EmptyView {
    init(glyph: PaperGlyph? = nil, symbol: String? = nil, glyphSize: CGFloat? = nil, glyphColor: Color = Theme.muted, title: String,
         titleColor: Color = Theme.foreground, subtitle: String? = nil, value: String? = nil,
         end: AccountRowEnd = .chevron, slot: Bool = true) {
        self.init(glyph: glyph, symbol: symbol, glyphSize: glyphSize, glyphColor: glyphColor, title: title, titleColor: titleColor,
                  subtitle: subtitle, value: value, end: end, slot: slot) { EmptyView() }
    }
}

/// A 13 Semibold muted label (4 in from the card's edge, 8 over it) and one radius-20 card of rows.
/// Sits inside a column that is already 16 from the screen's edges.
struct AccountGroup<Content: View>: View {
    let title: String?
    var count: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack(spacing: 8) {
                    Text(title).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    if let count { Text(count).font(Theme.font(13)).foregroundStyle(Theme.muted) }
                }
                .padding(.horizontal, 4).padding(.bottom, 8)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: shape)
                .clipShape(shape)
        }
    }
}

/// The page title under the back circle: an optional 13 Semibold eyebrow, the 34/40 Bold title
/// (-0.025em) and an optional 15/20 muted line, 4 in from the column (20 from the screen).
struct AccountPageTitle: View {
    var eyebrow: String? = nil
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let eyebrow {
                Text(eyebrow).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            Text(title).font(Theme.font(34, weight: .bold)).tracking(-0.85)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle).font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, eyebrow == nil ? 0 : 4)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Paper's "Added" / "New" pill beside a row's chevron: 12 Semibold brand text on the brand surface.
struct AccountRowPill: View {
    let text: String

    var body: some View {
        Text(text).font(Theme.font(12, weight: .semibold)).foregroundStyle(Theme.brandText)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Theme.brandSurface, in: Capsule())
    }
}

/// The person at the top of Settings and Account and data: a 40pt brand circle with white
/// initials, the name in 16 Medium, the email in 14 muted, and a chevron. 64 tall.
struct AccountPersonRow: View {
    let name: String
    let email: String?

    var body: some View {
        HStack(spacing: 12) {
            Text(initials(name))
                .font(.custom("Inter-Regular", fixedSize: 13).weight(.semibold)).foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .background(Theme.brand, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(Theme.font(16, weight: .medium)).tracking(-0.16)
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let email {
                    // An address breaks mid-word when it wraps, so it shrinks on one line instead.
                    Text(email).font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .lineLimit(1).minimumScaleFactor(0.6).truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PaperIcon(.acctChevron, size: 14, color: Theme.muted)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }
}

/// Paper 04 / 05: the 44pt brand tile with a white "T" (20 Bold), radius 12.
struct AccountBrandTile: View {
    var body: some View {
        Text(verbatim: "T")
            .font(.custom("Inter-Regular", fixedSize: 20).weight(.bold)).foregroundStyle(Color.white)
            .frame(width: 44, height: 44)
            .background(Theme.brand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement()
            .accessibilityLabel("Thorbis")
    }
}

#if DEBUG
/// Screenshot harness for the account pages (`--paper-preview-screen acct-…`, see PaperPreview.statesScreen).
struct AccountPreview: View {
    let screen: String

    var body: some View {
        switch screen {
        case "acct-intro", "acct-intro-2", "acct-intro-3":
            AppIntroView(startPage: screen == "acct-intro" ? 0 : screen == "acct-intro-2" ? 1 : 2) { _ in }
        case "acct-signup": SignUpView(initialEmail: "")
        case "acct-forgot": PasswordResetRequestView(initialEmail: "ramon@example.invalid")
        case "acct-forgot-sent": PasswordResetRequestView(initialEmail: "ramon@example.invalid", sent: true)
        case "acct-profile": EditProfileSheet(name: "Ramon Marlowe")
        default:
            NavigationStack {
                Color.clear.navigationDestination(isPresented: .constant(true)) {
                    Group {
                        switch screen {
                        case "acct-privacy": PrivacyPermissionsView()
                        case "acct-notifications": MyNotificationsView()
                        case "acct-menu": CustomizeMenuView()
                        case "acct-help": HelpView()
                        default: AccountAndDataView()
                        }
                    }
                    .thorbisBackButton()
                }
            }
        }
    }
}
#endif
