import Foundation

enum Environment {
    static let baseURL: URL = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
              let url = URL(string: raw) else {
            fatalError("API_BASE_URL not set in Info.plist. Check build settings.")
        }
        return url
    }()

    static let appGroupIdentifier = "group.ch.gograb.Trip-Planner"
    static let keychainAccessGroup = "JX6UQ959C6.ch.gograb.Trip-Planner"
}
