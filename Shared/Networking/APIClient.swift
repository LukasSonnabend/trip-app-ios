import Foundation

actor TokenRefreshActor {
    private var refreshTask: Task<(String, String), Error>?

    func refresh(using closure: @escaping () async throws -> (String, String)) async throws -> (String, String) {
        if let existing = refreshTask {
            return try await existing.value
        }
        let task = Task { try await closure() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }
}

final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let refreshActor = TokenRefreshActor()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    private var baseURL: URL { Environment.baseURL }

    // MARK: - Public methods

    func request<T: Decodable>(
        _ method: String,
        _ path: String,
        body: (any Encodable)? = nil,
        queryItems: [URLQueryItem]? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        let data = try await performRequest(
            method: method,
            path: path,
            body: body,
            queryItems: queryItems,
            authenticated: authenticated
        )
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func requestVoid(
        _ method: String,
        _ path: String,
        body: (any Encodable)? = nil,
        queryItems: [URLQueryItem]? = nil,
        authenticated: Bool = true
    ) async throws {
        _ = try await performRequest(
            method: method,
            path: path,
            body: body,
            queryItems: queryItems,
            authenticated: authenticated
        )
    }

    func uploadMultipart<T: Decodable>(
        _ path: String,
        textContent: String? = nil,
        url: String? = nil,
        fileData: Data? = nil,
        fileName: String? = nil,
        mimeType: String? = nil
    ) async throws -> T {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        if let text = textContent {
            appendFormField(&body, name: "content", value: text, boundary: boundary)
        }
        if let urlStr = url {
            appendFormField(&body, name: "url", value: urlStr, boundary: boundary)
        }
        if let fileData = fileData, let fileName = fileName, let mimeType = mimeType {
            appendFileData(&body, data: fileData, name: "file", fileName: fileName, mimeType: mimeType, boundary: boundary)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let urlRequest = try buildRequest(
            method: "POST",
            path: path,
            contentType: "multipart/form-data; boundary=\(boundary)",
            authenticated: true
        )

        let data = try await executeWithAuth(request: urlRequest, body: body)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Core

    private func performRequest(
        method: String,
        path: String,
        body: (any Encodable)?,
        queryItems: [URLQueryItem]?,
        authenticated: Bool
    ) async throws -> Data {
        let request = try buildRequest(
            method: method,
            path: path,
            queryItems: queryItems,
            body: body,
            authenticated: authenticated
        )
        let httpBody: Data? = if let body { try encoder.encode(AnyEncodable(body)) } else { nil }
        return try await executeWithAuth(request: request, body: httpBody)
    }

    private func buildRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: (any Encodable)? = nil,
        contentType: String = "application/json",
        authenticated: Bool = true
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true) else {
            throw APIError.invalidURL
        }
        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        if authenticated {
            guard let token = KeychainManager.shared.accessToken else {
                throw APIError.unauthenticated
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func executeWithAuth(request: URLRequest, body: Data? = nil) async throws -> Data {
        var req = request
        req.httpBody = body

        let (data, response) = try await session.data(for: req)
        return try await handleResponse(data: data, response: response, originalRequest: req, originalBody: body)
    }

    private func handleResponse(
        data: Data,
        response: URLResponse,
        originalRequest: URLRequest,
        originalBody: Data?
    ) async throws -> Data {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 401:
            return try await handleUnauthorized(
                originalRequest: originalRequest,
                originalBody: originalBody
            )
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 422:
            if let errorBody = try? decoder.decode(APIErrorResponse.self, from: data),
               let detail = errorBody.detail {
                throw APIError.message(detail)
            }
            throw APIError.serverError(422)
        case 500...599:
            throw APIError.serverError(httpResponse.statusCode)
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    private func handleUnauthorized(
        originalRequest: URLRequest,
        originalBody: Data?
    ) async throws -> Data {
        let (newAccess, _) = try await refreshActor.refresh {
            guard let currentRefresh = KeychainManager.shared.refreshToken else {
                throw APIError.unauthenticated
            }
            let response: AuthResponse = try await self.makeUnauthenticatedRequest(
                "POST",
                "auth/refresh",
                body: RefreshRequest(refreshToken: currentRefresh)
            )
            KeychainManager.shared.accessToken = response.accessToken
            KeychainManager.shared.refreshToken = response.refreshToken
            return (response.accessToken, response.refreshToken)
        }

        var retryRequest = originalRequest
        retryRequest.setValue("Bearer \(newAccess)", forHTTPHeaderField: "Authorization")
        retryRequest.httpBody = originalBody

        let (data, response) = try await session.data(for: retryRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            KeychainManager.shared.deleteAll()
            throw APIError.unauthenticated
        }

        if (200...299).contains(httpResponse.statusCode) {
            return data
        }
        throw APIError.serverError(httpResponse.statusCode)
    }

    private func makeUnauthenticatedRequest<T: Decodable>(
        _ method: String,
        _ path: String,
        body: (any Encodable)?
    ) async throws -> T {
        let request = try buildRequest(method: method, path: path, body: body, authenticated: false)
        var req = request
        req.httpBody = try encoder.encode(AnyEncodable(body as Any))
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Multipart helpers

    private func appendFormField(_ data: inout Data, name: String, value: String, boundary: String) {
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        data.append("\(value)\r\n".data(using: .utf8)!)
    }

    private func appendFileData(_ data: inout Data, data fileData: Data, name: String, fileName: String, mimeType: String, boundary: String) {
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        data.append(fileData)
        data.append("\r\n".data(using: .utf8)!)
    }

    // MARK: - Travelers

    func listTravelers(tripId: String) async throws -> [Traveler] {
        try await request("GET", "trips/\(tripId)/travelers")
    }

    func createTraveler(tripId: String, name: String, userId: String? = nil, color: String? = nil) async throws -> Traveler {
        try await request("POST", "trips/\(tripId)/travelers", body: CreateTravelerRequest(name: name, userId: userId, color: color))
    }

    func updateTraveler(tripId: String, travelerId: String, name: String? = nil, color: String? = nil) async throws -> Traveler {
        try await request("PATCH", "trips/\(tripId)/travelers/\(travelerId)", body: UpdateTravelerRequest(name: name, color: color))
    }

    func deleteTraveler(tripId: String, travelerId: String) async throws {
        try await requestVoid("DELETE", "trips/\(tripId)/travelers/\(travelerId)")
    }

    // MARK: - Expense Splits

    func getSplit(tripId: String, itemId: String) async throws -> ExpenseSplit {
        try await request("GET", "trips/\(tripId)/items/\(itemId)/split")
    }

    func upsertSplit(tripId: String, itemId: String, splitType: String, assignedTravelerId: String?, travelerIds: [String]?) async throws -> ExpenseSplit {
        try await request("PUT", "trips/\(tripId)/items/\(itemId)/split", body: UpsertSplitRequest(splitType: splitType, assignedTravelerId: assignedTravelerId, travelerIds: travelerIds))
    }

    func deleteSplit(tripId: String, itemId: String) async throws {
        try await requestVoid("DELETE", "trips/\(tripId)/items/\(itemId)/split")
    }

    func toggleSharePaid(tripId: String, itemId: String, shareId: String, isPaid: Bool) async throws -> ExpenseShare {
        struct TogglePaidBody: Codable {
            let isPaid: Bool
            enum CodingKeys: String, CodingKey { case isPaid = "is_paid" }
        }
        return try await request("PATCH", "trips/\(tripId)/items/\(itemId)/split/shares/\(shareId)", body: TogglePaidBody(isPaid: isPaid))
    }

    // MARK: - Budget

    func getBudget(tripId: String) async throws -> BudgetResponse {
        try await request("GET", "trips/\(tripId)/budget")
    }
}

struct AnyEncodable: Encodable {
    let value: Any
    init(_ value: Any) { self.value = value }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let encodable = value as? Encodable {
            try encodable.encode(to: encoder)
        } else {
            try container.encodeNil()
        }
    }
}
