import SwiftUI

/// v2 (design.thorbis.com Places, "Search is a route because comparing fifty records is a
/// workspace"): on the phone, Search is a pushed screen on the place showing, not a sheet or a
/// frosted overlay. A result pushes on top of it, so Back returns to the results; Back again (the
/// circle or the edge swipe) returns to the place.
struct SearchRoute: Hashable {}

/// What the phone shell lends the Search route: the shared model (its words survive while a
/// result is open), where a picked result goes, the actions search can run, the place it opened
/// over, and a way for the shell to close it again.
struct SearchRouteHost {
    let model: SearchModel
    let open: (SearchDestination) -> Void
    let actions: [SearchAction]
    let focus: SearchFocus
    let closer: SearchRouteCloser
    /// Told when the route comes into view and leaves it (a result pushed on top, or Back).
    let showing: (Bool) -> Void
}

/// Holds the route's own dismiss while it is on screen, so a search action (New job, Settings,
/// another place) can close search before it runs.
final class SearchRouteCloser {
    var close: (() -> Void)?
}

private struct SearchRouteHostKey: EnvironmentKey { nonisolated(unsafe) static let defaultValue: SearchRouteHost? = nil }
extension EnvironmentValues {
    var searchRouteHost: SearchRouteHost? {
        get { self[SearchRouteHostKey.self] }
        set { self[SearchRouteHostKey.self] = newValue }
    }
}

/// The Search route: Back, then the field as a sunk well at the top, then the results room.
struct SearchRoutePage: View {
    @Environment(\.searchRouteHost) private var host
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let host {
            SearchRouteContent(host: host, model: host.model, close: { dismiss() })
        }
    }
}

private struct SearchRouteContent: View {
    let host: SearchRouteHost
    @ObservedObject var model: SearchModel
    let close: () -> Void
    @FocusState private var fieldFocused: Bool
    @State private var focusedOnce = false

    var body: some View {
        VStack(spacing: 0) {
            // Paper 76: the 44pt card circle with a cross, 16 from the edge; 14 under it "Search"
            // (34/40 Bold) 20 in; 14 under that the field.
            VStack(alignment: .leading, spacing: 14) {
                PaperCircleButton(symbol: "xmark", label: "Close search", size: 44) { close() }
                PaperPageTitle(title: "Search", columnInset: PaperCardMetrics.margin, top: 0)
                field
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PaperCardMetrics.margin)
            .padding(.top, 2).padding(.bottom, 6)
            PaperGlobalSearch(model: model, openResult: host.open, focus: host.focus, actions: host.actions)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("bar-search-results")
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            host.closer.close = close
            host.showing(true)
            // Focus the field on the way in only; coming back from a result keeps the keyboard down.
            if !focusedOnce {
                focusedOnce = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    fieldFocused = true
                }
            }
        }
        .onDisappear { host.showing(false) }
    }

    /// Paper 76: the field on the card (radius 14, 46 tall, 12 in), an 18pt glass in ink once
    /// words are in it, and the brand rim while it is being typed in.
    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return HStack(spacing: 8) {
            PaperIcon(.search, size: 18, color: model.query.isEmpty ? Theme.muted : Theme.foreground)
            TextField("Search or ask", text: $model.query, prompt: .placeholder("Search or ask"))
                .font(Theme.font(16))
                .focused($fieldFocused)
                .submitLabel(.search)
                .onSubmit { model.submit() }
                .autocorrectionDisabled()
                .accessibilityIdentifier("search-field")
                .textInputAutocapitalization(.never)
                .frame(minHeight: 44)
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    PaperIcon(.close, size: 12, color: Theme.foreground)
                        .frame(width: 40, height: 40)
                        .background(Theme.quietFill, in: Circle())
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 12).padding(.trailing, model.query.isEmpty ? 12 : 4)
        .frame(minHeight: 46)
        .background(Theme.card, in: shape)
        .overlay { if fieldFocused || !model.query.isEmpty { shape.strokeBorder(Theme.brand, lineWidth: 1.5) } }
    }
}
