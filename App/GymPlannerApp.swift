import SwiftUI

@main
struct GymPlannerApp: App {
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            WebScreen()
                .ignoresSafeArea()
                .background(Color("LaunchBackground").ignoresSafeArea())
                .onChange(of: phase) { value in
                    // Write the safety copy of the page's data before the app can be suspended.
                    if value != .active { SavedData.shared.flush() }
                }
        }
    }
}
