import SwiftUI

struct SplitConfigSheet: View {
    let tripId: String
    let item: ItineraryItem
    let onDismiss: () -> Void

    @ObservedObject var travelersVM: TravelersViewModel

    @State private var split: ExpenseSplit?
    @State private var splitType = "equal"
    @State private var assignedTravelerId: String?
    @State private var selectedTravelerIds = Set<String>()
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let client = APIClient.shared

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                Section {
                    if let price = item.price {
                        LabeledContent("Item Price", value: price)
                            .fontWeight(.semibold)
                    }
                    if let traveler = item.travelerName {
                        LabeledContent("Traveler", value: traveler)
                    }
                }

                Section("Split Type") {
                    Picker("Split Type", selection: $splitType) {
                        Text("Split Equally").tag("equal")
                        Text("Assign to One").tag("assigned")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: splitType) { _, _ in
                        selectedTravelerIds.removeAll()
                    }
                }

                Section {
                    switch splitType {
                    case "assigned":
                        assignedPicker
                    case "equal":
                        equalPickerHeader
                        equalPicker
                    default:
                        EmptyView()
                    }
                }

                if !selectedTravelerIds.isEmpty || assignedTravelerId != nil {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(shareDescription)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let split, !split.shares.isEmpty {
                    Section("Paid") {
                        ForEach(split.shares) { share in
                            HStack(spacing: 12) {
                                travelerAvatar(for: share.travelerId)
                                Text(share.travelerName)
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { share.isPaid },
                                    set: { newValue in
                                        Task { await togglePaid(share: share, isPaid: newValue) }
                                    }
                                ))
                                .labelsHidden()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Split Cost")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    if split != nil {
                        Button("Remove", role: .destructive) {
                            Task {
                                isSaving = true
                                defer { isSaving = false }
                                do {
                                    try await client.deleteSplit(tripId: tripId, itemId: item.id)
                                    onDismiss()
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || (splitType == "assigned" && assignedTravelerId == nil) || (splitType == "equal" && selectedTravelerIds.count < 1))
                }
            }
            .task { await loadSplit() }
            .onAppear {
                Task { await travelersVM.loadTravelers(tripId: tripId) }
            }
        }
    }

    private var assignedPicker: some View {
        ForEach(travelersVM.travelers) { traveler in
            HStack(spacing: 12) {
                travelerAvatar(for: traveler.id)
                Text(traveler.name)
                Spacer()
                if assignedTravelerId == traveler.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { assignedTravelerId = traveler.id }
        }
    }

    private var equalPickerHeader: some View {
        HStack {
            Text("Travelers")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Select All") {
                selectedTravelerIds = Set(travelersVM.travelers.map { $0.id })
            }
            .font(.caption)
            .disabled(selectedTravelerIds.count == travelersVM.travelers.count)
        }
    }

    private var equalPicker: some View {
        ForEach(travelersVM.travelers) { traveler in
            HStack(spacing: 12) {
                travelerAvatar(for: traveler.id)
                Text(traveler.name)
                Spacer()
                if selectedTravelerIds.contains(traveler.id) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if selectedTravelerIds.contains(traveler.id) {
                    selectedTravelerIds.remove(traveler.id)
                } else {
                    selectedTravelerIds.insert(traveler.id)
                }
            }
        }
    }

    private var shareDescription: String {
        guard let priceStr = item.price else { return "No price set" }
        let digits = priceStr.filter { $0.isNumber || $0 == "." }
        guard let price = Double(digits) else { return priceStr }

        if splitType == "assigned" {
            if let id = assignedTravelerId,
               let traveler = travelersVM.travelers.first(where: { $0.id == id }) {
                return "\(traveler.name) pays \(priceStr)"
            }
            return ""
        }

        let count = selectedTravelerIds.count
        guard count > 0 else { return "" }
        let share = price / Double(count)
        let names = travelersVM.travelers
            .filter { selectedTravelerIds.contains($0.id) }
            .map { $0.name }
            .joined(separator: ", ")

        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let shareStr = formatter.string(from: NSNumber(value: share)) ?? String(format: "%.2f", share)

        let currencyPrefix = String(priceStr.prefix { !$0.isNumber && $0 != "." })
        return "\(names) pay \(currencyPrefix)\(shareStr) each"
    }

    private func travelerAvatar(for travelerId: String) -> some View {
        let traveler = travelersVM.travelers.first { $0.id == travelerId }
        return Circle()
            .fill(colorFor(traveler?.color))
            .frame(width: 28, height: 28)
            .overlay {
                Text(String((traveler?.name ?? "?").prefix(1).uppercased()))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }
    }

    private func loadSplit() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let existing = try await client.getSplit(tripId: tripId, itemId: item.id)
            split = existing
            splitType = existing.splitType
            if existing.splitType == "assigned" {
                assignedTravelerId = existing.assignedTravelerId
            } else {
                selectedTravelerIds = Set(existing.shares.map { $0.travelerId })
            }
        } catch APIError.notFound {
            split = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let travelerIds: [String]? = splitType == "equal" ? Array(selectedTravelerIds) : nil
            _ = try await client.upsertSplit(
                tripId: tripId,
                itemId: item.id,
                splitType: splitType,
                assignedTravelerId: assignedTravelerId,
                travelerIds: travelerIds
            )
            onDismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func togglePaid(share: ExpenseShare, isPaid: Bool) async {
        do {
            _ = try await client.toggleSharePaid(
                tripId: tripId, itemId: item.id, shareId: share.id, isPaid: isPaid
            )
            let updated = try await client.getSplit(tripId: tripId, itemId: item.id)
            split = updated
        } catch {
            errorMessage = error.localizedDescription
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
}
