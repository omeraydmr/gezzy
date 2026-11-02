import SwiftUI
import GezzyKit

/// Günün başındaki/sonundaki otel ya da havalimanı satırı; dokununca Rezervasyon sekmesi açılır.
struct AnchorRow: View {
    enum Role { case start, end }
    enum Timing {
        case arrival(FlightDayTiming.Arrival)
        case departure(FlightDayTiming.Departure)
    }

    let anchor: DayAnchor
    let role: Role
    var timing: Timing?
    @Environment(\.openReservations) private var openReservations

    var body: some View {
        Button(action: openReservations) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isAirport ? "airplane" : "bed.double.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isAirport ? Accent.blue.base : Accent.green.base)
                    .frame(width: 36, height: 36)
                    .background(isAirport ? Accent.blue.tint : Accent.green.tint, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.tBody).foregroundStyle(Color.ink).lineLimit(1)
                    ForEach(notes, id: \.text) { note in
                        FlightTimingNote(text: note.text, symbol: note.symbol)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.ink3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var isAirport: Bool { if case .airport = anchor { true } else { false } }

    private var title: String {
        switch (anchor, timing) {
        case (.airport(let airport, _), .arrival(let a)?):
            String(localized: "\(airport.code) · iniş \(AppFormat.time(minutes: a.landing))")
        case (.airport(let airport, _), .departure(let d)?):
            String(localized: "\(airport.code) · kalkış \(AppFormat.time(minutes: d.takeoff))")
        case (.lodging(let lodging), _):
            role == .start ? String(localized: "\(lodging.name) · başlangıç") : String(localized: "\(lodging.name) · bitiş")
        default:
            anchor.name
        }
    }

    private var notes: [(text: String, symbol: String)] {
        switch timing {
        case .arrival(let a)?:
            var list: [(text: String, symbol: String)] = [(String(localized: "Şehirde yaklaşık \(AppFormat.time(minutes: a.readyAt))"), "clock")]
            if a.ees { list.append((String(localized: "Yeni AB sınır kaydı (EES) nedeniyle pasaport sırası uzun sürebilir."), "person.badge.clock")) }
            return list
        case .departure(let d)?:
            var list: [(text: String, symbol: String)] = []
            if d.leaveBy < 6 * 60 {
                list.append((String(localized: "Sabah erken uçuş; bu gün için durak planlama."), "sunrise"))
            }
            list.append((String(localized: "Havalimanında ol: en geç \(AppFormat.time(minutes: max(0, d.beAtAirport)))"), "clock.badge.exclamationmark"))
            if d.transfer != nil {
                list.append((String(localized: "Havalimanına çıkış: yaklaşık \(AppFormat.time(minutes: max(0, d.leaveBy)))"), "car"))
            }
            list.append((String(localized: "Kapı ve biniş saatini bilette kontrol et."), "ticket"))
            if d.ees { list.append((String(localized: "Yeni AB sınır kaydı (EES) nedeniyle pasaport sırası uzun sürebilir."), "person.badge.clock")) }
            return list
        case nil:
            return []
        }
    }
}

struct FlightTimingNote: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(Color.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Varış günü: "Önce otele uğramak ister misin?" önerisi.
struct HotelVisitSuggestion: View {
    let lodging: Lodging
    let onAdd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "suitcase.rolling").foregroundStyle(Accent.green.base)
            Text("Önce otele uğramak ister misin?").font(.subheadline).foregroundStyle(Color.ink)
            Spacer(minLength: 4)
            Button("Ekle", action: onAdd).font(.subheadline.bold())
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.caption)
            }
            .accessibilityLabel("Öneriyi kapat")
        }
        .padding(10)
        .background(Accent.green.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.vertical, 6)
    }
}
