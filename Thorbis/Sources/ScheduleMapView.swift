import MapKit
import SwiftUI

/// Paper's Schedule "Map" segment: the day's stops as numbered pins, in route order,
/// with the selected stop's card and a one-tap route in Apple Maps.
struct ScheduleMapView: View {
    let jobs: [Job]
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var places: [String: ServiceLocationRecord] = [:]
    @State private var loaded = false
    /// iPad passes its sidebar selection so a row tap selects and centers the pin.
    var selection: Binding<String?>? = nil
    @State private var ownSelection: String?
    private var selectionBinding: Binding<String?> { selection ?? $ownSelection }
    private var selectedID: String? { selectionBinding.wrappedValue }
    @State private var position: MapCameraPosition = .automatic
    @EnvironmentObject private var session: SessionController
    /// The number to call per customer, read when their stop is the one shown.
    @State private var phones: [String: String] = [:]
    @State private var newJobAt: NewJobTarget?

    /// Paper 80's "+" on the stop card: another job for this customer at this address.
    private struct NewJobTarget: Identifiable {
        let customer: Customer
        let locationID: String
        var id: String { customer.id + "/" + locationID }
    }

    private struct Stop: Identifiable {
        let number: Int
        let job: Job
        let place: ServiceLocationRecord
        let coordinate: CLLocationCoordinate2D
        var id: String { job.id }
    }

    private var stops: [Stop] {
        jobs.enumerated().compactMap { index, job in
            guard let place = places[job.id], let point = place.coordinates else { return nil }
            return Stop(number: index + 1, job: job, place: place,
                        coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
        }
    }

    var body: some View {
        let stops = stops
        let shownCustomerID = (stops.first(where: { $0.id == selectedID }) ?? stops.first)?.job.customerId
        VStack(alignment: .leading, spacing: 0) {
            Map(position: $position, selection: selectionBinding) {
                // Paper 80: a dotted brand line joins the stops in the order they are driven.
                if stops.count > 1 {
                    MapPolyline(coordinates: stops.map(\.coordinate))
                        .stroke(Theme.brand, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0.1, 8]))
                }
                ForEach(stops) { stop in
                    Annotation(stop.job.title, coordinate: stop.coordinate, anchor: .bottom) {
                        pin(stop, selected: stop.id == selectedID)
                    }
                    .tag(stop.id)
                    .annotationTitles(.hidden)
                }
                UserAnnotation()
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls { MapUserLocationButton(); MapCompass() }
            .frame(height: 400)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                if !loaded {
                    Label("Finding today's stops…", systemImage: "mappin.and.ellipse")
                        .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 14).frame(height: Theme.chipHeight)
                        .background(Theme.card, in: Capsule())
                }
            }
            .padding(.horizontal, PaperCardMetrics.margin)
            .padding(.top, 16)
            .accessibilityLabel("Map of today's stops")

            if let stop = stops.first(where: { $0.id == selectedID }) ?? stops.first {
                let next = stops.first { $0.number > stop.number && !["completed", "canceled"].contains($0.job.status) }
                card(stop, next: next).padding(.horizontal, PaperCardMetrics.margin).padding(.top, 12)
            }

            let missing = loaded ? jobs.count - stops.count : 0
            if missing > 0 {
                Text("\(missing) job\(missing == 1 ? " has" : "s have") no mapped address yet.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, PaperCardMetrics.margin + 4).padding(.top, 10)
            }
        }
        .task(id: jobs.map(\.id)) { await loadPlaces() }
        .task(id: shownCustomerID) { await loadPhone(shownCustomerID) }
        .sheet(item: $newJobAt) { target in
            SheetSurface { NewJobSheet(preselected: target.customer, locationID: target.locationID) }
        }
        // A selection made outside the map (the iPad list) centers its pin too.
        .onChange(of: selectedID) { _, id in
            if let stop = stops.first(where: { $0.id == id }) { center(on: stop) }
        }
    }

    /// Paper 80: the chosen stop is a 34pt brand circle with a heavy rim; the others are 28pt card
    /// circles with a strong hairline. Finished stops read quieter.
    private func pin(_ stop: Stop, selected: Bool) -> some View {
        let done = stop.job.status == "completed"
        return Text("\(stop.number)")
            .font(Theme.font(selected ? 14 : 12, weight: selected ? .bold : .semibold))
            .foregroundStyle(selected ? Color.white : (done ? Theme.muted : Theme.foreground))
            .frame(width: selected ? 34 : 28, height: selected ? 34 : 28)
            .background(Circle().fill(selected ? Theme.brand : Theme.card))
            .overlay(Circle().strokeBorder(selected ? Theme.foreground : Theme.border, lineWidth: selected ? 3 : 2))
            .shadow(color: .black.opacity(selected ? 0.25 : 0.18), radius: selected ? 5 : 4, y: selected ? 3 : 2)
            .animation(.snappy, value: selected)
            .accessibilityLabel("Stop \(stop.number), \(stop.job.title)")
    }

    /// The stop's street line, the way every Today row leads.
    private func street(_ stop: Stop) -> String {
        NextStopPlace(jobID: stop.job.id, organizationID: "", customerID: "", address: stop.place.address).firstLine ?? stop.job.title
    }

    /// Paper 80: the chosen stop on one card. Its number on a brand circle, "AC not cooling —
    /// Marlowe" over the street and time (the words open the job), then Start route in Maps, and
    /// the next stop on the route in a quiet line.
    private func card(_ stop: Stop, next: Stop?) -> some View {
        let customer = store.customerName(stop.job.customerId)
        let time = JobFiltering.date(stop.job.scheduledFor)?.clockTime
        return VStack(alignment: .leading, spacing: 16) {
            NavigationLink(value: stop.job) {
                HStack(alignment: .center, spacing: 12) {
                    Text("\(stop.number)")
                        .font(Theme.font(13, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Theme.brand, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(stop.job.title) \u{2014} \(customer)".dashKeptWithWordBefore)
                            .font(Theme.font(17, weight: .semibold)).tracking(-0.17)
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text([street(stop), time].compactMap { $0 }.joined(separator: " · "))
                            .font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the job")
            // Paper 80: Start route, then Call and + as 48pt circles on the field fill.
            let route = Directions.url(address: stop.place.address, coordinates: stop.place.coordinates)
            let call = callURL(stop)
            let target = newJobTarget(stop)
            if route != nil || call != nil || target != nil {
                HStack(spacing: 8) {
                    if let route {
                        Button { openURL(route) } label: {
                            PaperPillLabel(title: "Start route", glyph: .navigate)
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Start route")
                        .accessibilityHint("Opens driving directions to stop \(stop.number) in Maps")
                    } else {
                        Spacer(minLength: 0)
                    }
                    if let call {
                        Button { openURL(call) } label: { cardCircle("phone") }
                            .buttonStyle(PressStyle())
                            .accessibilityLabel("Call \(customer)")
                            .accessibilityIdentifier("schedule-map-call")
                    }
                    if let target {
                        Button { newJobAt = target } label: { cardCircle("plus") }
                            .buttonStyle(PressStyle())
                            .accessibilityLabel("New job at this address")
                            .accessibilityIdentifier("schedule-map-new-job")
                    }
                }
            }
            if let next {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.right").font(.system(size: 11, weight: .medium)).accessibilityHidden(true)
                    Text("Next: \(store.customerName(next.job.customerId)) · \(street(next))")
                        .lineLimit(1)
                }
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// A 48pt circle on the field fill (Paper 80's Call and +).
    private func cardCircle(_ symbol: String) -> some View {
        PaperRoundLabel(glyph: symbol == "phone" ? .phone : .plusLight)
    }

    private func callURL(_ stop: Stop) -> URL? {
        guard let customerID = stop.job.customerId, let phone = phones[customerID] else { return nil }
        return JobReach(phone: phone, email: nil).call
    }

    private func newJobTarget(_ stop: Stop) -> NewJobTarget? {
        guard session.can("job.create", feature: "jobs"),
              let customer = store.customers.first(where: { $0.id == stop.job.customerId }) else { return nil }
        return NewJobTarget(customer: customer, locationID: stop.place.id)
    }

    /// The number the job screen's Call reaches, read once per customer when their stop is shown.
    private func loadPhone(_ customerID: String?) async {
        guard let customerID, phones[customerID] == nil,
              session.can("customer.view", feature: "core_crm") else { return }
        let organizationID = session.activeOrganization?.id
        guard let contacts = try? await api.fieldContacts(customerID) else { return }
        let verified = contacts.filter { $0.organizationId == organizationID && $0.customerId == customerID }
        var account: CustomerRecord?
        if NextStopPlace.phone(contacts: verified, account: nil) == nil,
           let record = try? await api.fieldCustomer(customerID),
           record.organizationId == organizationID, record.id == customerID {
            account = record
        }
        guard !Task.isCancelled else { return }
        if let phone = NextStopPlace.phone(contacts: verified, account: account) { phones[customerID] = phone }
    }

    private func select(_ stop: Stop) {
        selectionBinding.wrappedValue = stop.id
        center(on: stop)
    }

    private func center(on stop: Stop) {
        withAnimation(.snappy) {
            position = .region(MKCoordinateRegion(center: stop.coordinate, latitudinalMeters: 1_500, longitudinalMeters: 1_500))
        }
    }

    /// One locations request per customer; the job's own location wins, else the customer's first.
    private func loadPlaces() async {
        var byCustomer: [String: [ServiceLocationRecord]] = [:]
        for customerID in Set(jobs.compactMap(\.customerId)) where !Task.isCancelled {
            byCustomer[customerID] = (try? await api.fieldLocations(customerID)) ?? []
        }
        var found: [String: ServiceLocationRecord] = [:]
        for job in jobs {
            let options = job.customerId.flatMap { byCustomer[$0] } ?? []
            if let place = options.first(where: { $0.id == job.locationId }) ?? options.first { found[job.id] = place }
        }
        places = found
        loaded = true
        // A selection made before the stops were known (an iPad row tapped while loading,
        // or Map entered with a job already picked) centers once the pins exist.
        if let stop = stops.first(where: { $0.id == selectedID }) { center(on: stop) }
    }
}
