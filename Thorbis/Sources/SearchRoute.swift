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
            HStack(spacing: 6) {
                PaperCircleButton(symbol: "chevron.left", label: "Close search", size: 36) { close() }
                field
            }
            .padding(.leading, Theme.gutter - 4).padding(.trailing, Theme.gutter)
            .padding(.top, 4).padding(.bottom, 4)
            PaperGlobalSearch(model: model, openResult: host.open, focus: host.focus, actions: host.actions)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("bar-search-results")
        }
        .background(Theme.background.ignoresSafeArea())
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

    /// Sink (design.thorbis.com Depth): the field is a well one step darker than the canvas.
    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
            TextField("Street, name, phone or number", text: $model.query)
                .font(Theme.font(16))
                .focused($fieldFocused)
                .submitLabel(.search)
                .onSubmit { model.submit() }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(Theme.muted)
                        .frame(width: 28, height: 36).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.vertical, -4)
        .fieldWell()
    }
}
