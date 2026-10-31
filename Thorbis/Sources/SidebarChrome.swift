import SwiftUI

/// A rimmed search row. It lives under the workspace name, never in the footer.
struct SidebarSearchButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text("Search")
                Spacer(minLength: 0)
            }
            .font(Theme.font(15))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .panelBackground(cornerRadius: Theme.controlRadius)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Search")
    }
}

/// One account control. The name and Settings are the same button, tall enough to tap.
struct SidebarAccountButton: View {
    let name: String
    let action: () -> Void

    private var title: String { name.isEmpty ? "Account" : name }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Avatar(name: title, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Theme.font(15, weight: .medium))
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
