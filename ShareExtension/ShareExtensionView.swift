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
                        onSelect: { tripId in
                            viewModel.submitExtraction(tripId: tripId)
                            onDismiss()
                        },
                        onCancel: onDismiss
                    )

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
        case error(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading): return true
            case (.selectTrip(let a), .selectTrip(let b)): return a.map(\.id) == b.map(\.id)
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

    func submitExtraction(tripId: String) {
        let fileData = sharedFile?.0
        let fileName = sharedFile?.1
        let content = sharedContent
        let url = sharedURL
        let hasFile = sharedFile != nil

        Task {
            do {
                let items: [ItineraryItem] = try await client.uploadMultipart(
                    "trips/\(tripId)/items/extract",
                    textContent: hasFile ? nil : content,
                    url: hasFile ? nil : url,
                    fileData: fileData,
                    fileName: fileName,
                    mimeType: hasFile ? "application/pdf" : nil
                )
                if let data = fileData {
                    for item in items {
                        SourceDocumentStore.save(data: data, for: item.id)
                    }
                }
            } catch {
                _ = error
            }
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
