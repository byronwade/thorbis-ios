import SwiftUI

func statusIcon(_ s: String) -> (String, Color) {
    switch s {
    case "completed": return ("checkmark.circle.fill", Theme.success)
    case "in_progress", "arrived": return ("circle.lefthalf.filled", Theme.warning)
    case "en_route", "dispatched": return ("arrow.right.circle", Theme.brand)
    case "canceled": return ("xmark.circle", Theme.destructive)
    default: return ("circle", Theme.muted)
    }
}

struct JobRow: View {
    let job: Job
    let customer: String
    var body: some View {
        let (icon, tint) = statusIcon(job.status)
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).font(.system(size: 14))
            Text(job.shortRef).font(Theme.mono).foregroundStyle(Theme.muted)
            Text("\(job.title) — \(customer.split(separator: " ").last.map(String.init) ?? customer)")
                .font(.system(size: 14, weight: .medium)).lineLimit(1)
                .foregroundStyle(job.status == "completed" ? Theme.muted : Theme.foreground)
            Spacer()
            Avatar(name: customer, size: 22)
        }
        .padding(.horizontal, 16).frame(height: 44).contentShape(Rectangle())
    }
}

struct ScheduleView: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @State private var range = "Today"
    var active: [Job] { store.jobs.filter { !["completed", "canceled"].contains($0.status) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(icon: "calendar", title: "Schedule",
                             subtitle: "\(Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(active.count) jobs open")
                SegmentTabs(options: ["Today", "Week", "Map"], selected: $range)
                if let e = store.error { ErrorBanner(message: e) }
                if let next = active.first {
                    HStack { Text("Next up").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                        Text("updated \(relativeDay(next.updatedAt))").font(Theme.mono).foregroundStyle(Theme.muted.opacity(0.7)); Spacer() }
                        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
                    NavigationLink(value: next) { NextUpCard(job: next, customer: store.customerName(next.customerId)) }.buttonStyle(.plain)
                }
                SectionHeader(title: "Later", count: max(active.count - 1, 0))
                ForEach(active.dropFirst()) { j in
                    NavigationLink(value: j) {
                        HStack(alignment: .top, spacing: 12) {
                            Text(j.status.statusLabel).font(Theme.mono).foregroundStyle(Theme.muted).frame(width: 74, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(j.title) — \(store.customerName(j.customerId))").font(.system(size: 14, weight: .medium)).lineLimit(1)
                                Text(j.shortRef).font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: statusIcon(j.status).0).foregroundStyle(statusIcon(j.status).1).font(.system(size: 13))
                        }.padding(.horizontal, 16).padding(.vertical, 8).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                if active.isEmpty && !store.loading {
                    Text("Nothing scheduled. New jobs from the API show up here.").font(.system(size: 14)).foregroundStyle(Theme.muted).padding(16)
                }
                Spacer(minLength: 100)
            }
        }
        .refreshable { await store.refresh(api) }
    }
}

struct NextUpCard: View {
    let job: Job
    let customer: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text(job.status.statusLabel).font(Theme.mono).frame(width: 74, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.title).font(.system(size: 15, weight: .semibold))
                    Text(customer).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    HStack { Chip(text: job.status.statusLabel, icon: "arrow.right", tint: Theme.brand, bg: Theme.brandSurface); Chip(text: job.shortRef) }
                }
            }
            HStack(spacing: 8) {
                Label("Open job", systemImage: "location.north.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 34).background(Theme.brand, in: RoundedRectangle(cornerRadius: 8))
                Image(systemName: "phone").frame(width: 34, height: 34).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                Image(systemName: "bubble.left").frame(width: 34, height: 34).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
            }.padding(.leading, 86).font(.system(size: 13))
        }
        .padding(16).background(Theme.chrome)
    }
}

struct JobsView: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @State private var filter = "Assigned"
    @State private var showNew = false
    let groups: [(String, Set<String>)] = [
        ("In progress", ["in_progress", "arrived", "en_route", "dispatched"]),
        ("Scheduled", ["scheduled", "unscheduled", "draft"]),
        ("Done", ["completed"]),
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(icon: "briefcase", title: "Jobs",
                             subtitle: "\(store.jobs.filter { $0.status != "completed" }.count) active · \(store.jobs.count) total")
                SegmentTabs(options: ["Assigned", "All jobs", "Recent"], selected: $filter)
                if let e = store.error { ErrorBanner(message: e) }
                ForEach(groups, id: \.0) { g in
                    let items = store.jobs.filter { g.1.contains($0.status) }
                    if !items.isEmpty {
                        HStack { SectionHeader(title: g.0, count: items.count)
                            if g.0 != "Done" { Button { showNew = true } label: { Image(systemName: "plus") }.foregroundStyle(Theme.muted).padding(.trailing, 16).padding(.top, 12) } }
                        ForEach(items) { j in NavigationLink(value: j) { JobRow(job: j, customer: store.customerName(j.customerId)) }.buttonStyle(.plain) }
                    }
                }
                Spacer(minLength: 100)
            }
        }
        .refreshable { await store.refresh(api) }
        .sheet(isPresented: $showNew) { NewJobSheet().presentationDetents([.medium]) }
    }
}

struct NewJobSheet: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    var preselected: Customer? = nil
    @State private var title = ""
    @State private var customerId = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New job").font(.system(size: 20, weight: .bold))
            TextField("What's the job?", text: $title).padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            Picker("Customer", selection: $customerId) {
                ForEach(store.customers) { Text($0.name).tag($0.id) }
            }.pickerStyle(.menu)
            if let error { Text(error).foregroundStyle(Theme.destructive).font(.system(size: 13)) }
            PrimaryButton(title: "Create job", icon: "plus") {
                Task {
                    do { _ = try await api.createJob(customerId: customerId, title: title); await store.refresh(api); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
            }
            Spacer()
        }
        .padding(20).background(Theme.background)
        .onAppear { customerId = preselected?.id ?? store.customers.first?.id ?? "" }
    }
}

struct JobDetailView: View {
    let jobId: String
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @State private var job: Job?
    @State private var tab = "Overview"
    @State private var busy = false
    @State private var error: String?

    var nextStep: String? {
        guard let t = job?.allowedTransitions else { return nil }
        for s in ["en_route", "arrived", "in_progress"] where t.contains(s) { return s }
        return nil
    }
    var body: some View {
        ScrollView {
            if let job {
                let customer = store.customerName(job.customerId)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(job.shortRef) · \(customer)").font(Theme.mono).foregroundStyle(Theme.muted).padding(.horizontal, 16)
                    Text(job.title).font(.system(size: 24, weight: .bold)).padding(.horizontal, 16).padding(.top, 4)
                    HStack {
                        let (icon, tint) = statusIcon(job.status)
                        Chip(text: job.status.statusLabel, icon: icon, tint: tint, bg: tint.opacity(0.15))
                        Chip(text: "Updated \(relativeDay(job.updatedAt))", icon: "clock")
                    }.padding(.horizontal, 16).padding(.top, 10)
                    SegmentTabs(options: ["Overview", "Estimates", "Invoice", "Media", "Activity"], selected: $tab)
                    if let error { ErrorBanner(message: error) }
                    HStack { Text("Details").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted); Spacer() }
                        .padding(.horizontal, 16).padding(.top, 18)
                    detail("Customer", customer)
                    detail("Status", job.status.statusLabel)
                    detail("Created", relativeDay(job.createdAt))
                    detail("Job ID", String(job.id.prefix(13)) + "…", mono: true)
                    SectionHeader(title: "Next steps", count: job.allowedTransitions?.count)
                    FlowChips(items: (job.allowedTransitions ?? []).map { $0.statusLabel })
                    Spacer(minLength: 120)
                }.padding(.top, 8)
            } else if let error { ErrorBanner(message: error) } else { ProgressView().padding(40) }
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) {
            if let step = nextStep {
                HStack(spacing: 8) {
                    PrimaryButton(title: "Mark \(step.statusLabel.lowercased())", icon: "checkmark.circle", busy: busy) { Task { await advance(step) } }
                    Image(systemName: "phone").frame(width: 44, height: 44).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                }.padding(.horizontal, 16).padding(.vertical, 10).background(Theme.background)
            }
        }
        .toolbarBackground(Theme.background, for: .navigationBar)
        .task { await load() }
    }

    func detail(_ k: String, _ v: String, mono: Bool = false) -> some View {
        HStack { Text(k).foregroundStyle(Theme.muted); Spacer(); Text(v).font(mono ? Theme.mono : .system(size: 14, weight: .medium)) }
            .font(.system(size: 14)).padding(.horizontal, 16).frame(height: 40)
    }
    func load() async {
        do { job = try await api.job(jobId) } catch { self.error = error.localizedDescription }
    }
    func advance(_ step: String) async {
        busy = true; defer { busy = false }
        do { try await api.progress(jobId, to: step); await load(); await store.refresh(api); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct FlowChips: View {
    let items: [String]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack { ForEach(items, id: \.self) { Chip(text: $0) } }.padding(.horizontal, 16)
        }
    }
}

struct CustomersView: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @State private var showNew = false
    @State private var newName = ""
    var grouped: [(String, [Customer])] {
        Dictionary(grouping: store.customers.filter { $0.archived != true }) { String($0.name.prefix(1)).uppercased() }
            .sorted { $0.key < $1.key }.map { ($0.key, $0.value.sorted { $0.name < $1.name }) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(icon: "person.2", title: "Customers",
                             subtitle: "\(store.customers.count) customers · \(store.jobs.filter { $0.status != "completed" }.count) active jobs")
                if let e = store.error { ErrorBanner(message: e) }
                ForEach(grouped, id: \.0) { letter, items in
                    SectionHeader(title: letter, count: items.count)
                    ForEach(items) { c in
                        NavigationLink(value: c) {
                            HStack(spacing: 12) {
                                Avatar(name: c.name, size: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(c.name).font(.system(size: 14, weight: .medium))
                                    Text("\(store.jobs.filter { $0.customerId == c.id }.count) jobs").font(.system(size: 12)).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                if let open = store.jobs.first(where: { $0.customerId == c.id && $0.status != "completed" }) {
                                    Image(systemName: statusIcon(open.status).0).foregroundStyle(statusIcon(open.status).1)
                                }
                            }.padding(.horizontal, 16).frame(height: 48).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 100)
            }
        }
        .refreshable { await store.refresh(api) }
        .alert("New customer", isPresented: $showNew) {
            TextField("Name", text: $newName)
            Button("Create") { Task { _ = try? await api.createCustomer(name: newName); newName = ""; await store.refresh(api) } }
            Button("Cancel", role: .cancel) {}
        }
        .overlay(alignment: .bottomTrailing) {
            Button { showNew = true } label: { Image(systemName: "plus").font(.system(size: 16, weight: .semibold)) }
                .foregroundStyle(Theme.foreground).frame(width: 46, height: 46).background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(Theme.border)).padding(.trailing, 16).padding(.bottom, 64)
        }
    }
}

struct CustomerDetailView: View {
    let customer: Customer
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @State private var tab = "Overview"
    @State private var showNew = false
    var jobs: [Job] { store.jobs.filter { $0.customerId == customer.id } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("CUS-\(String(customer.id.suffix(4)).uppercased()) · Customer since \(relativeDay(customer.createdAt))").font(Theme.mono).foregroundStyle(Theme.muted).padding(.horizontal, 16)
                Text(customer.name).font(.system(size: 24, weight: .bold)).padding(.horizontal, 16).padding(.top, 4)
                HStack {
                    if jobs.contains(where: { $0.status == "in_progress" }) { Chip(text: "Job in progress", icon: "circle.lefthalf.filled", tint: Theme.warning, bg: Theme.warningSurface) }
                    Chip(text: "\(jobs.count) jobs", icon: "clock")
                }.padding(.horizontal, 16).padding(.top, 10)
                SegmentTabs(options: ["Overview", "Jobs", "Billing", "Media", "Activity"], selected: $tab)
                SectionHeader(title: "Job history", count: jobs.count)
                ForEach(jobs) { j in NavigationLink(value: j) { JobRow(job: j, customer: customer.name) }.buttonStyle(.plain) }
                if jobs.isEmpty { Text("No jobs yet.").font(.system(size: 14)).foregroundStyle(Theme.muted).padding(.horizontal, 16) }
                Spacer(minLength: 120)
            }.padding(.top, 8)
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "New job", icon: "plus") { showNew = true }.padding(.horizontal, 16).padding(.vertical, 10).background(Theme.background)
        }
        .sheet(isPresented: $showNew) { NewJobSheet(preselected: customer).presentationDetents([.medium]) }
    }
}

struct MoreView: View {
    @EnvironmentObject var api: APIClient
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Text("T").font(.system(size: 11, weight: .bold)).foregroundStyle(.white).frame(width: 20, height: 20).background(Theme.brand, in: RoundedRectangle(cornerRadius: 5))
                    Text(api.displayName.isEmpty ? "Workspace" : api.displayName).font(.system(size: 14, weight: .semibold))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(Theme.muted)
                }.padding(.horizontal, 10).frame(height: 34).background(Theme.surface, in: Capsule())
                Spacer()
            }.padding(16)
            VStack(alignment: .leading, spacing: 2) {
                row("calendar", "Schedule"); row("briefcase", "Jobs"); row("person.2", "Customers")
                row("bubble.left", "Messages"); row("book.closed", "Price book"); row("clock", "Time clock")
                Divider().overlay(Theme.border).padding(.vertical, 4)
                Button { api.signOut() } label: { rowLabel("rectangle.portrait.and.arrow.right", "Sign out") }.foregroundStyle(Theme.destructive)
            }
            .padding(6).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border)).padding(.horizontal, 16)
            Spacer()
        }
    }
    func row(_ icon: String, _ t: String) -> some View { rowLabel(icon, t).foregroundStyle(Theme.foreground) }
    func rowLabel(_ icon: String, _ t: String) -> some View {
        HStack(spacing: 10) { Image(systemName: icon).frame(width: 20).foregroundStyle(Theme.muted); Text(t).font(.system(size: 15)); Spacer() }
            .padding(.horizontal, 10).frame(height: 40)
    }
}
