import Combine
import Foundation

@MainActor
final class BudgetViewModel: ObservableObject {
    @Published var budget: BudgetResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let client = APIClient.shared

    func loadBudget(tripId: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            budget = try await client.getBudget(tripId: tripId)
        } catch {
            if error.isCancellationError { return }
            if case APIError.unauthenticated = error { return }
            errorMessage = error.localizedDescription
        }
    }
}
