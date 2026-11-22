import CoreLocation
import Foundation
import MapKit
import SwiftUI

// Next stop (technician home): the Schedule's lead card says where the tech is going, how long
// the drive is and how to get there. The address is the job's own service location; a job that
// records none is shown at the customer's only address on file, with that caveat
// (JobFallbackAddress), and never at a guess between several of their addresses.

/// The job's place and a number to call, as last read. Cached per job so the card still shows
/// the address offline; it lives with the job detail cache and is cleared on sign-out with it.
struct NextStopPlace: Codable, Equatable {
    let jobID: String
    let organizationID: String
    let customerID: String
    var locationID: String?
    var address: String?
    var coordinates: FieldCoordinates?
    var phone: String?
    /// True when the job records no site and `address` is the customer's only address on file.
    /// Optional, so a copy saved on this phone before it existed still reads.
    var fromCustomer: Bool?

    /// The street line: what a tech reads at a glance before tapping Directions.
    var firstLine: String? { Self.firstLine(address) }

    static func firstLine(_ address: String?) -> String? {
        guard let address else { return nil }
        let line = address.split(whereSeparator: { $0 == "," || $0 == "\n" }).first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return line.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Said with the street when it is the customer's address rather than the job's own site.
    var caveat: String? { fromCustomer == true && firstLine != nil ? JobFallbackAddress.caveat : nil }

    /// The place from the customer's locations as just read: the job's own site, or, when the job
    /// records none, the customer's only address on file.
    mutating func setPlace(from locations: [ServiceLocationRecord], customerAddress: String?) {
        if let locationID {
            // The job's own service location only, for its own customer (JobLocationPolicy).
            let record = locations.first { $0.id == locationID && $0.customerId == customerID && $0.organizationId == organizationID }
            address = record?.address
            coordinates = record?.coordinates
            fromCustomer = nil
        } else {
            let fallback = JobFallbackAddress.make(locationID: nil, customerID: customerID, organizationID: organizationID,
                                                   locations: locations, customerAddress: customerAddress)
            address = fallback?.address
            coordinates = fallback?.coordinates
            fromCustomer = fallback == nil ? nil : true
        }
    }

    var directions: URL? {
        guard let address, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Directions.url(address: address, coordinates: coordinates)
    }

    var call: URL? { JobReach(phone: phone, email: nil).call }

    /// The number the job screen's Call reaches: the primary contact, any contact, then the account.
    static func phone(contacts: [CustomerContactRecord], account: CustomerRecord?) -> String? {
        contacts.first(where: \.primary)?.phone ?? contacts.first(where: { $0.phone != nil })?.phone ?? account?.phone
    }
}

/// The plain-text line above the card: "Visit 3 of 6 · next at 2:30 PM".
enum NextStopDay {
    static func progress(jobs: [Job], lead: Job?) -> String? {
        let day = jobs.filter { $0.status != "canceled" }.sorted {
            (JobFiltering.date($0.scheduledFor) ?? .distantFuture) < (JobFiltering.date($1.scheduledFor) ?? .distantFuture)
        }
        guard !day.isEmpty else { return nil }
        let total = day.count
        if day.allSatisfy({ $0.status == "completed" }) {
            return total == 1 ? "Today's visit is done" : "All \(total) visits done"
        }
        guard let lead, let index = day.firstIndex(where: { $0.id == lead.id }) else { return nil }
        var text = "Visit \(index + 1) of \(total)"
        // On a job now, "next" is the one after it; otherwise it is this stop's own time.
        let next: Job? = ScheduleLead.activeStatuses.contains(lead.status)
            ? day[(index + 1)...].first { ["scheduled", "dispatched"].contains($0.status) }
            : lead
        if let time = JobFiltering.date(next?.scheduledFor) {
            text += " · next at \(time.tradeTime)"
        }
        return text
    }
}

extension NextStopDay {
    /// "Tuesday, July 21 · 2 of 6 jobs done": the day (Paper F1 spells it out) and how far through it
    /// the tech is, for the Today subtitle. The date alone when there are no visits; "all 6 visits
    /// done" once every visit is finished.
    static func subtitle(day: Date = .now, jobs: [Job], lead: Job?) -> String {
        let date = day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let visits = jobs.filter { $0.status != "canceled" }.sorted {
            (JobFiltering.date($0.scheduledFor) ?? .distantFuture) < (JobFiltering.date($1.scheduledFor) ?? .distantFuture)
        }
        guard !visits.isEmpty else { return date }
        if visits.allSatisfy({ $0.status == "completed" }) {
            return visits.count == 1 ? "\(date) · today's visit done" : "\(date) · all \(visits.count) visits done"
        }
        // Paper F1's words: "1 of 5 jobs done".
        let done = visits.filter { $0.status == "completed" }.count
        return "\(date) · \(done) of \(visits.count) jobs done"
    }
}

/// Street lines for the jobs on screen, read from each customer's own service locations (one
/// request per customer, cached). A job whose place can't be read has no street and its row leads
/// with the job title instead. A job without a `locationId` (BYR-1593) gets the customer's only
/// address on file (JobFallbackAddress) on the screens that pass `customerAddresses`; elsewhere it
/// has no street and its customer's places are not read for it.
@MainActor
final class JobAddressBook: ObservableObject {
    @Published private(set) var streets: [String: String] = [:]
    /// The full place behind each street, so a row's Directions needs no read of its own.
    private(set) var places: [String: (address: String, coordinates: FieldCoordinates?)] = [:]
    /// For jobs without a site of their own: the customer's only address on file, by customer.
    @Published private(set) var fallbacks: [String: JobFallbackAddress] = [:]
    private var loaded: Set<String> = []
    private var key = ""

    /// Keyed by customer and place, so a place is only ever read for its own customer's job.
    func street(_ job: Job) -> String? {
        guard let customerID = job.customerId else { return nil }
        guard let locationID = job.locationId else { return fallbacks[customerID]?.street }
        return streets["\(customerID)|\(locationID)"]
    }

    /// Said with `street` when it is the customer's only address on file, not the job's own site.
    func caveat(_ job: Job) -> String? {
        job.locationId == nil && street(job) != nil ? JobFallbackAddress.caveat : nil
    }

    /// Directions to the job's own service location (never another of the customer's addresses),
    /// or, for a job without one, to the customer's only address on file.
    func directions(_ job: Job) -> URL? {
        guard let customerID = job.customerId else { return nil }
        guard let locationID = job.locationId else { return fallbacks[customerID]?.directions }
        guard let place = places["\(customerID)|\(locationID)"] else { return nil }
        return Directions.url(address: place.address, coordinates: place.coordinates)
    }

    /// Reads the places for `jobs`, in their order (callers put the job that matters most first).
    /// Never more than `limit` customers per screen.
    /// - Parameter customerAddresses: each customer's own address, already loaded with the
    ///   customer list (`Store.customerAddresses`). When given, the customers of jobs without a
    ///   site are read too, so those jobs can show the only address on file; nil reads only the
    ///   customers of jobs with a site.
    func load(_ jobs: [Job], api: APIClient, organizationID: String?, identity: String, limit: Int = 20,
              customerAddresses: [String: String]? = nil) async {
        if identity != key { key = identity; streets = [:]; places = [:]; fallbacks = [:]; loaded = [] }
        guard let organizationID else { return }
        var seen = Set<String>()
        let customers = jobs.compactMap { $0.locationId == nil && customerAddresses == nil ? nil : $0.customerId }
            .filter { !loaded.contains($0) && seen.insert($0).inserted }.prefix(limit)
        for customerID in customers {
            guard !Task.isCancelled else { return }
            let places: [ServiceLocationRecord]
            do { places = try await api.fieldLocations(customerID) } catch {
                // Cancelled (the list changed) or offline: leave it unread so the next pass tries again.
                if Task.isCancelled { return }
                continue
            }
            guard identity == key else { return }
            loaded.insert(customerID)
            for place in places where place.customerId == customerID && place.organizationId == organizationID {
                let line = NextStopPlace.firstLine(place.address)
                if !place.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.places["\(customerID)|\(place.id)"] = (place.address, place.coordinates)
                }
                if let line { streets["\(customerID)|\(place.id)"] = line }
            }
            if let customerAddresses {
                fallbacks[customerID] = JobFallbackAddress.make(locationID: nil, customerID: customerID, organizationID: organizationID,
                                                                locations: places, customerAddress: customerAddresses[customerID])
            }
        }
    }
}

/// Drive time from where the phone is to the stop, by MapKit. Location is asked When In Use and
/// only when a card with a mapped address first needs it, after the explainer (Paper 70) says
/// what it is for. Denied, "Not now", no fix or no signal leaves the
/// card with its address and no ETA; nothing waits on it.
@MainActor
final class NextStopETA: ObservableObject {
    @Published private(set) var minutes: Int?
    /// The drive's length in miles, with the minutes (the map strip's "18 min · 6.2 mi").
    @Published private(set) var miles: Double?
    /// Location is denied or restricted for Thorbis, so there is no drive time to show. Never set
    /// while the permission is still undecided (the system prompt is about to ask).
    @Published private(set) var locationOff = false
    private var key: String?

    func update(to destination: FieldCoordinates?, key: String, enabled: Bool) async {
        guard key != self.key || minutes == nil else { return }
        self.key = key
        minutes = nil
        miles = nil
        #if DEBUG
        if PaperPreview.enabled {
            // Fixture: no screenshot ever depends on a permission prompt or the network (a fresh
            // simulator would otherwise cover every screen with the location alert).
            // `--paper-preview-location-off` shows the card as it is with location turned off.
            locationOff = ProcessInfo.processInfo.arguments.contains("--paper-preview-location-off")
            minutes = (PaperPreview.screen.hasPrefix("next-stop") || PaperPreview.screen == "job") && enabled && destination != nil && !locationOff ? 18 : nil
            miles = minutes == nil ? nil : 6.2
            return
        }
        #endif
        guard enabled, let destination else { return }
        var status = CLLocationManager().authorizationStatus
        if status == .notDetermined {
            // Paper 70: say what Location is for before the system asks. "Not now" leaves the
            // card with its address and no drive time, and the system is not asked.
            guard await PermissionPrimerPresenter.ask(.location), !Task.isCancelled, self.key == key else { return }
            status = CLLocationManager().authorizationStatus
        }
        locationOff = status == .denied || status == .restricted
        guard !locationOff else { return }
        guard let here = await Self.currentLocation(), !Task.isCancelled else {
            // The person may have just said no to the prompt.
            let after = CLLocationManager().authorizationStatus
            if after == .denied || after == .restricted { locationOff = true }
            return
        }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: here.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: destination.latitude, longitude: destination.longitude)))
        request.transportType = .automobile
        guard let eta = try? await MKDirections(request: request).calculateETA(), !Task.isCancelled,
              self.key == key else { return }
        minutes = max(1, Int((eta.expectedTravelTime / 60).rounded()))
        miles = eta.distance > 0 ? eta.distance / 1609.344 : nil
    }

    /// One fix, asking When In Use the first time. Gives up quietly on denial or after 15 seconds.
    private static func currentLocation() async -> CLLocation? {
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        return await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let location = update.location { return location }
                        if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted { return nil }
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(15))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

/// The Next stop card's one quiet line when Location is off: the drive time is missing because
/// of a setting, and here is the way to it. Shown once per launch until dismissed; it never
/// blocks the card or its commit.
struct NextStopLocationNotice: View {
    let dismiss: () -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Dismissed for the rest of this launch, on every Schedule that shows the card.
    @MainActor static var dismissedThisLaunch = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "location.slash").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
            // The words are the way to Settings, so the notice stays one line.
            Button { if let url = DevicePermission.location.settingsURL { openURL(url) } } label: {
                Text("Turn on location to see drive time").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                    .underline()
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.85)
                    .frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Turn on location to see drive time")
            .accessibilityHint("Opens Settings to turn on Location for Thorbis")
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Dismiss")
            .accessibilityHint("Hides this until Thorbis is opened again")
        }
        .padding(.leading, 12)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        // Paper v2: an inner tile on a radius-20 card is radius 14.
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("next-stop-location-off")
    }
}
