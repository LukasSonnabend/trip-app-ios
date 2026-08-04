import Combine
import Foundation

@MainActor
final class TravelersViewModel: ObservableObject {
    @Published var travelers: [Traveler] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let client = APIClient.shared

    func loadTravelers(tripId: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            travelers = try await client.listTravelers(tripId: tripId)
        } catch {
            if error.isCancellationError { return }
            if case APIError.unauthenticated = error { return }
            errorMessage = error.localizedDescription
        }
    }

    func addTraveler(tripId: String, name: String, color: String? = nil) async {
        do {
            let traveler = try await client.createTraveler(tripId: tripId, name: name, color: color)
            travelers.append(traveler)
        } catch {
            if error.isCancellationError { return }
            errorMessage = error.localizedDescription
        }
    }

    func updateTraveler(tripId: String, travelerId: String, name: String? = nil, color: String? = nil) async {
        do {
            let updated = try await client.updateTraveler(tripId: tripId, travelerId: travelerId, name: name, color: color)
            if let index = travelers.firstIndex(where: { $0.id == travelerId }) {
                travelers[index] = updated
            }
        } catch {
            if error.isCancellationError { return }
            errorMessage = error.localizedDescription
        }
    }

    func deleteTraveler(tripId: String, travelerId: String) async {
        let backup = travelers
        travelers.removeAll { $0.id == travelerId }
        do {
            try await client.deleteTraveler(tripId: tripId, travelerId: travelerId)
        } catch {
            if error.isCancellationError {
                travelers = backup
                return
            }
            travelers = backup
            errorMessage = error.localizedDescription
        }
    }
}
