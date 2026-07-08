import SwiftUI

@main
struct GoalCraftApp: App {
    @StateObject private var store = GoalStore()
    @StateObject private var auth = AuthManager()

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isAuthenticated {
                    DashboardView()
                        .environmentObject(store)
                } else {
                    LoginView()
                }
            }
            .environmentObject(auth)
            .preferredColorScheme(.dark)
        }
    }
}
