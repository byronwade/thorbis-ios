import CoreLocation
import SwiftUI

/// "You're here. Mark arrived?": while a job is on the way and the app is open, the phone coming
/// within about 125 m of the job's place offers the arrived step. It only ever offers: the person
/// taps to arrive. Location is read When In Use and only once it is already allowed; this never
/// asks for it, and with no coordinates on the job it does nothing.
enum ArrivalNudge {
    static let radiusMeters = 125.0
    /// A fix vaguer than this can't say the phone is at the address.
    static let worstAccuracyMeters = 100.0

    /// Great-circle distance in meters between two points given in degrees.
    static func distanceMeters(latitude: Double, longitude: Double, to place: FieldCoordinates) -> Double {
        let earth = 6_371_000.0
        let fromLatitude = latitude * .pi / 180, toLatitude = place.latitude * .pi / 180
        let deltaLatitude = (place.latitude - latitude) * .pi / 180
        let deltaLongitude = (place.longitude - longitude) * .pi / 180
        let a = sin(deltaLatitude / 2) * sin(deltaLatitude / 2)
            + cos(fromLatitude) * cos(toLatitude) * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
        return earth * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Near enough to offer: a usable fix inside the radius.
    static func isNear(distanceMeters: Double, accuracyMeters: Double) -> Bool {
        accuracyMeters >= 0 && accuracyMeters <= worstAccuracyMeters && distanceMeters <= radiusMeters
    }

    static func validCoordinates(_ place: FieldCoordinates?) -> FieldCoordinates? {
        guard let place, (-90...90).contains(place.latitude), (-180...180).contains(place.longitude),
              !(place.latitude == 0 && place.longitude == 0) else { return nil }
        return place
    }

    /// Whether the phone's place is worth watching at all: on the way, in the foreground, the
    /// server allows arriving, a place to measure to, location already allowed, and not waved off.
    static func watches(status: String, appActive: Bool, canArrive: Bool, hasPendingStatus: Bool,
                        place: FieldCoordinates?, locationAllowed: Bool, dismissed: Bool) -> Bool {
        status == "en_route" && appActive && canArrive && !hasPendingStatus && validCoordinates(place) != nil
            && locationAllowed && !dismissed
    }

    static func locationAllowed(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }
}

/// Jobs whose "Mark arrived?" was dismissed: not asked again for that job, across launches.
struct ArrivalNudgeDismissals {
    static let key = "arrivalNudge.dismissedJobs"
    static let limit = 200
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func contains(_ jobID: String) -> Bool {
        (defaults.stringArray(forKey: Self.key) ?? []).contains(jobID)
    }

    func dismiss(_ jobID: String) {
        var jobs = (defaults.stringArray(forKey: Self.key) ?? []).filter { $0 != jobID }
        jobs.append(jobID)
        defaults.set(Array(jobs.suffix(Self.limit)), forKey: Self.key)
    }
}

/// Watches the phone's place against one job's place while its task runs (the job screen cancels
/// it when the job leaves "on the way" or the app leaves the foreground).
@MainActor
final class ArrivalWatcher: ObservableObject {
    @Published private(set) var isNear = false

    func reset() { isNear = false }

    func watch(place: FieldCoordinates) async {
        isNear = false
        #if DEBUG
        if PaperPreview.enabled {
            // Fixture: screenshots never depend on a location fix or a permission.
            isNear = ProcessInfo.processInfo.arguments.contains("--paper-preview-arrival-nudge")
            return
        }
        #endif
        guard ArrivalNudge.locationAllowed(CLLocationManager().authorizationStatus) else { return }
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        do {
            for try await update in CLLocationUpdate.liveUpdates(.automotiveNavigation) {
                if Task.isCancelled { return }
                if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted { return }
                guard let fix = update.location else { continue }
                let distance = ArrivalNudge.distanceMeters(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude, to: place)
                if ArrivalNudge.isNear(distanceMeters: distance, accuracyMeters: fix.horizontalAccuracy) {
                    isNear = true
                    return
                }
            }
        } catch {}
    }
}

/// The offer, over the job's bar: the words, one tap to arrive, and a dismiss.
struct ArrivalNudgeBanner: View {
    let busy: Bool
    let arrive: () -> Void
    let dismiss: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
        HStack(alignment: .center, spacing: 4) {
            layout {
                HStack(spacing: 10) {
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.brandText).accessibilityHidden(true)
                    Text("You\u{2019}re here. Mark arrived?").font(Theme.font(15, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: arrive) {
                    Text("I\u{2019}ve arrived").paperButton(.card, tone: .tinted)
                }
                .buttonStyle(PressStyle())
                .disabled(busy)
                .accessibilityHint("Marks this job arrived")
                .accessibilityIdentifier("job-arrival-nudge-arrive")
            }
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Dismiss")
            .accessibilityHint("Doesn\u{2019}t ask again for this job")
            .accessibilityIdentifier("job-arrival-nudge-dismiss")
        }
        .padding(.leading, 14).padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.hairline))
        .padding(.horizontal, PaperCardMetrics.margin)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("job-arrival-nudge")
        .onAppear { AccessibilityNotification.Announcement("You\u{2019}re here. Mark arrived?").post() }
    }
}
