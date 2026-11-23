import SwiftUI
import UniformTypeIdentifiers

// Bring customers from other software (web onboarding "Import from your old software").
// `POST /v1/customer-imports` {dryRun, rows}: the server never sees the file, only rows already
// mapped to {name, phones, emails, addresses, notes}. At most 100 rows and 200 records per request
// (domains/customers CUSTOMER_IMPORT_MAX_ROWS / MAX_WORK), so rows are chunked by both.
// The server refuses a row with no phone and no email as "invalid", and commits each request in
// one transaction, so a chunk sent again after a lost answer creates nobody twice: the customers
// the lost try made come back as "duplicate" with their existingCustomerId.

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
        var row: Int
        var status: String
        var name: String? = nil
        var reasons: [String]? = nil
        var matchedOn: String? = nil
        /// "new": parts of the row that were accepted but could not be kept, in the server's words.
        var warnings: [String]? = nil
        /// "new" on a commit: the customer just created.
        var customerId: String? = nil
        /// "duplicate": the customer already in the workspace with that phone or email.
        var existingCustomerId: String? = nil
        /// "duplicate": an earlier row of the same request with that phone or email.
        var duplicateOfRow: Int? = nil
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
        didSet { if mapping != oldValue { forgetRun() } }
    }
    /// Chunks already imported, so Try again after an error carries on instead of starting over.
    private(set) var committedChunks = 0
    /// Each chunk's dry-run outcomes from `check`, by chunk index: what a row was expected to be.
    private(set) var previewOutcomes: [Int: [CustomerImportResult.Outcome]] = [:]
    /// The chunk whose last commit ended with no definite answer: it may have reached the server
    /// and been saved. Cleared once a commit answer for that chunk arrives.
    private(set) var uncertainChunk: Int?
    /// Every customer this import run has seen created, so a retried chunk never counts one twice.
    private(set) var createdCustomerIDs: Set<String> = []
    static let maxRows = 5000
    @Published var preview: CustomerImportResult.Summary?
    @Published var problems: [String] = []
    /// The first five rows the server will import without some of their details ("Row 7: notes …").
    @Published var warnings: [String] = []
    /// How many rows carry at least one warning.
    @Published var warningCount = 0
    @Published var imported = 0
    @Published var progress = 0.0
    @Published var error: String?
    /// The check or import in flight, so "Cancel import" (Paper 11A) can stop it.
    var running: Task<Void, Never>?

    func cancel() { running?.cancel() }

    /// Who is offered Import: true when `can` grants all three capabilities the route needs
    /// (customer.create, customer.edit and customer.view; services/api manifest, customers.import).
    nonisolated static func permitted(_ can: (String) -> Bool) -> Bool {
        ["customer.create", "customer.edit", "customer.view"].allSatisfy(can)
    }

    /// The import button on the last step.
    var commitTitle: String {
        // Also while a chunk is uncertain: its lost try may have saved it.
        if committedChunks > 0 || uncertainChunk != nil { return "Import the rest" }
        let new = preview?.new ?? 0
        return new == 1 ? "Import 1 customer" : "Import \(new) customers"
    }

    /// A 403 for the role (category "authorization", or none from an older server).
    nonisolated static func isRoleRefusal(_ error: Error) -> Bool {
        guard let problem = error as? Problem, problem.status == 403 else { return false }
        return problem.category == nil || problem.category == "authorization"
    }

    /// What a failed check or import says. A feature that is switched off (403
    /// "feature_unavailable") and every other error keep their own description.
    nonisolated static func message(for error: Error) -> String {
        isRoleRefusal(error) ? "Your role can\u{2019}t import customers." : error.localizedDescription
    }

    /// True when a commit may have reached the server and been saved although no answer came
    /// back: a timeout, a dropped connection, a server failure, or a Cancel while it was in
    /// flight. Not for a request that provably never left (`Problem.neverSent`) or a definite
    /// refusal (`RetryKey.isDefinite`: a 4xx other than 408 and 429).
    nonisolated static func answerWasLost(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if (error as? Problem)?.neverSent == true { return false }
        return !RetryKey<Int>.isDefinite(error)
    }

    /// The customers one committed chunk confirms, and the ids to remember as created this run.
    /// Not uncertain: the server's own `summary.new`. Uncertain (an earlier try of this chunk lost
    /// its answer, and a chunk lands whole or not at all): every row answered "new", plus each
    /// distinct `existingCustomerId` among rows the preview called "new" that now come back
    /// "duplicate", leaving out customers this run already counted (a row repeating a contact from
    /// an earlier chunk previews as new, because every chunk is previewed before any is saved).
    nonisolated static func confirmedNew(preview: [CustomerImportResult.Outcome]?, answer: CustomerImportResult,
                                         uncertain: Bool, alreadyCounted: Set<String>) -> (count: Int, created: Set<String>) {
        let createdNow = Set(answer.rows.compactMap { $0.status == "new" ? $0.customerId : nil })
        guard uncertain else { return (answer.summary.new, createdNow) }
        var previewStatus: [Int: String] = [:]
        for outcome in preview ?? [] where previewStatus[outcome.row] == nil { previewStatus[outcome.row] = outcome.status }
        var landed: Set<String> = []
        for outcome in answer.rows where outcome.status == "duplicate" && previewStatus[outcome.row] == "new" {
            if let id = outcome.existingCustomerId, !alreadyCounted.contains(id) { landed.insert(id) }
        }
        let newRows = answer.rows.filter { $0.status == "new" }.count
        return (newRows + landed.count, createdNow.union(landed))
    }

    /// The spreadsheet line of a chunk's row (`row` is 1-based within the chunk).
    static func line(chunkStart: Int, row: Int, lines: [Int]) -> Int {
        let position = chunkStart + row - 1
        return lines.indices.contains(position) ? lines[position] : position + 2
    }

    /// The mapping or the file changed: the next import is a new run.
    private func forgetRun() {
        committedChunks = 0
        uncertainChunk = nil
        previewOutcomes = [:]
        createdCustomerIDs = []
    }

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
        var outcomes: [Int: [CustomerImportResult.Outcome]] = [:]
        var warned: [String] = []
        var warnedRows = 0
        if !unnamed.isEmpty {
            let shown = unnamed.prefix(5).map(String.init).joined(separator: ", ")
            reasons.append(unnamed.count == 1 ? "Row \(shown): no name" : "Rows \(shown)\(unnamed.count > 5 ? " and \(unnamed.count - 5) more" : ""): no name")
        }
        do {
            for (index, range) in CustomerImportRow.chunks(all).enumerated() {
                try Task.checkCancellation()
                let result = try await api.importCustomers(Array(all[range]), dryRun: true)
                new += result.summary.new
                duplicate += result.summary.duplicate
                invalid += result.summary.invalid
                outcomes[index] = result.rows
                for outcome in result.rows where outcome.status == "invalid" && reasons.count < 5 {
                    let line = Self.line(chunkStart: range.lowerBound, row: outcome.row, lines: lines)
                    reasons.append("Row \(line): \((outcome.reasons ?? ["could not be read"]).joined(separator: ", "))")
                }
                for outcome in result.rows where outcome.status == "new" {
                    let notes = outcome.warnings ?? []
                    guard !notes.isEmpty else { continue }
                    warnedRows += 1
                    if warned.count < 5 {
                        let line = Self.line(chunkStart: range.lowerBound, row: outcome.row, lines: lines)
                        warned.append("Row \(line): \(notes.joined(separator: ", "))")
                    }
                }
                progress = Double(range.upperBound) / Double(all.count)
            }
            // A chunk whose answer was lost keeps the preview taken before it was sent: checking
            // again now would call the rows it saved duplicates, and they would never be counted.
            if let uncertainChunk, let kept = previewOutcomes[uncertainChunk] { outcomes[uncertainChunk] = kept }
            previewOutcomes = outcomes
            preview = .init(new: new, duplicate: duplicate, invalid: invalid + unnamed.count)
            problems = reasons
            warnings = warned
            warningCount = warnedRows
            phase = .preview
        } catch is CancellationError {
            phase = .map
        } catch {
            self.error = Self.message(for: error)
            phase = .map
        }
    }

    /// Commits chunk by chunk. Sending a chunk again is safe: every row the server accepts has a
    /// phone or an email, and a row matching a customer already saved (by an earlier try whose
    /// answer was lost, too) comes back as a duplicate, never as a second copy. Such a retry is
    /// counted with `confirmedNew`, so the total includes what the lost try saved.
    func commit(api: APIClient) async -> Bool {
        let all = rows
        phase = .importing
        error = nil
        if committedChunks == 0 { imported = 0; createdCustomerIDs = [] }
        let parts = CustomerImportRow.chunks(all)
        progress = committedChunks > 0 && parts.indices.contains(committedChunks - 1)
            ? Double(parts[committedChunks - 1].upperBound) / Double(max(all.count, 1)) : 0
        // The chunk whose request is out; nil while nothing is in flight.
        var sending: Int?
        do {
            for index in parts.indices where index >= committedChunks {
                try Task.checkCancellation()
                sending = index
                let result = try await api.importCustomers(Array(all[parts[index]]), dryRun: false)
                sending = nil
                let confirmed = Self.confirmedNew(preview: previewOutcomes[index], answer: result,
                                                  uncertain: uncertainChunk == index, alreadyCounted: createdCustomerIDs)
                imported += confirmed.count
                createdCustomerIDs.formUnion(confirmed.created)
                if uncertainChunk == index { uncertainChunk = nil }
                committedChunks = index + 1
                progress = Double(parts[index].upperBound) / Double(all.count)
            }
            phase = .done
            return true
        } catch {
            let lost = sending != nil && Self.answerWasLost(error)
            if lost, let sending { uncertainChunk = sending }
            // An earlier try of a chunk lost its answer and may have saved it: until an answer for
            // that chunk arrives, no message may say nothing was saved.
            let pending = uncertainChunk != nil
            let customers = imported == 1 ? "1 customer is" : "\(imported) customers are"
            if error is CancellationError {
                // Rows already added stay; importing again carries on from where it stopped.
                if lost {
                    self.error = "Import stopped while saving. \(customers) confirmed so far. Try again to finish; nobody already added is added twice."
                } else if imported > 0 {
                    self.error = imported == 1
                        ? "Import stopped. 1 customer was already added."
                        : "Import stopped. \(imported) customers were already added."
                }
            } else if lost {
                self.error = "The last save could not be confirmed. \(customers) confirmed so far. Try again to finish; nobody already added is added twice."
            } else if pending {
                self.error = "\(Self.message(for: error)) \(customers) confirmed so far. Try again to finish; nobody already added is added twice."
            } else if imported == 0, Self.isRoleRefusal(error) {
                self.error = Self.message(for: error)
            } else {
                self.error = "Imported \(imported) before an error: \(Self.message(for: error)) Try again to import the rest."
            }
            phase = .preview
            return false
        }
    }

    func reset() {
        phase = .choose; fileName = ""; headers = []; records = []; firstRecordLine = 2; mapping = .init()
        preview = nil; problems = []; warnings = []; warningCount = 0; imported = 0; progress = 0; error = nil
        forgetRun()
    }
}

/// Choose a CSV, check the columns, preview, import. Used by setup and by Customers.
struct CustomerImportPanel: View {
    @ObservedObject var model: CustomerImportModel
    var onImported: (() -> Void)? = nil
    /// On its own screen the panel's actions are the brand commit (Paper 97); inside setup the
    /// wizard's Continue is the commit, so they sit on the quieter fill pill.
    var prominentActions = false
    /// False when the screen pins `CustomerImportCommit` to its bottom edge (Paper 97).
    var showsCommit = true
    @State private var choosing = false
    /// The details the file has no column for are shown once asked for (Paper 97 lists only matched ones).
    @State private var showsUnmatched = false
    /// The app the file comes from ("Or import from", Paper 11); nil is any CSV.
    @State private var source: String?
    static let sources = ["ServiceTitan", "Jobber", "Housecall Pro", "QuickBooks"]

    /// "Step 2 of 3 · match the columns" (Paper 97's subtitle).
    static func stepLine(_ phase: CustomerImportModel.Phase) -> String {
        switch phase {
        case .choose: "Step 1 of 3 · choose a file"
        case .map, .checking: "Step 2 of 3 · match the columns"
        case .preview, .importing: "Step 3 of 3 · check and import"
        case .done: "Import finished"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch model.phase {
            case .choose:
                dropZone
            case .map:
                mappingSection
            case .checking, .importing:
                progressCard
            case .preview:
                previewSection
            case .done:
                PaperCard {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: "checkmark.circle").font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.statusDone).accessibilityHidden(true)
                        Text(model.imported == 1 ? "1 customer imported." : "\(model.imported) customers imported.")
                            .font(Theme.font(16, weight: .medium))
                    }
                    .padding(.horizontal, PaperCardMetrics.inset)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                }
                Button("Import another file") { model.reset() }
                    .font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.brandText).frame(minHeight: 44)
                    .padding(.horizontal, 4)
            }
            if let error = model.error { InlineProblem(message: error).padding(.horizontal, 4) }
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
            if case .success(let url) = result { model.read(url) }
        }
    }

    /// Paper 11/97: a dashed card with the file glyph on a brand-tinted circle and "Choose file…".
    private var dropZone: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { choosing = true } label: {
                VStack(spacing: 4) {
                    Image(systemName: "doc").font(.system(size: 22, weight: .medium)).foregroundStyle(Theme.brand)
                        .frame(width: 48, height: 48)
                        .background(Theme.brandSurface, in: Circle())
                        .accessibilityHidden(true)
                    Text("Choose a CSV file").font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                        .padding(.top, 12)
                    Text("Customers · CSV up to 5 MB and \(CustomerImportModel.maxRows.formatted()) rows")
                        .font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                    Text("Choose file…").font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.brandText)
                        .padding(.top, 8)
                }
                .padding(.vertical, 28).padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(dashedRim)
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Choose a CSV file")
            Text("Or import from").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 4).padding(.top, 14)
                .accessibilityAddTraits(.isHeader)
            FlowRow(spacing: 8, lineSpacing: 8) {
                ForEach(Self.sources, id: \.self) { name in
                    sourceChip(name)
                }
            }
            Text(sourceHelp)
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4).padding(.top, 4)
        }
    }

    private var sourceHelp: String {
        if let source {
            return "Export your customer list from \(source) as a CSV file, then choose that file above."
        }
        return "Export customers from your old software or a spreadsheet as a CSV file, then choose it above."
    }

    /// Paper 11/11A: the 1.5pt dashed rim in the strong border tone.
    private var dashedRim: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Theme.foreground.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
    }

    /// A pill on the card; the chosen app sits on the brand tint (Paper 97's source chips).
    private func sourceChip(_ name: String) -> some View {
        let chosen = source == name
        return Button { source = chosen ? nil : name } label: {
            PaperChoiceChipLabel(title: name, isOn: chosen)
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// Paper 11A: the same dashed card while the file is checked or imported: the file's name,
    /// how far along it is, and a way to stop.
    private var progressCard: some View {
        let percent = Int((min(max(model.progress, 0), 1) * 100).rounded())
        let count = model.rows.count
        let noun = count == 1 ? "1 customer" : "\(count) customers"
        let importing = model.phase == .importing
        return VStack(spacing: 4) {
            Image(systemName: "doc").font(.system(size: 22, weight: .medium)).foregroundStyle(Theme.brand)
                .frame(width: 48, height: 48)
                .background(Theme.brandSurface, in: Circle())
                .accessibilityHidden(true)
            Text(model.fileName).font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                .lineLimit(1).truncationMode(.middle)
                .padding(.top, 12)
            Text("\(importing ? "Importing" : "Checking") \(noun) · \(percent)%")
                .font(Theme.font(14)).foregroundStyle(Theme.muted).monospacedDigit()
                .multilineTextAlignment(.center)
            Button(importing ? "Cancel import" : "Cancel") { model.cancel() }
                .font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.brandText)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.top, 28).padding(.bottom, 16).padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(dashedRim)
    }

    private var mappingSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            PaperSection("Match columns") {
                // Paper 97 lists the details this file fills. The ones it has no column for wait
                // behind one quiet row, so any of them can still be matched by hand.
                columnPicker("Name", .name, first: true)
                if model.mapping.name == nil {
                    columnPicker("First name", .firstName)
                    columnPicker("Last name", .lastName)
                }
                let rest: [(String, CustomerImportMapping.Field)] = [("Phone", .phone), ("Email", .email), ("Address", .address),
                                                                     ("City", .city), ("State", .state), ("ZIP", .zip), ("Notes", .notes)]
                let unmatched = rest.filter { model.mapping[$0.1] == nil }
                ForEach(rest, id: \.0) { label, field in
                    if model.mapping[field] != nil || showsUnmatched { columnPicker(label, field) }
                }
                if !unmatched.isEmpty && !showsUnmatched {
                    WellDivider()
                    Button { showsUnmatched = true } label: {
                        HStack(spacing: 10) {
                            Text(unmatched.count == 1 ? "1 more detail not in this file" : "\(unmatched.count) more details not in this file")
                                .font(Theme.font(15)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            PaperIcon(.chevronDown, size: 16, color: Theme.muted).accessibilityHidden(true)
                        }
                        .padding(.leading, PaperCardMetrics.inset).padding(.trailing, 14)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityHint("Shows \(unmatched.map(\.0).joined(separator: ", ")) so you can match a column")
                    .accessibilityIdentifier("import-more-details")
                }
            }
            let samples = Array(model.rows.prefix(2))
            if !samples.isEmpty {
                PaperSection("Preview · \(model.rowCount == 1 ? "1 row" : "\(model.rowCount) rows")") {
                    ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                        if index > 0 { WellDivider() }
                        PaperListRow(title: sample.name,
                                     subtitle: ([sample.phones?.first, sample.addresses?.first].compactMap { $0 }).joined(separator: " · "))
                    }
                    // Paper 97: what the file is missing, in the warning ink under the samples.
                    let noPhone = model.rows.filter { ($0.phones ?? []).isEmpty }.count
                    if noPhone > 0 {
                        WellDivider()
                        Text(noPhone == 1 ? "1 row has no phone number" : "\(noPhone) rows have no phone number")
                            .font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, PaperCardMetrics.inset)
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    }
                }
            }
            VStack(spacing: 6) {
                if showsCommit { CustomerImportCommit(model: model, onImported: onImported, prominent: prominentActions) }
                Button("Choose another file") { model.reset() }
                    .font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.subtle)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let preview = model.preview {
                VStack(alignment: .leading, spacing: 8) {
                    PaperSection("Ready to import") {
                        countRow("New customers", preview.new, first: true)
                        if preview.duplicate > 0 {
                            countRow("Already in Thorbis", preview.duplicate, note: "Same phone or email · skipped")
                        }
                        if preview.invalid > 0 {
                            countRow("Can’t be read", preview.invalid, note: "Left out", warning: true)
                        }
                        if model.warningCount > 0 {
                            countRow("Added without some details", model.warningCount, note: "Reasons below", warning: true)
                        }
                    }
                    ForEach(model.problems, id: \.self) {
                        Text($0).font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                    }
                    // The server's own words for what each row leaves out.
                    ForEach(model.warnings, id: \.self) {
                        Text($0).font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                    }
                }
                VStack(spacing: 6) {
                    if showsCommit { CustomerImportCommit(model: model, onImported: onImported, prominent: prominentActions) }
                    Button("Change columns") { model.phase = .map }
                        .font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.subtle)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
    }

    private func countRow(_ title: String, _ count: Int, note: String? = nil, warning: Bool = false, first: Bool = false) -> some View {
        VStack(spacing: 0) {
            if !first { WellDivider() }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    if let note { Text(note).font(Theme.font(14)).foregroundStyle(warning ? Theme.warning : Theme.muted) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(count)").font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    /// Paper 97: the file's column (muted) → the Thorbis detail it fills, opening the column menu.
    private func columnPicker(_ label: String, _ field: CustomerImportMapping.Field, first: Bool = false) -> some View {
        let chosen = model.mapping[field]
        let names = model.headers.indices.map { model.headers[$0].isEmpty ? "Column \($0 + 1)" : model.headers[$0] }
        let chosenName = chosen.flatMap { names.indices.contains($0) ? names[$0] : nil }
        return VStack(spacing: 0) {
            if !first { WellDivider() }
            ThorbisMenu(items: [ThorbisMenuItem("Not in file", isSelected: chosen == nil) { model.mapping[field] = nil }]
                        + names.indices.map { index in
                            ThorbisMenuItem(names[index], isSelected: chosen == index) { model.mapping[field] = index }
                        },
                        title: label, accessibilityLabel: "\(label) column") {
                HStack(spacing: 10) {
                    Text(chosenName ?? "Not in file")
                        .font(Theme.font(15)).foregroundStyle(Theme.muted).lineLimit(1)
                        .frame(width: 104, alignment: .leading)
                    Image(systemName: "arrow.right").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                    Text(label).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PaperIcon(.chevronRight, size: 16, color: Theme.muted)
                }
                .padding(.leading, PaperCardMetrics.inset).padding(.trailing, 14)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityValue(chosenName ?? "Not in file")
        }
    }
}

/// The step's one commit: "Check N customers" on the columns step, "Import N customers" on the
/// last. Inline in setup; pinned to the bottom edge on the Import customers screen (Paper 97).
struct CustomerImportCommit: View {
    @ObservedObject var model: CustomerImportModel
    var onImported: (() -> Void)? = nil
    var prominent = false
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store

    var body: some View {
        switch model.phase {
        case .map:
            let count = model.rows.count
            actionButton(count == 1 ? "Check 1 customer" : "Check \(count) customers", symbol: "checklist",
                         enabled: model.mapping.canImport && count > 0) {
                model.running = Task { await model.check(api: api) }
            }
        case .preview:
            let new = model.preview?.new ?? 0
            actionButton(model.commitTitle, symbol: "square.and.arrow.down", enabled: new > 0 || model.committedChunks > 0 || model.uncertainChunk != nil) {
                model.running = Task {
                    if await model.commit(api: api) {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        _ = await store.refresh(api)
                        onImported?()
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func actionButton(_ title: String, symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        if prominent {
            Button(action: action) { Text(title).inkCommit(enabled: enabled) }
                .buttonStyle(PressStyle())
                .disabled(!enabled)
        } else {
            Button(action: action) { RimmedButtonLabel(title: title, symbol: symbol, enabled: enabled) }
                .buttonStyle(PressStyle())
                .disabled(!enabled)
        }
    }
}

/// Customers › Import: the same panel on its own screen (Paper 97).
struct CustomerImportView: View {
    @StateObject private var model = CustomerImportModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: "Import customers", subtitle: CustomerImportPanel.stepLine(model.phase))
                    .environment(\.paperMenuButton, false)
                    .environment(\.paperDrawer, nil)
                CustomerImportPanel(model: model, prominentActions: true, showsCommit: false)
                    .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 4).padding(.bottom, 28)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Paper 97: the commit rides the bottom edge, 16 from the sides.
            if model.phase == .map || model.phase == .preview {
                CustomerImportCommit(model: model, prominent: true)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .paperActionBarGround()
            }
        }
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .navigationBarTitleDisplayMode(.inline)
        #if DEBUG
        .task { if PaperPreview.enabled, PaperPreview.opensSheet("customers-import") { model.loadPreviewSample() } }
        #endif
    }
}

#if DEBUG
extension CustomerImportModel {
    /// The design preview's file: Paper 97's columns and first rows, read the way a real file is.
    func loadPreviewSample() {
        let text = """
        Client Name,Mobile,Street,Notes
        Danielle Marlowe,(916) 555-0148,412 Birchwood Ln,Gate code 4482
        Marcus Oyelaran,(916) 555-0172,88 Alder Creek Dr,
        Tom Becker,,17 Larkspur Way,
        Linda Park,(916) 555-0119,6 Fern Ct,
        """
        let table = CSVReader.rows(text)
        fileName = "customers.csv"
        headers = table[0]
        records = Array(table.dropFirst())
        firstRecordLine = 2
        mapping = .guess(headers)
        phase = .map
    }
}
#endif
