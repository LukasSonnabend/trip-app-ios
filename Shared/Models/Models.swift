import Foundation

// MARK: - Auth

struct LoginRequest: Codable {
    let email: String
    let password: String
}

struct SignupRequest: Codable {
    let email: String
    let password: String
    let name: String?
}

struct RefreshRequest: Codable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

struct LogoutRequest: Codable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
    }
}

// MARK: - Trips

struct TripSummary: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let createdAt: String
    let role: TripRole

    enum CodingKeys: String, CodingKey {
        case id, name, role
        case createdAt = "created_at"
    }
}

enum TripRole: String, Codable {
    case owner, member
}

struct TripDetail: Codable, Identifiable {
    let id: String
    let name: String
    let createdAt: String
    let members: [TripMember]

    enum CodingKeys: String, CodingKey {
        case id, name, members
        case createdAt = "created_at"
    }
}

struct TripMember: Codable, Identifiable {
    let userId: String
    let name: String?
    let email: String
    let role: TripRole
    let joinedAt: String

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name, email, role
        case joinedAt = "joined_at"
    }
}

struct CreateTripRequest: Codable {
    let name: String
}

struct CreateTripResponse: Codable, Identifiable {
    let id: String
    let name: String
    let createdAt: String
    let role: TripRole

    enum CodingKeys: String, CodingKey {
        case id, name, role
        case createdAt = "created_at"
    }
}

// MARK: - Invites

struct CreateInviteResponse: Codable, Identifiable {
    let code: String
    let tripId: String
    let createdAt: String

    var id: String { code }

    enum CodingKeys: String, CodingKey {
        case code
        case tripId = "trip_id"
        case createdAt = "created_at"
    }
}

struct InvitePreview: Codable {
    let tripId: String
    let tripName: String
    let memberCount: Int
    var alreadyAMember: Bool

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case tripName = "trip_name"
        case memberCount = "member_count"
        case alreadyAMember = "already_a_member"
    }
}

struct AcceptInviteResponse: Codable {
    let tripId: String
    let tripName: String
    let role: TripRole

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case tripName = "trip_name"
        case role
    }
}

// MARK: - Itinerary Items

enum ItemType: String, Codable, CaseIterable {
    case flight = "FLIGHT"
    case hotel = "HOTEL"
    case rentalCar = "RENTAL_CAR"
    case restaurant = "RESTAURANT"
    case train = "TRAIN"
    case event = "EVENT"
    case generic = "GENERIC"
    case unknown

    var displayName: String {
        switch self {
        case .flight: return "Flight"
        case .hotel: return "Hotel"
        case .rentalCar: return "Rental Car"
        case .restaurant: return "Restaurant"
        case .train: return "Train"
        case .event: return "Event"
        case .generic: return "Other"
        case .unknown: return "Unknown"
        }
    }

    var iconName: String {
        switch self {
        case .flight: return "airplane"
        case .hotel: return "bed.double"
        case .rentalCar: return "car"
        case .restaurant: return "fork.knife"
        case .train: return "tram"
        case .event: return "calendar"
        case .generic: return "mappin"
        case .unknown: return "questionmark"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = ItemType(rawValue: rawValue) ?? .unknown
    }
}

struct Location: Codable {
    let name: String?
    let address: String?
    let airportCode: String?
    let latitude: Double?
    let longitude: Double?

    enum CodingKeys: String, CodingKey {
        case name, address, latitude, longitude
        case airportCode = "airport_code"
    }
}

struct ItemDetails: Codable {
    let seat: String?
    let gate: String?
    let roomType: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case seat, gate, notes
        case roomType = "room_type"
    }
}

struct LegLocation: Codable {
    let name: String?
    let address: String?
    let airportCode: String?

    enum CodingKeys: String, CodingKey {
        case name, address
        case airportCode = "airport_code"
    }
}

struct Leg: Codable, Identifiable {
    var id: String { "\(departureAirportCode ?? "?")-\(arrivalAirportCode ?? "?")-\(startTime ?? "")" }

    let departureAirportCode: String?
    let arrivalAirportCode: String?
    let startTime: String?
    let endTime: String?
    let departureLocation: LegLocation
    let arrivalLocation: LegLocation
    let seat: String?

    enum CodingKeys: String, CodingKey {
        case seat
        case departureAirportCode = "departure_airport_code"
        case arrivalAirportCode = "arrival_airport_code"
        case startTime = "start_time"
        case endTime = "end_time"
        case departureLocation = "departure_location"
        case arrivalLocation = "arrival_location"
    }
}

struct ItineraryItem: Codable, Identifiable {
    let id: String
    let addedBy: String?
    let itemType: ItemType
    let title: String
    let provider: String?
    let confirmationCode: String?
    let travelerName: String?
    let price: String?
    let startTime: String?
    let endTime: String?
    let location: Location
    let endLocation: Location?
    let returnLocation: Location?
    let legs: [Leg]
    let confidence: String?
    let details: ItemDetails

    enum CodingKeys: String, CodingKey {
        case id, title, provider, location, details, price, legs, confidence
        case addedBy = "added_by"
        case itemType = "item_type"
        case confirmationCode = "confirmation_code"
        case travelerName = "traveler_name"
        case startTime = "start_time"
        case endTime = "end_time"
        case endLocation = "end_location"
        case returnLocation = "return_location"
    }
}

// MARK: - Item Coordinate Update

struct ItemCoordinateUpdate: Codable {
    let location: CoordinateData
    let endLocation: CoordinateData?

    struct CoordinateData: Codable {
        let latitude: Double
        let longitude: Double
    }

    enum CodingKeys: String, CodingKey {
        case location
        case endLocation = "end_location"
    }
}

// MARK: - Request Bodies

struct LocationBody: Encodable {
    let name: String?
    let address: String?
    let airportCode: String?
    let latitude: Double?
    let longitude: Double?

    enum CodingKeys: String, CodingKey {
        case name, address, latitude, longitude
        case airportCode = "airport_code"
    }
}

struct LocationUpdateBody: Encodable {
    let name: String?
    let address: String?
    let airportCode: String?
    let latitude: Double?
    let longitude: Double?

    enum CodingKeys: String, CodingKey {
        case name, address, latitude, longitude
        case airportCode = "airport_code"
    }
}

// MARK: - API Error

struct APIErrorResponse: Codable {
    let detail: String?
}

// MARK: - Travelers

struct Traveler: Codable, Identifiable, Hashable {
    let id: String
    let tripId: String
    let name: String
    let userId: String?
    let color: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, color
        case tripId = "trip_id"
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

struct CreateTravelerRequest: Codable {
    let name: String
    let userId: String?
    let color: String?

    enum CodingKeys: String, CodingKey {
        case name, color
        case userId = "user_id"
    }
}

struct UpdateTravelerRequest: Codable {
    let name: String?
    let color: String?

    enum CodingKeys: String, CodingKey {
        case name, color
    }
}

// MARK: - Expense Splits

struct ExpenseSplit: Codable {
    let splitType: String
    let assignedTravelerId: String?
    let shares: [ExpenseShare]

    enum CodingKeys: String, CodingKey {
        case splitType = "split_type"
        case assignedTravelerId = "assigned_traveler_id"
        case shares
    }
}

struct ExpenseShare: Codable, Identifiable {
    let id: String
    let travelerId: String
    let travelerName: String
    let isPaid: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case travelerId = "traveler_id"
        case travelerName = "traveler_name"
        case isPaid = "is_paid"
    }
}

struct UpsertSplitRequest: Codable {
    let splitType: String
    let assignedTravelerId: String?
    let travelerIds: [String]?

    enum CodingKeys: String, CodingKey {
        case splitType = "split_type"
        case assignedTravelerId = "assigned_traveler_id"
        case travelerIds = "traveler_ids"
    }
}

// MARK: - Budget

struct BudgetResponse: Codable {
    let total: String
    let unsplitTotal: String
    let perTraveler: [TravelerBudget]

    enum CodingKeys: String, CodingKey {
        case total
        case unsplitTotal = "unsplit_total"
        case perTraveler = "per_traveler"
    }
}

struct TravelerBudget: Codable, Identifiable {
    var id: String { travelerId }
    let travelerId: String
    let travelerName: String
    let color: String?
    let total: String
    let paid: String
    let unpaid: String
    let itemCount: Int
    let items: [BudgetItem]

    enum CodingKeys: String, CodingKey {
        case travelerId = "traveler_id"
        case travelerName = "traveler_name"
        case color, total, paid, unpaid, items
        case itemCount = "item_count"
    }
}

struct BudgetItem: Codable, Identifiable {
    var id: String { itemId }
    let itemId: String
    let itemTitle: String
    let itemType: String
    let price: String?
    let shareAmount: String
    let isPaid: Bool
    let shareId: String

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case itemTitle = "item_title"
        case itemType = "item_type"
        case price
        case shareAmount = "share_amount"
        case isPaid = "is_paid"
        case shareId = "share_id"
    }
}
