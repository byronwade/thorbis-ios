import SwiftUI
import UniformTypeIdentifiers

// Bring customers from other software (web onboarding "Import from your old software").
// `POST /v1/customer-imports` {dryRun, rows}: the server never sees the file, only rows already
// mapped to {name, phones, emails, addresses, notes}. At most 100 rows and 200 records per request
// (domains/customers CUSTOMER_IMPORT_MAX_ROWS / MAX_WORK), so rows are chunked by both.

/// A small RFC 4180 reader: quoted fields, doubled quotes, commas and line breaks inside quotes.
/// Blank rows are kept so a row's position still matches the row number in the spreadsheet.
enum CSVReader {
    static func rows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var iterator = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = iterator.next()
        while let scalar = pending {
            pending = iterator.next()
            if quoted {
                if scalar == "\"" {
                    if pending == "\"" { field.unicodeScalars.append("\""); pending = iterator.next() }
                    else { quoted = false }
                } else {
                    field.unicodeScalars.append(scalar)
                }
                continue
            }
            switch scalar {
            case "\"": quoted = true
            case ",": row.append(field); field = ""
            case "\r":
                if pending == "\n" { pending = iterator.next() }
                row.append(field); rows.append(row); row = []; field = ""
            case "\n":
                row.append(field); rows.append(row); row = []; field = ""
            default: field.unicodeScalars.append(scalar)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows.map { $0.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
    }

    static func isBlank(_ row: [String]) -> Bool { row.allSatisfy(\.isEmpty) }
}

/// Which column feeds each customer field. Columns are header positions; nil means unused.
struct CustomerImportMapping: Equatable {
    enum Field: Hashable { case name, firstName, lastName, phone, email, address, city, state, zip, notes }

    subscript(field: Field) -> Int? {
        get {
            switch field {
            case .name: name
            case .firstName: firstName
            case .lastName: lastName
            case .phone: phone
            case .email: email
            case .address: address
            case .city: city
            case .state: state
            case .zip: zip
            case .notes: notes
            }
        }
        set {
            switch field {
            case .name: name = newValue
            case .firstName: firstName = newValue
            case .lastName: lastName = newValue
            case .phone: phone = newValue
            case .email: email = newValue
            case .address: address = newValue
            case .city: city = newValue
            case .state: state = newValue
            case .zip: zip = newValue
            case .notes: notes = newValue
            }
        }
    }

    var name: Int?
    var firstName: Int?
    var lastName: Int?
    var phone: Int?
    var email: Int?
    var address: Int?
    var city: Int?
    var state: Int?
    var zip: Int?
    var notes: Int?

    /// Guesses from common export headers (ServiceTitan, Housecall Pro, Jobber, QuickBooks, Excel).
    static func guess(_ headers: [String]) -> CustomerImportMapping {
        let keys = headers.map { $0.lowercased().replacingOccurrences(of: "_", with: " ") }
        func first(_ test: (String) -> Bool) -> Int? { keys.firstIndex(where: test) }
        var mapping = CustomerImportMapping()
        mapping.firstName = first { $0.contains("first") && $0.contains("name") }
        mapping.lastName = first { $0.contains("last") && $0.contains("name") }
        mapping.name = first { key in
            ["name", "customer", "customer name", "full name", "display name", "client", "client name", "company", "company name"].contains(key)
        } ?? first { $0.contains("name") && !$0.contains("first") && !$0.contains("last") && !$0.contains("user") }
        mapping.phone = first { $0.contains("phone") || $0.contains("mobile") || $0.contains("cell") || $0 == "tel" }
        mapping.email = first { $0.contains("email") || $0.contains("e-mail") }
        mapping.address = first { ["address", "street", "address 1", "address line 1", "street address", "service address", "billing address"].contains($0) }
            ?? first { $0.contains("address") || $0.contains("street") }
        mapping.city = first { $0 == "city" || $0.hasSuffix(" city") }
        mapping.state = first { $0 == "state" || $0 == "province" || $0 == "region" || $0.hasSuffix(" state") }
        mapping.zip = first { $0.contains("zip") || $0.contains("postal") }
        mapping.notes = first { $0.contains("note") || $0.contains("comment") }
        return mapping
    }

    var canImport: Bool { name != nil || firstName != nil || lastName != nil }
}

struct CustomerImportRow: Encodable, Equatable {
    let name: String
    var phones: [String]?
    var emails: [String]?
    var addresses: [String]?
    var notes: String?

    /// Records the server counts against a request: the customer, each contact and each address.
    var work: Int { 1 + (phones?.count ?? 0) + (emails?.count ?? 0) + (addresses?.count ?? 0) }

    static let maxRowsPerRequest = 100
    static let maxWorkPerRequest = 200

    /// Splits rows so no request passes either server limit; the same rows always split the same way.
    static func chunks(_ rows: [CustomerImportRow]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start = 0, work = 0
        for (index, row) in rows.enumerated() {
            if index > start, index - start >= maxRowsPerRequest || work + row.work > maxWorkPerRequest {
                ranges.append(start..<index)
                start = index
                work = 0
            }
            work += row.work
        }
        if start < rows.count { ranges.append(start..<rows.count) }
        return ranges
    }

    /// One spreadsheet row to the server's shape; nil when it has no name to import.
    static func from(_ cells: [String], mapping: CustomerImportMapping) -> CustomerImportRow? {
        func cell(_ index: Int?) -> String {
            guard let index, cells.indices.contains(index) else { return "" }
            return cells[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var name = cell(mapping.name)
        if name.isEmpty {
            name = [cell(mapping.firstName), cell(mapping.lastName)].filter { !$0.isEmpty }.joined(separator: " ")
        }
        guard !name.isEmpty else { return nil }
        let split: (String) -> [String] = { value in
            value.split(whereSeparator: { $0 == ";" || $0 == "|" || $0 == "\n" })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        let phones = Array(split(cell(mapping.phone)).prefix(5))
        let emails = Array(split(cell(mapping.email)).prefix(5))
        let street = cell(mapping.address)
        let stateZip = [cell(mapping.state), cell(mapping.zip)].filter { !$0.isEmpty }.joined(separator: " ")
        let address = [street, cell(mapping.city), stateZip].filter { !$0.isEmpty }.joined(separator: ", ")
        let notes = cell(mapping.notes)
        return CustomerImportRow(name: String(name.prefix(200)),
                                 phones: phones.isEmpty ? nil : phones,
                                 emails: emails.isEmpty ? nil : emails,
                                 addresses: street.isEmpty ? nil : [String(address.prefix(500))],
                                 notes: notes.isEmpty ? nil : String(notes.prefix(2000)))
    }
}

struct CustomerImportResult: Decodable, Equatable {
    struct Summary: Decodable, Equatable { let new: Int; let duplicate: Int; let invalid: Int }
    struct Outcome: Decodable, Equatable {
        let row: Int
        let status: String
        let name: String?
        let reasons: [String]?
        let matchedOn: String?
    }
    let dryRun: Bool
    let summary: Summary
    let rows: [Outcome]
}

extension APIClient {
    func importCustomers(_ rows: [CustomerImportRow], dryRun: Bool) async throws -> CustomerImportResult {
        struct Body: Encodable { let dryRun: Bool; let rows: [CustomerImportRow] }
        return try await send("POST", "/v1/customer-imports", body: Body(dryRun: dryRun, rows: rows))
    }
}

@MainActor
final class CustomerImportModel: ObservableObject {
    enum Phase: Equatable { case choose, map, checking, preview, importing, done }

    @Published var phase: Phase = .choose
    @Published var fileName = ""
    @Published var headers: [String] = []
    /// Every row under the header, blank ones included, so positions map back to spreadsheet rows.
    @Published var records: [[String]] = []
    /// Spreadsheet row of `records[0]` (the header is the row above it).
    var firstRecordLine = 2
    @Published var mapping = CustomerImportMapping() {
        didSet { if mapping != oldValue { committedChunks = 0 } }
    }
    /// Chunks already imported, so Try again after an error carries on instead of starting over.
    private(set) var committedChunks = 0
    static let maxRows = 5000
    @Published var preview: CustomerImportResult.Summary?
    @Published var problems: [String] = []
    @Published var imported = 0
    @Published var progress = 0.0
    @Published var error: String?

    /// Rows to send, with the spreadsheet line each came from (line 1 is the header).
    var prepared: (rows: [CustomerImportRow], lines: [Int], unnamed: [Int]) {
        var rows: [CustomerImportRow] = [], lines: [Int] = [], unnamed: [Int] = []
        for (index, cells) in records.enumerated() where !CSVReader.isBlank(cells) {
            if let row = CustomerImportRow.from(cells, mapping: mapping) {
                rows.append(row); lines.append(index + firstRecordLine)
            } else {
                unnamed.append(index + firstRecordLine)
            }
        }
        return (rows, lines, unnamed)
    }

    var rows: [CustomerImportRow] { prepared.rows }
    var rowCount: Int { records.lazy.filter { !CSVReader.isBlank($0) }.count }

    func read(_ url: URL) {
        error = nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), data.count <= 5 * 1024 * 1024 else {
            error = "That file could not be read. Choose a CSV file under 5 MB."
            return
        }
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let table = CSVReader.rows(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        let headerIndex = table.firstIndex { !CSVReader.isBlank($0) }
        let body = headerIndex.map { Array(table[($0 + 1)...]) } ?? []
        let count = body.lazy.filter { !CSVReader.isBlank($0) }.count
        guard let headerIndex, count > 0 else {
            error = "That file has no customer rows. Export customers from your old software as CSV and try again."
            return
        }
        guard count <= Self.maxRows else {
            error = "That file has \(count) rows. Split it into files of \(Self.maxRows) customers or fewer and import each one."
            return
        }
        reset()
        fileName = url.lastPathComponent
        headers = table[headerIndex]
        records = body
        firstRecordLine = headerIndex + 2
        mapping = .guess(headers)
        phase = .map
    }

    /// Dry run every chunk: what would be new, what is already here, what cannot be read.
    func check(api: APIClient) async {
        let (all, lines, unnamed) = prepared
        guard !all.isEmpty else { error = "No row has a customer name in the column you chose."; return }
        phase = .checking
        error = nil
        var new = 0, duplicate = 0, invalid = 0
        var reasons: [String] = []
        if !unnamed.isEmpty {
            let shown = unnamed.prefix(5).map(String.init).joined(separator: ", ")
            reasons.append(unnamed.count == 1 ? "Row \(shown): no name" : "Rows \(shown)\(unnamed.count > 5 ? " and \(unnamed.count - 5) more" : ""): no name")
        }
        do {
            for range in CustomerImportRow.chunks(all) {
                let result = try await api.importCustomers(Array(all[range]), dryRun: true)
                new += result.summary.new
                duplicate += result.summary.duplicate
                invalid += result.summary.invalid
                for outcome in result.rows where outcome.status == "invalid" && reasons.count < 5 {
                    let position = range.lowerBound + outcome.row - 1
                    let line = lines.indices.contains(position) ? lines[position] : position + 2
                    reasons.append("Row \(line): \((outcome.reasons ?? ["could not be read"]).joined(separator: ", "))")
                }
                progress = Double(range.upperBound) / Double(all.count)
            }
            preview = .init(new: new, duplicate: duplicate, invalid: invalid + unnamed.count)
            problems = reasons
            phase = .preview
        } catch is CancellationError {
            phase = .map
        } catch {
            self.error = error.localizedDescription
            phase = .map
        }
    }

    /// Commits chunk by chunk. A repeated chunk is safe: rows matching an existing customer by
    /// phone or email come back as duplicates, never as second copies.
    func commit(api: APIClient) async -> Bool {
        let all = rows
        phase = .importing
        error = nil
        if committedChunks == 0 { imported = 0 }
        let parts = CustomerImportRow.chunks(all)
        progress = committedChunks > 0 && parts.indices.contains(committedChunks - 1)
            ? Double(parts[committedChunks - 1].upperBound) / Double(max(all.count, 1)) : 0
        do {
            for index in parts.indices where index >= committedChunks {
                let result = try await api.importCustomers(Array(all[parts[index]]), dryRun: false)
                imported += result.summary.new
                committedChunks = index + 1
                progress = Double(parts[index].upperBound) / Double(all.count)
            }
            phase = .done
            return true
        } catch is CancellationError {
            phase = .preview
            return false
        } catch {
            self.error = "Imported \(imported) before an error: \(error.localizedDescription) Try again to import the rest."
            phase = .preview
            return false
        }
    }

    func reset() {
        phase = .choose; fileName = ""; headers = []; records = []; firstRecordLine = 2; mapping = .init()
        preview = nil; problems = []; imported = 0; progress = 0; error = nil; committedChunks = 0
    }
}

/// Choose a CSV, check the columns, preview, import. Used by setup and by Customers.
struct CustomerImportPanel: View {
    @ObservedObject var model: CustomerImportModel
    var onImported: (() -> Void)? = nil
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @State private var choosing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch model.phase {
            case .choose:
                Text("Export customers from your old software (ServiceTitan, Housecall Pro, Jobber, QuickBooks or a spreadsheet) as a CSV file, then choose it here.")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                borderedButton("Choose a CSV file", symbol: "doc.badge.plus") { choosing = true }
            case .map:
                mappingSection
            case .checking, .importing:
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.phase == .checking ? "Checking \(model.rows.count) customers…" : "Importing… \(model.imported) added")
                        .font(Theme.font(15, weight: .medium))
                    ProgressView(value: model.progress).tint(Theme.success)
                }
            case .preview:
                previewSection
            case .done:
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                    Text(model.imported == 1 ? "1 customer imported." : "\(model.imported) customers imported.")
                        .font(Theme.font(15, weight: .medium))
                }
                Button("Import another file") { model.reset() }
                    .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.brandText).frame(minHeight: 44)
            }
            if let error = model.error { InlineProblem(message: error) }
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
            if case .success(let url) = result { model.read(url) }
        }
    }

    private var mappingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(model.fileName) · \(model.rowCount == 1 ? "1 row" : "\(model.rowCount) rows")")
                .font(Theme.font(15, weight: .medium))
            Text("Check which column holds each detail.").font(Theme.font(13)).foregroundStyle(Theme.muted)
            VStack(spacing: 0) {
                columnPicker("Name", .name)
                if model.mapping.name == nil {
                    columnPicker("First name", .firstName)
                    columnPicker("Last name", .lastName)
                }
                columnPicker("Phone", .phone)
                columnPicker("Email", .email)
                columnPicker("Street address", .address)
                columnPicker("City", .city)
                columnPicker("State", .state)
                columnPicker("ZIP", .zip)
                columnPicker("Notes", .notes)
            }
            if let sample = model.rows.first {
                Text("First customer: \(sample.name)\(sample.phones?.first.map { " · \($0)" } ?? "")\(sample.addresses?.first.map { " · \($0)" } ?? "")")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(2)
            }
            HStack(spacing: 12) {
                borderedButton("Check \(model.rows.count) customers", symbol: "checklist") { Task { await model.check(api: api) } }
                    .disabled(!model.mapping.canImport || model.rows.isEmpty)
                Button("Choose another") { model.reset() }
                    .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted).frame(minHeight: 44)
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let preview = model.preview {
                Text(preview.new == 1 ? "1 new customer is ready to import." : "\(preview.new) new customers are ready to import.")
                    .font(Theme.font(15, weight: .medium))
                if preview.duplicate > 0 {
                    Text(preview.duplicate == 1 ? "1 is already in Thorbis (same phone or email) and will be skipped."
                                                : "\(preview.duplicate) are already in Thorbis (same phone or email) and will be skipped.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                }
                if preview.invalid > 0 {
                    Text(preview.invalid == 1 ? "1 row can't be read and will be left out:" : "\(preview.invalid) rows can't be read and will be left out:")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    ForEach(model.problems, id: \.self) { Text($0).font(Theme.font(13)).foregroundStyle(Theme.muted) }
                }
                HStack(spacing: 12) {
                    borderedButton(preview.new == 1 ? "Import 1 customer" : "Import \(preview.new) customers", symbol: "square.and.arrow.down") {
                        Task {
                            if await model.commit(api: api) {
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                _ = await store.refresh(api)
                                onImported?()
                            }
                        }
                    }
                    .disabled(preview.new == 0)
                    Button("Change columns") { model.phase = .map }
                        .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted).frame(minHeight: 44)
                }
            }
        }
    }

    private func columnPicker(_ label: String, _ field: CustomerImportMapping.Field) -> some View {
        HStack {
            Text(label).font(Theme.font(15))
            Spacer()
            let chosen = model.mapping[field]
            let names = model.headers.indices.map { model.headers[$0].isEmpty ? "Column \($0 + 1)" : model.headers[$0] }
            ThorbisMenu(items: [ThorbisMenuItem("Not in file", isSelected: chosen == nil) { model.mapping[field] = nil }]
                        + names.indices.map { index in
                            ThorbisMenuItem(names[index], isSelected: chosen == index) { model.mapping[field] = index }
                        },
                        title: label, accessibilityLabel: "\(label) column") {
                HStack(spacing: 4) {
                    Text(chosen.flatMap { names.indices.contains($0) ? names[$0] : nil } ?? "Not in file")
                        .font(Theme.font(15)).foregroundStyle(Theme.muted).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                .frame(minHeight: 44)
            }
        }
        .frame(minHeight: 44)
    }

    private func borderedButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Theme.font(15, weight: .medium))
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.border))
                .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
        }
        .buttonStyle(PressStyle())
        .foregroundStyle(Theme.foreground)
    }
}

/// Customers › Import: the same panel on its own screen.
struct CustomerImportView: View {
    @StateObject private var model = CustomerImportModel()

    var body: some View {
        ScrollView {
            CustomerImportPanel(model: model)
                .padding(Theme.gutter)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .navigationTitle("Import customers")
        .navigationBarTitleDisplayMode(.inline)
    }
}
