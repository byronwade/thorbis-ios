import SwiftUI

struct EstimateRevisionEditorView: View {
    let estimate: EstimateRecord
    let onSaved: (EstimateRecord) -> Void

    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var editor: EstimateRevisionEditorState
    @State private var persistenceBaseline: EstimateRevisionEditorState
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
    @State private var descriptionProblem: String?
    @State private var staleRevision = false
    @State private var confirmReload = false
    @State private var pendingReload: EstimateRecord?
    @State private var pendingReloadScope: EstimateCreationScope?
    @State private var pendingReloadAttempt: UUID?
    @State private var confirmDiscard = false
    @State private var picker: EstimateBuilderTarget?
    @State private var discountTarget: EstimateBuilderTarget?
    @State private var expandedLine: UUID?
    @State private var revealProblem = 0
    @State private var keyboardUp = false
    @State private var scrollTarget: String?
    @State private var removed: RemovedLine?
    @State private var memberPricing: MemberPricing?
    @ObservedObject private var catalog = PriceBookCatalog.shared
    @FocusState private var focus: EstimateBuilderFocus?

    init(estimate: EstimateRecord, onSaved: @escaping (EstimateRecord) -> Void) {
        self.estimate = estimate
        self.onSaved = onSaved
        _editor = State(initialValue: EstimateRevisionEditorState(estimate: estimate))
        _persistenceBaseline = State(initialValue: EstimateRevisionEditorState(estimate: estimate))
    }

    private var canRevise: Bool {
        resourceAuthorized && ownsDraft && !cleanupFailedAfterSave && editor.canRevise && session.can("estimate.create", feature: "estimates")
    }

    private var currentScope: EstimateCreationScope? {
        guard session.phase == .ready, let actor = session.user?.id,
              let org = session.activeOrganization?.id, org == estimate.organizationId,
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
                     origin: originalScope.origin, kind: "estimate-revision", document: estimate.id)
    }
    private func restoreDraft() {
        guard scopeMatches, session.can("estimate.create", feature: "estimates"), let draftScope else { return }
        do {
            guard let draft = try CommercialDraftStore.shared.load(CommercialEstimateDraft.self, scope: draftScope) else { return }
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
              session.can("estimate.create", feature: "estimates") else { return }
        if !didRecoverDraft && verifiedScope == expected { return }
        guard !session.isOffline else { return }
        let attempt = UUID(); accessAttempt = attempt
        var latestRecord: EstimateRecord?
        let allowed = await CommercialDraftAccess.verify(expectedScope: expected, currentScope: { session.isOffline ? nil : currentScope },
            read: { try await api.fieldEstimate(estimate.id, requireFresh: true) }, matches: { latest in
                latestRecord = latest
                return latest.id == estimate.id && latest.organizationId == expected.organizationID
            })
        guard !Task.isCancelled, viewVisible, accessAttempt == attempt, !session.isOffline, currentScope == expected else { return }
        guard allowed else {
            verifiedScope = nil
            error = "Could not verify access or the document changed. Your draft is still on this phone."
            return
        }
        if error == "Could not verify access or the document changed. Your draft is still on this phone." { error = nil }
        verifiedScope = expected
        guard let latest = latestRecord, latest.currentRevisionNumber == editor.estimate.currentRevisionNumber && latest.status == editor.estimate.status else {
            recoveryBlocked = true
            staleRevision = true
            error = CommercialDraftRecoveryError.differentRevision.localizedDescription
            return
        }
        if !didRestoreDraft { didRestoreDraft = true; restoreDraft() }
        if recoveryBlocked { staleRevision = true }
    }
    private var hasRawDraftChanges: Bool {
        guard editor.title == persistenceBaseline.title,
              editor.lines.count == persistenceBaseline.lines.count,
              editor.options.count == persistenceBaseline.options.count else { return true }
        func changed(_ lhs: [EstimateRevisionLineDraft], _ rhs: [EstimateRevisionLineDraft]) -> Bool {
            lhs.count != rhs.count || zip(lhs, rhs).contains { a, b in
                a.originalLineID != b.originalLineID || a.description != b.description ||
                a.quantity != b.quantity || a.unitPrice != b.unitPrice || a.source != b.source ||
                a.group != b.group || a.movedByPerson != b.movedByPerson || a.showToCustomer != b.showToCustomer
            }
        }
        if changed(editor.lines, persistenceBaseline.lines) { return true }
        return zip(editor.options, persistenceBaseline.options).contains { a, b in
            a.id != b.id || a.title != b.title || a.description != b.description || changed(a.lines, b.lines)
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
        do { try CommercialDraftStore.shared.save(CommercialEstimateDraft(state: editor), scope: draftScope); if !didRecoverDraft { wroteFreshDraft = true } }
        catch { self.error = "This draft could not be saved on this phone. Keep this screen open and try again." }
    }
    private func discardDraft() {
        guard ownsDraft, scopeMatches, let draftScope else { dismiss(); return }
        do { try CommercialDraftStore.shared.remove(scope: draftScope); intentionallyDiscarded = true; dismiss() }
        catch { self.error = "The saved draft could not be removed. Try again." }
    }

    /// Good / better / best stays behind its flag (`estimate_option_signing`).
    private var optionsFeatureEnabled: Bool {
        session.can("estimate.create", feature: "estimate_option_signing")
    }

    private var canEdit: Bool {
        canRevise && (optionsFeatureEnabled || editor.options.isEmpty)
    }

    private var canDiscount: Bool {
        session.can("estimate.discount", feature: "estimates")
    }

    private var canUsePriceBook: Bool {
        session.can("pricebook.view", feature: "price_book")
    }

    private var sectionsDisabled: Bool { busy || !canEdit || editor.hasUnsupportedLineSources }
    /// EB-13: the workspace stores line groups and the materials switch.
    private var storesLineGroups: Bool { session.isFeatureOn("estimate_line_groups") }

    private func optionName(_ id: String?) -> String {
        guard let id, let index = editor.options.firstIndex(where: { $0.id == id }) else {
            return editor.options.isEmpty ? "this estimate" : "the main estimate"
        }
        let title = editor.options[index].title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Option \(index + 1)" : "Option \(index + 1) · \(title)"
    }

    private var editingDraft: Bool { editor.estimate.status == "draft" }

    private var revisionReady: Bool {
        !editingDraft && (editor.estimate.currentRevisionNumber ?? 0) > 0
    }

    private var canSave: Bool {
        !busy && canEdit && revisionReady &&
        editor.hasChanges && !editor.hasUnsupportedLineSources && (!editor.hasCreditLines || canDiscount)
    }

    var body: some View {
        NavigationStack { editorContainer }
    }

    private var editorScroll: some View {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        if !resourceAuthorized || !session.can("estimate.create", feature: "estimates") {
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
                    .onChange(of: revealProblem) { _, _ in
                        guard let id = expandedLine else { return }
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                    .onChange(of: scrollTarget) { _, target in
                        guard let target else { return }
                        withAnimation { proxy.scrollTo(target, anchor: .top) }
                        scrollTarget = nil
                    }
                }
                if resourceAuthorized && session.can("estimate.create", feature: "estimates") { revisionFooter }
            }
    }

    private var editorDecorated: some View {
        editorScroll
            .background(Theme.canvas)
            .foregroundStyle(Theme.foreground)
            .navigationTitle(editingDraft ? "Edit estimate" : "Revise estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                #if DEBUG
                if EstimateRecoveryPreview.heldReloadEnabled {
                    ThorbisToolbarItem(placement: .principal) {
                        HStack {
                            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                                Text("Sample reload requests")
                                    .accessibilityIdentifier("estimate-held-reload-count")
                                    .accessibilityValue(EstimateRecoveryPreview.shared.reloadHoldState)
                            }
                            Button("Dismiss held reload") {
                                CommercialDraftStore.trace("debug dismiss")
                                dismiss()
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(500))
                                    CommercialDraftStore.trace("debug release")
                                    EstimateRecoveryPreview.shared.release()
                                }
                            }.accessibilityIdentifier("estimate-held-reload-dismiss")
                        }
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
                #if DEBUG
                CommercialDraftStore.trace("open scene=\(String(describing: scenePhase))")
                #endif
                viewVisible = true
                if !scopeCaptured { scopeCaptured = true; originalScope = currentScope }
                guard scopeMatches, session.can("estimate.create", feature: "estimates"), let draftScope else { return }
                guard CommercialDraftStore.shared.acquire(scope: draftScope, owner: draftOwner) else {
                    recoveryBlocked = true; error = "This draft is already open in another window."; return
                }
                ownsDraft = true
                if !didRestoreDraft && !didRecoverDraft {
                    do {
                        if try CommercialDraftStore.shared.load(CommercialEstimateDraft.self, scope: draftScope) != nil {
                            didRecoverDraft = true
                        } else {
                            didRestoreDraft = true; verifiedScope = currentScope
                        }
                    } catch {
                        recoveryBlocked = true; self.error = "Your saved draft could not be opened. It is still on this phone."
                    }
                }
    }

    private var editorLifecycle: some View {
        editorDecorated
            .onAppear { openDraft() }
            .task(id: draftAccessKey) { await verifyDraftAccess() }
            .onChange(of: session.isOffline) { _, offline in
                if offline { accessAttempt = UUID(); invalidatePendingReload(); if didRecoverDraft { verifiedScope = nil } }
            }
            .onChange(of: scenePhase) { _, phase in
                #if DEBUG
                CommercialDraftStore.trace("scene \(String(describing: phase))")
                #endif
                if phase != .active {
                    invalidatePendingReload()
                    accessAttempt = UUID()
                    if didRecoverDraft { verifiedScope = nil }
                } else if didRecoverDraft && verifiedScope != currentScope {
                    Task { await verifyDraftAccess() }
                }
            }
            .onDisappear {
                #if DEBUG
                CommercialDraftStore.trace("disappear busy=\(busy)")
                #endif
                viewVisible = false; accessAttempt = UUID(); invalidatePendingReload(); if !busy { persistDraft(leavingOriginalScope: true); releaseDraft() }
            }
            .trackKeyboard($keyboardUp)
    }

    private var editorContainer: some View {
        editorLifecycle
            .discardChangesGuard(hasChanges: hasRawDraftChanges || didRecoverDraft || wroteFreshDraft || recoveryBlocked, busy: busy, isPresented: $confirmDiscard) { discardDraft() }
            .onChange(of: editor) { _, _ in persistDraft() }
            .onChange(of: scopeMatches) { wasMatching, matches in
                if !matches {
                    if wasMatching { persistDraft(leavingOriginalScope: true) }
                    picker = nil; discountTarget = nil; focus = nil
                }
            }
            .onChange(of: session.can("estimate.create", feature: "estimates")) { _, allowed in
                if !allowed { picker = nil; discountTarget = nil; focus = nil }
            }
            .sheet(item: $picker) { target in SheetSurface {
                PriceBookCartPicker(
                    destination: optionName(target.optionID),
                    canUsePriceBook: canUsePriceBook,
                    notice: editingDraft && canRevise ? "Draft changes can't be saved yet." : nil,
                    quantityInDraft: { id in lines(for: target.optionID).quantity(ofPriceBookItem: id) },
                    secondaryPriceText: { memberPricing?.secondaryPriceText($0) },
                    addItem: { add($0, to: target) },
                    addCustomLine: { addCustom($0, to: target) },
                    refresh: { await refreshCatalog(force: $0) }
                )
                .environmentObject(session).environmentObject(api)
                .opacity(resourceAuthorized ? 1 : 0)
                .accessibilityHidden(!resourceAuthorized)
                .allowsHitTesting(resourceAuthorized)
                .overlay { if !resourceAuthorized { ContentUnavailableView("Checking access", systemImage: "lock") } }
            } }
            .sheet(item: $discountTarget) { target in SheetSurface {
                EstimateDiscountSheet(target: optionName(target.optionID), subtotal: lines(for: target.optionID).subtotal()) { label, cents in
                    guard resourceAuthorized else { return }
                    mutateLines(target.optionID) { _ = $0.addCreditLine(label, cents: cents) }
                }
                .opacity(resourceAuthorized ? 1 : 0)
                .accessibilityHidden(!resourceAuthorized)
                .allowsHitTesting(resourceAuthorized)
                .overlay { if !resourceAuthorized { ContentUnavailableView("Checking access", systemImage: "lock") } }
            } }
            .animation(EstimateLineGroupsEditor.spring, value: keyboardUp)
            .task(id: PriceBookCatalogContext(organizationID: session.activeOrganization?.id, sessionGeneration: session.generation, authority: session.priceBookAuthority)) { await refreshCatalog() }
            .task(id: estimate.customerId) { memberPricing = try? await api.memberPricing(estimate.customerId) }
            .task(id: storesLineGroups) { editor.storesLineGroups = storesLineGroups }
            .onChange(of: catalog.items.map(\.id)) { classifyLines() }
            .onChange(of: (editor.lines + editor.options.flatMap(\.lines)).map(\.description)) { _, _ in
                if descriptionProblem != nil { refreshDescriptionProblem() }
            }
            .thorbisConfirm("Reload the latest estimate?",
                            message: "The estimate changed on the server. Reloading replaces this form with its latest saved lines and options.",
                            isPresented: $confirmReload,
                            actions: [ThorbisConfirmAction("Reload and discard my edits", role: .destructive) { applyPendingReload() }])
            #if DEBUG
            .task {
                guard PaperPreview.enabled else { return }
                if PaperPreview.screen == "builder-line" { expandedLine = editor.lines.first?.id ?? editor.options.first?.lines.first?.id }
                if PaperPreview.screen == "builder-picker" {
                    try? await Task.sleep(for: .milliseconds(400))
                    picker = EstimateBuilderTarget(optionID: editor.options.first?.id)
                }
            }
            #endif
    }

    private var revisionFooter: some View {
        VStack(spacing: 0) {
            if let removed {
                LineRemovedToast(removed: removed, undo: undoRemove, expire: { withAnimation { self.removed = nil } })
            }
            if !keyboardUp { footerTotal }
            if let descriptionProblem {
                FieldProblem(message: descriptionProblem)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.gutter)
            }
            PaperActionBar(title: saveTitle, symbol: "doc.badge.plus", busy: busy, disabled: !canSave) {
                Task { await save() }
            }
        }
        .padding(.bottom, keyboardUp ? 48 : 0)
        .background(Theme.canvas)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let error { ErrorBanner(message: error).padding(.horizontal, -Theme.gutter) }
            if staleRevision {
                Button { Task { await reloadLatest() } } label: {
                    Label("Review latest estimate", systemImage: "arrow.clockwise")
                        .font(Theme.font(14, weight: .medium))
                        .foregroundStyle(Theme.brandText)
                        .frame(minHeight: 44)
                }
                .accessibilityHint("Loads the current server version and replaces these edits")
            }
            if !editor.canRevise {
                ErrorBanner(message: "This estimate cannot be revised from its current status.")
            } else if !session.can("estimate.create", feature: "estimates") {
                ErrorBanner(message: "Your account cannot create estimate revisions.")
            } else if !editingDraft && (editor.estimate.currentRevisionNumber ?? 0) <= 0 {
                ErrorBanner(message: EstimateRevisionEditorError.missingRevision.localizedDescription)
            }
            if editingDraft && canRevise {
                ErrorBanner(message: "Draft changes can't be saved yet.")
            }
            if editor.hasUnsupportedLineSources {
                ErrorBanner(message: EstimateRevisionEditorError.unsupportedLineSource.localizedDescription)
            }
            if !optionsFeatureEnabled && !editor.options.isEmpty {
                ErrorBanner(message: EstimateRevisionEditorError.optionFeatureRequired.localizedDescription)
            }
            if editor.hasCreditLines && !canDiscount {
                ErrorBanner(message: EstimateRevisionEditorError.discountCapabilityRequired.localizedDescription)
            }

            estimateHeading
            mainSection
            optionSections
            Text(editingDraft
                 ? "Changes aren't saved when you close this screen."
                 : "Saving creates a replacement draft for the current estimate revision. It will not be sent automatically.")
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }

    /// The pinned total: the estimate's total, or each option's range once there are options.
    @ViewBuilder private var footerTotal: some View {
        if editor.options.isEmpty {
            let member = editor.lines.memberTotal(memberPricing).map { sum in
                "Member price \(money(sum, currency: "USD")) · \(memberPricing?.discountPercent ?? 0)% off"
            }
            EstimateBuilderTotal(total: editor.lines.subtotal(), detail: member)
        } else {
            let totals = editor.options.map { $0.lines.subtotal() }
            let known = totals.compactMap { $0 }
            let value = known.count == totals.count && !known.isEmpty
                ? (known.min() == known.max() ? money(known[0], currency: "USD")
                   : "\(money(known.min()!, currency: "USD"))–\(money(known.max()!, currency: "USD"))")
                : "—"
            EstimateBuilderTotal(label: "\(editor.options.count) \(editor.options.count == 1 ? "option" : "options")", value: value,
                                 detail: "The customer chooses one")
        }
    }

    private var estimateHeading: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaperEyebrow(reference: "EST-\(editor.estimate.id.suffix(4).uppercased())",
                         text: "Revision \(editor.estimate.currentRevisionNumber ?? 0) · \(editingDraft ? "Edit draft" : "New replacement draft")")
            TextField("Estimate title", text: $editor.title, prompt: .placeholder("Estimate title"), axis: .vertical)
                .font(Theme.font(24, weight: .medium)).tracking(-0.36)
                .accessibilityLabel("Estimate title")
                .disabled(busy || !canEdit)
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(Theme.warning).frame(width: 7, height: 7)
                    Text(editor.estimate.status.statusLabel).font(Theme.font(14, weight: .medium))
                }
                .accessibilityElement(children: .combine)
                Text(store.customerName(estimate.customerId))
                    .font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .accessibilityLabel("Customer \(store.customerName(estimate.customerId))")
            }
        }
    }

    private var mainSection: some View {
        let hasOptions = !editor.options.isEmpty
        var menu: [ThorbisMenuItem] = []
        if optionsFeatureEnabled, editor.options.count < 8, !editor.lines.isEmpty {
            menu.append(ThorbisMenuItem("Copy to a new option", icon: "plus.square.on.square",
                                        subtitle: "Start an option from these items") {
                if let id = editor.addOption(title: "", lines: editor.lines) { scrollToOption(id) }
            })
        }
        return EstimateBuilderSection(
            label: hasOptions ? "Main estimate" : (editor.lines.isEmpty ? "Items" : "Items · \(editor.lines.count)"),
            caption: hasOptions ? "Saved with every revision. With options, the customer chooses one option." : nil,
            lines: editableLines, disabled: sectionsDisabled, focus: $focus, expandedLine: $expandedLine,
            totalLabel: "Subtotal", showTotal: hasOptions, memberPricing: memberPricing, materialsSwitch: storesLineGroups, menuItems: menu,
            addItem: { picker = EstimateBuilderTarget() },
            addDiscount: canDiscount && !hasOptions ? { discountTarget = EstimateBuilderTarget() } : nil,
            removed: { line, index in withAnimation { removed = RemovedLine(line: line, index: index, optionID: nil) } }
        )
    }

    @ViewBuilder private var optionSections: some View {
        ForEach(Array(editor.options.enumerated()), id: \.element.id) { index, option in
            optionSection(index: index, option: option)
        }
        if optionsFeatureEnabled {
            Button(action: addOption) {
                HStack(spacing: 12) {
                    PaperCircleLabel(symbol: "plus", size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add option").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                        Text(editor.options.isEmpty ? "Offer good, better and best" : "Up to 8 options")
                            .font(Theme.font(14)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 52).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(sectionsDisabled || editor.options.count >= 8)
        } else {
            Text("Option packages require estimate option signing access.")
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 4)
        }
    }

    private func optionSection(index: Int, option: EstimateRevisionOptionDraft) -> some View {
        let binding = optionBinding(option.id)
        let title = option.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = title.isEmpty ? "Option \(index + 1)" : "Option \(index + 1) · \(title)"
        var menu: [ThorbisMenuItem] = []
        if editor.options.count < 8 {
            menu.append(ThorbisMenuItem("Copy option", icon: "plus.square.on.square", subtitle: "Start the next option from this one") {
                if let id = editor.copyOption(id: option.id) { scrollToOption(id) }
            })
        }
        if index > 0 { menu.append(ThorbisMenuItem("Move up", icon: "arrow.up") { withAnimation { editor.moveOption(id: option.id, by: -1) } }) }
        if index < editor.options.count - 1 {
            menu.append(ThorbisMenuItem("Move down", icon: "arrow.down") { withAnimation { editor.moveOption(id: option.id, by: 1) } })
        }
        menu.append(ThorbisMenuItem("Remove option", icon: "trash", role: .destructive) { withAnimation { editor.removeOption(id: option.id) } })
        let disabled = sectionsDisabled || !optionsFeatureEnabled
        return EstimateBuilderSection(
            label: label, lines: binding.lines, disabled: disabled, focus: $focus, expandedLine: $expandedLine,
            totalLabel: "Option total", memberPricing: memberPricing, materialsSwitch: storesLineGroups, menuItems: menu,
            addItem: { picker = EstimateBuilderTarget(optionID: option.id) },
            addDiscount: canDiscount ? { discountTarget = EstimateBuilderTarget(optionID: option.id) } : nil,
            removed: { line, lineIndex in withAnimation { removed = RemovedLine(line: line, index: lineIndex, optionID: option.id) } }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Option name, like Repair", text: binding.title, prompt: .placeholder("Option name, like Repair"))
                    .font(Theme.font(17, weight: .medium))
                    .accessibilityLabel("Option package title")
                    .frame(minHeight: 40)
                TextField("What this option includes", text: binding.description, prompt: .placeholder("What this option includes"), axis: .vertical)
                    .font(Theme.font(15)).lineLimit(1...)
                    .foregroundStyle(Theme.muted)
                    .accessibilityLabel("Option package description")
            }
            .disabled(disabled)
            .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 4)
        }
        .id("option-\(option.id)")
    }

    private func optionBinding(_ id: String) -> Binding<EstimateRevisionOptionDraft> {
        Binding(
            get: { editor.options.first { $0.id == id } ?? EstimateRevisionOptionDraft(id: id, title: "", description: "", lines: []) },
            set: { value in if let index = editor.options.firstIndex(where: { $0.id == id }) { editor.options[index] = value } }
        )
    }

    private func addOption() {
        guard let id = editor.addOption(title: "", lines: []) else { return }
        scrollToOption(id)
        picker = EstimateBuilderTarget(optionID: id)
    }

    private func scrollToOption(_ id: String) {
        expandedLine = nil
        Task { @MainActor in scrollTarget = "option-\(id)" }
    }

    private var editableLines: Binding<[EstimateRevisionLineDraft]> {
        Binding(
            get: { editor.lines },
            set: { proposed in
                guard editor.canRevise else { return }
                editor.lines = proposed
                for line in proposed {
                    let quantityText = line.quantity.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let quantity = Int(quantityText), (1...100_000).contains(quantity), String(quantity) == quantityText {
                        try? editor.setQuantity(line.id, quantity)
                    }
                }
            }
        )
    }

    private var saveTitle: String {
        let verb = editingDraft ? "Save draft" : "Save revised draft"
        guard editor.options.isEmpty, let total = editor.lines.subtotal() else { return verb }
        return "\(verb) · \(money(total, currency: "USD"))"
    }

    private func refreshCatalog(force: Bool = false) async {
        guard canUsePriceBook else { return }
        let org = session.activeOrganization?.id
        let generation = session.generation
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: session.priceBookAuthority, force: force)
        guard !Task.isCancelled, session.generation == generation, session.activeOrganization?.id == org else { return }
        classifyLines()
    }

    private func classifyLines() {
        let wasUntouched = !didRecoverDraft && !hasRawDraftChanges
        editor.classify(kinds: Dictionary(catalog.items.map { ($0.id, $0.kind) }, uniquingKeysWith: { first, _ in first }))
        if wasUntouched { persistenceBaseline = editor }
    }

    private func lines(for optionID: String?) -> [EstimateRevisionLineDraft] {
        guard let optionID else { return editor.lines }
        return editor.options.first { $0.id == optionID }?.lines ?? []
    }

    private func mutateLines(_ optionID: String?, _ change: (inout [EstimateRevisionLineDraft]) -> Void) {
        if let optionID {
            guard let index = editor.options.firstIndex(where: { $0.id == optionID }) else { return }
            change(&editor.options[index].lines)
        } else {
            change(&editor.lines)
        }
    }

    /// One more of a price book item; returns why it couldn't be added, or nil.
    private func add(_ item: PriceBookListItem, to target: EstimateBuilderTarget) -> String? {
        guard !busy else { return "Saving. Try again in a moment." }
        var addedLine = false
        withAnimation(EstimateLineGroupsEditor.spring) {
            mutateLines(target.optionID) { addedLine = $0.addPriceBookItem(item, to: target.group) != nil }
        }
        guard addedLine else { return EstimateRevisionEditorError.tooManyLines.localizedDescription }
        error = nil
        return nil
    }

    private func addCustom(_ text: String, to target: EstimateBuilderTarget) {
        guard !busy else { return }
        var lineID: UUID?
        mutateLines(target.optionID) { lineID = $0.addCustomLine(text, to: target.group ?? .work) }
        guard let lineID else {
            error = EstimateRevisionEditorError.tooManyLines.localizedDescription
            return
        }
        expandedLine = lineID
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            focus = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .description(lineID) : .price(lineID)
        }
    }

    private func undoRemove() {
        guard let removed else { return }
        withAnimation(EstimateLineGroupsEditor.spring) {
            if let optionID = removed.optionID {
                if let index = editor.options.firstIndex(where: { $0.id == optionID }) {
                    editor.options[index].lines.restoreLine(removed.line, at: removed.index)
                }
            } else {
                editor.lines.restoreLine(removed.line, at: removed.index)
            }
            self.removed = nil
        }
    }

    /// Canonicalize a finished price at save time. Live keystrokes keep the raw text.
    private func commitPrices() {
        for line in editor.lines {
            guard let cents = EstimateRevisionEditorState.parsePrice(line.unitPrice) else { continue }
            try? editor.setUnitPrice(line.id, cents: cents)
        }
    }

    private func refreshDescriptionProblem() {
        let lines = editor.lines + editor.options.flatMap(\.lines)
        if lines.contains(where: { $0.estimateDescriptionProblem == .priceBookOriginalTooLong }) {
            descriptionProblem = EstimateRevisionEditorError.priceBookOriginalTooLong.localizedDescription
        } else if let problem = CommercialDescriptionPolicy.problem(lines.map(\.description), kind: .estimate,
            optionCount: editor.options.count,
            capabilityVerified: session.isFeatureOn("commercial_extended_descriptions") && !session.isOffline) {
            descriptionProblem = problem.localizedDescription
        } else {
            descriptionProblem = nil
        }
    }

    private func save() async {
        guard !editingDraft else {
            error = "Draft changes can't be saved yet."
            return
        }
        guard canRevise else {
            error = "You no longer have permission to revise this estimate."
            return
        }
        let allLines = editor.lines + editor.options.flatMap(\.lines)
        if let line = allLines.first(where: { $0.estimateDescriptionProblem == .priceBookOriginalTooLong }) {
            refreshDescriptionProblem()
            expandedLine = line.id
            revealProblem += 1
            return
        }
        let descriptions = allLines.map(\.description)
        let requiresExtended = CommercialDescriptionPolicy.isExtended(descriptions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }, kind: .estimate)
        descriptionProblem = nil
        busy = true
        defer { busy = false; if !viewVisible { releaseDraft() } }
        do {
            let verified = requiresExtended ? await session.verifyExtendedCommercialText() : false
            if requiresExtended && !verified { throw CommercialDescriptionPolicy.Problem.unavailable }
            guard canEdit else { throw CommercialDescriptionPolicy.Problem.unavailable }
            commitPrices()
            let revised = try await api.reviseFieldEstimate(
                editor.estimate.id,
                request: editor.makeRequest(optionsFeatureEnabled: optionsFeatureEnabled, canDiscount: canDiscount, extendedTextVerified: verified)
            )
            guard scopeMatches, canEdit else { error = "The workspace or access changed. Your edits are still here. Check the original workspace before retrying."; return }
            intentionallyDiscarded = true
            onSaved(revised)
            do { if ownsDraft, let draftScope { try CommercialDraftStore.shared.remove(scope: draftScope) } }
            catch {
                cleanupFailedAfterSave = true
                self.error = "The estimate was saved, but its local draft could not be removed. Close this screen and check the saved estimate before making another change."
                return
            }
            dismiss()
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
            staleRevision = (error as? Problem)?.status == 409
        }
    }

    private func reloadLatest() async {
        #if DEBUG
        CommercialDraftStore.trace("reload start")
        #endif
        guard scopeMatches, let expected = currentScope, ownsDraft else { error = "The workspace changed. Your edits are still here."; return }
        busy = true
        let attempt = UUID(); accessAttempt = attempt
        #if DEBUG
        if EstimateRecoveryPreview.heldReloadEnabled { EstimateRecoveryPreview.shared.armHeldReload() }
        #endif
        defer { busy = false; if !viewVisible { releaseDraft() } }
        do {
            let latest = try await api.fieldEstimate(estimate.id, requireFresh: true)
            #if DEBUG
            CommercialDraftStore.trace("reload response visible=\(viewVisible) scene=\(String(describing: scenePhase)) sameAttempt=\(accessAttempt == attempt) cancelled=\(Task.isCancelled)")
            #endif
            guard !Task.isCancelled, viewVisible, scenePhase == .active, !session.isOffline, accessAttempt == attempt,
                  currentScope == expected, latest.id == estimate.id,
                  latest.organizationId == expected.organizationID,
                  session.can("estimate.create", feature: "estimates"), draftScope != nil else { return }
            pendingReload = latest
            pendingReloadScope = expected
            pendingReloadAttempt = attempt
            confirmReload = true
        } catch is CancellationError {
        } catch {
            #if DEBUG
            CommercialDraftStore.trace("reload error type=\(String(describing: type(of: error)))")
            #endif
            self.error = "The draft could not be cleared or the latest document could not be verified. Your draft is still on this phone."
        }
    }

    private func invalidatePendingReload() {
        pendingReload = nil
        pendingReloadScope = nil
        pendingReloadAttempt = nil
        confirmReload = false
    }

    private func applyPendingReload() {
        guard viewVisible, scenePhase == .active, !session.isOffline, ownsDraft,
              let expected = pendingReloadScope, pendingReloadAttempt == accessAttempt, currentScope == expected, verifiedScope == expected, scopeMatches,
              session.can("estimate.create", feature: "estimates"), let latest = pendingReload,
              latest.id == estimate.id, latest.organizationId == expected.organizationID,
              let draftScope else {
            invalidatePendingReload()
            error = "The workspace changed or the document is unavailable. Your draft is still on this phone."
            return
        }
        invalidatePendingReload()
        do {
            try CommercialDraftStore.shared.remove(scope: draftScope)
            didRestoreDraft = false; didRecoverDraft = false; wroteFreshDraft = false
            editor = EstimateRevisionEditorState(estimate: latest)
            persistenceBaseline = editor
            editor.storesLineGroups = storesLineGroups
            classifyLines()
            recoveryBlocked = false; staleRevision = false; error = nil
            didRestoreDraft = true; verifiedScope = expected
        } catch {
            self.error = "The draft could not be cleared or the latest document could not be verified. Your draft is still on this phone."
        }
    }

    private func releaseDraft() {
        if ownsDraft, let draftScope { CommercialDraftStore.shared.release(scope: draftScope, owner: draftOwner) }
        ownsDraft = false
    }
}
