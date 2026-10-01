import Observation
import TravellerKit

/// Bildirimden, widget'tan ya da canlı karttan gelen "şu seyahatin şu sekmesini aç" isteği.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    /// Ana ekran işleyene kadar bekleyen bağlantı.
    var pending: TripLink?

    func open(_ link: TripLink) {
        pending = link
    }
}

extension TripDetailView.TripSection {
    init(link: TripLink) {
        self = link.section.flatMap(Self.init(rawValue:)) ?? .plan
    }
}
