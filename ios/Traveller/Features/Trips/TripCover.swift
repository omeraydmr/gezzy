import SwiftUI
import TravellerKit

/// Seyahatin kapağı: kullanıcının fotoğrafı, yoksa pastel yer tutucu.
struct TripCover: View {
    let trip: Trip

    var body: some View {
        if let name = trip.coverPhoto, let image = CoverImageStore.shared.image(named: name) {
            Color.clear
                .overlay(Image(uiImage: image).resizable().scaledToFill())
                .clipped()
                .accessibilityHidden(true)
        } else {
            CoverArt(seed: trip.coverSeed)
        }
    }
}

extension Trip {
    /// Kartların dinamik vurgu rengi: fotoğrafın baskın tonu, yoksa paletten bir kategori rengi.
    @MainActor
    var tint: Color {
        if let name = coverPhoto, let color = CoverImageStore.shared.dominantColor(named: name) {
            return color
        }
        return Accent.cycle(coverSeed).base
    }

    var countdownTag: (text: String, accent: Accent) {
        if status == .draft { return ("Taslak", .orange) }
        let countdown = Countdown.make(start: startDate, end: endDate)
        let accent: Accent = switch countdown {
        case .days, .today: .blue
        case .months: .purple
        case .ongoing: .green
        case .past: .gray
        }
        return (AppFormat.countdown(countdown), accent)
    }
}
