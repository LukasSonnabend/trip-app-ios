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
        .task {
            await geocodeItems()
        }
    }

    private func shouldShowRoute(for type: ItemType) -> Bool {
        type == .flight || type == .rentalCar
    }

    private func geocodeItems() async {
        var grouped: [String: ItemAnnotation] = [:]
        var routeKeys: Set<String> = []
        var routeList: [RouteOverlay] = []
        var coordinateUpdates: [String: ItemCoordinateUpdate] = [:]

        for item in items {
            let (startCoord, startNew) = await resolveCoordinate(for: item.location)
            let hasRoute = shouldShowRoute(for: item.itemType) && item.endLocation != nil
            let (endCoord, endNew): (CLLocationCoordinate2D?, Bool) = if hasRoute, let endLoc = item.endLocation {
                await resolveCoordinate(for: endLoc)
            } else { (nil, false) }

            if startNew || endNew, let start = startCoord {
                coordinateUpdates[item.id] = ItemCoordinateUpdate(
                    location: ItemCoordinateUpdate.CoordinateData(
                        latitude: start.latitude,
                        longitude: start.longitude
                    ),
                    endLocation: endCoord.map {
                        ItemCoordinateUpdate.CoordinateData(latitude: $0.latitude, longitude: $0.longitude)
                    }
                )
            }

            if let start = startCoord {
                let key = coordinateKey(start)
                if var existing = grouped[key] {
                    existing.items.append(item)
                    grouped[key] = existing
                } else {
                    grouped[key] = ItemAnnotation(
                        id: key,
                        items: [item],
                        coordinate: start,
                        title: item.title,
                        iconName: item.itemType.iconName,
                        color: color(for: item.itemType)
                    )
                }
            }

            if let end = endCoord {
                let key = coordinateKey(end)
                if var existing = grouped[key] {
                    existing.items.append(item)
                    grouped[key] = existing
                } else {
                    grouped[key] = ItemAnnotation(
                        id: key,
                        items: [item],
                        coordinate: end,
                        title: item.title,
                        iconName: item.itemType.iconName,
                        color: color(for: item.itemType)
                    )
                }

                if let start = startCoord {
                    let rKey = "\(coordinateKey(start))->\(coordinateKey(end))"
                    if !routeKeys.contains(rKey) {
                        routeKeys.insert(rKey)
                        routeList.append(RouteOverlay(
                            id: rKey,
                            start: start,
                            end: end,
                            color: color(for: item.itemType)
                        ))
                    }
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
            }

            Section("Time") {
                if let start = item.startTime {
                    LabeledContent("Start", value: FlexibleDateFormatter.displayString(start))
                }
                if let end = item.endTime {
                    LabeledContent("End", value: FlexibleDateFormatter.displayString(end))
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

            if let seat = item.details.seat {
                Section("Details") {
                    LabeledContent("Seat", value: seat)
                }
            }
            if let gate = item.details.gate {
                Section("Details") {
                    LabeledContent("Gate", value: gate)
                }
            }
            if let room = item.details.roomType {
                Section("Details") {
                    LabeledContent("Room", value: room)
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
        }
        .sheet(isPresented: $showEdit) {
            EditItemSheet(
                item: item,
                tripId: tripId,
                onUpdate: { _ in showEdit = false },
                onClose: { showEdit = false }
            )
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
