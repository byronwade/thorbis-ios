import SwiftUI
import ThorbisCore

/// A commit is ink: type-colour fill, inverse type, 10pt radius, 1pt rim
/// (design.thorbis.com Controls). Guided/touch height is at least 44pt.
struct CommitButtonStyle: ButtonStyle {
    var role: ButtonRole?
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let destructive = role == .destructive
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(destructive ? Color.white : Theme.inkInverse)
            .frame(maxWidth: .infinity, minHeight: Theme.minimumHit)
            .padding(.horizontal, Theme.Space.l)
            .background(destructive ? Theme.destructive : Theme.ink, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(Theme.rimStrong.opacity(0.4)))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.6)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
    }
}

/// The quieter neighbour of a commit: a rimmed control on the sheet, same height and radius.
struct RimButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: Theme.minimumHit)
            .padding(.horizontal, Theme.Space.l)
            .background(configuration.isPressed ? Theme.selected : Theme.subtle, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(Theme.rimInteractive))
            .opacity(isEnabled ? 1 : 0.6)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
    }
}

extension ButtonStyle where Self == CommitButtonStyle {
    static var commit: CommitButtonStyle { CommitButtonStyle() }
    static var destructiveCommit: CommitButtonStyle { CommitButtonStyle(role: .destructive) }
}

extension ButtonStyle where Self == RimButtonStyle {
    static var rim: RimButtonStyle { RimButtonStyle() }
}

/// A commit with a word and an optional mark. Loading keeps the word (Controls).
struct CommitButton: View {
    let title: String
    var symbol: String?
    var role: ButtonRole?
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: Theme.Space.s) {
                if busy {
                    ProgressView().tint(role == .destructive ? .white : Theme.inkInverse)
                } else if let symbol {
                    Image(systemName: symbol).accessibilityHidden(true)
                }
                Text(title)
            }
        }
        .buttonStyle(CommitButtonStyle(role: role))
        .disabled(busy)
    }
}

/// Status as a word in a pill, with a small toned mark. Chips are pills.
struct StatusBadge: View {
    let text: String
    var symbol: String?
    var tone: Tone = .neutral

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            if let symbol {
                Image(systemName: symbol).imageScale(.small).foregroundStyle(tone.color).accessibilityHidden(true)
            }
            Text(text).foregroundStyle(Theme.inkSecondary)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, Theme.Space.xs)
        .background(Theme.subtle, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.rim))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(text)")
    }
}

extension StatusBadge {
    init(_ status: JobStatus) { self.init(text: status.label, symbol: status.symbol, tone: status.tone) }
    init(_ status: EstimateStatus) { self.init(text: Format.status(status), tone: status.tone) }
    init(_ status: InvoiceStatus) { self.init(text: Format.status(status), tone: status.tone) }
}

struct Avatar: View {
    let name: String
    var size: CGFloat = 32

    var body: some View {
        Text(Format.initials(name))
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.inkSecondary)
            .frame(width: size, height: size)
            .background(Theme.field, in: Circle())
            .overlay(Circle().strokeBorder(Theme.rim))
            .accessibilityHidden(true)
    }
}

/// Money in integer cents, tabular so columns compare.
struct MoneyText: View {
    let cents: Int
    var currency = "USD"

    var body: some View {
        Text(Format.money(cents, currency: currency)).monospacedDigit()
    }
}

/// A rounded sheet on the canvas (14pt), for content outside a List.
struct SheetCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) { content }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.Radius.sheet))
    }
}

/// Native lists on the Thorbis canvas: rows are the sheet, the void stays behind.
struct ThorbisListStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
    }
}

extension View {
    func thorbisList() -> some View { modifier(ThorbisListStyle()) }
    func sheetRow() -> some View { listRowBackground(Theme.sheet) }
}

/// Honest states (HIG-015): loading, empty, error with retry, distinct from each other.
struct LoadState<Content: View>: View {
    let isLoading: Bool
    let error: String?
    let isEmpty: Bool
    let emptyTitle: String
    let emptySymbol: String
    var emptyMessage: String?
    let retry: () async -> Void
    @ViewBuilder var content: Content

    var body: some View {
        if isEmpty, let error {
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try again") { Task { await retry() } }.buttonStyle(.rim).fixedSize()
            }
        } else if isEmpty, isLoading {
            ProgressView("Loading").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isEmpty {
            ContentUnavailableView {
                Label(emptyTitle, systemImage: emptySymbol)
            } description: {
                if let emptyMessage { Text(emptyMessage) }
            }
        } else {
            content
        }
    }
}

/// An inline problem that keeps the screen usable: the stale data stays, the reason shows.
struct InlineError: View {
    let message: String
    var retry: (() async -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warning).accessibilityHidden(true)
            Text(message).font(.footnote).foregroundStyle(Theme.inkSecondary)
            Spacer(minLength: 0)
            if let retry {
                Button("Retry") { Task { await retry() } }
                    .font(.footnote.weight(.medium))
                    .frame(minWidth: Theme.minimumHit, minHeight: Theme.minimumHit)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Label above, value below; long values wrap rather than truncate (HIG-008).
struct DetailRow: View {
    let label: String
    let value: String
    var symbol: String?

    var body: some View {
        LabeledContent {
            Text(value).foregroundStyle(Theme.ink).multilineTextAlignment(.trailing)
        } label: {
            if let symbol {
                Label(label, systemImage: symbol).foregroundStyle(Theme.inkSecondary)
            } else {
                Text(label).foregroundStyle(Theme.inkSecondary)
            }
        }
    }
}
