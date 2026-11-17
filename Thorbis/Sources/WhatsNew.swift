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
/// 2026-10-31: the highlights sit on one white panel over the cream ground, like every list.
struct WhatsNewSheet: View {
    let content: WhatsNewSheetContent
    let onContinue: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(content.buildLine)
                    .font(Theme.font(13, weight: .medium)).monospacedDigit().foregroundStyle(Theme.muted)
                Text("What's new")
                    .font(Theme.font(34, weight: .bold)).tracking(-0.85).foregroundStyle(Theme.foreground)
                    .padding(.top, 4)
                    .accessibilityAddTraits(.isHeader)
                PaperCard {
                    ForEach(Array(content.highlights.enumerated()), id: \.offset) { _, item in
                        WhatsNewHighlightRow(item: item)
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, PaperCardMetrics.margin - Theme.gutter)
                if let more = content.moreLine {
                    Text(more).font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.top, 12).padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 24).padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Got it", action: onContinue)
                .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 8)
                .background(Theme.canvas)
        }
        .background(Theme.canvas)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.cardRadius)
        .thorbisSheetSurface()
        .onAppear {
            // MA-22: large type and long notes start at the large detent, so nothing hides below.
            if typeSize.isAccessibilitySize || content.highlights.count > 3 { detent = .large }
        }
    }
}

/// One highlight: a neutral glyph, what you can now do (16/500) and one sentence under it.
struct WhatsNewHighlightRow: View {
    let item: ReleaseNote.Highlight
    @Environment(\.paperRowInset) private var inset

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: item.symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Theme.muted)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                Text(item.detail).font(Theme.font(15)).foregroundStyle(Theme.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, inset).padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// Settings > What's new: every entry, newest first, so the sheet is never the only way to read
/// the notes (MA-19). Each day is one section, like the sheet.
struct WhatsNewHistoryView: View {
    var notes: [ReleaseNote] = ReleaseNotes.all
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Paper 65F: two cards a row; one at accessibility sizes so the words never squeeze.
    private var columns: [GridItem] {
        typeSize.isAccessibilitySize
            ? [GridItem(.flexible(), alignment: .top)]
            : [GridItem(.flexible(), spacing: 10, alignment: .top), GridItem(.flexible(), spacing: 10, alignment: .top)]
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Paper 65F: the title in 28 Bold, one muted line under it.
                VStack(alignment: .leading, spacing: 2) {
                    Text("What's new").font(Theme.heading()).tracking(-0.56)
                        .accessibilityAddTraits(.isHeader)
                    Text("What you can do now, newest first").font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin).padding(.top, 14).padding(.bottom, 16)
                ForEach(notes) { note in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(note.dayLabel).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.horizontal, 4)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                            ForEach(Array(note.highlights.enumerated()), id: \.offset) { index, item in
                                WhatsNewHistoryCard(item: item, index: index)
                            }
                        }
                        if note.fixes > 0 {
                            Text("Also: \(note.fixes) smaller \(note.fixes == 1 ? "fix" : "fixes")")
                                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
            .paperCardMargin()
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One highlight as a Paper 65F card: its symbol on a tinted tile, the title (16 Semibold) and the
/// sentence under it. The tile's hue rotates so a row of cards scans; the words carry the meaning.
private struct WhatsNewHistoryCard: View {
    let item: ReleaseNote.Highlight
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: item.symbol)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, minHeight: 88)
                .background(surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                Text(item.detail).font(Theme.font(14)).foregroundStyle(Theme.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4).padding(.bottom, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .panelBackground()
        .accessibilityElement(children: .combine)
    }

    private var ink: Color {
        switch index % 4 {
        case 0: return Theme.brandText
        case 1: return Theme.success
        case 2: return Theme.ai
        default: return Theme.warning
        }
    }

    private var surface: Color {
        switch index % 4 {
        case 0: return Theme.brandSurface
        case 1: return Theme.successSurface
        case 2: return Theme.aiSurface
        default: return Theme.warningSurface
        }
    }
}
