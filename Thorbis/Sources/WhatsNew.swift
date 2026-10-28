import SwiftUI

/// Decides when the What's new sheet appears (design.thorbis.com MA-19, MA-22): once per set of
/// notes, after an update, on a signed-in home screen. Never after a fresh install, never twice.
@MainActor
final class WhatsNew: ObservableObject {
    /// What the sheet is showing now; nil when it is closed.
    @Published var showing: WhatsNewSheetContent?
    /// Set when the sign-in screen appears, so a first sign-in never opens the sheet.
    var signedInThisLaunch = false
    /// Set when a link or notification opened the app: the person came for something else.
    var skipThisLaunch = false
    /// Kept apart from `showing`, which a swipe down clears before `dismissed()` runs.
    private var presented: WhatsNewSheetContent?

    private let defaults: UserDefaults
    private let notes: [ReleaseNote]
    static let seenKey = "thorbis.whatsNew.seen"

    init(defaults: UserDefaults = .standard, notes: [ReleaseNote] = ReleaseNotes.all) {
        self.defaults = defaults
        self.notes = notes
    }

    /// Ids already shown on this phone; nil until the first time the app records any.
    private var seen: Set<String>? {
        (defaults.array(forKey: Self.seenKey) as? [String]).map { Set($0) }
    }

    /// The notes to show when a signed-in home screen appears, or nil for none.
    /// `signedInThisLaunch`: the person came through the sign-in screen, so with nothing recorded
    /// this is a fresh install (or a first sign-in) and every note counts as seen silently.
    /// Without it, nothing recorded means an update from a build before What's new existed:
    /// the older entries are recorded as seen now, so only the newest one is ever shown.
    func pending(signedInThisLaunch: Bool) -> [ReleaseNote] {
        guard let seen else {
            if signedInThisLaunch {
                markSeen(notes)
                return []
            }
            markSeen(Array(notes.dropFirst()))
            return Array(notes.prefix(1))
        }
        return notes.filter { !seen.contains($0.id) }
    }

    func presentIfNeeded(build: String = WhatsNew.currentBuild) {
        guard presented == nil else { return }
        // Runs first even when skipping, so a fresh install still records what it has seen.
        let unseen = pending(signedInThisLaunch: signedInThisLaunch)
        guard !unseen.isEmpty, !skipThisLaunch else { return }
        presented = WhatsNewSheetContent(notes: unseen, build: build)
        showing = presented
    }

    /// MA-22: Continue, a swipe down and a tap outside all count as read.
    func dismissed() {
        if let presented { markSeen(presented.notes) }
        presented = nil
        showing = nil
    }

    func markSeen(_ read: [ReleaseNote]) {
        let ids = (seen ?? []).union(read.map(\.id))
        defaults.set(ids.sorted(), forKey: Self.seenKey)
    }

    static var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }
}

/// One sheet's worth of notes: skipped builds fold together, newest first (MA-19).
struct WhatsNewSheetContent: Identifiable, Equatable {
    let notes: [ReleaseNote]
    let build: String
    var id: String { notes.map(\.id).joined(separator: "|") }

    /// MA-20: at most five highlights; the rest are counted below them.
    var highlights: [ReleaseNote.Highlight] { Array(allHighlights.prefix(ReleaseNote.maxHighlights)) }
    private var allHighlights: [ReleaseNote.Highlight] { notes.flatMap(\.highlights) }

    /// "Also: 3 smaller fixes", or "Also: 4 more changes" when highlights overflow; nil for none.
    var moreLine: String? {
        let overflow = allHighlights.count - highlights.count
        let fixes = notes.reduce(0) { $0 + $1.fixes }
        if overflow > 0 {
            let total = overflow + fixes
            return "Also: \(total) more \(total == 1 ? "change" : "changes")"
        }
        guard fixes > 0 else { return nil }
        return "Also: \(fixes) smaller \(fixes == 1 ? "fix" : "fixes")"
    }

    /// "Build 66 · Oct 28"
    var buildLine: String {
        let day = notes.first?.dayLabel ?? ""
        guard !build.isEmpty else { return day }
        return day.isEmpty ? "Build \(build)" : "Build \(build) · \(day)"
    }
}

/// MA-20: build line, title, up to five highlights, the count of the rest, one ink Continue.
struct WhatsNewSheet: View {
    let content: WhatsNewSheetContent
    let onContinue: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(content.buildLine)
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                Text("What's new")
                    .font(Theme.font(24, weight: .medium)).foregroundStyle(Theme.foreground)
                    .padding(.top, 4)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(content.highlights.enumerated()), id: \.offset) { _, item in
                        WhatsNewHighlightRow(item: item)
                    }
                }
                .padding(.top, 20)
                if let more = content.moreLine {
                    Text(more).font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.top, 16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 24).padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Continue", action: onContinue)
                .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 8)
                .background(Theme.surface)
        }
        .background(Theme.surface)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.cardRadius)
        .presentationBackground(Theme.surface)
        .onAppear {
            // MA-22: large type and long notes start at the large detent, so nothing hides below.
            if typeSize.isAccessibilitySize || content.highlights.count > 3 { detent = .large }
        }
    }
}

struct WhatsNewHighlightRow: View {
    let item: ReleaseNote.Highlight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.symbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Theme.muted)
                .frame(width: 36, height: 36)
                .background(Theme.fill, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                Text(item.detail).font(Theme.font(15)).foregroundStyle(Theme.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Settings > What's new: every entry, newest first, so the sheet is never the only way to read
/// the notes (MA-19).
struct WhatsNewHistoryView: View {
    var notes: [ReleaseNote] = ReleaseNotes.all

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(notes) { note in
                    SectionHeader(title: note.dayLabel).padding(.horizontal, -Theme.gutter)
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(note.highlights.enumerated()), id: \.offset) { _, item in
                            WhatsNewHighlightRow(item: item)
                        }
                        if note.fixes > 0 {
                            Text("Also: \(note.fixes) smaller \(note.fixes == 1 ? "fix" : "fixes")")
                                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
        .background(Theme.background)
        .navigationTitle("What's new")
        .navigationBarTitleDisplayMode(.inline)
    }
}
