import Combine
import Foundation
import SwiftUI

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var name = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isAuthenticated: Bool

    private let client = APIClient.shared

    init() {
        isAuthenticated = KeychainManager.shared.accessToken != nil
    }

    func login() async {
        isLoading = true
        errorMessage = nil
        do {
            let response: AuthResponse = try await client.request(
                "POST", "auth/login",
                body: LoginRequest(email: email, password: password),
                authenticated: false
            )
            KeychainManager.shared.accessToken = response.accessToken
            KeychainManager.shared.refreshToken = response.refreshToken
            isAuthenticated = true
        } catch {
            if error.isCancellationError { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func signup() async {
        isLoading = true
        errorMessage = nil
        do {
            let response: AuthResponse = try await client.request(
                "POST", "auth/signup",
                body: SignupRequest(email: email, password: password, name: name.isEmpty ? nil : name),
                authenticated: false
            )
            KeychainManager.shared.accessToken = response.accessToken
            KeychainManager.shared.refreshToken = response.refreshToken
            isAuthenticated = true
        } catch {
            if error.isCancellationError { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func logout() async {
        if let token = KeychainManager.shared.refreshToken {
            try? await client.requestVoid("POST", "auth/logout", body: LogoutRequest(refreshToken: token))
        }
        KeychainManager.shared.deleteAll()
        isAuthenticated = false
    }

    func checkAuth() {
        isAuthenticated = KeychainManager.shared.accessToken != nil
    }
}
