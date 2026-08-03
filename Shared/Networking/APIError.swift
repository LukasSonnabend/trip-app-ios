import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case forbidden
    case notFound
    case serverError(Int)
    case decodingError(Error)
    case networkError(Error)
    case unauthenticated
    case message(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response from server"
        case .unauthorized: return "Session expired. Please log in again."
        case .forbidden: return "You don't have permission to do that."
        case .notFound: return "Not found."
        case .serverError(let code): return "Server error (\(code))"
        case .decodingError(let error): return "Data error: \(error.localizedDescription)"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .unauthenticated: return "Please log in to continue."
        case .message(let msg): return msg
        }
    }
}
