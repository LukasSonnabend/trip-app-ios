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

        for car in items where car.itemType == .rentalCar {
            guard let pickupCoord = itemPickupCoords[car.id],
                  let dropoffCoord = itemDropoffCoords[car.id] else { continue }

            let carStart = car.startTime.flatMap(FlexibleDateFormatter.parseLocal(_:))
            let carEnd = car.endTime.flatMap(FlexibleDateFormatter.parseLocal(_:))

            let related = items
                .filter { $0.id != car.id }
                .filter { item in
                    guard let cs = carStart, let ce = carEnd,
                          let start = item.startTime.flatMap(FlexibleDateFormatter.parseLocal(_:)) else { return false }
                    return start >= cs && start <= ce
                }
                .sorted { a, b in
                    let dateA = a.startTime.flatMap(FlexibleDateFormatter.parseLocal(_:)) ?? Date.distantFuture
                    let dateB = b.startTime.flatMap(FlexibleDateFormatter.parseLocal(_:)) ?? Date.distantFuture
                    return dateA < dateB
                }

            var chainCoords = [pickupCoord]
            for relatedItem in related {
                if let coord = itemCoordMap[relatedItem.id] {
                    chainCoords.append(coord)
                }
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
        case .generic, .unknown: return .gray
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
