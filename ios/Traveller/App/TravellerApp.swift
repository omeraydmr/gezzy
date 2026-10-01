import CloudKit
import SwiftUI
import UIKit
import UserNotifications

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
                    LiveActivityController.refresh(trips: store.trips)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await CloudSync.shared.refresh() }
                LiveActivityController.refresh(trips: store.trips)
            }
        }
    }
}

/// iCloud davet bağlantısının uygulamada açılabilmesi için sahne temsilcisi gerekir.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // CloudKit sessiz bildirimleri için (kullanıcıdan izin gerektirmez).
        application.registerForRemoteNotifications()
        return true
    }

    /// Başka bir cihazda yapılan değişiklik: CloudKit sessiz bildirimi.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else { return .noData }
        return await CloudSync.shared.handleRemoteNotification() ? .newData : .noData
    }

    /// Uygulama açıkken de bildirimleri göster.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

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
