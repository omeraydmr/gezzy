import ActivityKit
import SwiftUI
import TravellerKit

/// Seyahat günü kilit ekranındaki canlı uçuş kartını başlatır ve günceller.
@MainActor
enum LiveActivityController {
    /// Kalkıştan bu kadar önce otomatik başlatılır (canlı etkinlikler en fazla ~8 saat güncel kalır).
    static let autoStartWindow: TimeInterval = 6 * 3600

    static var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    static func isRunning(for trip: Trip) -> Bool {
        !activities(for: trip).isEmpty
    }

    /// Kalkışa 24 saatten az kaldıysa elle başlatılabilir.
    static func canStart(for trip: Trip, now: Date = .now) -> Bool {
        guard isAvailable, let flight = trip.primaryFlight else { return false }
        let departure = flight.effectiveDeparture
        return departure > now && departure.timeIntervalSince(now) < 24 * 3600
    }

    static func start(for trip: Trip) {
        guard let flight = trip.primaryFlight, isAvailable, !isRunning(for: trip) else { return }
        let attributes = FlightActivityAttributes(
            tripID: trip.id.uuidString, tripName: trip.name, flightNumber: flight.flightNumber,
            fromCode: flight.fromCode, fromCity: flight.fromCity, toCode: flight.toCode, toCity: flight.toCity,
            scheduledDeparture: flight.departure, tint: trip.tint.rgbHex)
        _ = try? Activity.request(attributes: attributes,
                                  content: ActivityContent(state: state(for: flight), staleDate: flight.effectiveArrival),
                                  pushType: nil)
    }

    static func stop(for trip: Trip) {
        for activity in activities(for: trip) {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Uygulama öne geldiğinde ya da uçuş durumu değişince: yaklaşan uçuşları başlat, kartı güncelle, inenleri kapat.
    static func refresh(trips: [Trip], now: Date = .now) {
        guard isAvailable else { return }
        for trip in trips {
            guard let flight = trip.primaryFlight else { continue }
            let running = activities(for: trip)
            if flight.effectiveArrival < now || flight.live?.phase == .arrived {
                running.forEach { activity in Task { await activity.end(nil, dismissalPolicy: .default) } }
                continue
            }
            let departure = flight.effectiveDeparture
            if running.isEmpty, departure > now, departure.timeIntervalSince(now) < autoStartWindow,
               flight.live?.phase != .canceled {
                start(for: trip)
            }
            let latest = state(for: flight, now: now)
            for activity in running where activity.content.state != latest {
                Task { await activity.update(ActivityContent(state: latest, staleDate: flight.effectiveArrival)) }
            }
        }
    }

    static func state(for flight: FlightSegment, now: Date = .now) -> FlightActivityAttributes.ContentState {
        FlightActivityAttributes.ContentState(
            gate: flight.gate, seat: flight.seat, terminal: flight.live?.departureTerminal,
            status: status(for: flight, now: now), departure: flight.effectiveDeparture, arrival: flight.effectiveArrival,
            isDelayed: flight.isDelayed, isCanceled: flight.live?.phase == .canceled)
    }

    /// Servisten durum geldiyse onu, yoksa saate göre tahmini gösterir.
    static func status(for flight: FlightSegment, now: Date = .now) -> String {
        if let text = flight.statusText { return text }
        let minutes = flight.effectiveDeparture.timeIntervalSince(now) / 60
        if minutes <= 0 { return "Havada" }
        if minutes <= 40 { return "Biniş" }
        return "Zamanında"
    }

    private static func activities(for trip: Trip) -> [Activity<FlightActivityAttributes>] {
        Activity<FlightActivityAttributes>.activities.filter { $0.attributes.tripID == trip.id.uuidString }
    }
}
