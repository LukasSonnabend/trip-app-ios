import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var inviteCode: String?
    @State private var showInvite = false

    var body: some View {
        Group {
            if authVM.isAuthenticated {
                TripListView()
                    .sheet(isPresented: $showInvite) {
                        if let code = inviteCode {
                            InvitePreviewView(code: code)
                        }
                    }
            } else {
                LoginView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openInvite)) { notification in
            if let code = notification.userInfo?["code"] as? String {
                inviteCode = code
                showInvite = true
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
