import SwiftUI

/// Read-only issued terms; selection and approval stay in the handoff.
private struct CustomerHandoffEstimateDetails: View {
    @ObservedObject var model: JobEstimateHandoffModel
    let record: EstimateRecord
    private let authority: UUID
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var revision: CustomerIssuedEstimateRevision?
    @State private var loading = false
    @State private var error: String?

    init(model: JobEstimateHandoffModel, record: EstimateRecord) {
        self.model = model
        self.record = record
        authority = model.session.authorityRevision
    }

    private var type: CustomerType { CustomerType(sizeClass) }
    private var current: Bool { model.detailsCurrent(record, authority: authority) }
    private var revisionMatches: Bool {
        guard let revision else { return false }
        return revision.matchesDetails(for: record)
    }
    private var access: DocumentDescriptionAccess {
        .init(identity: .estimate(scope: model.scope, record: record, issued: revision),
              organizationID: model.scope.organizationID, capability: "estimate.view", feature: "estimates",
              sourceGeneration: model.session.generation, fresh: current && revisionMatches,
              active: current && revisionMatches, scopeValid: current && revisionMatches)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--paper-preview-handoff-details-mutation") {
                    Button("Replace sample revision shortly") { previewChange(revise: true) }
                    Button("Remove sample estimate shortly") { previewChange(revise: false) }
                }
                #endif
                if !current {
                    CustomerStateMessage(symbol: "lock", title: "This estimate needs a refresh",
                                         message: "Hand the device back to your technician to reopen this estimate.")
                } else if let revision, revisionMatches {
                    Text(revision.title).font(Theme.customerFont(type.heading, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if let options = revision.options, !options.isEmpty {
                        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(option.title).font(Theme.customerFont(type.body, weight: .medium))
                                if !option.description.isEmpty {
                                    ReadOnlyDocumentDescription(text: option.description, fontSize: type.body, access: access,
                                                                customerFacing: true, accessibilityContext: "Estimate EST-\(record.id.suffix(4).uppercased()), package \(index + 1)")
                                }
                                lines(option.lines, currency: option.currency, total: option.totalAmount,
                                      context: "Estimate EST-\(record.id.suffix(4).uppercased()), package \(index + 1)")
                            }
                        }
                    } else {
                        lines(revision.lines, currency: revision.currency, total: revision.totalAmount,
                              context: "Estimate EST-\(record.id.suffix(4).uppercased())")
                    }
                } else if revision != nil {
                    CustomerStateMessage(symbol: "lock", title: "This estimate needs a refresh",
                                         message: "Hand the device back to your technician to reopen this estimate.")
                } else if let error {
                    CustomerProblemBanner(message: error, actionTitle: "Try again") { await load() }
                } else {
                    CustomerSkeleton(caption: "Opening the current estimate…", heading: false)
                }
            }
            .padding(Theme.gutter).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(Theme.canvas).foregroundStyle(Theme.foreground)
        .navigationTitle("EST-\(record.id.suffix(4).uppercased())")
        .accessibilityIdentifier("handoff-estimate-details")
        .task { await load() }
    }

    #if DEBUG
    private func previewChange(revise: Bool) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            if revise { JobEstimateHandoffPreview.shared.reviseFirst() }
            else { JobEstimateHandoffPreview.shared.removeFirst() }
            await model.refresh()
        }
    }
    #endif

    @ViewBuilder private func lines(_ lines: [FieldLine], currency: String, total: Int, context: String) -> some View {
        if let amounts = CustomerDocumentAmounts(lines: lines, currency: currency), amounts.total == total,
           let projected = customerEstimateProjection(lines, currency: currency) {
            CustomerIncludedLabel(type: type)
            CustomerIncludedLines(lines: projected, type: type, rows: customerAmountRows(amounts, currency: currency, invoice: false),
                                  readingAccess: access, descriptionContext: context)
        } else {
            Text("These amounts couldn't be verified. Hand the device back to your technician.")
                .font(Theme.customerFont(type.body)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func load() async {
        guard current, !loading else { return }
        loading = true; revision = nil; error = nil
        defer { loading = false }
        do {
            let issued = try await model.issuedDetails(record, authority: authority)
            guard current, !Task.isCancelled else { return }
            revision = issued
        } catch is CancellationError {} catch {
            guard current else { return }
            self.error = error.customerSentence(.openEstimate)
        }
    }
}

/// Customer-only destinations inside the existing protected customer navigation owner.
struct JobEstimateHandoffView: View {
    @ObservedObject var model: JobEstimateHandoffModel
    let handBack: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var reviewing = false
    @State private var checkpointID: String?
    @State private var detailsID: String?
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
                    Text("Hand the device back to your technician").font(Theme.customerFont(type.heading, weight: .medium))
                    Text("This workspace or your access changed. Your technician needs to unlock and reopen the job.")
                        .font(Theme.customerFont(type.body))
                    CustomerSecondaryButton(title: "Hand back to the technician", type: type, action: handBack)
                }.padding(Theme.gutter)
            }
        }
        .background(Theme.canvas).foregroundStyle(Theme.foreground)
        .navigationTitle("Estimates").navigationBarTitleDisplayMode(.inline)
        .task { await model.refresh() }
        .onChange(of: api.requestGeneration) { _, _ in
            if !model.isCurrent { detailsID = nil; checkpointID = nil; reviewing = false; model.retire() }
        }
        .onChange(of: session.authorityRevision) { _, _ in
            detailsID = nil
            if !model.isCurrent { checkpointID = nil; reviewing = false; model.retire() }
        }
        .onChange(of: model.isCurrent) { _, current in
            if !current { detailsID = nil; checkpointID = nil; reviewing = false; model.retire() }
        }
        .onChange(of: model.approvalAuthority) { _, allowed in
            if !allowed { checkpointID = nil; reviewing = false; model.cancelApprovals() }
        }
        .thorbisDestination(item: $checkpointID) { id in checkpoint(id) }
        .thorbisDestination(item: $detailsID) { id in
            if let record = model.records.first(where: { $0.id == id }) {
                CustomerHandoffEstimateDetails(model: model, record: record)
                    .id(record)
                    .toolbar { ThorbisToolbarItem(placement: .topBarTrailing, customerFacing: true) { CustomerModeOwnerUnlockButton() } }
            }
        }
    }

    private var overview: some View {
        LazyVStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.jobTitle).font(Theme.customerFont(type.body, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                Text(model.complete ? "\(model.records.count) estimate\(model.records.count == 1 ? "" : "s") · Choose any work to approve" : model.loading ? "Loading more estimates…" : "Some estimates still need a refresh")
                    .font(Theme.customerFont(type.small)).foregroundStyle(Theme.muted)
            }
            if !model.approvalAuthority {
                Text("You can review these estimates. Your current access doesn't allow approvals.").font(Theme.customerFont(type.body)).foregroundStyle(Theme.muted)
            }
            if model.hasResults { results }
            if let error = model.error { CustomerProblemBanner(message: error, actionTitle: "Try again") { await model.refresh() } }
            if model.loading {
                if model.records.isEmpty { CustomerSkeleton(caption: "Opening current job estimates…", lines: 2) }
                else { Text("Opening current job estimates…").font(Theme.customerFont(type.small)).foregroundStyle(Theme.muted) }
            }
            ForEach(model.records) { record in estimateCard(record) }
            ForEach(model.unavailableIDs, id: \.self) { id in
                VStack(alignment: .leading, spacing: 8) {
                    Text("EST-\(id.suffix(4).uppercased()) · Unavailable").font(Theme.customerFont(type.body, weight: .medium))
                    Text("Refresh to see this estimate before deciding.").font(Theme.customerFont(type.body))
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
            if model.detailsCurrent(record, authority: session.authorityRevision) {
                Button { detailsID = record.id } label: {
                    Label("View details", systemImage: "doc.text")
                        .font(Theme.customerFont(type.body, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: type.target, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Read this estimate before choosing work")
                .accessibilityIdentifier("handoff-details-\(record.id)")
            }
            if record.status == "approved" {
                Text("Already approved · no approval needed").font(Theme.customerFont(type.body)).foregroundStyle(Theme.muted)
                if let signer = model.context(for: record.id)?.approvedSignerName {
                    Text("Signed by \(signer)").font(Theme.customerFont(type.small)).foregroundStyle(Theme.muted)
                } else if (record.options ?? []).isEmpty, let signature = record.approvalSignature {
                    Text("Signed by \(signature.signerName)").font(Theme.customerFont(type.small)).foregroundStyle(Theme.muted)
                }
            } else if record.status == "draft" {
                Text("Draft · your technician needs to review and send this first.").font(Theme.customerFont(type.body)).foregroundStyle(Theme.muted)
            } else if model.eligibleIDs.contains(record.id) {
                let selected = model.selectedIDs.contains(record.id)
                if selected, !model.options(for: record.id).isEmpty {
                    Text("Choose one package for this estimate").font(Theme.customerFont(type.body))
                    ForEach(Array(model.options(for: record.id).enumerated()), id: \.element.id) { index, option in
                        VStack(alignment: .leading, spacing: 4) {
                            Button { model.chooseOption(estimateID: record.id, optionID: option.id) } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: model.selection.optionIDs[record.id] == option.id ? "largecircle.fill.circle" : "circle")
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(option.title).font(Theme.customerFont(type.body, weight: .medium))
                                        Text(money(option.totalAmount, currency: option.currency)).font(Theme.customerFont(type.body, weight: .medium)).monospacedDigit()
                                    }
                                }.frame(maxWidth: .infinity, minHeight: type.target, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            .accessibilityIdentifier("handoff-option-\(record.id)-\(option.id)")
                            if !option.description.isEmpty {
                                ReadOnlyDocumentDescription(text: option.description, fontSize: type.body,
                                                            access: selectionDescriptionAccess(for: record), customerFacing: true,
                                                            accessibilityContext: "Estimate \((model.records.firstIndex(where: { $0.id == record.id }) ?? 0) + 1), EST-\(record.id.suffix(4).uppercased()), package \(index + 1)")
                                    .padding(.leading, 36)
                            }
                        }
                    }
                }
            } else if record.status == "sent" {
                Text("This estimate needs a refresh or your technician's access before approval.")
                    .font(Theme.customerFont(type.body)).foregroundStyle(Theme.muted)
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
                Text(record.title).font(Theme.customerFont(type.body, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                CustomerStatusWord(status: record.status, type: type)
            }
            Text("EST-\(record.id.suffix(4).uppercased())").font(Theme.customerMonoFont(type.small)).foregroundStyle(Theme.muted)
            if let context = model.context(for: record.id), context.outcome?.isApproved == true,
               let action = context.acceptedAction, let accepted = action.acceptance,
               let amount = Int(exactly: accepted.totalAmount), let option = action.options?.first(where: { $0.id == accepted.optionId }) {
                Text(option.title).font(Theme.customerFont(type.small)).foregroundStyle(Theme.muted)
                Text(money(amount, currency: option.currency)).font(Theme.customerFont(type.regular ? 34 : 28, weight: .medium)).monospacedDigit()
            } else if let revision = model.revision(for: record.id), (revision.options ?? []).isEmpty {
                Text(money(revision.totalAmount, currency: revision.currency)).font(Theme.customerFont(type.regular ? 34 : 28, weight: .medium)).monospacedDigit()
            } else if (record.options ?? []).isEmpty, let currency = record.lines.first?.unitPrice.currency,
                      let amounts = CustomerDocumentAmounts(lines: record.lines, currency: currency) {
                Text(money(amounts.total, currency: currency)).font(Theme.customerFont(type.regular ? 34 : 28, weight: .medium)).monospacedDigit()
            } else if (record.options ?? []).isEmpty {
                Text("Price needs current terms").font(Theme.customerFont(type.small)).foregroundStyle(Theme.muted)
            } else if record.status == "approved" {
                Text("Accepted package needs verification").font(Theme.customerFont(type.small)).foregroundStyle(Theme.muted)
            } else {
                Text("Choose a package").font(Theme.customerFont(type.small)).foregroundStyle(Theme.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(Theme.foreground)
    }

    private var selectedReview: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Review selected work").font(Theme.customerFont(type.heading, weight: .medium)).accessibilityAddTraits(.isHeader)
            Text("\(model.reviewed.count) separate estimates. You'll approve and sign each one.")
                .font(Theme.customerFont(type.body)).foregroundStyle(Theme.muted)
            ForEach(Array(model.reviewed.enumerated()), id: \.element.id) { index, item in
                let reference = "Estimate \(index + 1), EST-\(item.id.suffix(4).uppercased())"
                let option = item.revision.options?.first(where: { $0.id == item.optionID })
                Text(item.revision.title).font(Theme.customerFont(type.heading, weight: .medium))
                Text("EST-\(item.id.suffix(4).uppercased()) · Revision \(item.revision.revisionNumber)").font(Theme.customerMonoFont(type.small)).foregroundStyle(Theme.muted)
                if model.contexts[item.key]?.outcome == .unknown { Text("Approval needs confirmation").font(Theme.customerFont(type.body)) }
                else if model.contexts[item.key]?.outcome?.isApproved == true { Text("Approved").font(Theme.customerFont(type.body)) }
                if let option {
                    Text(option.title).font(Theme.customerFont(type.body, weight: .medium))
                    if !option.description.isEmpty {
                        ReadOnlyDocumentDescription(text: option.description, fontSize: type.body,
                                                    access: descriptionAccess(for: item), customerFacing: true,
                                                    accessibilityContext: "\(reference), package \((item.revision.options?.firstIndex(where: { $0.id == option.id }) ?? 0) + 1)")
                    }
                }
                let lines = option?.lines ?? item.revision.lines, currency = option?.currency ?? item.revision.currency
                if let amounts = CustomerDocumentAmounts(lines: lines, currency: currency),
                   let projected = customerEstimateProjection(lines, currency: currency) {
                    CustomerIncludedLabel(type: type)
                    CustomerIncludedLines(lines: projected, type: type,
                                          rows: customerAmountRows(amounts, currency: currency, invoice: false),
                                          readingAccess: descriptionAccess(for: item),
                                          descriptionContext: reference)
                } else {
                    Text("These amounts couldn't be verified. Hand the device back to your technician.")
                        .font(Theme.customerFont(type.body))
                }
            }
            ForEach(selectedTotals, id: \.currency) { value in
                Text("Selected work · \(money(value.amount, currency: value.currency)) \(value.currency)")
                    .font(Theme.customerFont(type.body, weight: .medium))
            }
            Text("These estimates stay separate and do not become one bill.").font(Theme.customerFont(type.small)).foregroundStyle(Theme.muted)
        }
    }
    private func selectionDescriptionAccess(for record: EstimateRecord) -> DocumentDescriptionAccess {
        .init(identity: .estimate(scope: model.scope, record: record, issued: model.revision(for: record.id)),
              organizationID: model.scope.organizationID, capability: "estimate.view", feature: "estimates",
              sourceGeneration: model.session.generation, fresh: model.complete && model.isCurrent,
              active: !reviewing && model.isCurrent && model.selectedIDs.contains(record.id),
              scopeValid: model.eligibleIDs.contains(record.id) && model.scope.contains(record, requestedID: record.id))
    }

    private func descriptionAccess(for item: JobEstimateReviewedItem) -> DocumentDescriptionAccess {
        .init(identity: .estimate(scope: model.scope, record: item.estimate, issued: item.revision),
              organizationID: model.scope.organizationID, capability: "estimate.view", feature: "estimates",
              sourceGeneration: model.session.generation, fresh: model.complete && model.isCurrent,
              active: reviewing && model.isCurrent,
              scopeValid: model.reviewed.contains(item) && model.scope.contains(item.estimate, requestedID: item.id)
                  && item.revision.estimateId == item.id && item.revision.revisionNumber == item.estimate.currentRevisionNumber)
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
            Text("Approval progress").font(Theme.customerFont(type.heading, weight: .medium))
            Text("\(model.approvedCount) approved\(model.unknownCount > 0 ? " · \(model.unknownCount) needs confirmation" : "")")
                .font(Theme.customerFont(type.body)).accessibilityIdentifier("handoff-results-summary")
            ForEach(model.resultContexts.filter { $0.outcome?.isApproved != true }) { context in
                VStack(alignment: .leading, spacing: 8) {
                    Text("EST-\(context.reviewed.id.suffix(4).uppercased()) · \(context.reviewed.revision.title)").font(Theme.customerFont(type.body, weight: .medium))
                    if context.running { ProgressView("Confirming this estimate…") }
                    else if case .approved? = context.outcome { Label("Approved", systemImage: "checkmark.circle") }
                    else if case .unknown? = context.outcome {
                        Text("Outcome unknown · check before trying again.").font(Theme.customerFont(type.body))
                        Button("Check approval") { Task { await model.reconcile(context.id) } }.frame(minHeight: type.target)
                        if context.retryVerified {
                            Button("Retry exact approval") { checkpointID = context.id }.frame(minHeight: type.target)
                        }
                    } else if case .retryable(let reason)? = context.outcome {
                        Text(reason).font(Theme.customerFont(type.body))
                        Button("Try again") { checkpointID = context.id }.frame(minHeight: type.target).disabled(!context.canApprove())
                    } else if case .needsReview(let reason)? = context.outcome {
                        Text(reason).font(Theme.customerFont(type.body)).fixedSize(horizontal: false, vertical: true)
                    }
                }.font(Theme.customerFont(type.body))
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
                    Text("Check unconfirmed approvals before trying again.").font(Theme.customerFont(type.small)).foregroundStyle(Theme.muted)
                } else {
                    Text("No further signatures are available for this selection.").font(Theme.customerFont(type.small)).foregroundStyle(Theme.muted)
                }
                CustomerSecondaryButton(title: "Back to estimates", type: type) { reviewing = false }
            } else {
                CustomerPresentationCommit(title: "Review selected (\(model.selectedIDs.count))", enabled: model.canReview, busy: model.loading, type: type) {
                    Task { await model.reviewSelected(); if !model.reviewed.isEmpty { reviewing = true } }
                }
                .accessibilityIdentifier("handoff-review-selected")
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, 12).background(Theme.canvas)
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
                currentAuthority: { context.current() && context.canApprove() },
                onApproved: { _ in }, onDone: {
                    if let next = nextPending(after: id) { checkpointID = next }
                    else { checkpointID = nil; reviewing = false }
                })
                .id(context.id)
                .navigationTitle("EST-\(item.id.suffix(4).uppercased())")
                .toolbar { ThorbisToolbarItem(placement: .topBarTrailing) { CustomerModeOwnerUnlockButton() } }
        } else {
            Text("Return to your estimates and refresh before deciding.").font(Theme.customerFont(type.body)).padding(Theme.gutter)
        }
    }
}

/// Customer view's one protected owner. It survives App's real session-generation and
/// authentication branch replacement, and gives the whole handoff one staff hand-back.
struct JobEstimateProtectedOwner: View {
    @ObservedObject var model: JobEstimateHandoffModel
    @ObservedObject var presenter: JobEstimateHandoffPresenter
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var api: APIClient
    /// Set after the technician unlocked while the customer's details have changes to review.
    @State private var reviewingDetails: CustomerViewExit?
    var body: some View {
        Group {
            if let exit = reviewingDetails, let details = presenter.details, model.isCurrentJob,
               session.can("customer.edit", feature: "core_crm") {
                // Staff side, after authentication: the existing review and audited save.
                CustomerSelfEditReview(model: details, currentAuthority: {
                    presenter.active === model && model.isCurrentJob && session.can("customer.edit", feature: "core_crm")
                }) { presenter.authenticatedExit(from: model, exit) }
            } else {
                CustomerModeContainer(onUnlocked: { leave(.done) }, ownerControlTitle: "Hand back", authenticateOwner: authenticateOwner) { handBack in
                    JobCustomerDocumentsView(scope: model.scope, documents: model.documents, sourceGeneration: presenter.sourceGeneration,
                        jobTitle: model.jobTitle, customerName: model.customerName, handBack: handBack,
                        onUnlocked: { leave(.done) },
                        requestPayment: { leave(.collect(invoiceID: $0)) },
                        invoiceUpdated: presenter.invoiceUpdated, authenticateOwner: documentAuthentication,
                        handoff: model, details: presenter.details, start: presenter.start)
                }
            }
        }
        .onChange(of: model.isCurrentJob) { _, valid in if !valid { model.retire() } }
        .onChange(of: model.approvalAuthority) { _, valid in if !valid { model.cancelApprovals() } }
    }
    /// Only the authenticated technician leaves; changed details are reviewed before staff screens return.
    private func leave(_ exit: CustomerViewExit) {
        if model.isCurrentJob, presenter.details?.hasChanges == true, session.can("customer.edit", feature: "core_crm") {
            reviewingDetails = exit
        } else {
            presenter.authenticatedExit(from: model, exit)
        }
    }
    private func authenticateOwner() async -> Bool {
        #if DEBUG
        if let authenticate = PaperPreview.ownerAuthentication { return await authenticate("Unlock to leave customer mode") }
        #endif
        return await StaffUnlock.unlock()
    }
    private var documentAuthentication: @MainActor (String) async -> Bool {
        #if DEBUG
        if let preview = PaperPreview.ownerAuthentication { return preview }
        #endif
        return { await StaffUnlock.unlock(reason: $0) }
    }
}
