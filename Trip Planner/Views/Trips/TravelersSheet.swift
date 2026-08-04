import SwiftUI

struct TravelersSheet: View {
    let tripId: String
    let onDismiss: () -> Void

    @ObservedObject var travelersVM: TravelersViewModel

    @State private var newTravelerName = ""
    @State private var editingTraveler: Traveler?
    @State private var editName = ""
    @State private var selectedColor = "#4A90D9"

    private let palette: [(String, Color)] = [
        ("#4A90D9", .blue),
        ("#E85D75", .pink),
        ("#58C4A8", .green),
        ("#F5A623", .orange),
        ("#7B61FF", .purple),
        ("#50C878", .mint),
        ("#FF6B6B", .red),
        ("#45B7D1", .cyan),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        TextField("Traveler name", text: $newTravelerName)
                            .textInputAutocapitalization(.words)
                        if !newTravelerName.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button("Add") {
                                addTraveler()
                            }
                            .fontWeight(.semibold)
                        }
                    }
                }

                Section {
                    if travelersVM.travelers.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "person.3")
                                    .font(.title)
                                    .foregroundStyle(.secondary)
                                Text("No travelers yet")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 20)
                            Spacer()
                        }
                    } else {
                        ForEach(travelersVM.travelers) { traveler in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(colorFor(traveler.color))
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        Text(String(traveler.name.prefix(1).uppercased()))
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.white)
                                    }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(traveler.name)
                                        .font(.body)
                                    if traveler.userId != nil {
                                        Text("Linked to account")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingTraveler = traveler
                                editName = traveler.name
                                selectedColor = traveler.color ?? "#4A90D9"
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                let traveler = travelersVM.travelers[index]
                                Task { await travelersVM.deleteTraveler(tripId: tripId, travelerId: traveler.id) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Travelers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss() }
                }
            }
            .sheet(item: $editingTraveler) { traveler in
                editView(for: traveler)
            }
            .task {
                await travelersVM.loadTravelers(tripId: tripId)
            }
        }
    }

    private func addTraveler() {
        let name = newTravelerName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        newTravelerName = ""
        Task {
            await travelersVM.addTraveler(tripId: tripId, name: name, color: selectedColor)
        }
    }

    @ViewBuilder
    private func editView(for traveler: Traveler) -> some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $editName)
                        .textInputAutocapitalization(.words)
                }
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        ForEach(palette, id: \.0) { hex, color in
                            Circle()
                                .fill(color)
                                .frame(width: 40, height: 40)
                                .overlay {
                                    if hex == selectedColor {
                                        Image(systemName: "checkmark")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { selectedColor = hex }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Edit Traveler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingTraveler = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let name = editName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        let color = selectedColor
                        let travelerId = traveler.id
                        editingTraveler = nil
                        Task {
                            await travelersVM.updateTraveler(tripId: tripId, travelerId: travelerId, name: name, color: color)
                        }
                    }
                }
            }
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
