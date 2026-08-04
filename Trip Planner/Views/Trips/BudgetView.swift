import SwiftUI

struct BudgetView: View {
    let tripId: String
    let tripName: String

    @StateObject private var vm = BudgetViewModel()
    @StateObject private var travelersVM = TravelersViewModel()

    private let client = APIClient.shared

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView()
            } else if let budget = vm.budget {
                budgetContent(budget)
            } else if let error = vm.errorMessage {
                ContentUnavailableView(
                    "Could not load budget",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ContentUnavailableView(
                    "No budget data",
                    systemImage: "chart.pie",
                    description: Text("Add some items with prices to see a cost breakdown.")
                )
            }
        }
        .navigationTitle("Budget")
        .task { await vm.loadBudget(tripId: tripId) }
        .task { await travelersVM.loadTravelers(tripId: tripId) }
    }

    @ViewBuilder
    private func budgetContent(_ budget: BudgetResponse) -> some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Total Trip Cost")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(budget.total)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)

                if budget.unsplitTotal != "0.00" {
                    LabeledContent("Unsplit", value: budget.unsplitTotal)
                        .foregroundStyle(.secondary)
                }
            }

            if !budget.perTraveler.isEmpty {
                ForEach(budget.perTraveler) { tb in
                    Section {
                        VStack(spacing: 8) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(colorFor(tb.travelerId))
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        Text(String(tb.travelerName.prefix(1).uppercased()))
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.white)
                                    }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tb.travelerName)
                                        .font(.headline)
                                    Text("\(tb.itemCount) item\(tb.itemCount == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(tb.total)
                                        .font(.headline)
                                        .fontWeight(.bold)
                                    HStack(spacing: 8) {
                                        Text("paid \(tb.paid)")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                        Text("·")
                                            .foregroundStyle(.secondary)
                                        Text("unpaid \(tb.unpaid)")
                                            .font(.caption2)
                                            .foregroundStyle(unpaidColor(tb.unpaid))
                                    }
                                }
                            }
                        }

                        ForEach(tb.items) { item in
                            HStack(spacing: 12) {
                                Image(systemName: iconFor(item.itemType))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.itemTitle)
                                        .font(.callout)
                                        .lineLimit(1)
                                    if let price = item.price {
                                        Text("\(price)  ·  \(item.shareAmount) share")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                if item.isPaid {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.callout)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                if item.isPaid {
                                    Button {
                                        Task { await togglePaid(item: item, isPaid: false) }
                                    } label: {
                                        Label("Unpay", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(.orange)
                                } else {
                                    Button {
                                        Task { await togglePaid(item: item, isPaid: true) }
                                    } label: {
                                        Label("Pay", systemImage: "checkmark")
                                    }
                                    .tint(.green)
                                }
                            }
                        }
                    } header: {
                        EmptyView()
                    }
                }
            } else {
                Section {
                    Text("No travelers added yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func togglePaid(item: BudgetItem, isPaid: Bool) async {
        do {
            _ = try await client.toggleSharePaid(
                tripId: tripId, itemId: item.itemId, shareId: item.shareId, isPaid: isPaid
            )
            await vm.loadBudget(tripId: tripId)
        } catch {}
    }

    private func unpaidColor(_ unpaid: String) -> Color {
        let value = Double(unpaid) ?? 0
        return value > 0 ? .orange : .green
    }

    private func colorFor(_ travelerId: String) -> Color {
        guard let hex = travelersVM.travelers.first(where: { $0.id == travelerId })?.color
        else { return .blue }
        let sanitized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard sanitized.count == 6, let int = UInt32(sanitized, radix: 16) else { return .blue }
        return Color(
            red: Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8) & 0xFF) / 255,
            blue: Double(int & 0xFF) / 255
        )
    }

    private func iconFor(_ type: String) -> String {
        switch type {
        case "FLIGHT": return "airplane"
        case "HOTEL": return "bed.double"
        case "RENTAL_CAR": return "car"
        case "RESTAURANT": return "fork.knife"
        case "TRAIN": return "tram"
        case "EVENT": return "calendar"
        default: return "mappin"
        }
    }
}
