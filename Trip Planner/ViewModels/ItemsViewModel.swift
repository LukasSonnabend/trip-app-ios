import Combine
import Foundation

@MainActor
final class ItemsViewModel: ObservableObject {
    @Published var items: [ItineraryItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let client = APIClient.shared
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func loadItems(tripId: String) async {
        let key = cacheKey(for: tripId)

        if let cached = loadCachedItems(key: key) {
            items = sortItems(cached)
        }

        if items.isEmpty {
            isLoading = true
        }
        errorMessage = nil
        defer { isLoading = false }

        do {
            let fetched: [ItineraryItem] = try await client.request("GET", "trips/\(tripId)/items")
            items = sortItems(fetched)
            saveCachedItems(fetched, key: key)
        } catch {
            if error.isCancellationError { return }
            if items.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    func deleteItem(tripId: String, itemId: String) async {
        let removed = items.first { $0.id == itemId }
        items.removeAll { $0.id == itemId }
        saveCurrentItems(tripId: tripId)

        do {
            try await client.requestVoid("DELETE", "trips/\(tripId)/items/\(itemId)")
        } catch {
            if error.isCancellationError { return }
            if let removed {
                items.append(removed)
                saveCurrentItems(tripId: tripId)
            }
            errorMessage = error.localizedDescription
        }
    }

    func deleteItems(tripId: String, itemIds: Set<String>) async {
        let removed = items.filter { itemIds.contains($0.id) }
        items.removeAll { itemIds.contains($0.id) }
        saveCurrentItems(tripId: tripId)
        errorMessage = nil

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for id in itemIds {
                    group.addTask {
                        try await self.client.requestVoid("DELETE", "trips/\(tripId)/items/\(id)")
                    }
                }
            }
        } catch {
            if error.isCancellationError { return }
            for r in removed {
                items.append(r)
            }
            saveCurrentItems(tripId: tripId)
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
                    airportCode: item.location.airportCode,
                    latitude: item.location.latitude,
                    longitude: item.location.longitude
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
                saveCurrentItems(tripId: tripId)
            }
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

    // MARK: - Cache

    private func cacheKey(for tripId: String) -> String {
        "cached_items_\(tripId)"
    }

    private func loadCachedItems(key: String) -> [ItineraryItem]? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? decoder.decode([ItineraryItem].self, from: data)
    }

    private func saveCachedItems(_ items: [ItineraryItem], key: String) {
        if let data = try? encoder.encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func saveCurrentItems(tripId: String) {
        saveCachedItems(items, key: cacheKey(for: tripId))
    }

    func sortItems(_ unsorted: [ItineraryItem]) -> [ItineraryItem] {
        unsorted.sorted { a, b in
            let dateA = (a.startTime ?? a.endTime).flatMap(FlexibleDateFormatter.parseLocal(_:))
            let dateB = (b.startTime ?? b.endTime).flatMap(FlexibleDateFormatter.parseLocal(_:))
            switch (dateA, dateB) {
            case (let da?, let db?): return da < db
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    }
}
