import SwiftUI
import TravellerKit

/// Destedeki bilet kartı: üstte kapak (fotoğraf ya da pastel), altta çentikle ayrılmış bilet koçanı. Tek şehirde kare;
/// çok şehirli seyahatte daha geniş ve koçan şehir şehir yırtık çizgilerle bölünmüş (şehir eklenince koçanlar birleşir).
///
/// Performans: kart `Equatable`; deste kaydırılırken yalnızca konumu değişir, içeriği yeniden kurulmaz.
/// İçerik `drawingGroup` ile tek dokuya çizilir, gölge ise yalnızca basit bir şeklin gölgesidir.
struct TripTicketCard: View, Equatable {
    let trip: Trip
    let side: CGFloat
    /// Çok şehirli kartın en fazla genişliği (deste ya da form genişliği).
    var maxWidth: CGFloat?

    nonisolated static func == (lhs: TripTicketCard, rhs: TripTicketCard) -> Bool {
        lhs.side == rhs.side && lhs.maxWidth == rhs.maxWidth && lhs.trip == rhs.trip
    }

    /// Çok şehirde her ek şehir için genişler (en fazla `maxWidth`).
    static func width(for trip: Trip, side: CGFloat, maxWidth: CGFloat?) -> CGFloat {
        guard trip.isMultiCity else { return side }
        let wanted = side * (1 + 0.16 * CGFloat(min(trip.cityLegs.count - 1, 3)))
        return min(wanted, maxWidth ?? wanted).rounded()
    }

    private var width: CGFloat { Self.width(for: trip, side: side, maxWidth: maxWidth) }
    private var coverHeight: CGFloat { (side * 0.6).rounded() }

    var body: some View {
        let tint = trip.tint
        VStack(spacing: 0) {
            cover(tint: tint)
                .frame(height: coverHeight)
            stub(tint: tint)
                .frame(maxHeight: .infinity)
        }
        .frame(width: width, height: side)
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
                Text("\(trip.countryCodes.map(Countries.flag).joined()) \(trip.cityTitle) · \(AppFormat.dateRange(trip.startDate, trip.endDate))")
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
            if trip.isMultiCity {
                CityStubs(trip: trip, tint: tint)
            } else if let flight = trip.primaryFlight {
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
        "\(trip.name), \(trip.cityTitle), \(AppFormat.dateRange(trip.startDate, trip.endDate)), \(trip.countdownTag.text)"
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

/// Çok şehirli koçan: her şehir kendi bölümü (ad, tarih, gece), aralarında yırtık çizgi. Şehir sayısı değişince
/// bölümler önce ayrı biletler gibi aralıklı görünür, sonra kayarak birleşir.
struct CityStubs: View {
    let trip: Trip
    let tint: Color
    @State private var joined = true

    var body: some View {
        let legs = trip.cityLegs
        HStack(spacing: joined ? 0 : 10) {
            ForEach(Array(legs.enumerated()), id: \.element.id) { index, leg in
                if index > 0 {
                    Perforation()
                        .stroke(Color.line, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: 1)
                        .opacity(joined ? 1 : 0)
                }
                segment(leg)
                    .padding(.horizontal, joined ? 0 : 8)
                    .padding(.vertical, joined ? 0 : 4)
                    .background(tint.opacity(joined ? 0 : 0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: legs.map(\.id)) { old, new in
            guard new.count > old.count else { return }
            // Yeni koçan önce ayrı durur, sonra diğerleriyle birleşir.
            joined = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(380))
                withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { joined = true }
            }
        }
    }

    private func segment(_ leg: TripLeg) -> some View {
        let range = trip.dateRange(of: leg)
        let nights = trip.days(in: leg).count - (leg.id == trip.cityLegs.last?.id ? 1 : 0)
        return VStack(alignment: .leading, spacing: 1) {
            Text("\(Countries.flag(leg.destination.countryCode)) \(leg.destination.city)")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text("\(AppFormat.dayPill(range.start)) · \(String(localized: "\(max(nights, 0)) gece"))")
                .font(.caption2)
                .foregroundStyle(Color.ink3)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    private struct Perforation: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            }
        }
    }
}
