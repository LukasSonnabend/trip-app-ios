import SwiftUI

struct TripDetailView: View {
    let tripId: String
    let tripName: String

    @StateObject private var tripsVM = TripsViewModel()
    @StateObject private var itemsVM = ItemsViewModel()
    @State private var showInvite = false
    @State private var showCreatedInvite = false
    @State private var editingItem: ItineraryItem?

    var body: some View {
        List {
            if let detail = tripsVM.tripDetail {
                Section("Members") {
                    ForEach(detail.members) { member in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(member.name ?? member.email)
                                    .font(.headline)
                                Text(member.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(member.role.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Items") {
                if itemsVM.isLoading && itemsVM.items.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if itemsVM.items.isEmpty {
                    Text("No items yet. Add some via the share extension!")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(itemsVM.items) { item in
                        ItemRow(item: item, tripId: tripId, onEdit: { editingItem = $0 }, onSplitPrice: { origin in
                            Task { await itemsVM.splitPrice(tripId: tripId, originItem: origin) }
                        })
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            let item = itemsVM.items[index]
                            Task { await itemsVM.deleteItem(tripId: tripId, itemId: item.id) }
                        }
                    }
                }
            }
        }
        .navigationTitle(tripName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    TripMapView(items: itemsVM.items, tripName: tripName, tripId: tripId)
                } label: {
                    Image(systemName: "map")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await tripsVM.createInvite(tripId: tripId)
                        showCreatedInvite = true
                    }
                } label: {
                    Image(systemName: "person.badge.plus")
                }
            }
        }
        .refreshable {
            async let tripLoad: () = tripsVM.loadTrip(id: tripId)
            async let itemsLoad: () = itemsVM.loadItems(tripId: tripId)
            _ = await (tripLoad, itemsLoad)
        }
        .task {
            async let tripLoad: () = tripsVM.loadTrip(id: tripId)
            async let itemsLoad: () = itemsVM.loadItems(tripId: tripId)
            _ = await (tripLoad, itemsLoad)
        }
        .alert("Invite Code", isPresented: $showCreatedInvite) {
            if let code = tripsVM.inviteCode {
                Button("Copy") {
                    UIPasteboard.general.string = "https://yourapp.example/join/\(code.code)"
                }
                Button("OK", role: .cancel) { }
            }
        } message: {
            if let code = tripsVM.inviteCode {
                Text("Share this code:\n\(code.code)\n\nOr link: https://yourapp.example/join/\(code.code)")
            }
        }
        .alert("Error", isPresented: .init(
            get: { itemsVM.errorMessage != nil || tripsVM.errorMessage != nil },
            set: { if !$0 { itemsVM.errorMessage = nil; tripsVM.errorMessage = nil } }
        )) {
            Button("OK") { itemsVM.errorMessage = nil; tripsVM.errorMessage = nil }
        } message: {
            Text(itemsVM.errorMessage ?? tripsVM.errorMessage ?? "")
        }
        .sheet(item: $editingItem) { item in
            EditItemSheet(
                item: item,
                tripId: tripId,
                onUpdate: { updated in
                    if let index = itemsVM.items.firstIndex(where: { $0.id == updated.id }) {
                        itemsVM.items[index] = updated
                    }
                },
                onClose: { editingItem = nil }
            )
        }
    }
}

struct ItemRow: View {
    let item: ItineraryItem
    let tripId: String
    let onEdit: (ItineraryItem) -> Void
    let onSplitPrice: (ItineraryItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: item.itemType.iconName)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.headline)
                    if let provider = item.provider {
                        Text(provider)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(item.itemType.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            if let traveler = item.travelerName {
                Label(traveler, systemImage: "person.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let start = item.startTime {
                Text(FlexibleDateFormatter.displayString(start))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let locName = item.location.name {
                Text(locName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let price = item.price {
                Text(price)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                onEdit(item)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            if item.price != nil {
                Button {
                    onSplitPrice(item)
                } label: {
                    Label("Split Price", systemImage: "divide")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        TripDetailView(tripId: "preview", tripName: "Tokyo Trip")
    }
}
