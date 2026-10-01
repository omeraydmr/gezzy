import CloudKit
import SwiftUI
import UIKit

@main
struct TravellerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = TripStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TripsView()
                .environment(store)
                .environment(\.locale, AppFormat.locale)
                .tint(Color.ink)
                .task {
                    await CloudSync.shared.start(with: store)
                    NotificationScheduler.shared.tripsChanged(store.trips)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await CloudSync.shared.refresh() }
            }
        }
    }
}

/// iCloud davet bağlantısının uygulamada açılabilmesi için sahne temsilcisi gerekir.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in
            await CloudSync.shared.accept(cloudKitShareMetadata)
        }
    }
}
