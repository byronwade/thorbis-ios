import SwiftUI

/// A customer as the booking search shows them: the full record (phone, address) when the role
/// can read customers, otherwise only the name the job list already carries.
struct CallerMatch: Identifiable, Hashable {
    let id: String
    let name: String
    var phone: String? = nil
    var address: String? = nil

    /// The quiet line under the name: where they are, else how to reach them.
    var detail: String? {
        [address, phone].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }
}

/// Pure helpers behind "Book a job": search, quick picks and the suggested tech.
enum BookJobSearch {
    /// Name, phone or address, as typed. Digits match a phone however it is formatted.
    static func matches(_ query: String, in people: [CallerMatch], limit: Int = 6) -> [CallerMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let digits = trimmed.filter(\.isNumber)
        let compact = trimmed.filter { !$0.isWhitespace && !"()-+.".contains($0) }
        let phoneLike = digits.count >= 3 && digits.count == compact.count
        let lowered = trimmed.lowercased()
        let found = people.filter { person in
            if person.name.localizedCaseInsensitiveContains(trimmed) { return true }
            if let address = person.address, address.localizedCaseInsensitiveContains(trimmed) { return true }
            if phoneLike, let phone = person.phone, phone.filter(\.isNumber).contains(digits) { return true }
            return false
        }
        return Array(found.sorted { lhs, rhs in
            let left = lhs.name.lowercased().hasPrefix(lowered), right = rhs.name.lowercased().hasPrefix(lowered)
            if left != right { return left }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }.prefix(limit))
    }

    /// The most recent job per customer (by visit time, else when it was created).
    static func lastJobs(_ jobs: [Job]) -> [String: Job] {
        jobs.reduce(into: [:]) { result, job in
            guard let customerID = job.customerId, job.status != "canceled" else { return }
            if let current = result[customerID], activity(current) >= activity(job) { return }
            result[customerID] = job
        }
    }

    static func activity(_ job: Job) -> Date {
        JobFiltering.date(job.scheduledFor) ?? JobFiltering.date(job.createdAt) ?? .distantPast
    }

    /// There is no job-type catalog in the API, so the quick picks are this workspace's own
    /// recent titles, the most used first.
    static func commonTitles(_ jobs: [Job], limit: Int = 6) -> [String] {
        let recent = jobs.sorted { activity($0) > activity($1) }.prefix(80)
        var counts: [String: Int] = [:]
        var spelling: [String: String] = [:]
        var order: [String] = []
        for job in recent {
            let title = job.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= 32 else { continue }
            let key = title.lowercased()
            if spelling[key] == nil { spelling[key] = title; order.append(key) }
            counts[key, default: 0] += 1
        }
        let ranked = order.enumerated().sorted { lhs, rhs in
            let left = counts[lhs.element] ?? 0, right = counts[rhs.element] ?? 0
            return left != right ? left > right : lhs.offset < rhs.offset
        }
        return ranked.prefix(limit).compactMap { spelling[$0.element] }
    }

    /// Jobs booked on `day` per technician, from the jobs this person can see. Canceled ones don't count.
    static func load(_ jobs: [Job], on day: Date, calendar: Calendar = .current) -> [String: Int] {
        jobs.reduce(into: [:]) { result, job in
            guard job.status != "canceled", let tech = job.assignedToUserId,
                  let when = JobFiltering.date(job.scheduledFor), calendar.isDate(when, inSameDayAs: day) else { return }
            result[tech, default: 0] += 1
        }
    }

    /// The least-booked technician that day; ties go by name so the pick is stable.
    static func suggested(_ people: [FieldAssignee], load: [String: Int]) -> FieldAssignee? {
        people.min { lhs, rhs in
            let left = load[lhs.userId] ?? 0, right = load[rhs.userId] ?? 0
            return left != right ? left < right : lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }
}

/// Book a job while the customer is still on the phone (CSR flow): who's calling, what's wrong,
/// where, when and who goes — one sheet, one commit. Every entry point (Schedule, Jobs, the
/// create menu, a customer's New job) opens this.
struct NewJobSheet: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FieldJobDraft
    @State private var busy = false
    @State private var error: String?
    @State private var createdJobID: String?

    // Who's calling
    @State private var query = ""
    @State private var records: [CustomerRecord] = []
    /// A customer the server's phone lookup found for the typed number.
    @State private var phoneMatch: Customer?
    /// Names learned outside the lists (lookups, a customer created here).
    @State private var knownNames: [String: String] = [:]
    @State private var addingCustomer = false
    @State private var newName = ""
    @State private var newPhone = ""
    @State private var newAddress = ""
    @State private var newLookup: CustomerPhoneLookup = .notApplicable
    @State private var showFullCustomer = false
    @State private var browsing = false

    // Where
    @State private var locations: [ServiceLocationRecord] = []
    @State private var locationsLoaded = false

    // When
    enum DayChoice: Hashable { case notYet, today, tomorrow, pick }
    @State private var dayChoice: DayChoice = .notYet
    @State private var pickedDay = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: .now)) ?? .now
    @State private var preset: Int?
    @State private var showsCustomTime = false
    @State private var customTime = NewJobSheet.nextHour()

    // Who goes
    @State private var tech: FieldAssignee?
    @State private var people: [FieldAssignee] = []

    /// Set once each part is saved, so a retry never creates a second customer or job.
    @State private var savedJob: JobRecord?
    @State private var timeSaved = false
    @State private var techSaved = false

    /// Problems shown under their fields after Book job is pressed (design.thorbis.com Forms:
    /// validate on commit, the error takes help's place). Cleared as soon as the field changes.
    @State private var callerProblem: String?
    @State private var titleProblem: String?
    @State private var timeProblem: String?

    @FocusState private var focus: Focus?
    private enum Focus: Hashable { case caller, newName, newPhone, newAddress, title, notes }

    private static let presets: [(hour: Int, minute: Int)] = [(8, 0), (10, 30), (13, 0), (15, 30)]

    private var canAssign: Bool { session.can("job.assign", feature: "jobs") }
    private var canReadCustomers: Bool { session.can("customer.view", feature: "core_crm") }
    private var canCreateCustomer: Bool { session.can("customer.create", feature: "core_crm") }
    private var locked: Bool { busy || savedJob != nil }

    init(preselected: Customer? = nil) {
        _draft = State(initialValue: FieldJobDraft(customerID: preselected?.id ?? ""))
        if let preselected { _knownNames = State(initialValue: [preselected.id: preselected.name]) }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                ScrollViewReader { reader in
                ScrollView {
                    // In the order a call gives it: who, what, where, when, who goes.
                    VStack(alignment: .leading, spacing: 24) {
                        // v2: the form's title on the compact ramp, Medium.
                        Text("New job")
                            .font(Theme.font(24, weight: .medium)).tracking(-0.3)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, 4)
                        callerSection
                        problemSection
                        if !draft.customerID.isEmpty || addingCustomer { addressSection }
                        if canAssign {
                            whenSection
                            techSection.id("book-job-tech")
                        }
                        if let error {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(Theme.font(13))
                                .foregroundStyle(Theme.destructive)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("new-job-error")
                            if let savedJob, session.can("job.view", feature: "jobs") {
                                Button("Open the job") { createdJobID = savedJob.id }
                                    .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.brandText)
                                    .frame(minHeight: 44)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.gutter).padding(.vertical, 8).padding(.bottom, 12)
                    // Redesign phase 3: result lists and the chosen customer sit on grouped wells.
                    .environment(\.paperGroupedWells, true)
                }
                .scrollDismissesKeyboard(.interactively)
                #if DEBUG
                .task {
                    // Design preview: `--paper-preview-scroll-end` shows the When and Tech sections.
                    guard PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--paper-preview-scroll-end") else { return }
                    try? await Task.sleep(for: .seconds(1.5))
                    reader.scrollTo("book-job-tech", anchor: .bottom)
                }
                #endif
                }
            }
            .foregroundStyle(Theme.foreground).background(Theme.background).buttonStyle(.plain)
            // The one commit rides above the keyboard, so typing never hides it.
            .safeAreaInset(edge: .bottom) { commit }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear(perform: start)
            .onChange(of: draft.customerID) { _, _ in callerProblem = nil }
            .onChange(of: newName) { _, _ in callerProblem = nil }
            .onChange(of: draft.title) { _, _ in titleProblem = nil }
            .onChange(of: dayChoice) { _, _ in timeProblem = nil }
            .onChange(of: preset) { _, _ in timeProblem = nil }
            .task(id: session.generation) { await loadLists() }
            .task(id: draft.customerID) { await loadLocations() }
            .task(id: CustomerPhoneLookup.digits(query)) { phoneMatch = await lookup(query) }
            .task(id: CustomerPhoneLookup.digits(newPhone)) {
                let found = await lookup(newPhone)
                newLookup = found.map(CustomerPhoneLookup.found) ?? .notApplicable
            }
            .sheet(isPresented: $browsing) {
                CustomerPickerSheet(selectedID: draft.customerID, canCreate: false, onNew: { _ in }) { id in
                    select(id); browsing = false
                }
            }
            .sheet(isPresented: $showFullCustomer) {
                NewCustomerSheet(initialName: newName, initialPhone: newPhone, initialAddress: newAddress) { customer in
                    knownNames[customer.id] = customer.name
                    select(customer.id)
                }
            }
            .thorbisDestination(isPresented: createdJobRoute) {
                if let createdJobID { JobDetailView(jobId: createdJobID) }
            }
            .thorbisDestination(for: Customer.self) { CustomerDetailView(customer: $0) }
            .thorbisDestination(for: Job.self) { JobDetailView(jobId: $0.id) }
            .thorbisDestination(for: PaperRoute.self) { PaperRouteView(route: $0) }
        }
        // A swipe never throws away what was typed (MA-16).
        .interactiveDismissDisabled(busy || (savedJob == nil && hasTypedAnything))
    }

    private var hasTypedAnything: Bool {
        !draft.title.isEmpty || !draft.notes.isEmpty || !query.isEmpty || !newName.isEmpty || !newPhone.isEmpty || !newAddress.isEmpty
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").frame(width: 38, height: 38).background(Theme.fill, in: Circle())
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Cancel new job").disabled(busy)
            Spacer()
            HStack(spacing: 5) {
                Image("ThorbisMark").resizable().scaledToFit().frame(width: 16, height: 16).accessibilityHidden(true)
                Text(session.activeOrganization?.name ?? "Workspace").font(Theme.font(13, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 12).frame(height: 30).background(Theme.fill, in: Capsule())
            Spacer()
            // Balances the close button so the workspace pill stays centred.
            Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 6).padding(.bottom, 10)
    }

    // MARK: Who's calling

    private var everyone: [CallerMatch] {
        if !records.isEmpty {
            return records.filter { !$0.archived }.map { CallerMatch(id: $0.id, name: $0.name, phone: $0.phone, address: $0.address) }
        }
        return store.customers.filter { $0.archived != true }.map { CallerMatch(id: $0.id, name: $0.name) }
    }

    private func match(for id: String) -> CallerMatch? {
        if let record = records.first(where: { $0.id == id }) {
            return CallerMatch(id: record.id, name: record.name, phone: record.phone, address: record.address)
        }
        if let name = store.customers.first(where: { $0.id == id })?.name ?? knownNames[id] { return CallerMatch(id: id, name: name) }
        return nil
    }

    private var lastJobs: [String: Job] { BookJobSearch.lastJobs(store.jobs) }

    /// Typed: up to six matches, a phone-lookup hit first. Empty: the customers with the latest jobs.
    private var shownMatches: [CallerMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let recentIDs = lastJobs.values.sorted { BookJobSearch.activity($0) > BookJobSearch.activity($1) }.compactMap(\.customerId)
            let recent = recentIDs.compactMap(match(for:)).prefix(4)
            if !recent.isEmpty { return Array(recent) }
            return Array(store.customers.filter { $0.archived != true }
                .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }.prefix(4).map { CallerMatch(id: $0.id, name: $0.name) })
        }
        var found = BookJobSearch.matches(trimmed, in: everyone)
        if let phoneMatch, !found.contains(where: { $0.id == phoneMatch.id }) {
            found.insert(match(for: phoneMatch.id) ?? CallerMatch(id: phoneMatch.id, name: phoneMatch.name), at: 0)
        }
        return found
    }

    @ViewBuilder private var callerSection: some View {
        if let chosen = draft.customerID.isEmpty ? nil : (match(for: draft.customerID) ?? CallerMatch(id: draft.customerID, name: "Customer")) {
            PaperFormField("Who's calling?") { chosenCustomer(chosen) }
        } else if addingCustomer {
            newCustomerForm
        } else {
            VStack(alignment: .leading, spacing: 10) {
                PaperFormField("Who's calling?") {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted)
                            .accessibilityHidden(true)
                        TextField("", text: $query, prompt: Text("Mike Reyes or (916) 555-0142").foregroundStyle(Theme.subtle))
                            .font(Theme.font(16))
                            .textContentType(.name)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .focused($focus, equals: .caller)
                            .accessibilityLabel("Who's calling? Search by name, phone or address")
                            .accessibilityIdentifier("book-job-caller")
                        if !query.isEmpty {
                            Button { query = "" } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(Theme.muted)
                                    .frame(width: 32, height: 32).contentShape(Rectangle())
                            }
                            .accessibilityLabel("Clear search")
                        }
                    }
                    .fieldWell()
                    if let callerProblem { FieldProblem(message: callerProblem) }
                    else { Text("Search by name, phone or street.").font(Theme.font(13)).foregroundStyle(Theme.muted) }
                }
                callerResults
            }
        }
    }

    @ViewBuilder private var callerResults: some View {
        let matches = shownMatches
        let typed = !query.trimmingCharacters(in: .whitespaces).isEmpty
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(typed ? (matches.isEmpty ? "No match" : "Matches") : "Recent customers")
                    .font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.muted)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if canReadCustomers && !store.customers.isEmpty {
                    // A 44pt target for a gloved thumb; the words stay quiet.
                    Button { browsing = true } label: {
                        Text("All customers").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.brandText)
                            .frame(minHeight: 44).padding(.horizontal, 4).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.horizontal, 4).padding(.bottom, 4)
            PaperCard {
                VStack(spacing: 0) {
                    ForEach(matches) { person in
                        // The Customers list's row: tinted initials, the name in semibold, where and the last job.
                        Button { select(person.id) } label: {
                            CustomerListRowContent(name: person.name, detail: person.detail, meta: lastJobLine(person.id))
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityHint("Books the job for \(person.name)")
                        if canCreateCustomer || person.id != matches.last?.id {
                            WellDivider(leading: CustomerListRowContent.dividerInset)
                        }
                    }
                    if canCreateCustomer {
                        Button { startNewCustomer() } label: {
                            PaperListRow(leading: .icon("person.badge.plus"),
                                         title: typed ? "New customer \u{201C}\(query.trimmingCharacters(in: .whitespaces))\u{201D}" : "New customer",
                                         subtitle: "Name, phone and address, right here")
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityIdentifier("book-job-new-customer")
                    } else if matches.isEmpty {
                        Text(typed ? "No customer matches \u{201C}\(query)\u{201D}." : "No customers yet.")
                            .font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 14)
                    }
                }
                .padding(.vertical, PaperCardMetrics.edge)
            }
        }
    }

    private func lastJobLine(_ customerID: String) -> String? {
        guard let job = lastJobs[customerID] else { return nil }
        let when = relativeDay(job.scheduledFor ?? job.createdAt)
        return when.isEmpty ? "Last job: \(job.title)" : "Last job: \(job.title) · \(when)"
    }

    private func chosenCustomer(_ person: CallerMatch) -> some View {
        PaperCard(padding: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name).font(Theme.font(16, weight: .medium)).lineLimit(2)
                    let detail = [person.phone, person.address].compactMap({ $0 }).filter({ !$0.isEmpty }).joined(separator: " · ")
                    if !detail.isEmpty {
                        Text(detail).font(Theme.font(14)).foregroundStyle(Theme.muted).lineLimit(2)
                    }
                    if let last = lastJobLine(person.id) {
                        Text(last).font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if savedJob == nil {
                    Button("Change") {
                        draft.customerID = ""
                        draft.locationID = nil
                        locations = []
                        locationsLoaded = false
                        focus = .caller
                    }
                    .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.brandText)
                    .frame(minHeight: 44).disabled(busy)
                    .accessibilityLabel("Change customer")
                }
            }
            .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 10)
            .accessibilityElement(children: .contain)
        }
    }

    private var newCustomerForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("New customer").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                Spacer()
                Button("Search instead") { addingCustomer = false; focus = .caller }
                    .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.brandText).frame(minHeight: 32)
                    .disabled(busy)
            }
            .padding(.horizontal, 4).padding(.bottom, -6)
            inlineField("Name", text: $newName, prompt: "Danielle Marlowe", focus: .newName, problem: callerProblem)
                .textContentType(.name).submitLabel(.next).onSubmit { focus = .newPhone }
            inlineField("Phone", text: $newPhone, prompt: "(555) 014-2276", focus: .newPhone)
                .textContentType(.telephoneNumber).keyboardType(.phonePad)
            if case .found(let existing) = newLookup { existingCustomerNotice(existing) }
            inlineField("Service address", text: $newAddress, prompt: "412 Birchwood Ln, Sacramento", focus: .newAddress)
                .textContentType(.fullStreetAddress).submitLabel(.next).onSubmit { focus = .title }
            // Email, account type and how they like to be reached stay one tap away.
            Button { showFullCustomer = true } label: {
                Text("More details (email, account, prefers)…").font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.brandText)
                    .frame(minHeight: 36)
            }
            .disabled(busy)
            if newName.trimmingCharacters(in: .whitespaces).count > 200 {
                FieldProblem(message: "Keep the name to 200 characters.")
            }
        }
        .disabled(locked)
    }

    private func inlineField(_ label: String, text: Binding<String>, prompt: String, focus field: Focus, problem: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(Theme.subtle))
                .font(Theme.font(16))
                .focused($focus, equals: field)
                .accessibilityLabel(label)
                .fieldWell()
            if let problem { FieldProblem(message: problem) }
        }
    }

    /// This number already belongs to someone: offer them instead of a duplicate.
    private func existingCustomerNotice(_ existing: Customer) -> some View {
        PaperCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(existing.name) already has this number").font(Theme.font(14, weight: .medium))
                Text("Use their record so the job and history stay in one place.").font(Theme.font(13)).foregroundStyle(Theme.muted)
                Button {
                    knownNames[existing.id] = existing.name
                    addingCustomer = false
                    select(existing.id)
                } label: {
                    Text("Use \(existing.name)").font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.foreground)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                }
                .buttonStyle(PressStyle())
            }
        }
    }

    // MARK: Problem

    private var problemSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaperFormField("What's wrong?") {
                TextField("", text: $draft.title, prompt: Text("AC not cooling").foregroundStyle(Theme.subtle), axis: .vertical)
                    .font(Theme.font(16))
                    .lineLimit(1...3)
                    .focused($focus, equals: .title)
                    .accessibilityLabel("Job title")
                    .disabled(locked)
                    .fieldWell()
                // Quick picks while the problem is still blank; once typed they get out of the way.
                let picks = draft.title.trimmingCharacters(in: .whitespaces).isEmpty ? BookJobSearch.commonTitles(store.jobs, limit: 5) : []
                if !picks.isEmpty && savedJob == nil {
                    FlowRow(spacing: 6, lineSpacing: 6) {
                        ForEach(picks, id: \.self) { title in
                            Button { draft.title = title; error = nil } label: {
                                Text(title).font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.foreground)
                                    .lineLimit(1).fixedSize()
                                    .padding(.horizontal, 12).frame(height: 34)
                                    .background(Theme.card, in: Capsule())
                                    .overlay(Capsule().strokeBorder(Theme.border))
                                    .padding(.vertical, 5).contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityLabel("Use \(title)")
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Recent job titles")
                }
                if draft.titleIsTooLong {
                    FieldProblem(message: "Keep the job title to 200 characters.")
                } else if let titleProblem {
                    FieldProblem(message: titleProblem)
                }
            }
            PaperFormField("Notes for the tech", note: "Optional") {
                TextField(text: $draft.notes, prompt: Text("Gate code 4412. Dog in the back yard.").foregroundStyle(Theme.subtle),
                          axis: .vertical) { Text("Job description") }
                    .font(Theme.font(15))
                    .lineLimit(2...6)
                    .focused($focus, equals: .notes)
                    .accessibilityLabel("Job description")
                    .disabled(locked)
                    .fieldWell()
                if draft.notesAreTooLong {
                    FieldProblem(message: "Keep notes to 10,000 characters.")
                } else {
                    Text("The tech reads this before they arrive.").font(Theme.font(13)).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    // MARK: Where

    @ViewBuilder private var addressSection: some View {
        PaperFormField("Service address") {
            if draft.customerID.isEmpty {
                // A new customer: the typed address is saved with them and becomes the job's place.
                Text(newAddress.trimmingCharacters(in: .whitespaces).isEmpty
                     ? "Add an address above, or set it on the job later."
                     : "\(newAddress.trimmingCharacters(in: .whitespaces)) — saved with the new customer.")
                    .font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 4)
            } else if !canReadCustomers {
                Text("Your role can't read customer addresses; the job is booked without one.")
                    .font(Theme.font(14)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
            } else if !locationsLoaded {
                SkeletonRows(count: 1, inset: 0)
            } else if locations.isEmpty {
                Text("No service address on file. Add one on the customer and set it on the job.")
                    .font(Theme.font(14)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
            } else {
                PaperCard {
                    VStack(spacing: 0) {
                        ForEach(locations) { place in
                            let chosen = draft.locationID == place.id
                            Button { draft.locationID = chosen ? nil : place.id } label: {
                                PaperListRow(title: place.address, subtitle: place.label) {
                                    if chosen {
                                        Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(Theme.brandText).accessibilityHidden(true)
                                    }
                                }
                            }
                            .buttonStyle(RowPressStyle())
                            .accessibilityAddTraits(chosen ? .isSelected : [])
                            .disabled(locked)
                        }
                    }
                    .padding(.vertical, PaperCardMetrics.edge)
                }
            }
        }
    }

    // MARK: When

    private var day: Date? {
        let calendar = Calendar.current
        switch dayChoice {
        case .notYet: return nil
        case .today: return calendar.startOfDay(for: .now)
        case .tomorrow: return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))
        case .pick: return calendar.startOfDay(for: pickedDay)
        }
    }

    private var when: Date? {
        guard let day else { return nil }
        if showsCustomTime {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: customTime)
            return JobScheduleSelection.date(on: day, hour: parts.hour ?? 9, minute: parts.minute ?? 0)
        }
        guard let preset, Self.presets.indices.contains(preset) else { return nil }
        return JobScheduleSelection.date(on: day, hour: Self.presets[preset].hour, minute: Self.presets[preset].minute)
    }

    private var whenSection: some View {
        PaperFormField("When", note: "Optional") {
            ThorbisSegmented(options: [(DayChoice.notYet, "Not yet"), (.today, "Today"), (.tomorrow, "Tomorrow"), (.pick, "Pick day")],
                             selection: Binding(get: { dayChoice }, set: { dayChoice = $0; timeSaved = false; dropPastPreset() }))
                .disabled(busy || timeSaved)
            if let timeProblem { FieldProblem(message: timeProblem) }
            if dayChoice == .pick {
                DatePicker("Day", selection: $pickedDay, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Theme.brand)
                    .accessibilityLabel("Choose the day")
                    .disabled(busy || timeSaved)
            }
            if let day {
                Text("Arrival · 2 hr window").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                    .padding(.top, 6).accessibilityHidden(true)
                PaperCard {
                    VStack(spacing: 0) {
                        ForEach(Self.presets.indices, id: \.self) { index in timeRow(index, on: day) }
                        if showsCustomTime {
                            HStack {
                                Text("Other time").font(Theme.font(16, weight: .medium))
                                Spacer()
                                DatePicker("Other time", selection: $customTime, displayedComponents: .hourAndMinute)
                                    .labelsHidden().datePickerStyle(.compact)
                                    .accessibilityLabel("Choose a start time")
                                Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.brandText).accessibilityHidden(true)
                            }
                            .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 52)
                        } else {
                            Button { showsCustomTime = true; preset = nil; timeSaved = false } label: {
                                Text("Other time…").font(Theme.font(16, weight: .medium))
                                    .padding(.horizontal, PaperCardMetrics.inset)
                                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).contentShape(Rectangle())
                            }
                            .buttonStyle(RowPressStyle())
                        }
                    }
                    .padding(.vertical, PaperCardMetrics.edge)
                }
                .disabled(busy || timeSaved)
                if when == nil {
                    Text("Pick an arrival time, or choose Not yet.").font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                }
            }
        }
    }

    private func timeRow(_ index: Int, on day: Date) -> some View {
        let option = Self.presets[index]
        let start = JobScheduleSelection.date(on: day, hour: option.hour, minute: option.minute)
        let past = start.map { $0 < .now } ?? true
        let chosen = preset == index && !showsCustomTime
        let label = start?.tradeTime ?? "\(option.hour):\(String(format: "%02d", option.minute))"
        return Button { preset = index; showsCustomTime = false; timeSaved = false } label: {
            HStack {
                Text(label).font(Theme.font(16, weight: .medium)).monospacedDigit()
                    .foregroundStyle(past ? Theme.muted : Theme.foreground)
                if past { Text("· passed").font(Theme.font(14)).foregroundStyle(Theme.muted) }
                Spacer()
                if chosen {
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.brandText).accessibilityHidden(true)
                }
            }
            .padding(.horizontal, PaperCardMetrics.inset).frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .disabled(past)
        .accessibilityLabel("\(label), two hour arrival window")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// Switching to Today drops a chosen time that has already gone by.
    private func dropPastPreset() {
        guard let day, let preset, let start = JobScheduleSelection.date(on: day, hour: Self.presets[preset].hour,
                                                                          minute: Self.presets[preset].minute), start < .now else { return }
        self.preset = nil
    }

    // MARK: Who goes

    @ViewBuilder private var techSection: some View {
        let load = day.map { BookJobSearch.load(store.jobs, on: $0) } ?? [:]
        let suggestion = day == nil ? nil : BookJobSearch.suggested(people, load: load)
        let ordered = people.sorted { lhs, rhs in
            if lhs == suggestion { return true }
            if rhs == suggestion { return false }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
        PaperFormField("Tech", note: day == nil ? "Optional · pick a day to see who's free" : "Optional") {
            PaperCard {
                VStack(spacing: 0) {
                    techRow(name: "No tech yet", detail: nil, suggested: false, chosen: tech == nil, placeholder: true) { tech = nil; techSaved = false }
                    ForEach(ordered) { person in
                        let count = load[person.userId] ?? 0
                        techRow(name: person.displayName,
                                detail: day == nil ? nil : "\(count) job\(count == 1 ? "" : "s") that day",
                                suggested: person == suggestion, chosen: tech == person) { tech = person; techSaved = false }
                    }
                }
                .padding(.vertical, PaperCardMetrics.edge)
            }
            .disabled(busy || techSaved)
            if people.isEmpty {
                Text("Loading the team…").font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
            }
        }
    }

    private func techRow(name: String, detail: String?, suggested: Bool, chosen: Bool, placeholder: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if placeholder {
                    Image(systemName: "person.crop.circle.badge.questionmark").font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.muted).frame(width: 30, height: 30).background(Theme.fill, in: Circle())
                        .accessibilityHidden(true)
                } else {
                    Avatar(name: name, size: 30)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    if let detail { Text(detail).font(Theme.font(14)).foregroundStyle(Theme.muted).monospacedDigit() }
                }
                Spacer(minLength: 8)
                if suggested {
                    Text("Suggested").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 8).frame(height: 24).background(Theme.fill, in: Capsule())
                }
                if chosen {
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.brandText).accessibilityHidden(true)
                }
            }
            .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 52).contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel([name, detail, suggested ? "Suggested, fewest jobs that day" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    // MARK: Commit

    private var newCustomerValid: Bool {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= 200 && newPhone.count <= 30 && newAddress.count <= 500
    }

    private var canBook: Bool {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let who = !draft.customerID.isEmpty || (addingCustomer && newCustomerValid && canCreateCustomer)
        let timeOK = !canAssign || dayChoice == .notYet || when != nil
        return who && !title.isEmpty && !draft.titleIsTooLong && !draft.notesAreTooLong && timeOK
            && session.can("job.create", feature: "jobs")
    }

    /// The one commit is never pre-disabled (design.thorbis.com "Don't lock the commit"): pressed
    /// with something missing, it says what under the field. While saving, the word stays and the
    /// mark turns.
    private var commit: some View {
        Button {
            if savedJob == nil && !canBook { showProblems(); return }
            Task { await book() }
        } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(Theme.onInk) }
                Text(savedJob == nil ? "Book job" : "Try again")
            }
            .inkCommit(enabled: session.can("job.create", feature: "jobs"))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(savedJob == nil ? "Book job" : "Try saving again")
        .accessibilityIdentifier("book-job-commit")
        .disabled(busy || !session.can("job.create", feature: "jobs"))
        .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 10)
        .background(Theme.background)
    }

    /// Says what's missing under each field, and moves to the first one.
    private func showProblems() {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.customerID.isEmpty {
            if addingCustomer {
                callerProblem = !canCreateCustomer ? "Your role can't add customers. Search for one instead."
                    : newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add the caller's name, like Danielle Marlowe." : nil
            } else {
                callerProblem = "Pick who's calling, or add them as a new customer."
            }
        } else { callerProblem = nil }
        titleProblem = title.isEmpty ? "Say what's wrong, like \u{201C}AC not cooling.\u{201D}" : nil
        timeProblem = canAssign && dayChoice != .notYet && when == nil ? "Pick an arrival time, or choose Not yet." : nil
        if callerProblem == nil, draft.customerID.isEmpty, addingCustomer {
            if newPhone.count > 30 { callerProblem = "Keep the phone number to 30 characters." }
            else if newAddress.count > 500 { callerProblem = "Keep the address to 500 characters." }
        }
        if callerProblem == nil, titleProblem == nil, timeProblem == nil, !draft.titleIsTooLong, !draft.notesAreTooLong {
            // Nothing in a field explains it: say so where the page's problems go.
            error = session.can("job.create", feature: "jobs") ? "This job can't be booked yet. Check each field above." : "Your role can't book jobs."
        }
        if callerProblem != nil { focus = addingCustomer ? .newName : .caller }
        else if titleProblem != nil { focus = .title }
    }

    // MARK: Actions

    private func start() {
        if draft.customerID.isEmpty { focus = .caller } else if draft.title.isEmpty { focus = .title }
        #if DEBUG
        if PaperPreview.enabled && PaperPreview.screen == "book-job" { query = "Mar" }
        // `--paper-preview-form-errors`: Book job pressed with the form blank, so the field errors show.
        if PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-form-errors") {
            query = ""
            showProblems()
            focus = nil
        }
        if PaperPreview.enabled && PaperPreview.screen == "book-job-filled" {
            select(PaperPreview.customerID)
            draft.title = "AC not cooling"
            dayChoice = .today
            showsCustomTime = true
            customTime = Calendar.current.date(byAdding: .hour, value: 2, to: NewJobSheet.nextHour()) ?? customTime
            focus = nil
        }
        #endif
    }

    private func select(_ id: String) {
        draft.customerID = id
        draft.locationID = nil
        addingCustomer = false
        locations = []
        locationsLoaded = false
        query = ""
        error = nil
        focus = draft.title.isEmpty ? .title : nil
    }

    private func startNewCustomer() {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // A typed number seeds the phone; anything else seeds the name.
        if !typed.isEmpty && typed.filter(\.isNumber).count >= 7 && typed.filter(\.isLetter).isEmpty {
            newPhone = typed
        } else if !typed.isEmpty {
            newName = typed
        }
        addingCustomer = true
        focus = newName.isEmpty ? .newName : .newPhone
    }

    private func loadLists() async {
        let generation = session.generation
        async let roster: [FieldAssignee] = canAssign ? ((try? await api.fieldAssignees()) ?? []) : []
        async let all: [CustomerRecord] = canReadCustomers ? ((try? await api.fieldCustomers()) ?? []) : []
        let (team, customers) = await (roster, all)
        guard session.generation == generation, !Task.isCancelled else { return }
        let organizationID = session.activeOrganization?.id
        people = team
        records = customers.filter { $0.organizationId == organizationID }
    }

    private func loadLocations() async {
        let customerID = draft.customerID
        guard !customerID.isEmpty, canReadCustomers else { return }
        let generation = session.generation
        let organizationID = session.activeOrganization?.id
        let places = (try? await api.fieldLocations(customerID)) ?? []
        guard session.generation == generation, draft.customerID == customerID, !Task.isCancelled else { return }
        locations = places.filter { $0.customerId == customerID && $0.organizationId == organizationID }
        locationsLoaded = true
        // One place on file is the place; with several the CSR picks.
        if draft.locationID == nil, locations.count == 1 { draft.locationID = locations[0].id }
    }

    /// The server's phone lookup for a typed number (7+ digits). Never blocks booking.
    private func lookup(_ phone: String) async -> Customer? {
        guard CustomerPhoneLookup.digits(phone).count >= 7, canReadCustomers else { return nil }
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled else { return nil }
        if case .found(let customer) = (try? await api.lookupCustomer(phone: phone)) ?? .unknown {
            knownNames[customer.id] = customer.name
            return customer
        }
        return nil
    }

    private static func nextHour() -> Date {
        let calendar = Calendar.current
        let next = calendar.date(byAdding: .hour, value: 1, to: .now) ?? .now
        return calendar.date(bySetting: .minute, value: 0, of: next) ?? next
    }

    private var createdJobRoute: Binding<Bool> {
        Binding(
            get: { createdJobID != nil },
            set: { isPresented in
                guard !isPresented, createdJobID != nil else { return }
                createdJobID = nil
                dismiss()
            }
        )
    }

    private func book() async {
        guard !busy, session.can("job.create", feature: "jobs") else { return }
        let sessionGeneration = session.generation
        let organizationID = session.activeOrganization?.id
        func stillHere() -> Bool { session.generation == sessionGeneration && session.activeOrganization?.id == organizationID }
        error = nil
        busy = true
        defer { busy = false }
        focus = nil
        do {
            // 1. A new caller becomes a customer first (once; a retry reuses them).
            if draft.customerID.isEmpty {
                guard addingCustomer, newCustomerValid, canCreateCustomer else { return }
                func clean(_ value: String) -> String? {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
                let body = NewCustomerRequest(name: newName.trimmingCharacters(in: .whitespacesAndNewlines),
                                              phone: clean(newPhone), address: clean(newAddress), accountType: "residential")
                let customer = try await api.createCustomer(body)
                guard stillHere() else { return }
                knownNames[customer.id] = customer.name
                draft.customerID = customer.id
                addingCustomer = false
                // The address saved with them is their one place; use it when the server made one.
                if body.address != nil, canReadCustomers, let places = try? await api.fieldLocations(customer.id) {
                    locations = places.filter { $0.customerId == customer.id && $0.organizationId == organizationID }
                    locationsLoaded = true
                    if locations.count == 1 { draft.locationID = locations[0].id }
                }
                guard stillHere() else { return }
            }
            // 2. The job (once; a failed time or tech retries on the same job).
            let job: JobRecord
            if let savedJob {
                job = savedJob
            } else {
                guard let request = draft.request else { return }
                job = try await api.createFieldJob(request)
                savedJob = job
            }
            guard stillHere() else { return }
            // 3. When and who, each only when chosen.
            var failed: [String] = []
            if canAssign, let when, !timeSaved,
               let request = JobScheduleSelection.request(for: job, selectedDate: when, timeZone: .current) {
                do {
                    _ = try await api.scheduleFieldJob(job.id, request: request)
                    timeSaved = true
                } catch is CancellationError { return } catch { failed.append("time") }
            }
            if canAssign, let tech, !techSaved {
                do {
                    _ = try await api.assignFieldJob(job.id, request: FieldAssignRequest(userId: tech.userId, expected: .unassigned))
                    techSaved = true
                } catch is CancellationError { return } catch { failed.append("technician") }
            }
            _ = await store.refresh(api)
            guard stillHere() else { return }
            if !failed.isEmpty {
                error = "The job was booked, but the \(failed.joined(separator: " and ")) didn't save. Tap Try again, or open the job to set it there."
                return
            }
            if session.can("job.view", feature: "jobs") { createdJobID = job.id } else { dismiss() }
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}
