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
        defer { isLoading = false }
        do {
            items = try await client.request("GET", "trips/\(tripId)/items")
        } catch {
            if error.isCancellationError { return }
            errorMessage = error.localizedDescription
        }
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

    func updateItem(tripId: String, item: ItineraryItem) async {
        do {
            let body = ItemUpdateBody(
                title: item.title,
                provider: item.provider,
                confirmationCode: item.confirmationCode,
                travelerName: item.travelerName,
                price: item.price,
                startTime: item.startTime,
                endTime: item.endTime,
                location: LocationUpdateBody(
                    name: item.location.name,
                    address: item.location.address,
                    airportCode: item.location.airportCode
                ),
                details: DetailsUpdateBody(
                    seat: item.details.seat,
                    gate: item.details.gate,
                    roomType: item.details.roomType,
                    notes: item.details.notes
                )
            )
            let updated: ItineraryItem = try await client.request(
                "PATCH",
                "trips/\(tripId)/items/\(item.id)",
                body: body
            )
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index] = updated
            }
        } catch {
            if error.isCancellationError { return }
            errorMessage = error.localizedDescription
        }
    }

    func splitPrice(tripId: String, originItem: ItineraryItem) async {
        guard let priceStr = originItem.price else { return }

        let numeric = priceStr
            .replacingOccurrences(of: ",", with: "")
            .filter { $0.isNumber || $0 == "." }
        guard let total = Double(numeric), total > 0 else { return }

        let currencyPrefix = String(priceStr.prefix { !$0.isNumber && $0 != " " && $0 != "," })

        let siblings: [ItineraryItem]
        if let code = originItem.confirmationCode {
            siblings = items.filter { $0.confirmationCode == code }
        } else {
            siblings = items
        }
        guard !siblings.isEmpty else { return }

        let share = total / Double(siblings.count)
        let newPrice = currencyPrefix + String(format: "%.2f", share)

        for sibling in siblings {
            do {
                let body = ItemUpdateBody(price: newPrice)
                let updated: ItineraryItem = try await client.request(
                    "PATCH", "trips/\(tripId)/items/\(sibling.id)", body: body
                )
                if let index = items.firstIndex(where: { $0.id == sibling.id }) {
                    items[index] = updated
                }
            } catch {
                if error.isCancellationError { return }
                errorMessage = error.localizedDescription
                return
            }
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
