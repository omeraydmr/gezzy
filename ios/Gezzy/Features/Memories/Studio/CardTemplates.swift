import SwiftUI
import GezzyKit

/// Paylaşım kartı: beş şablon, üç biçim. Tüm ölçüler genişliğe oranlıdır (`u = width / 360`), böylece önizleme
/// ve 1080 px çıktı aynı görünür. Gezzy işareti `config.showsBrand` ile çizilir; çağıran Premium kuralını
/// (`effectiveShowsBrand`) önceden uygular.
struct CardTemplateView: View {
    let trip: Trip
    let summary: TripSummary
    let config: ShareCardConfig
    let photos: [UIImage]
    let mapImage: UIImage?
    let palette: TripPalette
    let width: CGFloat
    /// Önizlemede harita alınamadıysa (çevrimdışı); nil harita bu durumda yükleniyor sayılmaz.
    var mapFailed = false

    private var u: CGFloat { width / 360 }
    private var height: CGFloat { width / config.format.aspect }
    private var isStory: Bool { config.format == .story }
    private var isSquare: Bool { config.format == .square }
    /// Story'de üst/alt boşluk büyür (uygulama arayüzleri kartın kenarlarını örter).
    private var verticalPad: CGFloat { (isStory ? 56 : 24) * u }

    var body: some View {
        Group {
            switch config.template {
            case .postcard: postcard
            case .stats: stats
            case .route: route
            case .collage: collage
            case .ticket: ticket
            }
        }
        .frame(width: width, height: height)
        .clipped()
        // Kart her temada aynı görünür.
        .environment(\.colorScheme, .light)
    }

    // MARK: Ortak

    private var title: String { config.title ?? trip.name }
    private var subtitle: String {
        config.subtitle ?? "\(trip.cityTitle) · \(AppFormat.dateRange(trip.startDate, trip.endDate))"
    }
    private var flags: String { trip.countryCodes.map(Countries.flag).joined() }

    private func font(_ size: CGFloat, _ weight: Font.Weight = .regular, _ design: Font.Design = .default) -> Font {
        .system(size: size * u, weight: weight, design: design)
    }

    @ViewBuilder private func brand(onDark: Bool) -> some View {
        if config.showsBrand {
            GezzyMark(onDark: onDark, scale: u * 0.6)
        }
    }

    private var statItems: [CardStat] {
        ShareCardConfig.Stat.allCases.filter(config.stats.contains).map { CardStat($0, summary, currency: trip.currency) }
    }

    /// Fotoğraf kırpılarak alanı doldurur; yoksa palet gradyanı.
    @ViewBuilder private func photoFill(_ image: UIImage?) -> some View {
        if let image {
            Color.clear
                .overlay { Image(uiImage: image).resizable().scaledToFill() }
                .clipped()
        } else {
            LinearGradient(colors: palette.bands.map { Color(hex: $0) }, startPoint: .top, endPoint: .bottom)
        }
    }

    private func statColumn(_ item: CardStat, value: CGFloat, label: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2 * u) {
            Text(item.value)
                .font(font(value, .bold, .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(item.label)
                .font(font(label, .medium))
                .opacity(0.8)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Kartpostal

    private var postcard: some View {
        ZStack(alignment: .bottom) {
            photoFill(photos.first)
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 14 * u) {
                HStack(alignment: .bottom, spacing: 12 * u) {
                    VStack(alignment: .leading, spacing: 6 * u) {
                        Text(title)
                            .font(font(28, .bold))
                            .lineLimit(3)
                            .minimumScaleFactor(0.7)
                        Text(subtitle)
                            .font(font(13, .medium))
                            .opacity(0.9)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    postageStamp
                }
                if !statItems.isEmpty {
                    HStack(alignment: .top, spacing: 10 * u) {
                        ForEach(statItems) { statColumn($0, value: 17, label: 10) }
                    }
                }
                brand(onDark: true).frame(maxWidth: .infinity)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20 * u)
            .padding(.vertical, verticalPad)
        }
    }

    /// Posta pulu: tırtıklı beyaz kare, bayrak, şehir, tarih; üstünde soluk mühür izi.
    private var postageStamp: some View {
        VStack(spacing: 3 * u) {
            Text(flags.isEmpty ? "✈️" : flags)
                .font(font(26))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(trip.destination.city.uppercased(with: AppFormat.locale))
                .font(font(10, .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(trip.startDate.formatted(.dateTime.day().month(.abbreviated).year().locale(AppFormat.locale))
                .uppercased(with: AppFormat.locale))
                .font(font(8, .semibold, .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(Color.ink)
        .padding(12 * u)
        .frame(width: 92 * u, height: 108 * u)
        .overlay(
            Rectangle()
                .strokeBorder(Color(hex: palette.accent).opacity(0.6), lineWidth: 1.2 * u)
                .padding(7 * u)
        )
        .background(
            PerforatedShape(radius: 3.2 * u)
                .fill(.white)
                .shadow(color: .black.opacity(0.3), radius: 6 * u, y: 3 * u)
        )
        .overlay(alignment: .topLeading) {
            StampImprint(subtitle: StampImprint.subtitle(for: trip, on: trip.startDate), scale: 0.45 * u)
                .rotationEffect(.degrees(-6))
                .opacity(0.35)
                .offset(x: -44 * u, y: -18 * u)
                .allowsHitTesting(false)
        }
    }

    // MARK: İstatistik

    private var stats: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "\(flags) \(trip.cityTitle)")
                .font(font(14, .semibold))
                .opacity(0.85)
                .lineLimit(1)
            Text(title)
                .font(font(isStory ? 40 : 34, .bold))
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .padding(.top, 8 * u)
            Text(subtitle)
                .font(font(14, .medium))
                .opacity(0.85)
                .lineLimit(2)
                .padding(.top, 6 * u)
            Spacer(minLength: 16 * u)
            Grid(alignment: .leading, horizontalSpacing: 16 * u, verticalSpacing: 18 * u) {
                let rows = statItems.chunked(isSquare ? 3 : 2)
                ForEach(rows.indices, id: \.self) { index in
                    GridRow {
                        ForEach(rows[index]) { statColumn($0, value: isSquare ? 26 : 32, label: 12) }
                    }
                }
            }
            if !summary.highlights.isEmpty {
                Text(String(localized: "Öne çıkanlar: ") + summary.highlights.joined(separator: " · "))
                    .font(font(12, .medium))
                    .opacity(0.9)
                    .lineLimit(2)
                    .padding(.top, 18 * u)
            }
            Spacer(minLength: 16 * u)
            brand(onDark: true).frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24 * u)
        .padding(.vertical, verticalPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            LinearGradient(stops: [.init(color: Color(hex: palette.accent), location: 0.3),
                                   .init(color: Color(hex: palette.bands[0]), location: 1)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                // Açık uçta beyaz yazı okunsun.
                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.3)], startPoint: .center, endPoint: .bottom))
        }
    }

    // MARK: Rota

    private var route: some View {
        let legend = CardRenderer.routeDays(trip).map(\.index)
        return VStack(spacing: 0) {
            Group {
                if let mapImage {
                    photoFill(mapImage)
                } else {
                    Group {
                        if !CardRenderer.hasRoute(trip) {
                            mapNote(String(localized: "Rota için konumlu durak gerekli"))
                        } else if mapFailed {
                            mapNote(String(localized: "Harita oluşturulamadı"))
                        } else {
                            ProgressView().controlSize(.large)
                        }
                    }
                    .foregroundStyle(Color.ink.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(hex: palette.bands[0]))
                }
            }
            .frame(height: height * 0.7)
            VStack(alignment: .leading, spacing: (isSquare ? 3 : 6) * u) {
                Text(title)
                    .font(font(isSquare ? 19 : 24, .bold))
                    .lineLimit(isSquare ? 1 : 2)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(font(isSquare ? 11 : 13, .medium))
                    .foregroundStyle(Color.ink2)
                    .lineLimit(1)
                if !legend.isEmpty {
                    Grid(alignment: .leading, horizontalSpacing: 12 * u, verticalSpacing: 6 * u) {
                        let rows = Array(legend.chunked(5).prefix(isStory ? 3 : 1))
                        // Sığmayan günler "+N" ile.
                        let hiddenDays = legend.count - rows.reduce(0) { $0 + $1.count }
                        ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                            GridRow {
                                ForEach(row, id: \.self) { day in
                                    HStack(spacing: 4 * u) {
                                        Circle().fill(palette.pin(day)).frame(width: 8 * u, height: 8 * u)
                                        Text(String(localized: "\(day + 1). gün"))
                                            .font(font(10, .semibold))
                                            .foregroundStyle(Color.ink2)
                                            .lineLimit(1)
                                    }
                                }
                                if rowIndex == rows.count - 1 && hiddenDays > 0 {
                                    Text(verbatim: "+\(hiddenDays)")
                                        .font(font(10, .bold))
                                        .foregroundStyle(Color.ink2)
                                }
                            }
                        }
                    }
                    .padding(.top, 4 * u)
                }
                Spacer(minLength: 0)
                brand(onDark: false).frame(maxWidth: .infinity)
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 22 * u)
            .padding(.top, (isSquare ? 12 : 18) * u)
            .padding(.bottom, (isStory ? 40 : 12) * u)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(hex: palette.softLight))
        }
    }

    private func mapNote(_ text: String) -> some View {
        VStack(spacing: 8 * u) {
            Image(systemName: "map").font(font(34))
            Text(text).font(font(13, .medium)).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24 * u)
    }

    // MARK: Kolaj

    private var collage: some View {
        let gap = 4 * u
        let band = ((isStory ? 120 : 70) + (config.showsBrand ? 18 : 0)) * u
        let gridHeight = height - band
        let columns = ShareCardConfig.collageColumns(count: photos.count, format: config.format)
        let rows = photos.chunked(columns)
        let cellHeight = rows.isEmpty ? gridHeight : (gridHeight - gap * CGFloat(rows.count - 1)) / CGFloat(rows.count)
        return VStack(spacing: 0) {
            Group {
                if rows.isEmpty {
                    photoFill(nil)
                } else {
                    // Alan dolsun diye hücre yüksekliği satır sayısından; eksik son satır genişler.
                    VStack(spacing: gap) {
                        ForEach(rows.indices, id: \.self) { row in
                            HStack(spacing: gap) {
                                ForEach(rows[row].indices, id: \.self) { index in
                                    photoFill(rows[row][index]).frame(height: cellHeight)
                                }
                            }
                        }
                    }
                }
            }
            .frame(height: gridHeight)
            VStack(spacing: 4 * u) {
                Text(title)
                    .font(font(18, .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(font(12, .medium))
                    .foregroundStyle(Color.ink2)
                    .lineLimit(1)
                if config.showsBrand {
                    brand(onDark: false).padding(.top, 4 * u)
                }
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 20 * u)
            .padding(.bottom, isStory ? 30 * u : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(hex: palette.softLight))
    }

    // MARK: Bilet

    private var ticket: some View {
        let cardHeight = height - 2 * verticalPad
        let stub = 58 * u
        let accent = Color(hex: palette.accent)
        return ZStack {
            LinearGradient(colors: palette.bands.map { Color(hex: $0) }, startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        // İşaret kapalıysa (Premium) üst satırda Gezzy yerine seyahat adı; başlıkla aynıysa şehirler.
                        Text(config.showsBrand ? "GEZZY" : ticketHeader.uppercased(with: AppFormat.locale))
                            .font(font(12, .heavy))
                            .tracking(3 * u)
                            .foregroundStyle(accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer()
                        Text(flags).font(font(16)).lineLimit(1)
                    }
                    Text(title)
                        .font(font(22, .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 8 * u)
                    Spacer(minLength: 10 * u)
                    routeRow(accent: accent)
                    Spacer(minLength: 10 * u)
                    ticketFields
                }
                .padding(20 * u)
                .frame(maxHeight: .infinity, alignment: .top)
                Line()
                    .stroke(Color.ink3.opacity(0.5), style: StrokeStyle(lineWidth: 1.2 * u, dash: [4 * u, 4 * u]))
                    .frame(height: 1)
                    .padding(.horizontal, 16 * u)
                HStack {
                    if config.showsBrand {
                        brand(onDark: false)
                    } else {
                        Text(StampImprint.subtitle(for: trip, on: trip.startDate))
                            .font(font(10, .bold, .monospaced))
                            .foregroundStyle(Color.ink2)
                    }
                    Spacer()
                    Image(systemName: "airplane")
                        .font(font(14, .semibold))
                        .foregroundStyle(accent)
                }
                .padding(.horizontal, 20 * u)
                .frame(height: stub)
            }
            .foregroundStyle(Color.ink)
            .frame(height: cardHeight)
            .background(
                TicketShape(notchY: cardHeight - stub, notchRadius: 11 * u, cornerRadius: 24 * u)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.2), radius: 12 * u, y: 6 * u)
            )
            .padding(.horizontal, 22 * u)
        }
    }

    /// Kalkış/varış: birincil uçuş kodları, yoksa ilk ve son şehir.
    @ViewBuilder private func routeRow(accent: Color) -> some View {
        let arc = FlightArc(accent: accent)
            .frame(width: 90, height: 30)
            .scaleEffect(u)
            .frame(width: 90 * u, height: 30 * u)
        if let flight = trip.primaryFlight {
            HStack(alignment: .bottom, spacing: 8 * u) {
                endpoint(flight.fromCode, flight.fromCity, alignment: .leading)
                arc
                endpoint(flight.toCode, flight.toCity, alignment: .trailing)
            }
        } else {
            let cities = trip.cityLegs.map(\.destination.city)
            if let first = cities.first, let last = cities.last, cities.count > 1 {
                HStack(alignment: .center, spacing: 8 * u) {
                    cityName(first, alignment: .leading)
                    arc
                    cityName(last, alignment: .trailing)
                }
            } else {
                VStack(spacing: 6 * u) {
                    arc
                    cityName(trip.destination.city, alignment: .center)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func endpoint(_ code: String, _ city: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2 * u) {
            Text(code)
                .font(font(34, .bold, .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(city)
                .font(font(11, .medium))
                .foregroundStyle(Color.ink2)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }

    private func cityName(_ name: String, alignment: HorizontalAlignment) -> some View {
        Text(name)
            .font(font(22, .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }

    private var ticketHeader: String { title == trip.name ? trip.cityTitle : trip.name }

    private var ticketFields: some View {
        var fixed = [
            CardStat(id: nil, value: AppFormat.dateRange(trip.startDate, trip.endDate), label: String(localized: "Tarih")),
            CardStat(id: nil, value: "\(summary.nights)", label: String(localized: "Gece")),
            CardStat(id: nil, value: "\(summary.travellers)", label: String(localized: "Kişi")),
        ]
        if let seat = trip.primaryFlight?.seat, !seat.isEmpty {
            fixed.append(CardStat(id: nil, value: seat, label: String(localized: "Koltuk")))
        }
        // Kişi her zaman sabit alanda; anahtarlardan tekrar gelmez.
        let extra = statItems.filter { $0.stat != .travellers }.chunked(3).prefix(isSquare ? 1 : 2)
        let rows = [fixed] + extra
        return Grid(alignment: .leading, horizontalSpacing: 12 * u, verticalSpacing: 10 * u) {
            ForEach(rows.indices, id: \.self) { index in
                GridRow {
                    ForEach(rows[index]) { item in
                        VStack(alignment: .leading, spacing: 2 * u) {
                            Text(item.label.uppercased(with: AppFormat.locale))
                                .font(font(9, .semibold))
                                .tracking(0.8 * u)
                                .foregroundStyle(Color.ink3)
                                .lineLimit(1)
                            Text(item.value)
                                .font(font(15, .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

// MARK: - Yardımcılar

/// Kartta gösterilen bir bilgi (değer + etiket).
struct CardStat: Identifiable {
    /// Bir satırdaki etiketler benzersizdir.
    var id: String { label }
    let stat: ShareCardConfig.Stat?
    let value: String
    let label: String

    init(id stat: ShareCardConfig.Stat?, value: String, label: String) {
        self.stat = stat
        self.value = value
        self.label = label
    }

    init(_ stat: ShareCardConfig.Stat, _ summary: TripSummary, currency: String) {
        switch stat {
        // Etiket sayıdan ayrı çizilir; tekil için ayrı anahtar ("gün (1)": en "day").
        case .days:
            self.init(id: stat, value: "\(summary.days)",
                      label: summary.days == 1 ? String(localized: "gün (1)") : String(localized: "gün"))
        case .stops:
            self.init(id: stat, value: "\(summary.stops)",
                      label: summary.stops == 1 ? String(localized: "durak (1)") : String(localized: "durak"))
        case .distance:
            self.init(id: stat,
                      value: (summary.routeMeters / 1000).formatted(.number.precision(.fractionLength(0...1))
                          .locale(AppFormat.locale)),
                      label: String(localized: "km"))
        case .travellers:
            self.init(id: stat, value: "\(summary.travellers)",
                      label: summary.travellers == 1 ? String(localized: "kişi (1)") : String(localized: "kişi"))
        case .spent:
            self.init(id: stat, value: AppFormat.money(summary.totalSpent, currency), label: String(localized: "harcama"))
        case .perPerson:
            self.init(id: stat, value: AppFormat.money(summary.perPerson, currency), label: String(localized: "kişi başı"))
        }
    }
}

/// Kenarları küçük yarım dairelerle tırtıklı dikdörtgen (posta pulu).
struct PerforatedShape: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        var path = Path()
        path.move(to: corners[0])
        for edge in 0..<4 {
            let start = corners[edge], end = corners[(edge + 1) % 4]
            let dx = end.x - start.x, dy = end.y - start.y
            let length = hypot(dx, dy)
            guard length > 0, radius > 0 else { path.addLine(to: end); continue }
            let ux = dx / length, uy = dy / length
            let angle = Angle(radians: atan2(uy, ux))
            let count = max(1, Int((length / (radius * 3.2)).rounded()))
            let step = length / CGFloat(count)
            for index in 0..<count {
                let distance = step * (CGFloat(index) + 0.5)
                let center = CGPoint(x: start.x + ux * distance, y: start.y + uy * distance)
                path.addLine(to: CGPoint(x: center.x - ux * radius, y: center.y - uy * radius))
                // İçeri doğru yarım daire.
                path.addArc(center: center, radius: radius, startAngle: angle + .degrees(180), endAngle: angle,
                            clockwise: true)
            }
            path.addLine(to: end)
        }
        path.closeSubpath()
        return path
    }
}

/// Yatay çizgi (bilet ayracı).
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
