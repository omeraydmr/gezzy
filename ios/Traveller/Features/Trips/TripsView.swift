import SwiftUI
import TravellerKit

struct TripsView: View {
    @Environment(TripStore.self) private var store
    @State private var scope: Scope = .upcoming
    @State private var isCreating = false
    @State private var path: [Trip.ID] = []

    enum Scope: Hashable { case upcoming, past }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    content
                    HStack(spacing: 12) {
                        Button {
                            isCreating = true
                        } label: {
                            Label("Seyahat planla", systemImage: "plus")
                        }
                        .buttonStyle(.primary)
                    }
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .background(Color.canvas.ignoresSafeArea())
            .navigationDestination(for: Trip.ID.self) { id in
                TripDetailView(tripID: id)
            }
            .sheet(isPresented: $isCreating) {
                NewTripSheet { trip in
                    store.add(trip)
                    path.append(trip.id)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Label("Seyahatler", systemImage: "suitcase.fill")
                .font(.tTitle)
                .foregroundStyle(Color.ink2)
            Spacer()
            PillPicker(selection: $scope, options: [.upcoming, .past]) { $0 == .upcoming ? "Yaklaşan" : "Geçmiş" }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        let trips = scope == .upcoming ? store.upcoming : store.past
        if trips.isEmpty {
            EmptyHint(symbol: "map", text: scope == .upcoming ? "Henüz planlanmış bir seyahat yok." : "Geçmiş seyahat yok.")
                .tray()
        } else {
            if scope == .upcoming, let featured = trips.first, let flight = featured.primaryFlight {
                NavigationLink(value: featured.id) {
                    BoardingPassCard(trip: featured, flight: flight)
                }
                .buttonStyle(.plain)
                ForEach(trips.dropFirst()) { trip in
                    row(trip)
                }
            } else {
                ForEach(trips) { trip in
                    row(trip)
                }
            }
        }
    }

    private func row(_ trip: Trip) -> some View {
        NavigationLink(value: trip.id) {
            TripRow(trip: trip)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Seyahati sil", systemImage: "trash", role: .destructive) {
                store.delete(trip.id)
            }
        }
    }
}

struct TripRow: View {
    let trip: Trip

    var body: some View {
        HStack(spacing: 16) {
            ZStack(alignment: .bottomLeading) {
                CoverArt(seed: trip.coverSeed)
                    .frame(width: 76, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
                    .opacity(0.5)
                    .offset(x: -6, y: -6)
                CoverArt(seed: trip.coverSeed)
                    .frame(width: 76, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
                    .softShadow()
                FlagBadge(countryCode: trip.destination.countryCode)
                    .padding(6)
            }
            .padding(.leading, 6)
            .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(trip.name)
                    .font(.tBodyStrong)
                    .foregroundStyle(Color.ink)
                Text(AppFormat.dateRange(trip.startDate, trip.endDate))
                    .font(.tBody)
                    .foregroundStyle(Color.ink2)
                HStack {
                    AvatarStack(members: trip.members, size: 26)
                    Spacer(minLength: 8)
                    statusTag
                }
                .padding(.top, 4)
            }
        }
        .tray(padding: 14)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusTag: some View {
        if trip.status == .draft {
            Tag(text: "Taslak", accent: .orange)
        } else {
            let countdown = Countdown.make(start: trip.startDate, end: trip.endDate)
            let accent: Accent = switch countdown {
            case .days, .today: .blue
            case .months: .purple
            case .ongoing: .green
            case .past: .gray
            }
            Tag(text: AppFormat.countdown(countdown), accent: accent)
        }
    }
}
