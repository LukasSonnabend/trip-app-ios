import SwiftUI
import MapKit

struct TripMapView: View {
    let items: [ItineraryItem]
    let tripName: String
    let tripId: String

    @State private var annotations: [ItemAnnotation] = []
    @State private var routes: [RouteOverlay] = []
    @State private var selectedItem: ItineraryItem?
    @State private var camera: MapCameraPosition = .automatic
    @State private var selection: String?
    @State private var showLocations = true

    private var locationItems: [ItineraryItem] {
        items.filter { $0.startTime == nil && $0.endTime == nil }
    }

    private var itineraryItems: [ItineraryItem] {
        items.filter { $0.startTime != nil || $0.endTime != nil }
    }

    private var displayedItems: [ItineraryItem] {
        showLocations ? items : itineraryItems
    }

    var body: some View {
        Map(position: $camera, selection: $selection) {
            ForEach(annotations) { annotation in
                Marker(annotation.title, systemImage: annotation.iconName, coordinate: annotation.coordinate)
                    .tint(annotation.color)
                    .tag(annotation.id)
            }
            ForEach(routes) { route in
                MapPolyline(coordinates: [route.start, route.end])
                    .stroke(route.color, lineWidth: 2)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .navigationTitle(tripName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedItem) { item in
            NavigationStack {
                ItemDetailSheet(item: item, tripId: tripId)
            }
            .presentationDetents([.medium])
        }
        .onChange(of: selection) { _, id in
            if let annotation = annotations.first(where: { $0.id == id }) {
                selectedItem = annotation.representativeItem
            }
        }
        .onChange(of: showLocations) { _, _ in
            Task { await geocodeItems() }
        }
        .task {
            await geocodeItems()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !locationItems.isEmpty {
                    Button {
                        showLocations.toggle()
                    } label: {
                        Image(systemName: showLocations ? "mappin.circle.fill" : "mappin.circle")
                    }
                }
            }
        }
    }

    private func geocodeItems() async {
        var grouped: [String: ItemAnnotation] = [:]
        var routeKeys: Set<String> = []
        var routeList: [RouteOverlay] = []
        var coordinateUpdates: [String: ItemCoordinateUpdate] = [:]
        var itemPickupCoords: [String: CLLocationCoordinate2D] = [:]
        var itemDropoffCoords: [String: CLLocationCoordinate2D] = [:]
        let rentalCarIds = Set(displayedItems.filter { $0.itemType == .rentalCar }.map(\.id))

        for item in displayedItems {
            let locs: [(Location, Bool)] = if !item.legs.isEmpty {
                item.legs.flatMap { leg -> [(Location, Bool)] in
                    var results: [(Location, Bool)] = [
                        (Location(name: leg.departureLocation.name, address: leg.departureLocation.address, airportCode: leg.departureAirportCode, latitude: nil, longitude: nil), false),
                    ]
                    if leg.arrivalAirportCode != nil {
                        results.append((Location(name: leg.arrivalLocation.name, address: leg.arrivalLocation.address, airportCode: leg.arrivalAirportCode, latitude: nil, longitude: nil), true))
                    }
                    return results
                }
            } else {
                [(item.location, false)]
                + [item.endLocation].compactMap { $0 }.map { ($0, true) }
                + [item.returnLocation].compactMap { $0 }.map { ($0, true) }
            }

            var legStartCoord: CLLocationCoordinate2D?
            var firstCoordForItem = true

            for (loc, isEnd) in locs {
                let (coord, isNew) = await resolveCoordinate(for: loc)
                guard let coord else { continue }

                if isNew {
                    let key = isEnd ? "end_\(item.id)" : item.id
                    coordinateUpdates[key] = ItemCoordinateUpdate(
                        location: ItemCoordinateUpdate.CoordinateData(latitude: coord.latitude, longitude: coord.longitude),
                        endLocation: nil
                    )
                }

                let key = coordinateKey(coord)
                if var existing = grouped[key] {
                    existing.items.append(item)
                    grouped[key] = existing
                } else {
                    grouped[key] = ItemAnnotation(
                        id: key,
                        items: [item],
                        coordinate: coord,
                        title: item.title,
                        iconName: item.itemType.iconName,
                        color: color(for: item.itemType)
                    )
                }

                if firstCoordForItem {
                    itemPickupCoords[item.id] = coord
                    firstCoordForItem = false
                }
                if isEnd {
                    itemDropoffCoords[item.id] = coord
                    if let start = legStartCoord, !rentalCarIds.contains(item.id) {
                        let rKey = "\(coordinateKey(start))->\(key)"
                        if !routeKeys.contains(rKey) {
                            routeKeys.insert(rKey)
                            routeList.append(RouteOverlay(
                                id: rKey,
                                start: start,
                                end: coord,
                                color: color(for: item.itemType)
                            ))
                        }
                    }
                }
                legStartCoord = coord
            }
        }

        let itemCoordMap = buildItemCoordMap(from: grouped)
        let itemTimeZones = buildItemTimeZones(from: itemCoordMap)

        for car in items where car.itemType == .rentalCar {
            guard let pickupCoord = itemPickupCoords[car.id],
                  let dropoffCoord = itemDropoffCoords[car.id] else { continue }

            let carTZ = itemTimeZones[car.id] ?? TimeZone.current
            let carStart = car.startTime.flatMap { FlexibleDateFormatter.parseInTimeZone($0, timeZone: carTZ) }
            let carEnd = car.endTime.flatMap { FlexibleDateFormatter.parseInTimeZone($0, timeZone: carTZ) }

            let related = items
                .filter { $0.id != car.id }
                .filter { item in
                    guard let cs = carStart,
                          let itemStart = item.startTime.flatMap({ FlexibleDateFormatter.parseInTimeZone($0, timeZone: itemTimeZones[item.id] ?? TimeZone.current) }) else { return false }
                    if let ce = carEnd {
                        return itemStart >= cs && itemStart <= ce
                    }
                    return itemStart >= cs
                }
                .sorted { a, b in
                    if let orderA = a.displayOrder, let orderB = b.displayOrder {
                        return orderA < orderB
                    }
                    if a.displayOrder != nil { return true }
                    if b.displayOrder != nil { return false }
                    let tz = itemTimeZones[a.id] ?? TimeZone.current
                    let dateA = a.startTime.flatMap({ FlexibleDateFormatter.parseInTimeZone($0, timeZone: tz) }) ?? Date.distantFuture
                    let dateB = b.startTime.flatMap({ FlexibleDateFormatter.parseInTimeZone($0, timeZone: tz) }) ?? Date.distantFuture
                    return dateA < dateB
                }

            var chainCoords = [pickupCoord]
            for idx in related.indices {
                guard let coord = itemCoordMap[related[idx].id] else { continue }
                if idx > 0,
                   let bridgingHotel = hotelBridging(related[idx - 1], related[idx], timeZones: itemTimeZones, coordMap: itemCoordMap) {
                    chainCoords.append(bridgingHotel)
                }
                chainCoords.append(coord)
            }
            chainCoords.append(dropoffCoord)

            for i in 0..<(chainCoords.count - 1) {
                let start = chainCoords[i]
                let end = chainCoords[i + 1]
                let rKey = "rental-\(car.id)-\(i)"
                if !routeKeys.contains(rKey) {
                    routeKeys.insert(rKey)
                    routeList.append(RouteOverlay(
                        id: rKey,
                        start: start,
                        end: end,
                        color: color(for: .rentalCar)
                    ))
                }
            }
        }

        let excludedFromHotel = Set([ItemType.flight, .rentalCar])

        for hotel in items where hotel.itemType == .hotel {
            guard let hotelCoord = itemCoordMap[hotel.id] else { continue }

            let hotelTZ = itemTimeZones[hotel.id] ?? TimeZone.current
            let hotelStart = hotel.startTime.flatMap { FlexibleDateFormatter.parseInTimeZone($0, timeZone: hotelTZ) }
            let hotelEnd = hotel.endTime.flatMap { FlexibleDateFormatter.parseInTimeZone($0, timeZone: hotelTZ) }

            let related = items
                .filter { $0.id != hotel.id }
                .filter { !excludedFromHotel.contains($0.itemType) }
                .filter { item in
                    guard let hs = hotelStart,
                          let itemStart = item.startTime.flatMap({ FlexibleDateFormatter.parseInTimeZone($0, timeZone: itemTimeZones[item.id] ?? TimeZone.current) }) else { return false }
                    if let he = hotelEnd {
                        return itemStart >= hs && itemStart <= he
                    }
                    return itemStart >= hs
                }
                .sorted { a, b in
                    if let orderA = a.displayOrder, let orderB = b.displayOrder {
                        return orderA < orderB
                    }
                    if a.displayOrder != nil { return true }
                    if b.displayOrder != nil { return false }
                    let tz = itemTimeZones[a.id] ?? TimeZone.current
                    let dateA = a.startTime.flatMap({ FlexibleDateFormatter.parseInTimeZone($0, timeZone: tz) }) ?? Date.distantFuture
                    let dateB = b.startTime.flatMap({ FlexibleDateFormatter.parseInTimeZone($0, timeZone: tz) }) ?? Date.distantFuture
                    return dateA < dateB
                }

            guard !related.isEmpty else { continue }

            var coords = [hotelCoord]
            for relatedItem in related {
                if let coord = itemCoordMap[relatedItem.id] {
                    coords.append(coord)
                    coords.append(hotelCoord)
                }
            }

            for i in 0..<(coords.count - 1) {
                let start = coords[i]
                let end = coords[i + 1]
                let rKey = "hotel-\(hotel.id)-\(i)"
                if !routeKeys.contains(rKey) {
                    routeKeys.insert(rKey)
                    routeList.append(RouteOverlay(
                        id: rKey,
                        start: start,
                        end: end,
                        color: color(for: .hotel)
                    ))
                }
            }
        }

        annotations = Array(grouped.values)
        routes = routeList

        if !coordinateUpdates.isEmpty {
            await persistCoordinates(coordinateUpdates)
        }

        if let first = annotations.first {
            camera = .region(MKCoordinateRegion(
                center: first.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2)
            ))
        }
    }

    private func buildItemTimeZones(from coordMap: [String: CLLocationCoordinate2D]) -> [String: TimeZone] {
        var result: [String: TimeZone] = [:]
        for (itemId, coord) in coordMap {
            let offset = Int(round(coord.longitude / 15.0))
            if let tz = TimeZone(secondsFromGMT: offset * 3600) {
                result[itemId] = tz
            }
        }
        // Fall back to offset inference for items without coordinates
        let pattern = try! Regex(#"([+-]\d{2}):(\d{2})$"#)
        for item in items where result[item.id] == nil {
            for ts in [item.startTime, item.endTime].compactMap({ $0 }) {
                if let match = ts.firstMatch(of: pattern),
                   let hours = Int(match[1].substring ?? ""),
                   let minutes = Int(match[2].substring ?? "") {
                    let totalSeconds = hours * 3600 + (hours < 0 ? -minutes : minutes) * 60
                    if let tz = TimeZone(secondsFromGMT: totalSeconds) {
                        result[item.id] = tz
                        break
                    }
                }
            }
        }
        return result
    }

    private func hotelBridging(
        _ a: ItineraryItem, _ b: ItineraryItem,
        timeZones: [String: TimeZone],
        coordMap: [String: CLLocationCoordinate2D]
    ) -> CLLocationCoordinate2D? {
        let tzA = (a.startTime ?? a.endTime).flatMap { extractOffsetTZ($0) }
            ?? timeZones[a.id] ?? TimeZone.current
        let tzB = (b.startTime ?? b.endTime).flatMap { extractOffsetTZ($0) }
            ?? timeZones[b.id] ?? TimeZone.current
        guard let dateA = (a.startTime ?? a.endTime).flatMap({ FlexibleDateFormatter.parseInTimeZone($0, timeZone: tzA) }),
              let dateB = (b.startTime ?? b.endTime).flatMap({ FlexibleDateFormatter.parseInTimeZone($0, timeZone: tzB) }),
              !Calendar.current.isDate(dateA, inSameDayAs: dateB) else { return nil }

        for hotel in items where hotel.itemType == .hotel {
            guard let hotelCoord = coordMap[hotel.id] else { continue }
            let tzH = (hotel.startTime ?? hotel.endTime).flatMap { extractOffsetTZ($0) }
                ?? timeZones[hotel.id] ?? TimeZone.current
            guard let hs = hotel.startTime.flatMap({ FlexibleDateFormatter.parseInTimeZone($0, timeZone: tzH) }) else { continue }
            let he = hotel.endTime.flatMap({ FlexibleDateFormatter.parseInTimeZone($0, timeZone: tzH) }) ?? hs.addingTimeInterval(86400)
            if dateA <= he && dateB >= hs {
                return hotelCoord
            }
        }
        return nil
    }

    private func extractOffsetTZ(_ string: String) -> TimeZone? {
        let pattern = try! Regex(#"([+-]\d{2}):(\d{2})$"#)
        guard let match = string.firstMatch(of: pattern),
              let hours = Int(match[1].substring ?? ""),
              let minutes = Int(match[2].substring ?? "") else { return nil }
        let seconds = hours * 3600 + (hours < 0 ? -minutes : minutes) * 60
        return TimeZone(secondsFromGMT: seconds)
    }

    private func buildItemCoordMap(from grouped: [String: ItemAnnotation]) -> [String: CLLocationCoordinate2D] {
        var map: [String: CLLocationCoordinate2D] = [:]
        for annotation in grouped.values {
            for item in annotation.items {
                map[item.id] = annotation.coordinate
            }
        }
        return map
    }

    private func resolveCoordinate(for location: Location) async -> (CLLocationCoordinate2D?, Bool) {
        if let lat = location.latitude, let lng = location.longitude {
            return (CLLocationCoordinate2D(latitude: lat, longitude: lng), false)
        }
        let coord = await geocode(location: location)
        return (coord, coord != nil)
    }

    private func geocode(location: Location) async -> CLLocationCoordinate2D? {
        let query: String = {
            if let address = location.address { return address }
            if let name = location.name { return name }
            return ""
        }()
        guard !query.isEmpty else { return nil }
        do {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            let search = MKLocalSearch(request: request)
            let response = try await search.start()
            if let first = response.mapItems.first {
                return first.location.coordinate
            }
        } catch {}
        return nil
    }

    private func persistCoordinates(_ updates: [String: ItemCoordinateUpdate]) async {
        let client = APIClient.shared
        for (itemId, update) in updates {
            try? await client.requestVoid(
                "PATCH",
                "trips/\(tripId)/items/\(itemId)",
                body: update
            )
        }
    }

    private func coordinateKey(_ coord: CLLocationCoordinate2D) -> String {
        String(format: "%.4f,%.4f", coord.latitude, coord.longitude)
    }

    private func color(for type: ItemType) -> Color {
        switch type {
        case .flight: return .blue
        case .hotel: return .purple
        case .restaurant: return .orange
        case .rentalCar: return .green
        case .train: return .teal
        case .event: return .red
        case .generic, .expense, .unknown: return .gray
        }
    }
}

struct ItemAnnotation: Identifiable {
    let id: String
    var items: [ItineraryItem]
    let coordinate: CLLocationCoordinate2D
    let title: String
    let iconName: String
    let color: Color

    var representativeItem: ItineraryItem {
        items.first!
    }
}

struct RouteOverlay: Identifiable {
    let id: String
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
    let color: Color
}

struct ItemDetailSheet: View {
    let item: ItineraryItem
    let tripId: String

    @State private var showEdit = false
    @State private var showSourcePDF = false
    @State private var showNavigate = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: item.itemType.iconName)
                        .font(.title2)
                        .foregroundStyle(.tint)
                    Text(item.title)
                        .font(.headline)
                }
                if let provider = item.provider {
                    LabeledContent("Provider", value: provider)
                }
                if let code = item.confirmationCode {
                    LabeledContent("Confirmation", value: code)
                }
                if let traveler = item.travelerName {
                    LabeledContent("Traveler", value: traveler)
                }
                if let price = item.price {
                    LabeledContent("Price", value: price)
                }
                if let confidence = item.confidence {
                    LabeledContent("Confidence") {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(confidenceColor)
                                .frame(width: 8, height: 8)
                            Text(confidence.capitalized)
                        }
                    }
                }
            }

            Section("Time") {
                if let start = item.startTime {
                    LabeledContent("Start", value: FlexibleDateFormatter.displayString(start))
                }
                if let end = item.endTime {
                    LabeledContent("End", value: FlexibleDateFormatter.displayString(end))
                }
            }

            if !item.legs.isEmpty {
                Section("Legs") {
                    ForEach(Array(item.legs.enumerated()), id: \.offset) { index, leg in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                if let dep = leg.departureAirportCode, let arr = leg.arrivalAirportCode {
                                    Text("\(dep) → \(arr)")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                Spacer()
                                if let seat = leg.seat {
                                    Text(seat)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let start = leg.startTime {
                                Text(FlexibleDateFormatter.displayString(start))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let end = leg.endTime {
                                Text(FlexibleDateFormatter.displayString(end))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("Location") {
                if let name = item.location.name {
                    LabeledContent("Name", value: name)
                }
                if let address = item.location.address {
                    LabeledContent("Address", value: address)
                }
                if let code = item.location.airportCode {
                    LabeledContent("Airport", value: code)
                }
                Button {
                    showNavigate = true
                } label: {
                    Label("Navigate", systemImage: "location.fill")
                }
            }

            if let endLoc = item.endLocation {
                Section("End Location") {
                    if let name = endLoc.name {
                        LabeledContent("Name", value: name)
                    }
                    if let address = endLoc.address {
                        LabeledContent("Address", value: address)
                    }
                    if let code = endLoc.airportCode {
                        LabeledContent("Airport", value: code)
                    }
                }
            }

            if let returnLoc = item.returnLocation {
                Section("Return Location") {
                    if let name = returnLoc.name {
                        LabeledContent("Name", value: name)
                    }
                    if let address = returnLoc.address {
                        LabeledContent("Address", value: address)
                    }
                    if let code = returnLoc.airportCode {
                        LabeledContent("Airport", value: code)
                    }
                }
            }

            if item.details.seat != nil || item.details.gate != nil || item.details.roomType != nil {
                Section("Details") {
                    if let seat = item.details.seat {
                        LabeledContent("Seat", value: seat)
                    }
                    if let gate = item.details.gate {
                        LabeledContent("Gate", value: gate)
                    }
                    if let room = item.details.roomType {
                        LabeledContent("Room", value: room)
                    }
                }
            }
            if let notes = item.details.notes {
                Section("Notes") {
                    Text(notes)
                }
            }
        }
        .navigationTitle(item.itemType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showEdit = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNavigate = true
                } label: {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond")
                }
            }
            if SourceDocumentStore.exists(for: item.id) {
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        showSourcePDF = true
                    } label: {
                        Label("View Source PDF", systemImage: "doc.text")
                    }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            EditItemSheet(
                item: item,
                tripId: tripId,
                onUpdate: { _ in showEdit = false },
                onClose: { showEdit = false }
            )
        }
        .sheet(isPresented: $showSourcePDF) {
            if let url = SourceDocumentStore.url(for: item.id) {
                PDFPreviewView(url: url)
            }
        }
        .confirmationDialog("Navigate with", isPresented: $showNavigate, titleVisibility: .visible) {
            if let url = appleMapsURL() {
                Button("Apple Maps") { UIApplication.shared.open(url) }
            }
            if let url = googleMapsURL() {
                Button("Google Maps") { UIApplication.shared.open(url) }
            }
            if let url = wazeURL() {
                Button("Waze") { UIApplication.shared.open(url) }
            }
        }
    }

    private func destinationQuery() -> String {
        if let lat = item.location.latitude, let lng = item.location.longitude {
            return "\(lat),\(lng)"
        }
        if let address = item.location.address {
            return address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? address
        }
        if let name = item.location.name {
            return name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        }
        return ""
    }

    private func destinationName() -> String {
        (item.location.name ?? item.location.address ?? "Destination")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Destination"
    }

    private func appleMapsURL() -> URL? {
        let query = destinationQuery()
        guard !query.isEmpty else { return nil }
        if item.location.latitude != nil {
            return URL(string: "https://maps.apple.com/?daddr=\(query)&q=\(destinationName())")
        }
        return URL(string: "https://maps.apple.com/?q=\(query)")
    }

    private func googleMapsURL() -> URL? {
        guard UIApplication.shared.canOpenURL(URL(string: "comgooglemaps://")!) else { return nil }
        let query = destinationQuery()
        guard !query.isEmpty else { return nil }
        if item.location.latitude != nil {
            return URL(string: "comgooglemaps://?daddr=\(query)&navigate=yes")
        }
        return URL(string: "comgooglemaps://?q=\(query)")
    }

    private func wazeURL() -> URL? {
        guard UIApplication.shared.canOpenURL(URL(string: "waze://")!) else { return nil }
        if let lat = item.location.latitude, let lng = item.location.longitude {
            return URL(string: "waze://?ll=\(lat),\(lng)&navigate=yes")
        }
        let query = destinationQuery()
        guard !query.isEmpty else { return nil }
        return URL(string: "waze://?q=\(query)")
    }

    private var confidenceColor: Color {
        switch item.confidence {
        case "high": return .green
        case "medium": return .orange
        case "low": return .red
        default: return .gray
        }
    }
}

#Preview {
    NavigationStack {
        TripMapView(
            items: [],
            tripName: "Preview Trip",
            tripId: "preview"
        )
    }
}
