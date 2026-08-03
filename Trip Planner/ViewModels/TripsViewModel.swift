import Combine
import Foundation

@MainActor
final class TripsViewModel: ObservableObject {
    @Published var trips: [TripSummary] = []
    @Published var tripDetail: TripDetail?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var inviteCode: CreateInviteResponse?

    private let client = APIClient.shared

    func loadTrips() async {
        isLoading = true
        errorMessage = nil
        do {
            trips = try await client.request("GET", "trips")
        } catch {
            if error.isCancellationError { return }
            if case APIError.unauthenticated = error { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func createTrip(name: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let response: CreateTripResponse = try await client.request(
                "POST", "trips",
                body: CreateTripRequest(name: name)
            )
            await loadTrips()
            _ = response
        } catch {
            if error.isCancellationError { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadTrip(id: String) async {
        isLoading = true
        errorMessage = nil
        tripDetail = nil
        do {
            tripDetail = try await client.request("GET", "trips/\(id)")
        } catch {
            if error.isCancellationError { return }
            if case APIError.notFound = error {
                errorMessage = "You don't have access to this trip."
            } else {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    func createInvite(tripId: String) async {
        isLoading = true
        errorMessage = nil
        do {
            inviteCode = try await client.request("POST", "trips/\(tripId)/invites")
        } catch {
            if error.isCancellationError { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func revokeInvite(tripId: String, code: String) async {
        do {
            try await client.requestVoid("DELETE", "trips/\(tripId)/invites/\(code)")
        } catch {
            if error.isCancellationError { return }
            errorMessage = error.localizedDescription
        }
    }
}
