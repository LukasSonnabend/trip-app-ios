import SwiftUI

struct TripDetailView: View {
    let tripId: String
    let tripName: String

    @StateObject private var tripsVM = TripsViewModel()
    @StateObject private var itemsVM = ItemsViewModel()
    @StateObject private var travelersVM = TravelersViewModel()
    @State private var showInvite = false
    @State private var showCreatedInvite = false
    @State private var editingItem: ItineraryItem?
    @State private var showingCreateItem = false
    @State private var showingTravelersSheet = false
    @State private var splitConfigItem: ItineraryItem?
    @State private var isSelecting = false
    @State private var selectedIds = Set<String>()
    @State private var selectedTab = 0

    private var itineraryItems: [ItineraryItem] {
        itemsVM.items.filter { $0.startTime != nil || $0.endTime != nil }
    }

    private var locationItems: [ItineraryItem] {
        itemsVM.items.filter { $0.startTime == nil && $0.endTime == nil }
    }

    private var currentItems: [ItineraryItem] {
        selectedTab == 0 ? itineraryItems : locationItems
    }

    var body: some View {
        List {
            travelersSection
            Section {
                Picker("View", selection: $selectedTab) {
                    Text("Itinerary").tag(0)
                    Text("Locations").tag(1)
                }
                .pickerStyle(.segmented)
            }
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
        .sheet(isPresented: $showingCreateItem) {
            CreateItemSheet(
                tripId: tripId,
                    onCreate: { newItem in
                        itemsVM.items.append(newItem)
                        itemsVM.items = itemsVM.sortItems(itemsVM.items)
                    },
                onClose: { showingCreateItem = false }
            )
        }
        .sheet(isPresented: $showingTravelersSheet) {
            TravelersSheet(tripId: tripId, onDismiss: { showingTravelersSheet = false }, travelersVM: travelersVM)
        }
        .sheet(item: $splitConfigItem) { item in
            SplitConfigSheet(tripId: tripId, item: item, onDismiss: { splitConfigItem = nil }, travelersVM: travelersVM)
        }
        .onChange(of: isSelecting) { _, newValue in
            if !newValue { selectedIds.removeAll() }
        }
    }

    @ViewBuilder
    private var travelersSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(travelersVM.travelers) { traveler in
                        VStack(spacing: 4) {
                            Circle()
                                .fill(colorFor(traveler.color))
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Text(String(traveler.name.prefix(1).uppercased()))
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                }
                            Text(traveler.name)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .frame(width: 56)
                    }
                    VStack(spacing: 4) {
                        Circle()
                            .stroke(.secondary, lineWidth: 1.5)
                            .frame(width: 40, height: 40)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        Text("Add")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 56)
                    .onTapGesture { showingTravelersSheet = true }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
            }
        } header: {
            HStack {
                Text("Travelers")
                Spacer()
                if !travelersVM.travelers.isEmpty {
                    NavigationLink {
                        BudgetView(tripId: tripId, tripName: tripName)
                    } label: {
                        Text("Budget")
                            .font(.caption)
                    }
                }
            }
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
        Section(selectedTab == 0 ? "Itinerary" : "Locations") {
            if itemsVM.isLoading && itemsVM.items.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if currentItems.isEmpty {
                Text(selectedTab == 0
                     ? "No itinerary items yet. Add some via the share extension!"
                     : "No saved locations yet. Share a map link or add one manually.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(currentItems) { item in
                    HStack(spacing: 0) {
                        if isSelecting {
                            let isItemSelected = selectedIds.contains(item.id)
                            Image(systemName: isItemSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isItemSelected ? Color.accentColor : Color.secondary)
                                .font(.title3)
                                .padding(.trailing, 12)
                        }
                        ItemCard(item: item, tripId: tripId,
                            isLocation: selectedTab == 1,
                            onEdit: { editingItem = $0 },
                            onConfigureSplit: { splitConfigItem = $0 },
                            onAddToItinerary: { date in addToItinerary(item: item, date: date) },
                            travelers: travelersVM.travelers
                        )
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { toggleSelection(item.id) }
                }
                .onDelete { offsets in
                    for index in offsets {
                        let item = currentItems[index]
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

    private func addToItinerary(item: ItineraryItem, date: Date) {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let startTime = isoFormatter.string(from: date)

        struct DateOnlyUpdate: Codable {
            let startTime: String
            enum CodingKeys: String, CodingKey { case startTime = "start_time" }
        }

        Task {
            do {
                let _: ItineraryItem = try await APIClient.shared.request(
                    "PATCH", "trips/\(tripId)/items/\(item.id)",
                    body: DateOnlyUpdate(startTime: startTime)
                )
                await itemsVM.loadItems(tripId: tripId)
            } catch {}
        }
    }

    private func refresh() async {
        async let tripLoad: () = tripsVM.loadTrip(id: tripId)
        async let itemsLoad: () = itemsVM.loadItems(tripId: tripId)
        async let travelersLoad: () = travelersVM.loadTravelers(tripId: tripId)
        _ = await (tripLoad, itemsLoad, travelersLoad)
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
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreateItem = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

struct ItemCard: View {
    let item: ItineraryItem
    let tripId: String
    let isLocation: Bool
    let onEdit: (ItineraryItem) -> Void
    let onConfigureSplit: (ItineraryItem) -> Void
    let onAddToItinerary: (Date) -> Void
    let travelers: [Traveler]

    @State private var expanded = false
    @State private var showSourcePDF = false
    @State private var quickAssignedTravelerId: String?
    @State private var quickAssignedName: String?
    @State private var showDatePicker = false
    @State private var itineraryDate = Date()

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

                if item.confidence == "low" || item.confidence == "medium" {
                    Text("!")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(item.confidence == "low" ? Color.red : Color.orange, in: Capsule())
                }

                if let price = item.price {
                    HStack(spacing: 4) {
                        if let traveler = badgeTraveler {
                            Circle()
                                .fill(colorFor(traveler.color))
                                .frame(width: 16, height: 16)
                                .overlay {
                                    Text(String(traveler.name.prefix(1).uppercased()))
                                        .font(.system(size: 8))
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                }
                        }
                        Text(price)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.tint)
                    }
                }
            }

            if let traveler = item.travelerName {
                Label(traveler, systemImage: "person.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isLocation, let locName = item.location.name {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(locName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let addr = item.location.address {
                        Text("· \(addr)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if let start = item.startTime {
                HStack(spacing: 4) {
                    Text(FlexibleDateFormatter.displayString(start))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let end = item.endTime {
                        Text("→")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(FlexibleDateFormatter.displayString(end))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !item.legs.isEmpty {
                routeSummary

                Button {
                    withAnimation { expanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                        Text(expanded ? "Hide details" : "Show details")
                            .font(.caption2)
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
            if isLocation {
                Button {
                    itineraryDate = Date()
                    showDatePicker = true
                } label: {
                    Label("Add to Itinerary", systemImage: "calendar.badge.plus")
                }
            }
            if item.price != nil, !travelers.isEmpty {
                Menu {
                    if let current = quickAssignedTravelerId {
                        Button(role: .destructive) {
                            Task { await quickUnassign() }
                        } label: {
                            Label("Unassign", systemImage: "xmark.circle")
                        }
                    }
                    ForEach(travelers) { traveler in
                        Button {
                            Task { await quickAssign(to: traveler) }
                        } label: {
                            Label(traveler.name, systemImage: quickAssignedTravelerId == traveler.id ? "checkmark" : "person")
                        }
                    }
                } label: {
                    Label("Assign to...", systemImage: "person.badge.plus")
                }
                Button {
                    onConfigureSplit(item)
                } label: {
                    Label("Split Cost", systemImage: "dollarsign.arrow.circlepath")
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
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                VStack(spacing: 0) {
                    DatePicker(
                        "Date",
                        selection: $itineraryDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                    .padding()
                }
                .navigationTitle("Add to Itinerary")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showDatePicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            let date = itineraryDate
                            showDatePicker = false
                            onAddToItinerary(date)
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .task {
            guard item.price != nil, quickAssignedTravelerId == nil else { return }
            do {
                let split = try await APIClient.shared.getSplit(tripId: tripId, itemId: item.id)
                if split.splitType == "assigned", let id = split.assignedTravelerId {
                    quickAssignedTravelerId = id
                    quickAssignedName = split.shares.first?.travelerName
                }
            } catch {}
        }
    }

    private var badgeTraveler: Traveler? {
        if let id = quickAssignedTravelerId {
            return travelers.first { $0.id == id } ?? matchedTraveler
        }
        return matchedTraveler
    }

    private var matchedTraveler: Traveler? {
        guard let name = item.travelerName else { return nil }
        return travelers.first { $0.name == name }
    }

    private func quickAssign(to traveler: Traveler) async {
        do {
            _ = try await APIClient.shared.upsertSplit(
                tripId: tripId,
                itemId: item.id,
                splitType: "assigned",
                assignedTravelerId: traveler.id,
                travelerIds: nil
            )
            quickAssignedTravelerId = traveler.id
            quickAssignedName = traveler.name
        } catch {}
    }

    private func quickUnassign() async {
        do {
            try await APIClient.shared.deleteSplit(tripId: tripId, itemId: item.id)
            quickAssignedTravelerId = nil
            quickAssignedName = nil
        } catch {}
    }

    private var routeSummary: some View {
        HStack(spacing: 6) {
            if let from = item.location.airportCode {
                Text(from)
                    .font(.caption)
                    .fontWeight(.medium)
            } else if let name = item.location.name {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if item.endLocation?.airportCode != nil || item.endLocation?.name != nil {
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let to = item.endLocation?.airportCode {
                    Text(to)
                        .font(.caption)
                        .fontWeight(.medium)
                } else if let name = item.endLocation?.name {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if item.legs.count > 1 {
                Text("·")
                    .foregroundStyle(.secondary)
                Text("\(item.legs.count - 1) stop\(item.legs.count - 1 > 1 ? "s" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                } else if let depName = leg.departureLocation.name, let arrName = leg.arrivalLocation.name {
                    Text("\(depName) → \(arrName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let start = leg.startTime {
                    Text(FlexibleDateFormatter.displayString(start))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let end = leg.endTime {
                    Text("Arr: \(FlexibleDateFormatter.displayString(end))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let seat = leg.seat {
                Text(seat)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
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

private func colorFor(_ hex: String?) -> Color {
    guard let hex else { return .blue }
    let sanitized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard sanitized.count == 6, let int = UInt32(sanitized, radix: 16) else { return .blue }
    return Color(
        red: Double((int >> 16) & 0xFF) / 255,
        green: Double((int >> 8) & 0xFF) / 255,
        blue: Double(int & 0xFF) / 255
    )
}
