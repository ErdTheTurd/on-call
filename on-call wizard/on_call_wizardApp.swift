import SwiftUI

@main
struct on_call_wizardApp: App {
    @AppStorage(ThemeManager.storageKey) private var themeRaw: String = ThemeManager.Theme.system.rawValue
    @StateObject private var deepLinks = DeepLinkRouter.shared

    init() {
        Task { @MainActor in
            await NotificationService.shared.requestAuthorization()
            DataSyncCoordinator.shared.startPeriodicSync()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .appColorScheme()
                .id(themeRaw)
                .environmentObject(deepLinks)
                .onOpenURL { url in
                    deepLinks.handle(url)
                }
        }
    }
}
