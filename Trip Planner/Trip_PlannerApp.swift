import SwiftUI

@main
struct Trip_PlannerApp: App {
    @StateObject private var authVM = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authVM)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let host = components.host else { return }

        if host == "join" || host == "invite" {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !path.isEmpty {
                NotificationCenter.default.post(
                    name: .openInvite,
                    object: nil,
                    userInfo: ["code": path]
                )
            }
        }
    }
}

extension Notification.Name {
    static let openInvite = Notification.Name("openInvite")
}
