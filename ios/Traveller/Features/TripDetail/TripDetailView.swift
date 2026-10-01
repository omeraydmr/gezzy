import SwiftUI
import TravellerKit

struct TripDetailView: View {
    @Environment(TripStore.self) private var store
    let tripID: Trip.ID
    @State private var section: TripSection
    @State private var coverTarget: Trip.ID?

    init(tripID: Trip.ID, initialSection: TripSection = .plan) {
        self.tripID = tripID
        _section = State(initialValue: initialSection)
    }

    enum TripSection: String, CaseIterable, Hashable {
        case plan, money, packing, visa, crew

        var title: String {
            switch self {
            case .plan: "Plan"
            case .money: "Bütçe"
            case .packing: "Valiz"
            case .visa: "Vize"
            case .crew: "Ekip"
            }
        }
    }

    var body: some View {
        Group {
            if let trip = store.trip(tripID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(trip)
                        ScrollView(.horizontal, showsIndicators: false) {
                            PillPicker(selection: $section, options: TripSection.allCases) { $0.title }
                        }
                        switch section {
                        case .plan: PlanSection(trip: trip)
                        case .money: MoneySection(trip: trip)
                        case .packing: PackingSection(trip: trip)
                        case .visa: VisaSection(trip: trip)
                        case .crew: CrewSection(trip: trip)
                        }
                    }
                    .padding(16)
                }
                .background(Color.canvas.ignoresSafeArea())
                .navigationTitle(trip.name)
                .navigationBarTitleDisplayMode(.inline)
                .coverPhotoPicker(for: $coverTarget)
            } else {
                ContentUnavailableView("Seyahat bulunamadı", systemImage: "suitcase")
            }
        }
    }

    private func header(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                TripCover(trip: trip)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                FlagBadge(countryCode: trip.destination.countryCode)
                    .padding(12)
            }
            .overlay(alignment: .topTrailing) {
                Menu {
                    Button("Kapak fotoğrafı seç", systemImage: "photo") { coverTarget = trip.id }
                    if trip.coverPhoto != nil {
                        Button("Fotoğrafı kaldır", systemImage: "photo.badge.minus", role: .destructive) {
                            withAnimation { store.removeCoverPhoto(for: trip.id) }
                        }
                    }
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .frame(width: 36, height: 36)
                        .background(.regularMaterial, in: Circle())
                }
                .padding(10)
                .accessibilityLabel("Kapak fotoğrafı")
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.name).font(.tHeadline).foregroundStyle(Color.ink)
                    Text("\(trip.destination.city) · \(AppFormat.dateRange(trip.startDate, trip.endDate)) · \(trip.nights()) gece")
                        .font(.tBody)
                        .foregroundStyle(Color.ink2)
                }
                Spacer(minLength: 8)
                AvatarStack(members: trip.members, size: 30)
            }
            .padding(.top, 14)
            .padding(.horizontal, 6)
        }
        .tray(padding: 12)
    }
}
