import SwiftUI
import TravellerKit

/// Destedeki kare bilet kartı: üstte kapak (fotoğraf ya da pastel), altta çentikle ayrılmış bilet koçanı.
///
/// Performans: kart `Equatable`; deste kaydırılırken yalnızca konumu değişir, içeriği yeniden kurulmaz.
/// İçerik `drawingGroup` ile tek dokuya çizilir, gölge ise yalnızca basit bir şeklin gölgesidir.
struct TripTicketCard: View, Equatable {
    let trip: Trip
    let side: CGFloat

    nonisolated static func == (lhs: TripTicketCard, rhs: TripTicketCard) -> Bool {
        lhs.side == rhs.side && lhs.trip == rhs.trip
    }

    private var coverHeight: CGFloat { (side * 0.6).rounded() }

    var body: some View {
        let tint = trip.tint
        VStack(spacing: 0) {
            cover(tint: tint)
                .frame(height: coverHeight)
            stub(tint: tint)
                .frame(maxHeight: .infinity)
        }
        .frame(width: side, height: side)
        .background(Color.tray)
        .clipShape(TicketShape(notchY: coverHeight))
        .overlay(
            TicketShape(notchY: coverHeight)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .drawingGroup()
        .background {
            TicketShape(notchY: coverHeight)
                .fill(Color.tray)
                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                .shadow(color: tint.opacity(0.28), radius: 18, y: 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    // MARK: Cover

    private func cover(tint: Color) -> some View {
        ZStack(alignment: .bottomLeading) {
            TripCover(trip: trip, maxPixelSize: CoverImageStore.cardPixelSize)
            LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 3) {
                Text(trip.name)
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(Countries.flag(trip.destination.countryCode)) \(trip.destination.city) · \(AppFormat.dateRange(trip.startDate, trip.endDate))")
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .overlay(alignment: .topTrailing) {
            let tag = trip.countdownTag
            Text(tag.text)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(tag.accent == .gray ? Color.ink2 : tag.accent.base)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                // Materyal (arka plan bulanıklığı) yerine düz zemin: dokuya çizilebilir ve ucuz.
                .background(Color.tray.opacity(0.92), in: Capsule())
                .padding(12)
        }
    }

    // MARK: Stub

    private func stub(tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let flight = trip.primaryFlight {
                HStack(alignment: .center, spacing: 10) {
                    code(flight.fromCode, AppFormat.time(flight.departure, timeZone: flight.departureTimeZone))
                    FlightArc(accent: tint)
                        .frame(height: 24)
                    code(flight.toCode, AppFormat.time(flight.arrival, timeZone: flight.arrivalTimeZone), trailing: true)
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trip.destination.city)
                            .font(.system(.title3, weight: .semibold))
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                        Text("Uçuş eklenmedi")
                            .font(.caption)
                            .foregroundStyle(Color.ink3)
                    }
                    Spacer()
                }
            }

            HStack(spacing: 8) {
                AvatarStack(members: trip.members, size: 24, limit: 3)
                Text(summary)
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(Color.ink2)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Barcode()
                    .frame(width: 34, height: 22)
                    .opacity(0.8)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(colors: [tint.opacity(0.10), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .top) {
            Line()
                .stroke(Color.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(height: 1)
                .padding(.horizontal, 16)
        }
    }

    private func code(_ code: String, _ time: String, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 0) {
            Text(code)
                .font(.system(.title2, weight: .semibold))
                .foregroundStyle(Color.ink)
            Text(time)
                .font(.caption)
                .foregroundStyle(Color.ink2)
        }
        .fixedSize()
    }

    private var summary: String {
        var parts = [String(localized: "\(trip.nights()) gece")]
        if trip.members.count > 1 { parts.append(String(localized: "\(trip.members.count) kişi")) }
        return parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        "\(trip.name), \(trip.destination.city), \(AppFormat.dateRange(trip.startDate, trip.endDate)), \(trip.countdownTag.text)"
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }
}
