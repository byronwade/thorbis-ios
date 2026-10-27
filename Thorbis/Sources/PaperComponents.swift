import SwiftUI

/// Native counterparts of the shared Thorbis Mobile Paper components.
struct PaperHeader: View {
    let title: String
    let icon: String
    let subtitle: String
    var search: () -> Void = {}
    @EnvironmentObject private var session: SessionController
    @Environment(\.paperShowMenu) private var showMenu

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 12) {
                Button(action: showMenu) {
                    HStack(spacing: 8) {
                        Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Theme.brand)
                        Text(title).font(Theme.font(22, weight: .semibold)).tracking(-0.44)
                        Image(systemName: "chevron.down").font(.system(size: 10)).foregroundStyle(Theme.muted)
                    }
                }.buttonStyle(.plain).accessibilityLabel("\(title), open navigation")
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Button(action: search) { Image(systemName: "magnifyingglass").font(.system(size: 14)).frame(width: 32, height: 32).background(Theme.fill, in: Circle()) }
                        .accessibilityLabel("Search \(title.lowercased())")
                    Button(action: showMenu) {
                        Text(initials(session.user?.name ?? session.user?.email ?? ""))
                            .font(Theme.font(12, weight: .semibold)).foregroundStyle(Theme.brand)
                            .frame(width: 32, height: 32).background(Theme.brandSurface, in: Circle())
                    }.accessibilityLabel("Workspace menu")
                }.buttonStyle(.plain)
            }
            Text(subtitle).font(Theme.font(13)).foregroundStyle(Theme.muted).frame(minHeight: 18, alignment: .leading)
        }.foregroundStyle(Theme.foreground).padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 10)
    }
}

struct PaperTabs: View {
    let options: [String]
    @Binding var selection: String
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(options, id: \.self) { option in
                    Button { selection = option } label: {
                        Text(option).font(Theme.font(13, weight: selection == option ? .semibold : .medium))
                            .foregroundStyle(selection == option ? Theme.foreground : Theme.muted)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(selection == option ? Theme.fill : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).accessibilityAddTraits(selection == option ? .isSelected : [])
                }
            }
        }.scrollIndicators(.hidden).padding(.horizontal, 16).padding(.bottom, 12)
    }
}

struct PaperSearchField: View {
    @Binding var text: String
    var prompt: String = "Search"
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField(prompt, text: $text).textInputAutocapitalization(.never).autocorrectionDisabled()
            if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear search") }
        }.font(Theme.font(14)).padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border)).padding(.horizontal, 16).padding(.bottom, 12)
    }
}

private struct PaperShowMenuKey: EnvironmentKey {
    static let defaultValue: @Sendable () -> Void = {}
}
extension EnvironmentValues {
    var paperShowMenu: @Sendable () -> Void {
        get { self[PaperShowMenuKey.self] }
        set { self[PaperShowMenuKey.self] = newValue }
    }
}
