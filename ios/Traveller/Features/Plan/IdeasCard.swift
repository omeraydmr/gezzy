import SwiftUI
import TravellerKit

/// Henüz bir güne konmamış yerler. "Güne ekle" ile seçili günün sonuna taşınır.
struct IdeasCard: View {
    @Environment(TripStore.self) private var store
    let trip: Trip
    let day: Date
    @State private var isAdding = false

    var body: some View {
        let ideas = trip.ideaList
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Fikirler", systemImage: "lightbulb.fill")
                    .font(.tBodyStrong)
                    .foregroundStyle(Color.ink)
                if !ideas.isEmpty {
                    Text("\(ideas.count)").font(.tCaption).foregroundStyle(Color.ink3)
                }
                Spacer()
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.circleIcon(size: 32))
                .accessibilityLabel("Fikir ekle")
            }

            if ideas.isEmpty {
                EmptyHint(symbol: "lightbulb", text: "Gitmek istediğin ama gününü bilmediğin yerleri buraya at.")
            }

            ForEach(ideas) { idea in
                HStack(spacing: 12) {
                    Image(systemName: idea.kind.symbol)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.ink2)
                        .frame(width: 34, height: 34)
                        .background(Color.track, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(idea.name).font(.subheadline).foregroundStyle(Color.ink).lineLimit(1)
                        if !idea.note.isEmpty {
                            Text(idea.note).font(.caption).foregroundStyle(Color.ink3).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Button {
                        withAnimation(.spring(duration: 0.3)) { schedule(idea) }
                    } label: {
                        Text("\(AppFormat.dayPill(day)) ekle")
                            .font(.system(.caption, weight: .bold))
                            .foregroundStyle(Color.onInk)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .contextMenu {
                    Button("Sil", systemImage: "trash", role: .destructive) {
                        withAnimation { store.update(trip.id) { $0.ideas?.removeAll { $0.id == idea.id } } }
                    }
                }
            }
        }
        .tray()
        .sheet(isPresented: $isAdding) {
            AddStopSheet(trip: trip, day: day, asIdea: true)
        }
    }

    /// Fikri günün sonuna durak olarak ekler. Durak yeni kimlik alır; böylece fikrin silinmesi
    /// eşitlemede diğer cihazlara da yansır.
    private func schedule(_ idea: Stop) {
        store.update(trip.id) { trip in
            let order = (trip.stops(on: day).map(\.order).max() ?? -1) + 1
            var stop = idea
            stop.id = UUID()
            stop.day = Calendar.current.startOfDay(for: day)
            stop.order = order
            trip.stops.append(stop)
            trip.ideas?.removeAll { $0.id == idea.id }
        }
    }
}
