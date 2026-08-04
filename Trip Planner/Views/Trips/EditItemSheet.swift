import SwiftUI

struct EditItemSheet: View {
    let item: ItineraryItem
    let tripId: String
    let onUpdate: (ItineraryItem) -> Void
    let onClose: () -> Void

    @State private var title: String
    @State private var provider: String
    @State private var confirmationCode: String
    @State private var travelerName: String
    @State private var price: String
    @State private var startTime: String
    @State private var endTime: String
    @State private var locationName: String
    @State private var locationAddress: String
    @State private var airportCode: String
    @State private var seat: String
    @State private var gate: String
    @State private var roomType: String
    @State private var notes: String

    @State private var isSaving = false
    @State private var errorMessage: String?

    private let client = APIClient.shared

    init(item: ItineraryItem, tripId: String, onUpdate: @escaping (ItineraryItem) -> Void, onClose: @escaping () -> Void) {
        self.item = item
        self.tripId = tripId
        self.onUpdate = onUpdate
        self.onClose = onClose
        _title = State(initialValue: item.title)
        _provider = State(initialValue: item.provider ?? "")
        _confirmationCode = State(initialValue: item.confirmationCode ?? "")
        _travelerName = State(initialValue: item.travelerName ?? "")
        _price = State(initialValue: item.price ?? "")
        _startTime = State(initialValue: item.startTime ?? "")
        _endTime = State(initialValue: item.endTime ?? "")
        _locationName = State(initialValue: item.location.name ?? "")
        _locationAddress = State(initialValue: item.location.address ?? "")
        _airportCode = State(initialValue: item.location.airportCode ?? "")
        _seat = State(initialValue: item.details.seat ?? "")
        _gate = State(initialValue: item.details.gate ?? "")
        _roomType = State(initialValue: item.details.roomType ?? "")
        _notes = State(initialValue: item.details.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Info") {
                    TextField("Title", text: $title)
                    TextField("Provider", text: $provider)
                    TextField("Confirmation Code", text: $confirmationCode)
                }

                Section("Traveler & Price") {
                    TextField("Traveler Name", text: $travelerName)
                    TextField("Price", text: $price)
                        .keyboardType(.default)
                }

                Section("Time") {
                    TextField("Start Time", text: $startTime)
                        .keyboardType(.default)
                    TextField("End Time", text: $endTime)
                        .keyboardType(.default)
                }

                Section("Location") {
                    TextField("Name", text: $locationName)
                    TextField("Address", text: $locationAddress)
                    TextField("Airport Code", text: $airportCode)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }

                Section("Details") {
                    TextField("Seat", text: $seat)
                    TextField("Gate", text: $gate)
                    TextField("Room Type", text: $roomType)
                    TextField("Notes", text: $notes)
                }
            }
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView()
                }
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
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

        let body = ItemUpdateBody(
            title: nilOrValue(title),
            provider: nilOrValue(provider),
            confirmationCode: nilOrValue(confirmationCode),
            travelerName: nilOrValue(travelerName),
            price: nilOrValue(price),
            startTime: nilOrValue(startTime),
            endTime: nilOrValue(endTime),
            location: LocationUpdateBody(
                name: nilOrValue(locationName),
                address: nilOrValue(locationAddress),
                airportCode: nilOrValue(airportCode)
            ),
            details: DetailsUpdateBody(
                seat: nilOrValue(seat),
                gate: nilOrValue(gate),
                roomType: nilOrValue(roomType),
                notes: nilOrValue(notes)
            )
        )

        do {
            let updated: ItineraryItem = try await client.request("PATCH", "trips/\(tripId)/items/\(item.id)", body: body)
            onUpdate(updated)
            onClose()
        } catch {
            if error.isCancellationError { return }
            errorMessage = error.localizedDescription
        }
    }

    private func nilOrValue(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct ItemUpdateBody: Encodable {
    var title: String? = nil
    var provider: String? = nil
    var confirmationCode: String? = nil
    var travelerName: String? = nil
    var price: String? = nil
    var startTime: String? = nil
    var endTime: String? = nil
    var location: LocationUpdateBody? = nil
    var endLocation: LocationUpdateBody? = nil
    var details: DetailsUpdateBody? = nil

    enum CodingKeys: String, CodingKey {
        case title, provider, price
        case confirmationCode = "confirmation_code"
        case travelerName = "traveler_name"
        case startTime = "start_time"
        case endTime = "end_time"
        case location
        case endLocation = "end_location"
        case details
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(provider, forKey: .provider)
        try container.encodeIfPresent(confirmationCode, forKey: .confirmationCode)
        try container.encodeIfPresent(travelerName, forKey: .travelerName)
        try container.encodeIfPresent(price, forKey: .price)
        try container.encodeIfPresent(startTime, forKey: .startTime)
        try container.encodeIfPresent(endTime, forKey: .endTime)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(endLocation, forKey: .endLocation)
        try container.encodeIfPresent(details, forKey: .details)
    }
}

struct LocationUpdateBody: Encodable {
    let name: String?
    let address: String?
    let airportCode: String?

    enum CodingKeys: String, CodingKey {
        case name, address
        case airportCode = "airport_code"
    }
}

struct DetailsUpdateBody: Encodable {
    let seat: String?
    let gate: String?
    let roomType: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case seat, gate, notes
        case roomType = "room_type"
    }
}
