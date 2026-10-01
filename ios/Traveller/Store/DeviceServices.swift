import MapKit
import Network
import Observation
import SwiftUI
import TravellerKit
import UserNotifications

// MARK: - Notifications

/// Seyahat günü bildirimlerini (yerel) planlar. Seyahatler değiştikçe kısa bir gecikmeyle yeniden kurulur.
@MainActor
@Observable
final class NotificationScheduler {
    static let shared = NotificationScheduler()
    private static let enabledKey = "traveller.notifications.enabled"

    /// iOS en fazla 64 bekleyen bildirime izin verir.
    private static let globalLimit = 60

    var isEnabled: Bool = UserDefaults.standard.bool(forKey: NotificationScheduler.enabledKey)
    private(set) var authorizationDenied = false
    private var latestTrips: [Trip] = []
    private var task: Task<Void, Never>?

    /// Kullanıcı açınca izin ister; reddedilirse kapalı kalır.
    func setEnabled(_ enabled: Bool) async {
        if enabled {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            authorizationDenied = !granted
            isEnabled = granted
        } else {
            isEnabled = false
        }
        UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
        await reschedule()
    }

    /// Başka bir ekip üyesinin değişikliğini hemen bildirir ("Elif bir harcama ekledi").
    func notifyCloudChange(_ summary: TripChanges.Summary) async {
        guard isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = summary.title
        content.body = summary.body
        content.sound = .default
        content.threadIdentifier = "cloud-\(summary.title)"
        let request = UNNotificationRequest(identifier: "cloud-\(UUID().uuidString)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    func tripsChanged(_ trips: [Trip]) {
        latestTrips = trips
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await reschedule()
        }
    }

    private func reschedule() async {
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("trip-") }
        center.removePendingNotificationRequests(withIdentifiers: existing)
        guard isEnabled else { return }

        let planned = latestTrips
            .flatMap { NotificationPlanner.plan(for: $0) }
            .sorted { $0.date < $1.date }
            .prefix(Self.globalLimit)
        for item in planned {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }
}

// MARK: - Network

/// Bağlantı durumu; çevrimdışıyken kayıtlı harita görüntüsü gösterilir.
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()
    private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in NetworkMonitor.shared.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "traveller.network"))
    }
}

// MARK: - Offline maps

/// Her günün rotasını, numaralı pinleriyle birlikte görüntü olarak cihaza kaydeder.
/// İnternet yokken plan bu görüntüleri gösterir (MapKit uygulamalara karo indirme izni vermez).
@MainActor
@Observable
final class OfflineMapStore {
    static let shared = OfflineMapStore()

    enum State: Equatable {
        case idle
        case saving(done: Int, total: Int)
        case saved(Date)
        case failed(String)
    }

    private(set) var states: [UUID: State] = [:]
    private let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("OfflineMaps", isDirectory: true)

    func state(for tripID: UUID) -> State {
        if let state = states[tripID] { return state }
        if let date = savedDate(for: tripID) { return .saved(date) }
        return .idle
    }

    func image(tripID: UUID, day: Date) -> UIImage? {
        UIImage(contentsOfFile: fileURL(tripID: tripID, day: day).path)
    }

    /// Tüm günlerin haritalarını oluşturur (durak konumu olan günler).
    func save(_ trip: Trip) async {
        let days = trip.days().filter { day in trip.stops(on: day).contains { $0.coordinate != nil } }
        guard !days.isEmpty else {
            states[trip.id] = .failed("Konumu olan durak yok.")
            return
        }
        let folder = directory.appendingPathComponent(trip.id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        for (index, day) in days.enumerated() {
            states[trip.id] = .saving(done: index, total: days.count)
            do {
                let image = try await Self.render(stops: trip.stops(on: day))
                try image.pngData()?.write(to: fileURL(tripID: trip.id, day: day), options: .atomic)
            } catch {
                states[trip.id] = .failed("Harita kaydedilemedi: \(error.localizedDescription)")
                return
            }
        }
        states[trip.id] = .saved(.now)
    }

    func remove(_ tripID: UUID) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(tripID.uuidString))
        states[tripID] = .idle
    }

    private func savedDate(for tripID: UUID) -> Date? {
        let folder = directory.appendingPathComponent(tripID.uuidString)
        let attributes = try? FileManager.default.attributesOfItem(atPath: folder.path)
        return attributes?[.modificationDate] as? Date
    }

    private func fileURL(tripID: UUID, day: Date) -> URL {
        let key = Int(Calendar.current.startOfDay(for: day).timeIntervalSince1970)
        return directory.appendingPathComponent(tripID.uuidString).appendingPathComponent("\(key).png")
    }

    /// MKMapSnapshotter ile haritayı çizer, üstüne rota ve numaralı pinleri ekler.
    private static func render(stops: [Stop]) async throws -> UIImage {
        let points = stops.compactMap { stop in stop.coordinate.map { (stop, $0) } }
        let coordinates = points.map { CLLocationCoordinate2D(latitude: $0.1.latitude, longitude: $0.1.longitude) }
        let options = MKMapSnapshotter.Options()
        options.region = region(fitting: coordinates)
        options.size = CGSize(width: 900, height: 600)
        options.pointOfInterestFilter = .excludingAll
        let snapshot = try await MKMapSnapshotter(options: options).start()

        return UIGraphicsImageRenderer(size: options.size).image { context in
            snapshot.image.draw(at: .zero)
            let positions = coordinates.map { snapshot.point(for: $0) }

            // Kesikli rota
            if positions.count > 1 {
                let path = UIBezierPath()
                path.move(to: positions[0])
                positions.dropFirst().forEach { path.addLine(to: $0) }
                path.lineWidth = 4
                path.lineCapStyle = .round
                path.setLineDash([1, 10], count: 2, phase: 0)
                UIColor(Color.ink).setStroke()
                path.stroke()
            }

            // Numaralı pinler
            for (index, position) in positions.enumerated() {
                let radius: CGFloat = 17
                let circle = CGRect(x: position.x - radius, y: position.y - radius, width: radius * 2, height: radius * 2)
                UIColor.white.setFill()
                UIBezierPath(ovalIn: circle.insetBy(dx: -3, dy: -3)).fill()
                UIColor(Accent.cycle(index).base).setFill()
                UIBezierPath(ovalIn: circle).fill()
                let label = "\(index + 1)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 16, weight: .bold), .foregroundColor: UIColor.white,
                ]
                let size = label.size(withAttributes: attributes)
                label.draw(at: CGPoint(x: position.x - size.width / 2, y: position.y - size.height / 2), withAttributes: attributes)
            }
            _ = context
        }
    }

    private static func region(fitting coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let bounds = Geo.bounds(coordinates.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) })
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: bounds.center.latitude, longitude: bounds.center.longitude),
            span: MKCoordinateSpan(latitudeDelta: bounds.latitudeSpan, longitudeDelta: bounds.longitudeSpan))
    }
}
