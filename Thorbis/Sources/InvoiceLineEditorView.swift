import SwiftUI

struct InvoiceLineEditorView: View {
    let invoice: InvoiceRecord
    let onSaved: (InvoiceRecord) -> Void

    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var editor: InvoiceLineEditorState
    @State private var persistenceBaseline: InvoiceLineEditorState
    @State private var showPriceBook = false
    @State private var confirmReload = false
    @State private var confirmVerifiedReload = false
    @State private var pendingReload: InvoiceRecord?
    @State private var pendingReloadScope: EstimateCreationScope?
    @State private var pendingReloadAttempt: UUID?
    #if DEBUG
    @State private var simulatedConfirmationInterruption = false
    @State private var sampleFinalReadResult = "idle"
    @State private var sampleNetworkState = "online"
    @State private var samplePermissionState = "allowed"
    #endif
    @State private var confirmIssue = false
    @State private var confirmDiscard = false
    @State private var busy = false
    @State private var error: String?
    @State private var originalScope: EstimateCreationScope?
    @State private var scopeCaptured = false
    @State private var recoveryBlocked = false
    @State private var draftOwner = UUID()
    @State private var ownsDraft = false
    @State private var viewVisible = false
    @State private var didRestoreDraft = false
    @State private var didRecoverDraft = false
    @State private var wroteFreshDraft = false
    @State private var verifiedScope: EstimateCreationScope?
    @State private var accessAttempt = UUID()
    @State private var intentionallyDiscarded = false
    @State private var cleanupFailedAfterSave = false
    @State private var staleRevision = false
    @ObservedObject private var catalog = PriceBookCatalog.shared
    @State private var addedLineSelection: InvoiceCatalogLineSelection?
    @State private var expandedLine: UUID?
    @FocusState private var focus: EstimateBuilderFocus?

    private var catalogContext: PriceBookCatalogContext {
        .init(organizationID: session.activeOrganization?.id, sessionGeneration: session.generation, authority: session.priceBookAuthority)
    }

    private var currentScope: EstimateCreationScope? {
        guard session.phase == .ready, let actor = session.user?.id,
              let org = session.activeOrganization?.id, org == invoice.organizationId,
              let origin = api.normalizedOrigin else { return nil }
        return .init(actorID: actor, organizationID: org, sessionGeneration: session.generation,
                     authorityRevision: session.authorityRevision, requestGeneration: api.requestGeneration, origin: origin)
    }
    private var scopeMatches: Bool {
        guard let originalScope, let currentScope else { return false }
        return originalScope.sameIdentityAndTransport(as: currentScope)
    }
    private var resourceAuthorized: Bool {
        guard let currentScope else { return false }
        return (!didRecoverDraft || !session.isOffline) && scopeMatches && verifiedScope == currentScope && !recoveryBlocked
    }
    private struct DraftAccessKey: Equatable {
        let scope: EstimateCreationScope?
        let ownsDraft: Bool
        let offline: Bool
    }
    private var draftAccessKey: DraftAccessKey { .init(scope: currentScope, ownsDraft: ownsDraft, offline: session.isOffline) }
    private var draftScope: CommercialDraftScope? {
        guard let originalScope else { return nil }
        return .init(actor: originalScope.actorID, organization: originalScope.organizationID,
                     origin: originalScope.origin, kind: "invoice-lines", document: invoice.id)
    }
    private func restoreDraft() {
        guard scopeMatches, session.can("invoice.edit", feature: "invoicing"), let draftScope else { return }
        do {
            guard let draft = try CommercialDraftStore.shared.load(CommercialInvoiceDraft.self, scope: draftScope) else { return }
            didRecoverDraft = true
            do { try draft.apply(to: &editor) }
            catch CommercialDraftRecoveryError.differentRevision {
                recoveryBlocked = true
                error = CommercialDraftRecoveryError.differentRevision.localizedDescription
            }
        } catch { recoveryBlocked = true; self.error = "Your saved draft could not be opened. It is still on this phone." }
    }
    private func verifyDraftAccess() async {
        guard !Task.isCancelled else { return }
        accessAttempt = UUID()
        invalidatePendingReload()
        guard viewVisible, ownsDraft, scopeMatches, let expected = currentScope,
              session.can("invoice.edit", feature: "invoicing") else { return }
        if !didRecoverDraft && verifiedScope == expected { return }
        guard !session.isOffline else { return }
        #if DEBUG
        if didRecoverDraft && EstimateRecoveryPreview.invoiceVerificationHeldEnabled { EstimateRecoveryPreview.shared.armFirstInvoiceVerification() }
        #endif
        let attempt = UUID(); accessAttempt = attempt
        var latestRecord: InvoiceRecord?
        let allowed = await CommercialDraftAccess.verify(expectedScope: expected, currentScope: { session.isOffline ? nil : currentScope },
            read: { try await api.fieldInvoice(invoice.id, requireFresh: true) }, matches: { latest in
                latestRecord = latest
                return latest.id == invoice.id && latest.organizationId == expected.organizationID
            })
        guard !Task.isCancelled, viewVisible, accessAttempt == attempt, !session.isOffline, currentScope == expected else { return }
        guard allowed else {
            verifiedScope = nil
            error = "Could not verify access or the document changed. Your draft is still on this phone."
            return
        }
        if error == "Could not verify access or the document changed. Your draft is still on this phone." { error = nil }
        verifiedScope = expected
        guard let latest = latestRecord, latest.linesRevision == editor.invoice.linesRevision && latest.status == editor.invoice.status else {
            recoveryBlocked = true
            staleRevision = true
            error = CommercialDraftRecoveryError.differentRevision.localizedDescription
            return
        }
        if !didRestoreDraft { didRestoreDraft = true; restoreDraft() }
        if recoveryBlocked { staleRevision = true }
    }
    private var hasRawDraftChanges: Bool {
        if editor.hasChanges { return true }
        let baseline = persistenceBaseline
        guard editor.lines.count == baseline.lines.count else { return true }
        return zip(editor.lines, baseline.lines).contains { a, b in
            a.description != b.description || a.quantity != b.quantity || a.unitPrice != b.unitPrice
        }
    }
    private func persistDraft(leavingOriginalScope: Bool = false) {
        guard !intentionallyDiscarded, ownsDraft, didRestoreDraft, (scopeMatches || leavingOriginalScope), !recoveryBlocked, let draftScope else { return }
        if !didRecoverDraft && !hasRawDraftChanges {
            guard wroteFreshDraft else { return }
            do { try CommercialDraftStore.shared.remove(scope: draftScope); wroteFreshDraft = false }
            catch { self.error = "The undone draft could not be removed from this phone. Try again before closing." }
            return
        }
        do { try CommercialDraftStore.shared.save(CommercialInvoiceDraft(state: editor), scope: draftScope); if !didRecoverDraft { wroteFreshDraft = true } }
        catch { self.error = "This draft could not be saved on this phone. Keep this screen open and try again." }
    }
    private func discardDraft() {
        guard ownsDraft, scopeMatches, let draftScope else { dismiss(); return }
        do { try CommercialDraftStore.shared.remove(scope: draftScope); intentionallyDiscarded = true; dismiss() }
        catch { self.error = "The saved draft could not be removed. Try again." }
    }

    init(invoice: InvoiceRecord, onSaved: @escaping (InvoiceRecord) -> Void) {
        self.invoice = invoice
        self.onSaved = onSaved
        _editor = State(initialValue: InvoiceLineEditorState(invoice: invoice))
        _persistenceBaseline = State(initialValue: InvoiceLineEditorState(invoice: invoice))
    }

    private var canEdit: Bool {
        resourceAuthorized && ownsDraft && !cleanupFailedAfterSave && editor.invoice.status == "draft" && session.can("invoice.edit", feature: "invoicing")
    }

    private var canUsePriceBook: Bool {
        session.can("pricebook.view", feature: "price_book") && invoice.currency == "USD"
    }

    private var canIssue: Bool {
        resourceAuthorized && ownsDraft && !cleanupFailedAfterSave && editor.invoice.status == "draft" && session.can("invoice.issue", feature: "invoicing")
    }

    private var linesDisabled: Bool { busy || !canEdit || editor.hasUnsupportedLineSources }

    var body: some View {
        editorBase
        .discardChangesGuard(hasChanges: hasRawDraftChanges || didRecoverDraft || wroteFreshDraft || recoveryBlocked, busy: busy, isPresented: $confirmDiscard) { discardDraft() }
        .onChange(of: editor) { _, _ in persistDraft() }
        .onChange(of: scopeMatches) { wasMatching, matches in
            if !matches {
                if wasMatching { persistDraft(leavingOriginalScope: true) }
                showPriceBook = false; addedLineSelection = nil; focus = nil
            }
        }
        .onChange(of: session.can("invoice.edit", feature: "invoicing")) { _, allowed in
            if !allowed { showPriceBook = false; addedLineSelection = nil; focus = nil }
        }
        .safeAreaInset(edge: .bottom) { if resourceAuthorized && session.can("invoice.edit", feature: "invoicing") { invoiceCommitActions } }
        .thorbisConfirm("Issue invoice?",
                        message: "The current lines will be saved first if needed, then locked as issued invoice paper.",
                        isPresented: $confirmIssue,
                        actions: [ThorbisConfirmAction("Issue invoice", role: .destructive) { Task { await issue() } }])
        .sheet(isPresented: $showPriceBook, onDismiss: openAddedLine) { SheetSurface {
            PriceBookCartPicker(
                destination: "INV-\(invoice.id.suffix(4).uppercased())",
                canUsePriceBook: canUsePriceBook,
                unavailableReason: invoice.currency == "USD" ? nil : "Catalog selection requires a USD invoice.",
                searchIdentifier: "invoice-catalog-search",
                quantityInDraft: { editor.quantity(ofPriceBookItem: $0) },
                secondaryPriceText: { memberPricing?.secondaryPriceText($0) },
                addItem: addCatalogItem,
                addCustomLine: addCustomLine,
                refresh: { await refreshCatalog(force: $0) }
            )
            .environmentObject(session).environmentObject(api)
                .opacity(resourceAuthorized ? 1 : 0)
                .accessibilityHidden(!resourceAuthorized)
                .allowsHitTesting(resourceAuthorized)
                .overlay { if !resourceAuthorized { ContentUnavailableView("Checking access", systemImage: "lock") } }
        } }
        .task(id: "\(catalogContext.organizationID ?? "")|\(catalogContext.sessionGeneration)|\(invoice.customerId)") {
            memberPricing = nil
            guard canUsePriceBook else { return }
            let expected = catalogContext
            let pricing = try? await api.memberPricing(invoice.customerId)
            guard !Task.isCancelled, catalogContext == expected else { return }
            memberPricing = pricing
        }
        .thorbisConfirm("Reload the latest invoice?",
                        message: "The invoice changed on the server. Reloading replaces this form with the latest saved lines.",
                        isPresented: $confirmReload,
                        actions: [ThorbisConfirmAction("Check latest before discarding") { Task { await verifyPendingReload() } }])
        .thorbisConfirm("Discard saved draft?",
                        message: "The latest document was checked. Discard the saved draft and open it?",
                        isPresented: $confirmVerifiedReload,
                        actions: [ThorbisConfirmAction("Discard draft and reload", role: .destructive) { applyPendingReload() }])
        #if DEBUG
        .task {
            if PaperPreview.enabled, PaperPreview.screen == "invoice-editor-line" { expandedLine = editor.lines.first?.id }
        }
        #endif
    }

    private var editorScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if !resourceAuthorized || !session.can("invoice.edit", feature: "invoicing") {
                    VStack {
                                ContentUnavailableView("Document unavailable", systemImage: "lock", description: Text(
                                    error == "The draft could not be cleared or the latest document could not be verified. Your draft is still on this phone."
                                    ? "The draft could not be cleared or the latest document could not be verified. Your draft is still on this phone."
                                    : "Connect to verify access to this document. Your draft stays on this phone."))
                                if recoveryBlocked && verifiedScope == currentScope && scopeMatches && staleRevision {
                                    Button("Review latest and discard draft") { Task { await reloadLatest() } }
                                        .buttonStyle(.bordered)
                                } else if scopeMatches && ownsDraft {
                                    Button("Try again") { Task { await verifyDraftAccess() } }
                                        .buttonStyle(.bordered)
                                }
                            }
                } else { content }
            }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focus) { _, value in
                    guard let id = value?.lineID else { return }
                    expandedLine = id
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
                .onChange(of: expandedLine) { _, id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
        }
    }

    private var editorDecorated: some View {
        editorScroll
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .navigationTitle("Edit invoice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            #if DEBUG
            if EstimateRecoveryPreview.invoiceVerificationHeldEnabled {
                ThorbisToolbarItem(placement: .principal) {
                    HStack {
                        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                            Text("Reads")
                                .accessibilityIdentifier("invoice-verification-requests")
                                .accessibilityValue("\(EstimateRecoveryPreview.shared.invoiceVerificationReadCount):\(EstimateRecoveryPreview.shared.reloadHoldState)")
                        }
                        Button("Refresh") { Task { await session.revalidate() } }
                            .accessibilityIdentifier("invoice-verification-refresh")
                        Button("Access") {
                            PaperPreviewProtocol.toggleInvoiceAccess()
                            Task { await session.revalidate() }
                        }.accessibilityIdentifier("invoice-verification-toggle-resource")
                        Button("Release") { EstimateRecoveryPreview.shared.release() }
                            .accessibilityIdentifier("invoice-verification-release")
                    }
                }
            }
            if PaperPreview.enabled && (ProcessInfo.processInfo.arguments.contains("--paper-preview-invoice-check-workspace") || ProcessInfo.processInfo.arguments.contains("--paper-preview-invoice-confirm-workspace-interruption")) {
                ThorbisToolbarItem(placement: .principal) {
                    TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                        Text("Sample workspace switch")
                            .accessibilityIdentifier("invoice-workspace-switch-result")
                            .accessibilityValue(EstimateRecoveryPreview.invoiceWorkspaceKey.map { UserDefaults.standard.bool(forKey: $0) } == true ? "switched" : "not switched")
                    }
                }
            }
            if PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-invoice-confirm-permission-interruption") {
                ThorbisToolbarItem(placement: .principal) {
                    HStack {
                        Text("Sample access").accessibilityIdentifier("invoice-confirm-permission-state").accessibilityValue(samplePermissionState)
                        if samplePermissionState == "denied" {
                            Button("Restore sample permission") {
                                Task { @MainActor in
                                    PaperPreviewProtocol.toggleInvoiceEditing()
                                    await session.revalidate()
                                    samplePermissionState = session.can("invoice.edit", feature: "invoicing") ? "allowed" : "denied"
                                }
                            }.accessibilityIdentifier("invoice-confirm-permission-restore")
                        }
                    }
                }
            }
            if PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-invoice-confirm-network-interruption") {
                ThorbisToolbarItem(placement: .principal) {
                    HStack {
                        Text("Sample network").accessibilityIdentifier("invoice-confirm-network-state").accessibilityValue(sampleNetworkState)
                        if sampleNetworkState == "offline" {
                            Button("Restore sample connection") {
                                Task { @MainActor in
                                    PaperPreviewProtocol.simulateNoSignal = false
                                    await session.revalidate()
                                    sampleNetworkState = session.isOffline ? "offline" : "online"
                                }
                            }.accessibilityIdentifier("invoice-confirm-network-restore")
                        }
                    }
                }
            }
            if PaperPreview.enabled && (ProcessInfo.processInfo.arguments.contains("--paper-preview-invoice-final-read-denied") || ProcessInfo.processInfo.arguments.contains("--paper-preview-invoice-final-read-changed")) {
                ThorbisToolbarItem(placement: .principal) {
                    Text("Sample final read")
                        .accessibilityIdentifier("invoice-final-read-result")
                        .accessibilityValue(sampleFinalReadResult)
                }
            }
            if PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-invoice-check-delivery") {
                ThorbisToolbarItem(placement: .principal) {
                    Text("Sample delivery")
                        .accessibilityIdentifier("invoice-reload-delivery")
                        .accessibilityValue(EstimateRecoveryPreview.invoiceDeliveryKey.map { UserDefaults.standard.bool(forKey: $0) } == true ? "delivered" : "not delivered")
                }
            }
            if EstimateRecoveryPreview.invoiceHeldReloadEnabled || EstimateRecoveryPreview.invoiceFinalReadHeldEnabled {
                ThorbisToolbarItem(placement: .principal) {
                    HStack {
                        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                            Text("Sample invoice reload")
                                .accessibilityIdentifier("invoice-held-reload-count")
                                .accessibilityValue(EstimateRecoveryPreview.shared.reloadHoldState)
                        }
                        Button("Dismiss held reload") {
                            dismiss()
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(500))
                                EstimateRecoveryPreview.shared.release()
                            }
                        }.accessibilityIdentifier("invoice-held-reload-dismiss")
                    }
                }
            }
            if PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-invoice-toggle-access") {
                ThorbisToolbarItem(placement: .principal) {
                    Button("Toggle sample invoice access") {
                        PaperPreviewProtocol.toggleInvoiceAccess()
                        Task { await session.revalidate() }
                    }.accessibilityIdentifier("invoice-toggle-sample-access")
                }
            }
            #endif
            ThorbisToolbarItem(placement: .cancellationAction) {
                Button(cleanupFailedAfterSave ? "Close" : "Cancel") { if cleanupFailedAfterSave { dismiss() } else if hasRawDraftChanges || didRecoverDraft || wroteFreshDraft || recoveryBlocked { confirmDiscard = true } else { dismiss() } }.disabled(busy)
            }
        }
        .keyboardDoneButton()
    }

    private func openDraft() {
            viewVisible = true
            if !scopeCaptured { scopeCaptured = true; originalScope = currentScope }
            guard scopeMatches, session.can("invoice.edit", feature: "invoicing"), let draftScope else { return }
            guard CommercialDraftStore.shared.acquire(scope: draftScope, owner: draftOwner) else {
                recoveryBlocked = true; error = "This draft is already open in another window."; return
            }
            ownsDraft = true
            if !didRestoreDraft && !didRecoverDraft {
                do {
                    if try CommercialDraftStore.shared.load(CommercialInvoiceDraft.self, scope: draftScope) != nil {
                        didRecoverDraft = true
                    } else {
                        didRestoreDraft = true; verifiedScope = currentScope
                    }
                } catch {
                    recoveryBlocked = true; self.error = "Your saved draft could not be opened. It is still on this phone."
                }
            }
    }

    private var editorBase: some View {
        editorDecorated
        .onAppear { openDraft() }
        .task(id: draftAccessKey) { await verifyDraftAccess() }
        .onChange(of: session.isOffline) { _, offline in
            if offline { accessAttempt = UUID(); invalidatePendingReload(); if didRecoverDraft { verifiedScope = nil } }
        }
        #if DEBUG
        .onChange(of: confirmReload) { _, presented in
            let network = ProcessInfo.processInfo.arguments.contains("--paper-preview-invoice-confirm-network-interruption")
            let revision = ProcessInfo.processInfo.arguments.contains("--paper-preview-invoice-confirm-revision-change")
            let permission = ProcessInfo.processInfo.arguments.contains("--paper-preview-invoice-confirm-permission-interruption")
            let workspace = ProcessInfo.processInfo.arguments.contains("--paper-preview-invoice-confirm-workspace-interruption")
            guard PaperPreview.enabled, presented, !simulatedConfirmationInterruption, network || revision || permission || workspace else { return }
            simulatedConfirmationInterruption = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1500))
                if network {
                    PaperPreviewProtocol.simulateNoSignal = true
                    await session.revalidate()
                    sampleNetworkState = session.isOffline ? "offline" : "online"
                }
                if revision { EstimateRecoveryPreview.shared.advanceInvoiceRevision() }
                if revision { await session.revalidate() }
                if permission {
                    PaperPreviewProtocol.toggleInvoiceEditing()
                    await session.revalidate()
                    samplePermissionState = session.can("invoice.edit", feature: "invoicing") ? "allowed" : "denied"
                }
                if workspace {
                    PaperPreviewProtocol.switchSavedWorkWorkspace()
                    await session.revalidate()
                    if session.activeOrganization?.id == "00000000-0000-4000-8000-000000000003", let key = EstimateRecoveryPreview.invoiceWorkspaceKey {
                        UserDefaults.standard.set(true, forKey: key)
                    }
                }
            }
        }
        #endif
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                invalidatePendingReload()
                accessAttempt = UUID()
                if didRecoverDraft { verifiedScope = nil }
            } else if didRecoverDraft && verifiedScope != currentScope {
                Task { await verifyDraftAccess() }
            }
        }
        .onDisappear { viewVisible = false; accessAttempt = UUID(); invalidatePendingReload(); if !busy { persistDraft(leavingOriginalScope: true); releaseDraft() } }
        .task(id: catalogContext) { await refreshCatalog() }
        .onChange(of: catalogContext) { previous, current in
            if !previous.preservesInvoicePickerState(comparedTo: current) {
                addedLineSelection = nil
                showPriceBook = false
            }
        }

    }

    @State private var memberPricing: MemberPricing?

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let error { ErrorBanner(message: error).padding(.horizontal, -Theme.gutter) }
            if staleRevision {
                Button { Task { await reloadLatest() } } label: {
                    Label("Review latest invoice", systemImage: "arrow.clockwise")
                        .font(Theme.font(14, weight: .medium))
                        .foregroundStyle(Theme.brandText)
                        .frame(minHeight: 44)
                }
                .accessibilityHint("Reloads the current server version and discards these unsaved edits")
            }
            if editor.invoice.status != "draft" {
                ErrorBanner(message: "This invoice is now \(editor.invoice.status.statusLabel.lowercased()); its line items are final.")
            }
            if editor.hasUnsupportedLineSources {
                ErrorBanner(message: "This invoice has line provenance this app cannot safely retain. Review it in Thorbis web before editing.")
            }

            invoiceEditorHeading

            VStack(alignment: .leading, spacing: 6) {
                Text(editor.lines.isEmpty ? "Line items" : "Line items · \(editor.lines.count)")
                    .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("invoice-line-count")
                    .padding(.horizontal, 4)
                PaperCard {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(editor.lines) { line in
                            lineRow(line)
                        }
                        Button { showPriceBook = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus").font(.system(size: 15, weight: .medium))
                                Text("Add item").font(Theme.font(16, weight: .medium))
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(Theme.foreground)
                            .padding(.horizontal, 14).frame(minHeight: 52).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(linesDisabled || editor.lines.count >= 500)
                        .accessibilityHint(canUsePriceBook ? "Opens the price book" : "Adds a custom line item")
                        .accessibilityIdentifier("invoice-add-item")
                    }
                }
            }

            if editor.needsPriceBookOverrideReason {
                priceBookOverrideReasonField
            }

            Text("Line changes are checked against the current invoice revision before saving.")
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }

    /// The shared builder line, over an invoice draft line. Quantities still go through
    /// `committedLine` so the editor's own validation runs.
    private func lineRow(_ line: InvoiceLineDraft) -> some View {
        let binding = committedLine(lineBinding(line.id))
        let canMoveUp = editor.lines.first?.id != line.id
        let canMoveDown = editor.lines.last?.id != line.id
        var items: [ThorbisMenuItem] = []
        if canMoveUp { items.append(ThorbisMenuItem("Move up", icon: "arrow.up") { moveLine(line.id, offset: -1) }) }
        if canMoveDown { items.append(ThorbisMenuItem("Move down", icon: "arrow.down") { moveLine(line.id, offset: 1) }) }
        items.append(ThorbisMenuItem("Remove line", icon: "trash", role: .destructive) { removeLine(line.id) })
        let total: Int? = {
            guard let cents = InvoiceLineEditorState.priceCents(line.unitPrice),
                  let quantity = Int(line.quantity.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
            let (amount, overflow) = cents.multipliedReportingOverflow(by: quantity)
            return overflow ? nil : amount
        }()
        return BuilderLineRow(
            description: binding.description, quantity: binding.quantity, unitPrice: binding.unitPrice,
            lineID: line.id, currency: invoice.currency, lineTotal: total, unitLabel: line.unitLabel,
            note: sourceNote(line), menuItems: items, expanded: expandedLine == line.id,
            toggle: { withAnimation(EstimateLineGroupsEditor.spring) { expandedLine = expandedLine == line.id ? nil : line.id } },
            remove: { removeLine(line.id) }, focus: $focus,
            descriptionIdentifier: "invoice-line-description-\(line.id)",
            quantityIdentifier: "invoice-line-quantity-\(line.id)",
            priceIdentifier: "invoice-line-price-\(line.id)"
        )
        .disabled(linesDisabled)
        .accessibilityAction(named: "Move up") { if canMoveUp { moveLine(line.id, offset: -1) } }
        .accessibilityAction(named: "Move down") { if canMoveDown { moveLine(line.id, offset: 1) } }
    }

    private func sourceNote(_ line: InvoiceLineDraft) -> String? {
        switch line.source {
        case .priceBookSelection: "Price Book selection · server verifies the revision"
        case .retainedPriceBook: "Price Book source retained"
        case .estimate: "Estimate source retained"
        default: nil
        }
    }

    private func lineBinding(_ id: UUID) -> Binding<InvoiceLineDraft> {
        Binding(
            get: { editor.lines.first { $0.id == id } ?? InvoiceLineDraft(id: id, description: "", quantity: "1", unitPrice: "") },
            set: { value in if let index = editor.lines.firstIndex(where: { $0.id == id }) { editor.lines[index] = value } }
        )
    }

    private func removeLine(_ id: UUID) {
        do {
            try editor.removeLine(id: id)
            if expandedLine == id { expandedLine = nil }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// After the picker closes, the last catalog line it added opens for a price or wording check.
    private func openAddedLine() {
        guard canEdit, canUsePriceBook, !editor.hasUnsupportedLineSources,
              invoice.organizationId == catalogContext.organizationID,
              let id = addedLineSelection?.resolvedLineID(in: editor.lines, context: catalogContext) else { return }
        addedLineSelection = nil
        withAnimation(EstimateLineGroupsEditor.spring) { expandedLine = id }
    }

    /// Why the commits are off, in words under them (design.thorbis.com "Disabled needs a reason").
    private var commitBlockedReason: String? {
        guard !busy else { return nil }
        if !canEdit { return "Your role can't change this invoice." }
        if editor.hasUnsupportedLineSources { return "Some lines came from somewhere this phone can't edit. Change them on the web." }
        if !canIssue && !editor.hasChanges { return "No changes to save yet." }
        return nil
    }

    private var invoiceCommitActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            invoiceCommitButtons
            if let reason = commitBlockedReason {
                Text(reason).font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 8)
        .background(Theme.canvas)
    }

    private var invoiceCommitButtons: some View {
        let accessible = dynamicTypeSize.isAccessibilitySize
        let layout = accessible ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            if canIssue {
                Button { Task { await save() } } label: {
                    Text("Save draft")
                    .font(Theme.font(17, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, accessible ? 16 : 0)
                    .padding(.vertical, accessible ? 12 : 0)
                    .frame(width: accessible ? nil : 132, height: accessible ? nil : Theme.commitHeight)
                    .frame(maxWidth: accessible ? .infinity : nil, minHeight: Theme.commitHeight)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
                }
                    .buttonStyle(PressStyle())
                    .disabled(busy || !canEdit || !editor.hasChanges || editor.hasUnsupportedLineSources)
                PrimaryButton(title: "Issue invoice", busy: busy) { confirmIssue = true }
                    .disabled(busy || !canEdit || editor.hasUnsupportedLineSources)
            } else {
                PrimaryButton(title: "Save draft", busy: busy) { Task { await save() } }
                    .disabled(busy || !canEdit || !editor.hasChanges || editor.hasUnsupportedLineSources)
            }
        }
    }

    private var priceBookOverrideReasonField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reason for Price Book change")
                .font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.muted)
            TextField("Describe the approved change", text: $editor.priceBookOverrideReason, prompt: .placeholder("Describe the approved change"), axis: .vertical)
                .lineLimit(2...4)
                .font(Theme.font(14))
                .padding(12)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.border, lineWidth: 1))
                .disabled(busy || !canEdit || editor.hasUnsupportedLineSources)
                .accessibilityLabel("Reason for Price Book change")
        }
    }

    private func committedLine(_ line: Binding<InvoiceLineDraft>) -> Binding<InvoiceLineDraft> {
        Binding(
            get: { line.wrappedValue },
            set: { proposed in
                guard editor.invoice.status == "draft" else { return }
                var next = proposed
                let quantityText = proposed.quantity.trimmingCharacters(in: .whitespacesAndNewlines)
                if let quantity = Int(quantityText), (1...100_000).contains(quantity), String(quantity) == quantityText {
                    try? editor.setQuantity(proposed.id, quantity)
                    if let stored = editor.lines.first(where: { $0.id == proposed.id })?.quantity {
                        next.quantity = stored
                    }
                }
                line.wrappedValue = next
            }
        )
    }

    private func priceBookQuantity(_ itemID: String) -> Int? {
        editor.quantity(ofPriceBookItem: itemID)
    }

    /// One more of a price book item; returns why it couldn't be added, or nil.
    private func addCatalogItem(_ item: PriceBookListItem) -> String? {
        guard !busy, canEdit, !editor.hasUnsupportedLineSources, canUsePriceBook,
              invoice.organizationId == catalogContext.organizationID,
              catalog.context == catalogContext else { return "This invoice can't take price book items right now." }
        do {
            let before = editor.lines.map(\.id)
            try editor.addPriceBookItem(item)
            if let added = editor.lines.first(where: { !before.contains($0.id) }) ?? editor.lines.last {
                addedLineSelection = InvoiceCatalogLineSelection(lineID: added.id, context: catalogContext)
            }
            error = nil
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func addCustomLine(_ text: String) {
        guard !busy, canEdit, !editor.hasUnsupportedLineSources else { return }
        let before = editor.lines.count
        editor.addManualLine()
        guard editor.lines.count > before, let index = editor.lines.indices.last else {
            error = InvoiceLineEditorError.tooManyLines.localizedDescription
            return
        }
        editor.lines[index].description = text
        let id = editor.lines[index].id
        addedLineSelection = nil
        expandedLine = id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            focus = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .description(id) : .price(id)
        }
    }

    private func refreshCatalog(force: Bool = false) async {
        guard canUsePriceBook else { return }
        let expected = catalogContext
        await catalog.refresh(api: api, organizationID: expected.organizationID,
                              sessionGeneration: expected.sessionGeneration, authority: expected.authority, force: force)
    }

    private var invoiceEditorHeading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INV-\(invoice.id.suffix(4).uppercased())")
                .font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.muted)
            HStack(spacing: 10) {
                // Status is a word and a dot, as on the new estimate and the invoice's rows (was a
                // warning-tinted badge that made a draft read like a problem).
                let status = DocumentStatus(invoice: editor.invoice)
                StatusLabel(tone: status.tone, word: status.word, emphasis: .quiet)
                Text("Revision \(editor.invoice.linesRevision)")
                    .font(Theme.font(12)).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editorDetail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label).foregroundStyle(Theme.muted)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(Theme.foreground).multilineTextAlignment(.trailing)
        }
        .font(Theme.font(13)).padding(.vertical, 8)
    }

    private func save() async {
        guard canEdit else {
            error = "You no longer have permission to edit this invoice."
            return
        }
        guard editor.hasChanges else { return }
        busy = true
        defer { busy = false; if !viewVisible { releaseDraft() } }
        do {
            let descriptions = editor.lines.map { $0.description.trimmingCharacters(in: .whitespacesAndNewlines) }
            let requiresExtended = CommercialDescriptionPolicy.isExtended(descriptions, kind: .invoice)
            let verified = requiresExtended ? await session.verifyExtendedCommercialText() : false
            if requiresExtended && !verified { throw CommercialDescriptionPolicy.Problem.unavailable }
            guard canEdit else { throw CommercialDescriptionPolicy.Problem.unavailable }
            commitPrices()
            let request = try editor.makeRequest(extendedTextVerified: verified)
            let updated = try await api.replaceFieldInvoiceLines(invoice.id, request: request)
            guard scopeMatches, canEdit else { error = "The workspace or access changed. Your edits are still here. Check the original workspace before retrying."; return }
            intentionallyDiscarded = true
            addedLineSelection = nil
            onSaved(updated)
            do { if ownsDraft, let draftScope { try CommercialDraftStore.shared.remove(scope: draftScope) } }
            catch {
                cleanupFailedAfterSave = true
                self.error = "The invoice was saved, but its local draft could not be removed. Close this screen and check the saved invoice before making another change."
                return
            }
            dismiss()
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
            staleRevision = (error as? Problem)?.status == 409
        }
    }

    /// Canonicalize a finished price at save time. Live keystrokes keep the raw text.
    private func commitPrices() {
        for line in editor.lines {
            guard let cents = InvoiceLineEditorState.priceCents(line.unitPrice) else { continue }
            try? editor.setUnitPrice(line.id, cents: cents)
        }
    }

    private func moveLine(_ id: UUID, offset: Int) {
        guard let index = editor.lines.firstIndex(where: { $0.id == id }) else { return }
        editor.moveLine(id: id, to: index + offset)
    }

    private func reloadLatest() async {
        guard !busy else { return }
        guard scopeMatches, let expected = currentScope, ownsDraft else { error = "The workspace changed. Your edits are still here."; return }
        busy = true
        let attempt = UUID(); accessAttempt = attempt
        #if DEBUG
        if EstimateRecoveryPreview.invoiceHeldReloadEnabled { EstimateRecoveryPreview.shared.armHeldReload() }
        #endif
        defer { busy = false; if !viewVisible { releaseDraft() } }
        do {
            let latest = try await api.fieldInvoice(invoice.id, requireFresh: true)
            guard !Task.isCancelled, viewVisible, scenePhase == .active, !session.isOffline, accessAttempt == attempt,
                  currentScope == expected, latest.id == invoice.id,
                  latest.organizationId == expected.organizationID,
                  session.can("invoice.edit", feature: "invoicing"), draftScope != nil else { return }
            pendingReload = latest
            pendingReloadScope = expected
            pendingReloadAttempt = attempt
            confirmReload = true
        } catch is CancellationError {
        } catch {
            self.error = "The draft could not be cleared or the latest document could not be verified. Your draft is still on this phone."
        }
    }

    private func invalidatePendingReload() {
        pendingReload = nil
        pendingReloadScope = nil
        pendingReloadAttempt = nil
        confirmReload = false
        confirmVerifiedReload = false
    }

    private func verifyPendingReload() async {
        guard !busy else { return }
        guard viewVisible, scenePhase == .active, !session.isOffline, ownsDraft,
              let expected = pendingReloadScope, currentScope == expected, verifiedScope == expected,
              pendingReloadAttempt == accessAttempt, let prior = pendingReload else {
            invalidatePendingReload()
            error = "The workspace changed or the document is unavailable. Your draft is still on this phone."
            return
        }
        busy = true
        let attempt = UUID(); accessAttempt = attempt; pendingReloadAttempt = attempt
        #if DEBUG
        if EstimateRecoveryPreview.invoiceFinalReadHeldEnabled { EstimateRecoveryPreview.shared.armHeldReload() }
        if PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-invoice-final-read-denied") {
            EstimateRecoveryPreview.shared.denyNextInvoiceRead()
        }
        if PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-invoice-final-read-changed") {
            EstimateRecoveryPreview.shared.advanceInvoiceRevision()
        }
        #endif
        defer { busy = false; if !viewVisible { releaseDraft() } }
        do {
            let latest = try await api.fieldInvoice(invoice.id, requireFresh: true)
            guard !Task.isCancelled, viewVisible, scenePhase == .active, !session.isOffline,
                  accessAttempt == attempt, currentScope == expected, verifiedScope == expected,
                  pendingReloadAttempt == attempt, latest.id == prior.id,
                  latest.organizationId == expected.organizationID, latest == prior else {
                guard accessAttempt == attempt else { return }
                #if DEBUG
                sampleFinalReadResult = "changed"
                #endif
                invalidatePendingReload()
                error = "The document or access changed. Your draft is still on this phone. Check again."
                return
            }
            pendingReload = latest
            confirmVerifiedReload = true
        } catch {
            guard accessAttempt == attempt else { return }
            #if DEBUG
            sampleFinalReadResult = "denied or failed"
            #endif
            invalidatePendingReload()
            self.error = "The latest document could not be verified. Your draft is still on this phone."
        }
    }

    private func applyPendingReload() {
        guard viewVisible, scenePhase == .active, !session.isOffline, ownsDraft,
              let expected = pendingReloadScope, pendingReloadAttempt == accessAttempt, currentScope == expected, verifiedScope == expected, scopeMatches,
              session.can("invoice.edit", feature: "invoicing"), let latest = pendingReload,
              latest.id == invoice.id, latest.organizationId == expected.organizationID,
              let draftScope else {
            invalidatePendingReload()
            error = "The workspace changed or the document is unavailable. Your draft is still on this phone."
            return
        }
        invalidatePendingReload()
        do {
            try CommercialDraftStore.shared.remove(scope: draftScope)
            didRestoreDraft = false; didRecoverDraft = false; wroteFreshDraft = false
            editor = InvoiceLineEditorState(invoice: latest)
            persistenceBaseline = editor
            addedLineSelection = nil
            recoveryBlocked = false; staleRevision = false; error = nil
            didRestoreDraft = true; verifiedScope = expected
        } catch {
            self.error = "The draft could not be cleared or the latest document could not be verified. Your draft is still on this phone."
        }
    }

    private func issue() async {
        guard canIssue, canEdit else {
            error = "You no longer have permission to issue this invoice."
            return
        }
        busy = true
        defer { busy = false; if !viewVisible { releaseDraft() } }
        do {
            commitPrices()
            var current = editor.invoice
            let descriptions = editor.lines.map { $0.description.trimmingCharacters(in: .whitespacesAndNewlines) }
            let requiresExtended = CommercialDescriptionPolicy.isExtended(descriptions, kind: .invoice)
            let verified = requiresExtended ? await session.verifyExtendedCommercialText() : false
            if requiresExtended && !verified { throw CommercialDescriptionPolicy.Problem.unavailable }
            guard canEdit, canIssue else { throw CommercialDescriptionPolicy.Problem.unavailable }
            if editor.hasChanges {
                current = try await api.replaceFieldInvoiceLines(invoice.id, request: editor.makeRequest(extendedTextVerified: verified))
                guard scopeMatches, canEdit, canIssue else { error = "The workspace changed. Your edits are still here."; return }
                addedLineSelection = nil
                editor = InvoiceLineEditorState(invoice: current)
                onSaved(current)
            }
            let issued = try await api.issueFieldInvoice(invoice.id, expectedLinesRevision: current.linesRevision)
            guard scopeMatches, canIssue else { error = "The workspace or access changed. Check the invoice in the original workspace."; return }
            intentionallyDiscarded = true
            onSaved(issued)
            do { if ownsDraft, let draftScope { try CommercialDraftStore.shared.remove(scope: draftScope) } }
            catch {
                cleanupFailedAfterSave = true
                self.error = "The invoice was issued, but its local draft could not be removed. Close this screen and check the issued invoice before making another change."
                return
            }
            dismiss()
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
            staleRevision = (error as? Problem)?.status == 409
        }
    }
    private func releaseDraft() {
        if ownsDraft, let draftScope { CommercialDraftStore.shared.release(scope: draftScope, owner: draftOwner) }
        ownsDraft = false
    }
}

/// A catalogue quick editor never resolves by description, source item, or array position.
struct InvoiceCatalogLineSelection: Equatable {
    let lineID: UUID
    let context: PriceBookCatalogContext

    func resolvedLineID(in lines: [InvoiceLineDraft], context current: PriceBookCatalogContext) -> UUID? {
        guard context.preservesInvoicePickerState(comparedTo: current), current.organizationID?.isEmpty == false,
              lines.filter({ $0.id == lineID }).count == 1 else { return nil }
        return lineID
    }
}

private extension PriceBookCatalogContext {
    /// Local revalidation revisions retire requests but do not change a verified invoice draft's identity.
    func preservesInvoicePickerState(comparedTo other: PriceBookCatalogContext) -> Bool {
        guard organizationID == other.organizationID, sessionGeneration == other.sessionGeneration else { return false }
        switch (authority, other.authority) {
        case (nil, nil): return true
        case let (old?, new?):
            return old.actorID == new.actorID && old.policyVersion == new.policyVersion && old.generation == new.generation
        default: return false
        }
    }
}
