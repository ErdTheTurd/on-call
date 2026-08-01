import SwiftUI

@main
struct on_call_wizardApp: App {
    init() {
        Task { @MainActor in
            await NotificationService.shared.requestAuthorization()
            DataSyncCoordinator.shared.startPeriodicSync()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
