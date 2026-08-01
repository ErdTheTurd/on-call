import SwiftUI

@main
struct on_call_wizardApp: App {
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
                .environmentObject(deepLinks)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    deepLinks.handle(url)
                }
        }
    }
}
