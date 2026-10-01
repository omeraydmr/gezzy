import SwiftUI
import TravellerKit

/// Bir sonraki seyahatin biniş kartı görünümü.
struct BoardingPassCard: View {
    let trip: Trip
    let flight: FlightSegment

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                CoverArt(seed: trip.coverSeed)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                HStack(spacing: 8) {
                    Text(Countries.flag(trip.destination.countryCode))
                    Text(trip.name).font(.tBodyStrong).foregroundStyle(Color.ink)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(Color.tray, in: Capsule())
                .softShadow()
                .offset(y: 18)
            }
            .padding([.horizontal, .top], 12)

            route
                .padding(.horizontal, 24)
                .padding(.top, 34)

            meta
                .padding(.horizontal, 24)
                .padding(.vertical, 20)

            Perforation()
                .frame(height: 24)

            crew
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
        }
        .background(Color.tray, in: RoundedRectangle(cornerRadius: Radius.tray, style: .continuous))
        .softShadow()
        .accessibilityElement(children: .combine)
    }

    private var route: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(flight.fromCode).font(.tDisplay).foregroundStyle(Color.ink)
                Text("\(flight.fromCity) · \(AppFormat.time(flight.departure, timeZone: flight.departureTimeZone))")
                    .font(.tBody).foregroundStyle(Color.ink2)
            }
            .layoutPriority(1)
            VStack(spacing: 4) {
                FlightArc()
                    .frame(height: 34)
                Text(AppFormat.duration(minutes: flight.durationMinutes))
                    .font(.tBody).foregroundStyle(Color.ink3)
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .trailing, spacing: 6) {
                Text(flight.toCode).font(.tDisplay).foregroundStyle(Color.ink)
                Text("\(AppFormat.time(flight.arrival, timeZone: flight.arrivalTimeZone)) · \(flight.toCity)")
                    .font(.tBody).foregroundStyle(Color.ink2)
            }
            .layoutPriority(1)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var meta: some View {
        HStack(alignment: .top) {
            field("Tarih", AppFormat.shortDate(flight.departure))
            Spacer()
            field("Kapı", flight.gate ?? "—")
            Spacer()
            field("Koltuk", flight.seat ?? "—")
            Spacer()
            field("Konaklama", "\(trip.nights()) gece")
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.tCaption).foregroundStyle(Color.ink3)
            Text(value).font(.tBodyStrong).foregroundStyle(Color.ink)
        }
    }

    private var crew: some View {
        let readyCount = trip.members.filter { member in
            let result = VisaAdvisor.assess(countryCode: trip.destination.countryCode, passport: member.passport,
                                            tripStart: trip.startDate, tripEnd: trip.endDate)
            return !result.needsAction
        }.count
        let allReady = readyCount == trip.members.count
        return HStack(spacing: 14) {
            AvatarStack(members: trip.members, size: 40, limit: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(trip.members.count) yolcu").font(.tBodyStrong).foregroundStyle(Color.ink)
                Text(allReady ? "Belgeler tamam ✓" : "\(trip.members.count - readyCount) kişinin belgesi eksik")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(allReady ? Color.success : Color.food)
            }
            Spacer()
            Barcode()
                .frame(width: 64, height: 40)
        }
    }
}

/// Kalkış ve varış arasındaki kesikli yay + uçak.
struct FlightArc: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 4, y: h - 4))
                    path.addQuadCurve(to: CGPoint(x: w - 4, y: h - 4), control: CGPoint(x: w / 2, y: -h * 0.4))
                }
                .stroke(Color.ink3, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 5]))
                Circle().fill(Color.ink3).frame(width: 7, height: 7).position(x: 4, y: h - 4)
                Circle().fill(Color.success).frame(width: 7, height: 7).position(x: w - 4, y: h - 4)
                Image(systemName: "airplane")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .position(x: w / 2, y: h * 0.18)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Bileti ikiye bölen kesikli çizgi; yan çentikler zemin rengiyle çizilir.
struct Perforation: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle().fill(Color.canvas).frame(width: 24, height: 24).offset(x: -12)
            Line()
                .stroke(Color.line, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                .frame(height: 2)
            Circle().fill(Color.canvas).frame(width: 24, height: 24).offset(x: 12)
        }
        .accessibilityHidden(true)
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

struct Barcode: View {
    private static let widths: [CGFloat] = [2, 1, 3, 1, 1, 2, 1, 3, 2, 1, 1, 2, 3, 1, 2, 1, 1, 3, 1, 2, 2, 1, 3, 1]

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(Self.widths.indices, id: \.self) { index in
                Rectangle().fill(Color.ink).frame(width: Self.widths[index])
            }
        }
        .accessibilityHidden(true)
    }
}
