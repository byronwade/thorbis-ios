import SwiftUI

/// Customer-only destinations inside the existing protected customer navigation owner.
struct JobEstimateHandoffView: View {
    @ObservedObject var model: JobEstimateHandoffModel
    let handBack: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var reviewing = false
    @State private var checkpointID: String?
    private var type: CustomerType { CustomerType(sizeClass) }

    var body: some View {
        Group {
            if model.isCurrent {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if reviewing { selectedReview } else { overview }
                    }
                    .padding(Theme.gutter).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("job-estimate-handoff")
                .safeAreaInset(edge: .bottom) { footer }
            } else {
                VStack(spacing: 20) {
                    Text("Hand the device back to your technician").font(Theme.font(type.heading, weight: .medium))
                    Text("This workspace or your access changed. Your technician needs to unlock and reopen the job.")
                        .font(Theme.font(type.body))
                    CustomerSecondaryButton(title: "Hand back to the technician", type: type, action: handBack)
                }.padding(Theme.gutter)
            }
        }
        .background(Theme.background).foregroundStyle(Theme.foreground)
        .navigationTitle("Estimates").navigationBarTitleDisplayMode(.inline)
        .task { await model.refresh() }
        .onChange(of: model.isCurrent) { _, current in
            if !current { checkpointID = nil; reviewing = false; model.retire() }
        }
        .onChange(of: model.approvalAuthority) { _, allowed in
            if !allowed { checkpointID = nil; reviewing = false; model.cancelApprovals() }
        }
        .navigationDestination(item: $checkpointID) { id in checkpoint(id) }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.jobTitle).font(Theme.font(type.body, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                Text(model.complete ? "\(model.records.count) estimates · Choose any work to approve" : "Some estimates still need a refresh")
                    .font(Theme.font(type.small)).foregroundStyle(Theme.muted)
            }
            if !model.approvalAuthority {
                Text("You can review these estimates. Your current access doesn't allow approvals.").font(Theme.font(type.body)).foregroundStyle(Theme.muted)
            }
            if model.hasResults { results }
            if let error = model.error { ErrorBanner(message: error) { await model.refresh() } }
            if model.loading { ProgressView("Opening current job estimates…").font(Theme.font(type.body)) }
            ForEach(model.records) { record in estimateCard(record) }
            ForEach(model.unavailableIDs, id: \.self) { id in
                VStack(alignment: .leading, spacing: 8) {
                    Text("EST-\(id.suffix(4).uppercased()) · Unavailable").font(Theme.font(type.body, weight: .medium))
                    Text("Refresh to see this estimate before deciding.").font(Theme.font(type.body))
                }
            }
        }
    }

    private func estimateCard(_ record: EstimateRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.eligibleIDs.contains(record.id) {
                let selected = model.selectedIDs.contains(record.id)
                Button { model.setSelected(record.id, selected: !selected) } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 25)).foregroundStyle(selected ? Theme.brandText : Theme.muted)
                            .frame(width: 30).frame(minHeight: 56)
                        estimateSummary(record)
                    }.frame(maxWidth: .infinity, minHeight: type.target, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(selected ? "Deselect" : "Select") \(record.title), EST-\(record.id.suffix(4).uppercased())")
                .accessibilityValue(selectionValue(record))
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityIdentifier("handoff-select-\(record.id)")
            } else { estimateSummary(record) }
            if record.status == "approved" {
                Text("Already approved · no approval needed").font(Theme.font(type.body)).foregroundStyle(Theme.muted)
                if let signer = model.context(for: record.id)?.approvedSignerName {
                    Text("Signed by \(signer)").font(Theme.font(type.small)).foregroundStyle(Theme.muted)
                } else if (record.options ?? []).isEmpty, let signature = record.approvalSignature {
                    Text("Signed by \(signature.signerName)").font(Theme.font(type.small)).foregroundStyle(Theme.muted)
                }
            } else if record.status == "draft" {
                Text("Draft · your technician needs to review and send this first.").font(Theme.font(type.body)).foregroundStyle(Theme.muted)
            } else if model.eligibleIDs.contains(record.id) {
                let selected = model.selectedIDs.contains(record.id)
                if selected, !model.options(for: record.id).isEmpty {
                    Text("Choose one package for this estimate").font(Theme.font(type.body))
                    ForEach(model.options(for: record.id)) { option in
                        Button { model.chooseOption(estimateID: record.id, optionID: option.id) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: model.selection.optionIDs[record.id] == option.id ? "largecircle.fill.circle" : "circle")
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(option.title).font(Theme.font(type.body, weight: .medium))
                                    if !option.description.isEmpty { Text(option.description).font(Theme.font(type.small)) }
                                    Text(money(option.totalAmount, currency: option.currency)).font(Theme.monoFont(type.body, weight: .medium))
                                }
                            }.frame(maxWidth: .infinity, minHeight: type.target, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .accessibilityIdentifier("handoff-option-\(record.id)-\(option.id)")
                    }
                }
            } else if record.status == "sent" {
                Text("This estimate needs a refresh or your technician's access before approval.")
                    .font(Theme.font(type.body)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func selectionValue(_ record: EstimateRecord) -> String {
        let state = model.selectedIDs.contains(record.id) ? "Selected" : "Not selected"
        let price: String
        if let option = model.options(for: record.id).first(where: { $0.id == model.selection.optionIDs[record.id] }) {
            price = "\(option.title), \(money(option.totalAmount, currency: option.currency))"
        } else if let revision = model.revision(for: record.id), (revision.options ?? []).isEmpty {
            price = money(revision.totalAmount, currency: revision.currency)
        } else if (record.options ?? []).isEmpty, let currency = record.lines.first?.unitPrice.currency,
                  let amounts = CustomerDocumentAmounts(lines: record.lines, currency: currency) {
            price = money(amounts.total, currency: currency)
        } else {
            price = (record.options ?? []).isEmpty ? "Price needs current terms" : "Choose a package"
        }
        return "\(state), \(record.status.capitalized), \(price)"
    }

    private func estimateSummary(_ record: EstimateRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(record.title).font(Theme.font(type.body, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                PaperStatusChip(status: record.status)
            }
            Text("EST-\(record.id.suffix(4).uppercased())").font(Theme.monoFont(type.small)).foregroundStyle(Theme.muted)
            if let context = model.context(for: record.id), context.outcome?.isApproved == true,
               let action = context.acceptedAction, let accepted = action.acceptance,
               let amount = Int(exactly: accepted.totalAmount), let option = action.options?.first(where: { $0.id == accepted.optionId }) {
                Text(option.title).font(Theme.font(type.small)).foregroundStyle(Theme.muted)
                Text(money(amount, currency: option.currency)).font(Theme.monoFont(type.regular ? 34 : 28, weight: .medium))
            } else if let revision = model.revision(for: record.id), (revision.options ?? []).isEmpty {
                Text(money(revision.totalAmount, currency: revision.currency)).font(Theme.monoFont(type.regular ? 34 : 28, weight: .medium))
            } else if (record.options ?? []).isEmpty, let currency = record.lines.first?.unitPrice.currency,
                      let amounts = CustomerDocumentAmounts(lines: record.lines, currency: currency) {
                Text(money(amounts.total, currency: currency)).font(Theme.monoFont(type.regular ? 34 : 28, weight: .medium))
            } else if (record.options ?? []).isEmpty {
                Text("Price needs current terms").font(Theme.font(type.small)).foregroundStyle(Theme.muted)
            } else if record.status == "approved" {
                Text("Accepted package needs verification").font(Theme.font(type.small)).foregroundStyle(Theme.muted)
            } else {
                Text("Choose a package").font(Theme.font(type.small)).foregroundStyle(Theme.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(Theme.foreground)
    }

    private var selectedReview: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Review selected work").font(Theme.font(type.heading, weight: .medium)).accessibilityAddTraits(.isHeader)
            Text("\(model.reviewed.count) separate estimates. You'll approve and sign each one.")
                .font(Theme.font(type.body)).foregroundStyle(Theme.muted)
            ForEach(model.reviewed) { item in
                let option = item.revision.options?.first(where: { $0.id == item.optionID })
                Text(item.revision.title).font(Theme.font(type.heading, weight: .medium))
                Text("EST-\(item.id.suffix(4).uppercased()) · Revision \(item.revision.revisionNumber)").font(Theme.monoFont(type.small)).foregroundStyle(Theme.muted)
                if model.contexts[item.key]?.outcome == .unknown { Text("Approval needs confirmation").font(Theme.font(type.body)) }
                else if model.contexts[item.key]?.outcome?.isApproved == true { Text("Approved").font(Theme.font(type.body)) }
                if let option { Text(option.title).font(Theme.font(type.body, weight: .medium)) }
                let lines = option?.lines ?? item.revision.lines, currency = option?.currency ?? item.revision.currency
                if let amounts = CustomerDocumentAmounts(lines: lines, currency: currency) {
                    CustomerLinesCard(lines: lines, currency: currency, type: type,
                        rows: customerAmountRows(amounts, currency: currency, invoice: false))
                }
            }
            ForEach(selectedTotals, id: \.currency) { value in
                Text("Selected work · \(money(value.amount, currency: value.currency)) \(value.currency)")
                    .font(Theme.font(type.body, weight: .medium))
            }
            Text("These estimates stay separate and do not become one bill.").font(Theme.font(type.small)).foregroundStyle(Theme.muted)
        }
    }
    private var selectedTotals: [(currency: String, amount: Int)] {
        var values: [String: Int] = [:]
        for item in model.reviewed {
            let option = item.revision.options?.first(where: { $0.id == item.optionID })
            let currency = option?.currency ?? item.revision.currency
            let sum = (values[currency] ?? 0).addingReportingOverflow(option?.totalAmount ?? item.revision.totalAmount)
            guard !sum.overflow else { return [] }
            values[currency] = sum.partialValue
        }
        return values.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
    private var results: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Approval progress").font(Theme.font(type.heading, weight: .medium))
            Text("\(model.approvedCount) approved\(model.unknownCount > 0 ? " · \(model.unknownCount) needs confirmation" : "")")
                .font(Theme.font(type.body)).accessibilityIdentifier("handoff-results-summary")
            ForEach(model.resultContexts.filter { $0.outcome?.isApproved != true }) { context in
                VStack(alignment: .leading, spacing: 8) {
                    Text("EST-\(context.reviewed.id.suffix(4).uppercased()) · \(context.reviewed.revision.title)").font(Theme.font(type.body, weight: .medium))
                    if context.running { ProgressView("Confirming this estimate…") }
                    else if case .approved? = context.outcome { Label("Approved", systemImage: "checkmark.circle") }
                    else if case .unknown? = context.outcome {
                        Text("Outcome unknown · check before trying again.").font(Theme.font(type.body))
                        Button("Check approval") { Task { await model.reconcile(context.id) } }.frame(minHeight: type.target)
                        if context.retryVerified {
                            Button("Retry exact approval") { checkpointID = context.id }.frame(minHeight: type.target)
                        }
                    } else if case .retryable(let reason)? = context.outcome {
                        Text(reason).font(Theme.font(type.body))
                        Button("Try again") { checkpointID = context.id }.frame(minHeight: type.target).disabled(!context.canApprove())
                    } else if case .needsReview(let reason)? = context.outcome {
                        Text(reason).font(Theme.font(type.body)).fixedSize(horizontal: false, vertical: true)
                    }
                }.font(Theme.font(type.body))
            }
            if let next = nextPending(after: nil) {
                CustomerSecondaryButton(title: "Continue selected approvals", type: type) { checkpointID = next }
            }
        }
    }
    @ViewBuilder private var footer: some View {
        if reviewing || !model.complete || !model.eligibleIDs.isEmpty {
        VStack(spacing: 8) {
            if reviewing {
                if let next = nextPending(after: nil) {
                    CustomerPresentationCommit(title: "Continue to signatures", enabled: true, busy: false, type: type) { checkpointID = next }
                        .accessibilityIdentifier("handoff-continue-signatures")
                } else if model.unknownCount > 0 {
                    Text("Check unconfirmed approvals before trying again.").font(Theme.font(type.small)).foregroundStyle(Theme.muted)
                } else {
                    Text("No further signatures are available for this selection.").font(Theme.font(type.small)).foregroundStyle(Theme.muted)
                }
                CustomerSecondaryButton(title: "Back to estimates", type: type) { reviewing = false }
            } else {
                CustomerPresentationCommit(title: "Review selected (\(model.selectedIDs.count))", enabled: model.canReview, busy: model.loading, type: type) {
                    Task { await model.reviewSelected(); if !model.reviewed.isEmpty { reviewing = true } }
                }
                .accessibilityIdentifier("handoff-review-selected")
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, 12).background(Theme.background)
        }
    }
    private func nextPending(after current: String?) -> String? {
        model.reviewed.first { item in
            item.key != current && model.contexts[item.key]?.outcome == nil && model.contexts[item.key]?.running != true && model.contexts[item.key]?.canApprove() == true
        }?.key
    }
    @ViewBuilder private func checkpoint(_ id: String) -> some View {
        if let context = model.checkpointContext(for: id), model.isCurrent {
            let item = context.reviewed
            let destination = $checkpointID, review = $reviewing
            let _ = context.configureNavigation(back: { destination.wrappedValue = nil; review.wrappedValue = true })
            let _ = { context.continueTitle = nextPending(after: id) == nil ? "See approvals" : "Next estimate" }()
            CustomerEstimatePresentation(estimate: item.estimate, jobID: model.scope.jobID, customerName: model.customerName,
                preselectedOptionID: item.optionID, handoff: context,
                onApproved: { _ in }, onDone: {
                    if let next = nextPending(after: id) { checkpointID = next }
                    else { checkpointID = nil; reviewing = false }
                })
                .id(context.id)
                .navigationTitle("EST-\(item.id.suffix(4).uppercased())")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { CustomerModeOwnerUnlockButton() } }
        } else {
            Text("Return to your estimates and refresh before deciding.").font(Theme.font(type.body)).padding(Theme.gutter)
        }
    }
}

/// This owner survives App's real session-generation and authentication branch replacement.
struct JobEstimateProtectedOwner: View {
    @ObservedObject var model: JobEstimateHandoffModel
    @ObservedObject var presenter: JobEstimateHandoffPresenter
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var api: APIClient
    var body: some View {
        CustomerModeContainer(onUnlocked: { presenter.authenticatedExit() }, ownerControlTitle: "Hand back", authenticateOwner: authenticateOwner) { handBack in
            JobEstimateHandoffView(model: model, handBack: handBack)
        }
        .onChange(of: model.isCurrent) { _, valid in if !valid { model.retire() } }
        .onChange(of: model.approvalAuthority) { _, valid in if !valid { model.cancelApprovals() } }
    }
    private func authenticateOwner() async -> Bool {
        #if DEBUG
        if let authenticate = PaperPreview.ownerAuthentication { return await authenticate("Unlock to leave customer mode") }
        #endif
        return await StaffUnlock.unlock()
    }
}
