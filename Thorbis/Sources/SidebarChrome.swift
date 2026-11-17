import SwiftUI

/// The sidebar's search row (Paper T01 rail): "Search" on the quiet fill, no rim. It lives under
/// the workspace name, never in the footer.
struct SidebarSearchButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium))
                    .accessibilityHidden(true)
                Text("Search").font(Theme.font(15))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Search")
    }
}

/// One account control (Paper T01 rail foot): the person's initials on the brand surface, their
/// name in 15 Semibold and "Settings" under it. The whole row is the button, tall enough to tap.
struct SidebarAccountButton: View {
    let name: String
    let action: () -> Void

    private var title: String { name.isEmpty ? "Account" : name }
    private var initials: String {
        title.split(separator: " ").prefix(2).map { String($0.prefix(1)) }.joined().uppercased()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(initials)
                    .font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.brandText)
                    .frame(width: 36, height: 36)
                    .background(Theme.brandSurface, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(Theme.font(15, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    Text("Settings")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel("Settings, \(title)")
    }
}
