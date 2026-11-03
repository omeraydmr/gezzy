import SwiftUI
import GezzyKit

/// Seyahat ekranının dört sekmesi; Valiz, Vize, Ekip ve Anılar "Daha fazla" altında.
enum TripTab: CaseIterable, Hashable {
    case plan, reservations, money, more

    var title: String {
        switch self {
        case .plan: String(localized: "Plan")
        case .reservations: String(localized: "Rezervasyon")
        case .money: String(localized: "Para")
        case .more: String(localized: "Daha fazla")
        }
    }

    var symbol: String {
        switch self {
        case .plan: "map.fill"
        case .reservations: "suitcase.rolling.fill"
        case .money: "chart.pie.fill"
        case .more: "square.grid.2x2.fill"
        }
    }

    /// Sekmenin doğrudan açtığı bölüm; "Daha fazla" için yok (ızgara).
    var section: TripDetailView.TripSection? {
        switch self {
        case .plan: .plan
        case .reservations: .reservations
        case .money: .money
        case .more: nil
        }
    }
}

extension TripDetailView.TripSection {
    var tab: TripTab {
        switch self {
        case .plan: .plan
        case .reservations: .reservations
        case .money: .money
        case .packing, .visa, .crew, .memories: .more
        }
    }

    static let moreItems: [TripDetailView.TripSection] = [.packing, .visa, .crew, .memories]
}

/// Seyahat özetleri: Seyahatler listesindeki bakış karoları ve "Daha fazla" ızgarası ortak kullanır.
enum TripSummaries {
    /// Vize için işlem bekleyen kişi sayısı.
    @MainActor
    static func visaPending(_ trip: Trip, store: TripStore) -> Int {
        trip.members.filter { store.visaAssessment(for: $0, in: trip).needsAction }.count
    }

    /// Vize kısa metni: bekleyen yoksa "Hazır ✓".
    @MainActor
    static func visaText(_ trip: Trip, store: TripStore) -> String {
        let pending = visaPending(trip, store: store)
        return pending == 0 ? String(localized: "Hazır ✓") : String(localized: "\(pending) kişi bekliyor")
    }

    /// Valiz: hazır ve toplam eşya sayısı.
    static func packing(_ trip: Trip) -> (packed: Int, count: Int) {
        (trip.packing.filter(\.isPacked).count, trip.packing.count)
    }
}

/// "Daha fazla" sekmesi: 2×2 ızgara, her karo bir bölümü aynı yerde açar.
struct MoreSections: View {
    let trip: Trip
    let open: (TripDetailView.TripSection) -> Void
    @Environment(TripStore.self) private var store
    @Environment(\.tripPalette) private var palette
    @Environment(\.tripText) private var tripText

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(TripDetailView.TripSection.moreItems, id: \.self) { section in
                tile(section)
            }
        }
    }

    private func tile(_ section: TripDetailView.TripSection) -> some View {
        let summary = summary(for: section)
        return Button {
            open(section)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tripText)
                    .frame(width: 32, height: 32)
                    .background(Color.soft(palette), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.tBodyStrong)
                        .foregroundStyle(Color.ink)
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(Color.ink2)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground(Color.tray, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(section.title): \(summary)"))
        .accessibilityAddTraits(.isButton)
    }

    private func summary(for section: TripDetailView.TripSection) -> String {
        switch section {
        case .packing:
            let packing = TripSummaries.packing(trip)
            return packing.count == 0
                ? String(localized: "Liste boş")
                : String(localized: "\(packing.packed)/\(packing.count) hazır")
        case .visa:
            return trip.members.isEmpty ? String(localized: "Kişi ekle") : TripSummaries.visaText(trip, store: store)
        case .crew:
            return String(localized: "\(trip.members.count) kişi")
        case .memories:
            return trip.isPast()
                ? String(localized: "Fotoğraflar ve paylaşım kartı")
                : String(localized: "Seyahatten sonra")
        default:
            return ""
        }
    }
}
