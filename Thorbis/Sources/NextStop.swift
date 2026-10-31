import CoreLocation
import Foundation
import MapKit

// Next stop (technician home): the Schedule's lead card says where the tech is going, how long
// the drive is and how to get there. The address is the job's own service location only; a
// customer's other addresses never stand in for the job site (JobLocationPolicy).

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

    /// The street line: what a tech reads at a glance before tapping Directions.
    var firstLine: String? {
        guard let address else { return nil }
        let line = address.split(whereSeparator: { $0 == "," || $0 == "\n" }).first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return line.flatMap { $0.isEmpty ? nil : $0 }
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
            text += " · next at \(time.formatted(.dateTime.hour().minute()))"
        }
        return text
    }
}

extension NextStopDay {
    /// "Fri, Oct 30 · visit 3 of 6": the day and where the tech is in it, for the Today subtitle.
    /// Nil when there are no visits; "all 6 done" once every visit is finished.
    static func subtitle(day: Date = .now, jobs: [Job], lead: Job?) -> String {
        let date = day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let visits = jobs.filter { $0.status != "canceled" }.sorted {
            (JobFiltering.date($0.scheduledFor) ?? .distantFuture) < (JobFiltering.date($1.scheduledFor) ?? .distantFuture)
        }
        guard !visits.isEmpty else { return date }
        if visits.allSatisfy({ $0.status == "completed" }) {
            return visits.count == 1 ? "\(date) · today's visit done" : "\(date) · all \(visits.count) visits done"
        }
        if let lead, let index = visits.firstIndex(where: { $0.id == lead.id }) {
            return "\(date) · visit \(index + 1) of \(visits.count)"
        }
        return "\(date) · \(visits.count) visit\(visits.count == 1 ? "" : "s")"
    }
}

/// Street lines for the jobs on screen, read from each customer's own service locations (one
/// request per customer, cached). A job without a `locationId`, or whose place can't be read,
/// has no street and its row leads with the job title instead (BYR-1593).
@MainActor
final class JobAddressBook: ObservableObject {
    @Published private(set) var streets: [String: String] = [:]
    private var loaded: Set<String> = []
    private var key = ""

    /// Keyed by customer and place, so a place is only ever read for its own customer's job.
    func street(_ job: Job) -> String? {
        guard let locationID = job.locationId, let customerID = job.customerId else { return nil }
        return streets["\(customerID)|\(locationID)"]
    }

    /// Reads the places for `jobs`. Never more than `limit` customers per screen.
    func load(_ jobs: [Job], api: APIClient, organizationID: String?, identity: String, limit: Int = 20) async {
        if identity != key { key = identity; streets = [:]; loaded = [] }
        guard let organizationID else { return }
        let customers = Array(Set(jobs.compactMap { $0.locationId == nil ? nil : $0.customerId }))
            .filter { !loaded.contains($0) }.sorted().prefix(limit)
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
                let line = NextStopPlace(jobID: "", organizationID: organizationID, customerID: customerID,
                                         locationID: place.id, address: place.address).firstLine
                if let line { streets["\(customerID)|\(place.id)"] = line }
            }
        }
    }
}

/// Drive time from where the phone is to the stop, by MapKit. Location is asked When In Use and
/// only when a card with a mapped address first needs it. Denied, no fix or no signal leaves the
/// card with its address and no ETA; nothing waits on it.
@MainActor
final class NextStopETA: ObservableObject {
    @Published private(set) var minutes: Int?
    private var key: String?

    func update(to destination: FieldCoordinates?, key: String, enabled: Bool) async {
        guard key != self.key || minutes == nil else { return }
        self.key = key
        minutes = nil
        #if DEBUG
        if PaperPreview.enabled, PaperPreview.screen.hasPrefix("next-stop") {
            // Fixture: the screenshot never depends on a permission prompt or the network.
            minutes = enabled && destination != nil ? 18 : nil
            return
        }
        #endif
        guard enabled, let destination else { return }
        let status = CLLocationManager().authorizationStatus
        guard status != .denied, status != .restricted else { return }
        guard let here = await Self.currentLocation(), !Task.isCancelled else { return }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: here.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: destination.latitude, longitude: destination.longitude)))
        request.transportType = .automobile
        guard let eta = try? await MKDirections(request: request).calculateETA(), !Task.isCancelled,
              self.key == key else { return }
        minutes = max(1, Int((eta.expectedTravelTime / 60).rounded()))
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
