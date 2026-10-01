import SwiftUI

@main
struct TravellerApp: App {
    @State private var store = TripStore()

    var body: some Scene {
        WindowGroup {
            TripsView()
                .environment(store)
                .environment(\.locale, AppFormat.locale)
                .tint(Color.ink)
        }
    }
}
