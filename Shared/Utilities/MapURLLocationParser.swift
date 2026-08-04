import Foundation
import UniformTypeIdentifiers

struct ParsedMapLocation {
    let name: String?
    let address: String?
    let latitude: Double?
    let longitude: Double?
}

enum MapURLLocationParser {

    static func parse(_ url: URL) -> ParsedMapLocation? {
        if isAppleMapsURL(url) {
            return parseAppleMaps(url)
        }
        if isGoogleMapsURL(url) {
            return parseGoogleMaps(url)
        }
        return nil
    }

    static func parseResolving(_ url: URL) async -> ParsedMapLocation? {
        if let local = parse(url) { return local }
        if isGoogleMapsShortURL(url) {
            guard let resolved = await resolveGoogleMapsShort(url) else { return nil }
            return parse(resolved)
        }
        return nil
    }

    static func isMapsURL(_ url: URL) -> Bool {
        isAppleMapsURL(url) || isGoogleMapsURL(url) || isGoogleMapsShortURL(url)
    }

    // MARK: - Apple Maps

    private static func isAppleMapsURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "maps.apple.com"
    }

    private static func parseAppleMaps(_ url: URL) -> ParsedMapLocation? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return nil }

        let params = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        var lat: Double?
        var lng: Double?
        if let ll = params["ll"] {
            let parts = ll.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 2 {
                lat = parts[0]
                lng = parts[1]
            }
        }

        let name = params["q"]?.removingPercentEncoding
        let address = params["address"]?.removingPercentEncoding

        return ParsedMapLocation(
            name: name ?? address,
            address: address,
            latitude: lat,
            longitude: lng
        )
    }

    // MARK: - Google Maps

    private static func isGoogleMapsURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("google.com") && host.contains("maps")
    }

    private static func isGoogleMapsShortURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "maps.app.goo.gl" || host == "goo.gl"
    }

    private static func resolveGoogleMapsShort(_ url: URL) async -> URL? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return response.url
        } catch {
            return nil
        }
    }

    private static func parseGoogleMaps(_ url: URL) -> ParsedMapLocation? {
        let urlString = url.absoluteString

        if let atMatch = extractGoogleAtCoords(urlString) {
            var name: String?
            if let pathComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path {
                let parts = pathComponents.split(separator: "/")
                if let placeIndex = parts.firstIndex(of: "place"), placeIndex + 1 < parts.count {
                    name = String(parts[placeIndex + 1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding
                }
            }
            return ParsedMapLocation(name: name, address: nil, latitude: atMatch.lat, longitude: atMatch.lng)
        }

        if let qMatch = extractGoogleQCoords(urlString) {
            return ParsedMapLocation(name: nil, address: nil, latitude: qMatch.lat, longitude: qMatch.lng)
        }

        return nil
    }

    private static func extractGoogleAtCoords(_ string: String) -> (lat: Double, lng: Double)? {
        let pattern = #"@(-?\d+\.\d+),(-?\d+\.\d+)"#
        guard let regex = try? Regex(pattern),
              let match = string.firstMatch(of: regex),
              let lat = Double(match[1].substring ?? ""),
              let lng = Double(match[2].substring ?? "") else { return nil }
        return (lat, lng)
    }

    private static func extractGoogleQCoords(_ string: String) -> (lat: Double, lng: Double)? {
        guard let components = URLComponents(string: string),
              let queryItems = components.queryItems else { return nil }

        let params = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        guard let q = params["q"] else { return nil }
        let parts = q.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 2 {
            return (parts[0], parts[1])
        }
        return nil
    }
}
