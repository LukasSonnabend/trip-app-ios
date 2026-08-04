import SwiftUI

struct TripDetailView: View {
    let tripId: String
    let tripName: String

    @StateObject private var tripsVM = TripsViewModel()
    @StateObject private var itemsVM = ItemsViewModel()
    @State private var showInvite = false
    @State private var showCreatedInvite = false
    @State private var editingItem: ItineraryItem?
    @State private var isSelecting = false
    @State private var selectedIds = Set<String>()

    var body: some View {
        List {
            membersSection
            itemsSection
        }
        .navigationTitle(tripName)
        .toolbar { toolbarContent }
        .refreshable { await refresh() }
        .task { await refresh() }
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
        .onChange(of: isSelecting) { _, newValue in
            if !newValue { selectedIds.removeAll() }
        }
    }

    @ViewBuilder
    private var membersSection: some View {
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
    }

    @ViewBuilder
    private var itemsSection: some View {
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
                    HStack(spacing: 0) {
                        if isSelecting {
                                let isItemSelected = selectedIds.contains(item.id)
                                Image(systemName: isItemSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isItemSelected ? Color.accentColor : Color.secondary)
                                    .font(.title3)
                                    .padding(.trailing, 12)
                            }
                        ItemCard(item: item, tripId: tripId, onEdit: { editingItem = $0 }, onSplitPrice: { origin in
                            Task { await itemsVM.splitPrice(tripId: tripId, originItem: origin) }
                        })
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { toggleSelection(item.id) }
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

    private func toggleSelection(_ id: String) {
        guard isSelecting else { return }
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func refresh() async {
        async let tripLoad: () = tripsVM.loadTrip(id: tripId)
        async let itemsLoad: () = itemsVM.loadItems(tripId: tripId)
        _ = await (tripLoad, itemsLoad)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    isSelecting = false
                    selectedIds.removeAll()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    Task {
                        await itemsVM.deleteItems(tripId: tripId, itemIds: selectedIds)
                        isSelecting = false
                        selectedIds.removeAll()
                    }
                } label: {
                    Text("Delete (\(selectedIds.count))")
                }
                .disabled(selectedIds.isEmpty)
            }
        } else {
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
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isSelecting = true
                } label: {
                    Image(systemName: "checkmark.circle")
                }
            }
        }
    }
}

struct ItemCard: View {
    let item: ItineraryItem
    let tripId: String
    let onEdit: (ItineraryItem) -> Void
    let onSplitPrice: (ItineraryItem) -> Void

    @State private var expanded = false
    @State private var showSourcePDF = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: item.itemType.iconName)
                    .frame(width: 24)
                    .foregroundStyle(.tint)

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

                if let price = item.price {
                    Text(price)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
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

            if !item.legs.isEmpty {
                Button {
                    withAnimation { expanded.toggle() }
                } label: {
                    HStack {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                        Text("\(item.legs.count) leg\(item.legs.count == 1 ? "" : "s")")
                            .font(.caption)
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if expanded {
                    ForEach(item.legs) { leg in
                        LegRow(leg: leg)
                    }
                }
            }

            if item.legs.isEmpty {
                if let locName = item.location.name {
                    Text(locName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
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
            if SourceDocumentStore.exists(for: item.id) {
                Button {
                    showSourcePDF = true
                } label: {
                    Label("View Source PDF", systemImage: "doc.text")
                }
            }
        }
        .sheet(isPresented: $showSourcePDF) {
            if let url = SourceDocumentStore.url(for: item.id) {
                PDFPreviewView(url: url)
            }
        }
    }
}

struct LegRow: View {
    let leg: Leg

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if let dep = leg.departureAirportCode, let arr = leg.arrivalAirportCode {
                    Text("\(dep) → \(arr)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                if let start = leg.startTime {
                    Text(FlexibleDateFormatter.displayString(start))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let seat = leg.seat {
                Text(seat)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 32)
    }
}

#Preview {
    NavigationStack {
        TripDetailView(tripId: "preview", tripName: "Tokyo Trip")
    }
}
