import Combine
import Foundation

@MainActor
final class ItemsViewModel: ObservableObject {
    @Published var items: [ItineraryItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let client = APIClient.shared

    func loadItems(tripId: String) async {
        isLoading = true
        errorMessage = nil
        do {
            items = try await client.request("GET", "trips/\(tripId)/items")
        } catch {
            if error.isCancellationError { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func deleteItem(tripId: String, itemId: String) async {
        do {
            try await client.requestVoid("DELETE", "trips/\(tripId)/items/\(itemId)")
            await loadItems(tripId: tripId)
        } catch {
            if error.isCancellationError { return }
            errorMessage = error.localizedDescription
        }
    }

    func extract(
        tripId: String,
        content: String?,
        url: String?,
        fileData: Data?,
        fileName: String?,
        mimeType: String?
    ) async -> [ItineraryItem] {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result: [ItineraryItem] = try await client.uploadMultipart(
                "trips/\(tripId)/items/extract",
                textContent: content,
                url: url,
                fileData: fileData,
                fileName: fileName,
                mimeType: mimeType
            )
            return result
        } catch {
            if error.isCancellationError { return [] }
            errorMessage = error.localizedDescription
            return []
        }
    }
}
