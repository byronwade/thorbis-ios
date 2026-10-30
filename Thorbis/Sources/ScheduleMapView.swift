import MapKit
import SwiftUI

/// Paper's Schedule "Map" segment: the day's stops as numbered pins, in route order,
/// with the selected stop's card and a one-tap route in Apple Maps.
struct ScheduleMapView: View {
    let jobs: [Job]
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @Environment(\.openURL) private var openURL
    @State private var places: [String: ServiceLocationRecord] = [:]
    @State private var loaded = false
    /// iPad passes its sidebar selection so a row tap selects and centers the pin.
    var selection: Binding<String?>? = nil
    @State private var ownSelection: String?
    private var selectionBinding: Binding<String?> { selection ?? $ownSelection }
    private var selectedID: String? { selectionBinding.wrappedValue }
    @State private var position: MapCameraPosition = .automatic

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
        VStack(alignment: .leading, spacing: 0) {
            Map(position: $position, selection: selectionBinding) {
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
            .frame(height: 380)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5)
                if !loaded {
                    Label("Finding today's stops…", systemImage: "mappin.and.ellipse")
                        .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 14).frame(height: Theme.chipHeight)
                        .background(Theme.card, in: Capsule()).overlay(Capsule().stroke(Theme.border))
                }
            }
            .padding(.horizontal, Theme.gutter)
            .accessibilityLabel("Map of today's stops")

            if let stop = stops.first(where: { $0.id == selectedID }) ?? stops.first {
                card(stop).padding(.horizontal, Theme.gutter).padding(.top, 12)
            }

            PaperGroupHeader(title: "Stops", count: stops.count)
                .padding(.horizontal, Theme.gutter).padding(.top, 20)
            ForEach(stops) { stop in
                Button { select(stop) } label: { stopRow(stop) }.buttonStyle(.plain)
            }
            let missing = loaded ? jobs.count - stops.count : 0
            if missing > 0 {
                Text("\(missing) job\(missing == 1 ? " has" : "s have") no mapped address yet.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, Theme.gutter).padding(.top, 10)
            }
        }
        .task(id: jobs.map(\.id)) { await loadPlaces() }
        // A selection made outside the map (the iPad list) centers its pin too.
        .onChange(of: selectedID) { _, id in
            if let stop = stops.first(where: { $0.id == id }) { center(on: stop) }
        }
    }

    private func pin(_ stop: Stop, selected: Bool) -> some View {
        let (_, color) = statusIcon(stop.job.status)
        return Text("\(stop.number)")
            .font(Theme.monoFont(12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: selected ? 34 : 28, height: selected ? 34 : 28)
            .background(Circle().fill(stop.job.status == "completed" ? Theme.muted : (color == Theme.muted ? Theme.brand : color)))
            .overlay(Circle().strokeBorder(.white, lineWidth: selected ? 2.5 : 1.5))
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            .animation(.snappy, value: selected)
            .accessibilityLabel("Stop \(stop.number), \(stop.job.title)")
    }

    private func card(_ stop: Stop) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(JobFiltering.date(stop.job.scheduledFor)?.formatted(.dateTime.hour().minute()) ?? "Stop \(stop.number)")
                    .font(Theme.monoFont(13, weight: .medium)).foregroundStyle(Theme.brandText)
                Text(stop.job.status.statusLabel).font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.muted)
                Spacer()
                Text(stop.job.shortRef).font(Theme.monoFont(11, weight: .medium)).foregroundStyle(Theme.muted)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.job.title).font(Theme.font(17, weight: .semibold)).lineLimit(2)
                Text("\(store.customerName(stop.job.customerId)) · \(stop.place.address)")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(2)
            }
            HStack(spacing: 8) {
                PaperCompatibleLink(value: stop.job) {
                    Text("Open job").inkCommit()
                }
                .buttonStyle(PressStyle())
                if let url = Directions.url(address: stop.place.address, coordinates: stop.place.coordinates) {
                    PaperSquareButton(symbol: "arrow.triangle.turn.up.right.diamond", label: "Directions in Maps") { openURL(url) }
                }
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
    }

    private func stopRow(_ stop: Stop) -> some View {
        HStack(spacing: 12) {
            Text("\(stop.number)")
                .font(Theme.monoFont(12, weight: .semibold))
                .foregroundStyle(stop.id == selectedID ? .white : Theme.foreground)
                .frame(width: 26, height: 26)
                .background(Circle().fill(stop.id == selectedID ? Theme.brand : Theme.fill))
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.job.title).font(Theme.font(15, weight: .medium)).lineLimit(1)
                Text(stop.place.address).font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(JobFiltering.date(stop.job.scheduledFor)?.formatted(.dateTime.hour().minute()) ?? "")
                .font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
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
