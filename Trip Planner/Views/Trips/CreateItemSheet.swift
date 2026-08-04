import SwiftUI

struct CreateItemSheet: View {
    let tripId: String
    let onCreate: (ItineraryItem) -> Void
    let onClose: () -> Void

    @State private var itemType: ItemType = .flight
    @State private var title = ""
    @State private var provider = ""
    @State private var confirmationCode = ""
    @State private var travelerName = ""
    @State private var price = ""
    @State private var startTime = ""
    @State private var endTime = ""
    @State private var locationName = ""
    @State private var locationAddress = ""
    @State private var airportCode = ""
    @State private var seat = ""
    @State private var gate = ""
    @State private var roomType = ""
    @State private var notes = ""

    @State private var isSaving = false
    @State private var errorMessage: String?

    private let client = APIClient.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Item Type", selection: $itemType) {
                        ForEach(ItemType.allCases.filter { $0 != .unknown }, id: \.self) { type in
                            Label(type.displayName, systemImage: type.iconName)
                                .tag(type)
                        }
                    }
                }

                Section("Basic Info") {
                    TextField("Title", text: $title)
                    TextField("Provider", text: $provider)
                    TextField("Confirmation Code", text: $confirmationCode)
                }

                Section("Traveler & Price") {
                    TextField("Traveler Name", text: $travelerName)
                    TextField("Price", text: $price)
                }

                Section("Time") {
                    TextField("Start Time (YYYY-MM-DDTHH:MM:SS)", text: $startTime)
                    TextField("End Time (YYYY-MM-DDTHH:MM:SS)", text: $endTime)
                }

                Section("Location") {
                    TextField("Name", text: $locationName)
                    TextField("Address", text: $locationAddress)
                    TextField("Airport Code", text: $airportCode)
                }

                Section("Details") {
                    TextField("Seat", text: $seat)
                    TextField("Gate", text: $gate)
                    TextField("Room Type", text: $roomType)
                    TextField("Notes", text: $notes)
                }
            }
            .navigationTitle("New Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await save() }
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .overlay {
                if isSaving { ProgressView() }
            }
            .alert("Error", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let body = CreateItemBody(
            itemType: itemType,
            title: title.trimmingCharacters(in: .whitespaces),
            provider: nilOrEmpty(provider),
            confirmationCode: nilOrEmpty(confirmationCode),
            travelerName: nilOrEmpty(travelerName),
            price: nilOrEmpty(price),
            startTime: nilOrEmpty(startTime),
            endTime: nilOrEmpty(endTime),
            location: LocationBody(
                name: nilOrEmpty(locationName),
                address: nilOrEmpty(locationAddress),
                airportCode: nilOrEmpty(airportCode),
                latitude: nil,
                longitude: nil
            ),
            endLocation: nil,
            details: DetailsBody(
                seat: nilOrEmpty(seat),
                gate: nilOrEmpty(gate),
                roomType: nilOrEmpty(roomType),
                notes: nilOrEmpty(notes)
            )
        )

        do {
            let item: ItineraryItem = try await client.request("POST", "trips/\(tripId)/items", body: body)
            onCreate(item)
            onClose()
        } catch {
            if error.isCancellationError { return }
            errorMessage = error.localizedDescription
        }
    }

    private func nilOrEmpty(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct CreateItemBody: Encodable {
    let itemType: ItemType
    let title: String
    let provider: String?
    let confirmationCode: String?
    let travelerName: String?
    let price: String?
    let startTime: String?
    let endTime: String?
    let location: LocationBody
    let endLocation: LocationBody?
    let details: DetailsBody

    enum CodingKeys: String, CodingKey {
        case title, provider, price, location, details
        case itemType = "item_type"
        case confirmationCode = "confirmation_code"
        case travelerName = "traveler_name"
        case startTime = "start_time"
        case endTime = "end_time"
        case endLocation = "end_location"
    }
}

struct DetailsBody: Encodable {
    let seat: String?
    let gate: String?
    let roomType: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case seat, gate, notes
        case roomType = "room_type"
    }
}
