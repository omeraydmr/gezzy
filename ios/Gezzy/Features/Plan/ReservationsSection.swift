import SwiftUI
import GezzyKit

/// Rezervasyon sekmesi: uçuşlar ve konaklama.
struct ReservationsSection: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FlightsCard(trip: trip)
            LodgingCard(trip: trip)
        }
    }
}
