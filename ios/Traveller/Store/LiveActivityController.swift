import ActivityKit
import SwiftUI
import TravellerKit
import UIKit

/// Seyahat günü kilit ekranındaki canlı uçuş kartını başlatır ve günceller.
@MainActor
enum LiveActivityController {
    /// Kalkıştan bu kadar önce otomatik başlatılır (canlı etkinlikler en fazla ~8 saat güncel kalır).
    static let autoStartWindow: TimeInterval = 6 * 3600

    static var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    static func isRunning(for trip: Trip) -> Bool {
        Activity<FlightActivityAttributes>.activities.contains { $0.attributes.tripID == trip.id.uuidString }
    }

    /// Kalkışa 24 saatten az kaldıysa elle başlatılabilir.
    static func canStart(for trip: Trip, now: Date = .now) -> Bool {
        guard isAvailable, let flight = trip.primaryFlight else { return false }
        return flight.departure > now && flight.departure.timeIntervalSince(now) < 24 * 3600
    }

    static func start(for trip: Trip) {
        guard let flight = trip.primaryFlight, isAvailable, !isRunning(for: trip) else { return }
        let attributes = FlightActivityAttributes(
            tripID: trip.id.uuidString, tripName: trip.name, flightNumber: flight.flightNumber,
            fromCode: flight.fromCode, fromCity: flight.fromCity, toCode: flight.toCode, toCity: flight.toCity,
            departure: flight.departure, arrival: flight.arrival, tint: hex(of: trip.tint))
        let state = FlightActivityAttributes.ContentState(gate: flight.gate, seat: flight.seat, status: status(for: flight))
        _ = try? Activity.request(attributes: attributes,
                                  content: ActivityContent(state: state, staleDate: flight.arrival),
                                  pushType: nil)
    }

    static func stop(for trip: Trip) {
        for activity in Activity<FlightActivityAttributes>.activities where activity.attributes.tripID == trip.id.uuidString {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Uygulama öne geldiğinde: yaklaşan uçuşları başlat, kapı/koltuk değiştiyse güncelle, inenleri kapat.
    static func refresh(trips: [Trip], now: Date = .now) {
        guard isAvailable else { return }
        for trip in trips {
            guard let flight = trip.primaryFlight else { continue }
            let running = Activity<FlightActivityAttributes>.activities.filter { $0.attributes.tripID == trip.id.uuidString }
            if flight.arrival < now {
                running.forEach { activity in Task { await activity.end(nil, dismissalPolicy: .default) } }
                continue
            }
            if running.isEmpty, flight.departure > now, flight.departure.timeIntervalSince(now) < autoStartWindow {
                start(for: trip)
            }
            let state = FlightActivityAttributes.ContentState(gate: flight.gate, seat: flight.seat, status: status(for: flight, now: now))
            for activity in running where activity.content.state != state {
                Task { await activity.update(ActivityContent(state: state, staleDate: flight.arrival)) }
            }
        }
    }

    static func status(for flight: FlightSegment, now: Date = .now) -> String {
        let minutes = flight.departure.timeIntervalSince(now) / 60
        if minutes <= 0 { return "Havada" }
        if minutes <= 40 { return "Biniş" }
        return "Zamanında"
    }

    private static func hex(of color: Color) -> UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> UInt32 { UInt32(max(0, min(255, (value * 255).rounded()))) }
        return byte(red) << 16 | byte(green) << 8 | byte(blue)
    }
}
