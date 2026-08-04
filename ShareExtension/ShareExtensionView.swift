import Combine
import SwiftUI

struct ShareExtensionMainView: View {
    let onDismiss: () -> Void
    let extractedItems: [ItineraryItem]

    @StateObject private var viewModel = ShareExtensionViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .loading:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading your trips...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                case .selectTrip(let trips):
                    TripSelectionView(
                        trips: trips,
                        inputSummary: viewModel.inputSummary,
                        onSelect: { tripId in Task { await viewModel.extract(tripId: tripId) } },
                        onCancel: onDismiss
                    )

                case .extracting:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Extracting itinerary items...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                case .result(let items):
                    ExtractionResultView(items: items, onDone: onDismiss)

                case .error(let message):
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(message)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        Button("Try Again") {
                            Task { await viewModel.loadTrips() }
                        }
                        .buttonStyle(.bordered)
                        Button("Close", action: onDismiss)
                            .buttonStyle(.bordered)
                    }
                    .padding()
                }
            }
            .navigationTitle("Add to Trip")
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await viewModel.loadTrips() }
            .onReceive(NotificationCenter.default.publisher(for: .shareInputReady)) { notification in
                if let content = notification.userInfo?["content"] as? String {
                    viewModel.sharedContent = content
                }
                if let url = notification.userInfo?["url"] as? String {
                    viewModel.sharedURL = url
                }
                if let fileData = notification.userInfo?["fileData"] as? (Data, String) {
                    viewModel.sharedFile = fileData
                }
                viewModel.updateSummary()
            }
        }
    }
}

@MainActor
final class ShareExtensionViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case selectTrip([TripSummary])
        case extracting
        case result([ItineraryItem])
        case error(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading): return true
            case (.selectTrip(let a), .selectTrip(let b)): return a.map(\.id) == b.map(\.id)
            case (.extracting, .extracting): return true
            case (.result(let a), .result(let b)): return a.map(\.id) == b.map(\.id)
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    @Published var state: State = .loading
    @Published var inputSummary: String = ""
    var sharedContent: String?
    var sharedURL: String?
    var sharedFile: (Data, String)?

    private var trips: [TripSummary] = []
    private let client = APIClient.shared

    func loadTrips() async {
        state = .loading
        do {
            trips = try await client.request("GET", "trips")
            state = trips.isEmpty ? .error("No trips found. Create one in the app first.") : .selectTrip(trips)
        } catch {
            if error.isCancellationError { return }
            state = .error(error.localizedDescription)
        }
    }

    func updateSummary() {
        if let url = sharedURL {
            inputSummary = "Link: \(URL(string: url)?.host ?? url)"
        } else if let content = sharedContent {
            inputSummary = content.count > 80 ? String(content.prefix(80)) + "..." : content
        } else if let (_, name) = sharedFile {
            inputSummary = "PDF: \(name)"
        }
    }

    func extract(tripId: String) async {
        state = .extracting
        let pdfData = sharedFile?.0
        do {
            let hasFile = sharedFile != nil
            let items: [ItineraryItem] = try await client.uploadMultipart(
                "trips/\(tripId)/items/extract",
                textContent: hasFile ? nil : sharedContent,
                url: hasFile ? nil : sharedURL,
                fileData: pdfData,
                fileName: sharedFile?.1,
                mimeType: sharedFile != nil ? "application/pdf" : nil
            )
            if let data = pdfData {
                for item in items {
                    SourceDocumentStore.save(data: data, for: item.id)
                }
            }
            state = .result(items)
        } catch {
            if error.isCancellationError { return }
            state = .error(error.localizedDescription)
        }
    }
}

struct TripSelectionView: View {
    let trips: [TripSummary]
    let inputSummary: String
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !inputSummary.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sharing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(inputSummary)
                        .font(.callout)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .padding()
            }

            Text("Select a trip to add to:")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 8)

            List(trips) { trip in
                Button {
                    onSelect(trip.id)
                } label: {
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.tint)
                        Text(trip.name)
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }
}

struct ExtractionResultView: View {
    let items: [ItineraryItem]
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Nothing found")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("We couldn't extract any travel information from what you shared. The content may not contain recognizable itinerary details.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 48)
            } else {
                Text("Added \(items.count) item\(items.count == 1 ? "" : "s")")
                    .font(.headline)
                    .padding()

                List(items) { item in
                    HStack {
                        Image(systemName: item.itemType.iconName)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if let traveler = item.travelerName {
                                Text(traveler)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let start = item.startTime {
                                Text(FlexibleDateFormatter.displayString(start))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let price = item.price {
                            Text(price)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .listStyle(.inset)
            }

            Spacer()

            Button {
                onDone()
            } label: {
                Text("Done")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
        }
    }
}

struct NotAuthenticatedExtensionView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Not Logged In")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Open the Trip Planner app and log in to start adding items to your trips.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button("Close", action: onDismiss)
                .buttonStyle(.bordered)
                .padding(.top, 8)
        }
    }
}
