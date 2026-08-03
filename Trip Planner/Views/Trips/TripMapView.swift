import SwiftUI
import MapKit

struct TripMapView: View {
    let items: [ItineraryItem]
    let tripName: String

    @State private var annotations: [ItemAnnotation] = []
    @State private var selectedItem: ItineraryItem?
    @State private var camera: MapCameraPosition = .automatic
    @State private var selection: String?

    var body: some View {
        Map(position: $camera, selection: $selection) {
            ForEach(annotations) { annotation in
                Marker(annotation.item.title, systemImage: annotation.item.itemType.iconName, coordinate: annotation.coordinate)
                    .tint(color(for: annotation.item.itemType))
                    .tag(annotation.id)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .navigationTitle(tripName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedItem) { item in
            NavigationStack {
                ItemDetailSheet(item: item)
            }
            .presentationDetents([.medium])
        }
        .onChange(of: selection) { _, id in
            if let annotation = annotations.first(where: { $0.id == id }) {
                selectedItem = annotation.item
            }
        }
        .task {
            await geocodeItems()
        }
    }

    private func geocodeItems() async {
        let geocoder = CLGeocoder()
        var results: [ItemAnnotation] = []

        for item in items {
            let query: String = {
                if let address = item.location.address { return address }
                if let name = item.location.name { return name }
                return ""
            }()

            guard !query.isEmpty else { continue }

            do {
                let placemarks = try await geocoder.geocodeAddressString(query)
                if let placemark = placemarks.first, let location = placemark.location {
                    results.append(ItemAnnotation(
                        id: item.id,
                        item: item,
                        coordinate: location.coordinate
                    ))
                }
            } catch {
                continue
            }
        }
        annotations = results

        if let first = results.first {
            camera = .region(MKCoordinateRegion(
                center: first.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2)
            ))
        }
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
    let item: ItineraryItem
    let coordinate: CLLocationCoordinate2D
}

struct ItemDetailSheet: View {
    let item: ItineraryItem

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
    }
}

#Preview {
    NavigationStack {
        TripMapView(
            items: [],
            tripName: "Preview Trip"
        )
    }
}
