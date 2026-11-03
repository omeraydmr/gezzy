import SwiftUI
import GezzyKit

/// Gitmek istenen ama henüz bir güne konmamış yerler. Elle ya da önerilerden eklenir; satırdaki "+" ile
/// seçili güne (basılı tutunca başka bir güne) taşınır ya da "Otomatik rota" hepsini günlere dağıtır.
struct IdeasCard: View {
    @Environment(\.tripPalette) private var palette
    @Environment(\.tripTint) private var tint
    @Environment(\.tripText) private var tintText
    @Environment(TripStore.self) private var store
    let trip: Trip
    let day: Date
    @State private var isPicking = false
    @State private var isPlanning = false
    @Environment(Entitlements.self) private var entitlements
    @State private var isShowingPaywall = false
    @State private var planAfterPaywall = false
    /// Son otomatik rotadan önceki duraklar ve fikirler; "Geri al" bunları geri yükler.
    @State private var undo: (stops: [Stop], ideas: [Stop]?)?

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
                    isPicking = true
                } label: {
                    HeaderPlusLabel()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Yer ekle")
            }

            if ideas.isEmpty {
                AddPlaceholder(title: String(localized: "Yer ekle"),
                               subtitle: String(localized: "Gitmek istediğin yerleri ekle; sonra otomatik rota günlere dağıtsın.")) {
                    isPicking = true
                }
            }

            HStack(spacing: 8) {
                if !ideas.isEmpty {
                    Button {
                        if entitlements.isPremium {
                            isPlanning = true
                        } else {
                            isShowingPaywall = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Label("Otomatik rota", systemImage: "wand.and.stars")
                            if !entitlements.isPremium {
                                Image(systemName: "lock.fill").font(.system(size: 10))
                            }
                        }
                    }
                    .buttonStyle(PillButtonStyle(tint: tintText, soft: .soft(palette)))
                }
                if let undo {
                    Button {
                        withAnimation(.spring(duration: 0.35)) {
                            store.update(trip.id) { trip in
                                trip.stops = undo.stops
                                // Fikirler uygulanınca silindi olarak işaretlendi; eşitlemede kaybolmasınlar
                                // diye geri gelenler yeni kimlik alır.
                                trip.ideas = undo.ideas?.map { idea in
                                    var copy = idea
                                    if trip.tombstones?.contains(idea.id) == true { copy.id = UUID() }
                                    return copy
                                }
                            }
                        }
                        self.undo = nil
                    } label: {
                        Label("Geri al", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(PillButtonStyle())
                }
            }

            ForEach(ideas) { idea in
                HStack(spacing: 12) {
                    Image(systemName: idea.kind.symbol)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.ink2)
                        .frame(width: 28, height: 28)
                        .background(Color.track, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(idea.name).font(.subheadline).foregroundStyle(Color.ink).lineLimit(1)
                        if !idea.note.isEmpty {
                            Text(idea.note).font(.caption).foregroundStyle(Color.ink3).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Menu {
                        ForEach(trip.days(), id: \.self) { target in
                            Button("\(AppFormat.dayPill(target)) ekle") {
                                withAnimation(.spring(duration: 0.3)) { schedule(idea, on: target) }
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(tintText)
                            .frame(width: 32, height: 32)
                            .background(Color.soft(palette), in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    } primaryAction: {
                        withAnimation(.spring(duration: 0.3)) { schedule(idea, on: day) }
                    }
                    .accessibilityLabel(Text("\(AppFormat.dayPill(day)) gününe ekle"))
                }
                .contextMenu {
                    Button("Sil", systemImage: "trash", role: .destructive) {
                        withAnimation { store.update(trip.id) { $0.ideas?.removeAll { $0.id == idea.id } } }
                    }
                }
            }
        }
        .tray()
        .fullScreenCover(isPresented: $isPicking) {
            PlacePickerSheet(trip: trip, target: .ideas, openingDay: day)
                .environment(\.tripPalette, palette)
                .environment(\.tripTint, tint)
                .environment(\.tripText, tintText)
        }
        .sheet(isPresented: $isShowingPaywall, onDismiss: {
            if planAfterPaywall {
                planAfterPaywall = false
                isPlanning = true
            }
        }) {
            PaywallSheet(reason: .autoPlan) { planAfterPaywall = true }
        }
        .sheet(isPresented: $isPlanning) {
            AutoPlanSheet(trip: trip) { before in
                withAnimation { undo = before }
            }
        }
    }

    /// Fikri günün sonuna durak olarak ekler. Durak yeni kimlik alır; böylece fikrin silinmesi
    /// eşitlemede diğer cihazlara da yansır.
    private func schedule(_ idea: Stop, on target: Date) {
        store.update(trip.id) { trip in
            let order = (trip.stops(on: target).map(\.order).max() ?? -1) + 1
            var stop = idea
            stop.id = UUID()
            stop.day = Calendar.current.startOfDay(for: target)
            stop.order = order
            trip.stops.append(stop)
            trip.ideas?.removeAll { $0.id == idea.id }
        }
    }
}

/// Kart içi küçük hap düğme; `tint` verilirse yumuşak zemin + renkli metin.
struct PillButtonStyle: ButtonStyle {
    var tint: Color?
    var soft: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(tint ?? Color.ink)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(soft ?? Color.track, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
