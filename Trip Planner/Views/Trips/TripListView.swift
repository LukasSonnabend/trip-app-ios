import SwiftUI

struct TripListView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var tripsVM = TripsViewModel()
    @State private var showCreate = false
    @State private var newTripName = ""

    var body: some View {
        NavigationStack {
            Group {
                if tripsVM.isLoading && tripsVM.trips.isEmpty {
                    ProgressView("Loading trips...")
                } else if tripsVM.trips.isEmpty {
                    ContentUnavailableView(
                        "No Trips Yet",
                        systemImage: " suitcase",
                        description: Text("Create your first trip to get started")
                    )
                } else {
                    List {
                        ForEach(tripsVM.trips) { trip in
                            NavigationLink {
                                TripDetailView(tripId: trip.id, tripName: trip.name)
                            } label: {
                                TripRow(trip: trip)
                            }
                        }
                    }
                }
            }
            .navigationTitle("My Trips")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newTripName = ""
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button(role: .destructive) {
                        Task { await authVM.logout() }
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .alert("Create Trip", isPresented: $showCreate) {
                TextField("Trip name", text: $newTripName)
                Button("Cancel", role: .cancel) { }
                Button("Create") {
                    Task { await tripsVM.createTrip(name: newTripName) }
                }
                .disabled(newTripName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .alert("Error", isPresented: .init(
                get: { tripsVM.errorMessage != nil },
                set: { if !$0 { tripsVM.errorMessage = nil } }
            )) {
                Button("OK") { tripsVM.errorMessage = nil }
            } message: {
                if let err = tripsVM.errorMessage { Text(err) }
            }
            .refreshable { await tripsVM.loadTrips() }
            .task { await tripsVM.loadTrips() }
        }
    }
}

struct TripRow: View {
    let trip: TripSummary

    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundStyle(.tint)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(trip.name)
                    .font(.headline)
                Text(trip.role.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    TripListView()
        .environmentObject(AuthViewModel())
}
