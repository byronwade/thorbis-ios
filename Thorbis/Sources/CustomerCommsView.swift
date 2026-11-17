import SwiftUI

/// Paper 48N › Texts and calls: Call and Text, then this customer's calls from the business's
/// call log and the drafts written to them on this phone, newest first. Sits inside the
/// customer's hub page, under its title.
struct CustomerCommsSection: View {
    let customerID: String
    let customerName: String
    /// Every number and address on file for the customer and their contacts.
    let numbers: [String]
    let emails: [String]
    /// The number Call and Text reach (the primary contact's), digits and "+" only.
    let dialable: String?
    /// customer.view with call_recording: without it the call log is not read at all.
    let callsAvailable: Bool
    @ObservedObject var model: CustomerCommsModel
    @EnvironmentObject private var api: APIClient
    @Environment(\.openURL) private var openURL
    @Environment(\.inboxText) private var inboxText
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var open: CommsOpen?

    private var entries: [CustomerCommsEntry] {
        let calls = callsAvailable ? CustomerComms.calls(model.calls, customerID: customerID, numbers: numbers) : []
        return CustomerComms.entries(calls: calls,
                                     threads: CustomerComms.threads(model.threads, numbers: numbers, emails: emails))
    }

    private var waitingForCalls: Bool { callsAvailable && !model.denied && !model.loaded }

    var body: some View {
        let entries = entries
        VStack(alignment: .leading, spacing: 16) {
            actions
            if callsAvailable, let error = model.error {
                ErrorBanner(message: entries.isEmpty ? "Calls did not load. \(error)" : error) { await model.refresh(api: api) }
                    .flush()
                    .accessibilityIdentifier("customer-comms-retry")
            }
            if entries.isEmpty {
                if waitingForCalls {
                    PaperCard { SkeletonRows(count: 3, leading: false, inset: PaperCardMetrics.inset) }
                } else {
                    PaperCard {
                        LearnEmptyRow(title: "No texts or calls yet",
                                      message: numbers.isEmpty
                                        ? "Add a phone number for \(customerName) and their calls show here."
                                        : "Calls with \(customerName)\u{2019}s numbers and what you write to them on this phone show here.")
                    }
                    .accessibilityIdentifier("customer-comms-empty")
                }
            } else {
                PaperCard {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { WellDivider(leading: PaperCardMetrics.inset + 32 + 12) }
                            row(entry)
                        }
                    }
                }
                .accessibilityIdentifier("customer-comms-list")
            }
            if callsAvailable && !model.denied && model.hasOlder {
                Button { Task { await model.loadOlder(api: api) } } label: {
                    Text(model.loading ? "Loading\u{2026}" : "Look through older calls")
                        .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .disabled(model.loading)
                .accessibilityIdentifier("customer-comms-older")
            }
            LearnFootnote(text: footnote)
        }
        .thorbisDestination(item: $open) { target in
            switch target {
            case .calls(let id):
                if let inbox = model.inbox, let local = model.local {
                    CommsCallThreadView(threadID: id, model: inbox, local: local).tabletReadable()
                }
            case .local(let id):
                if let local = model.local {
                    CommsLocalThreadView(threadID: id, store: local).tabletReadable()
                }
            }
        }
        .task(id: callsAvailable) {
            if callsAvailable && !model.loaded { await model.refresh(api: api) }
        }
    }

    /// What the page can and cannot know, said once under the list.
    private var footnote: String {
        let texts = "Texts and emails here are drafts kept on this phone. Thorbis has not sent them."
        if !callsAvailable || model.denied { return "Your role can\u{2019}t see the call log. \(texts)" }
        return model.hasOlder
            ? "Calls come from your business\u{2019}s call log, newest 200 first. \(texts)"
            : "Calls come from your business\u{2019}s call log. \(texts)"
    }

    /// Call and Text, side by side; stacked at the largest text sizes.
    @ViewBuilder private var actions: some View {
        if let dialable, let call = URL(string: "tel:\(dialable)"), let text = URL(string: "sms:\(dialable)") {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
            layout {
                action("Call", symbol: "phone", identifier: "customer-comms-call") { openURL(call) }
                action("Text", symbol: "message", identifier: "customer-comms-text") {
                    inboxText(text, name: customerName, openURL: openURL)
                }
            }
        }
    }

    private func action(_ title: String, symbol: String, identifier: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium)).accessibilityHidden(true)
                Text(title).font(Theme.font(16, weight: .semibold))
            }
            .foregroundStyle(Theme.foreground)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.card, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(title) \(customerName)")
        .accessibilityIdentifier(identifier)
    }

    private func row(_ entry: CustomerCommsEntry) -> some View {
        let time = CustomerComms.when(entry.at)
        return Button {
            open = entry.kind == .call ? .calls(entry.threadID) : .local(entry.threadID)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: entry.symbol).font(.system(size: 14, weight: .medium))
                    .foregroundStyle(entry.attention ? Theme.destructive : Theme.foreground)
                    .frame(width: 32, height: 32)
                    .background(entry.attention ? Theme.destructiveSurface : Theme.fill, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.title).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !time.isEmpty {
                            Text(time).font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                        }
                    }
                    if let detail = entry.detail {
                        Text(detail).font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.leading)
                            .lineLimit(typeSize.isAccessibilitySize ? 6 : 3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 5)
            }
            .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(entry.kind == .call ? "Opens the calls with this number" : "Opens the conversation on this phone")
        .accessibilityIdentifier("customer-comms-row-\(entry.id)")
    }
}
