import PhotosUI
import SwiftUI
import Vision
import VisionKit

struct AddExpenseSheet: View {
    let tripId: String
    let travelers: [Traveler]
    let onCreate: (ItineraryItem) -> Void
    let onClose: () -> Void

    @State private var title = ""
    @State private var amount = ""
    @State private var date = Date()
    @State private var selectedTravelerId: String?
    @State private var notes = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var receiptImage: UIImage?
    @State private var showDocumentScanner = false
    @State private var showPhotoPicker = false
    @State private var isScanning = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let client = APIClient.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Traveler") {
                    Picker("Paid by", selection: $selectedTravelerId) {
                        Text("None").tag(nil as String?)
                        ForEach(travelers) { traveler in
                            Text(traveler.name).tag(traveler.id as String?)
                        }
                    }
                }

                Section("Receipt") {
                    HStack {
                        Button {
                            showDocumentScanner = true
                        } label: {
                            Label("Scan", systemImage: "doc.text.viewfinder")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            showPhotoPicker = true
                        } label: {
                            Label("Library", systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(.bordered)
                    }

                    if let image = receiptImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        if !isScanning {
                            Button {
                                Task { await scanReceipt() }
                            } label: {
                                Label("Extract details", systemImage: "text.viewfinder")
                            }
                        } else {
                            HStack {
                                ProgressView()
                                Text("Scanning receipt...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await save() }
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .overlay {
                if isSaving { ProgressView() }
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
            .onChange(of: selectedPhoto) { _, newItem in
                Task { await loadReceiptImage(from: newItem) }
            }
            .fullScreenCover(isPresented: $showDocumentScanner) {
                DocumentScanner { image in
                    receiptImage = image
                    showDocumentScanner = false
                }
                .ignoresSafeArea()
            }
        }
    }

    private func loadReceiptImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            receiptImage = image
        }
    }

    private func scanReceipt() async {
        guard let image = receiptImage,
              let cgImage = image.cgImage else { return }
        isScanning = true
        defer { isScanning = false }

        let recognized = await recognizeText(in: cgImage)
        guard !recognized.isEmpty else {
            errorMessage = "No text found in receipt image."
            return
        }

        do {
            let items: [ItineraryItem] = try await client.uploadMultipart(
                "trips/\(tripId)/items/extract",
                textContent: recognized
            )
            if let first = items.first {
                title = first.title.isEmpty ? title : first.title
                amount = first.price ?? amount
                if let travelerName = first.travelerName {
                    if let match = travelers.first(where: { $0.name == travelerName }) {
                        selectedTravelerId = match.id
                    }
                }
            }
        } catch {
            if !error.isCancellationError {
                errorMessage = "Extraction failed: \(error.localizedDescription)"
            }
        }
    }

    private func recognizeText(in cgImage: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedAmount = amount.trimmingCharacters(in: .whitespaces)

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let startTime = isoFormatter.string(from: date)

        let body = CreateExpenseBody(
            itemType: .expense,
            title: trimmedTitle,
            price: trimmedAmount.isEmpty ? nil : trimmedAmount,
            travelerName: selectedTravelerId.flatMap { id in
                travelers.first(where: { $0.id == id })?.name
            },
            startTime: startTime,
            details: DetailsBody(
                seat: nil,
                gate: nil,
                roomType: nil,
                notes: nOrEmpty(notes)
            )
        )

        do {
            let item: ItineraryItem = try await client.request(
                "POST", "trips/\(tripId)/items", body: body
            )
            onCreate(item)
            onClose()
        } catch {
            if error.isCancellationError { return }
            errorMessage = error.localizedDescription
        }
    }

    private func nOrEmpty(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }
}

struct CreateExpenseBody: Encodable {
    let itemType: ItemType
    let title: String
    let price: String?
    let travelerName: String?
    let startTime: String?
    let details: DetailsBody

    enum CodingKeys: String, CodingKey {
        case title, price, details
        case itemType = "item_type"
        case travelerName = "traveler_name"
        case startTime = "start_time"
    }
}

struct DocumentScanner: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onCapture: (UIImage) -> Void

        init(onCapture: @escaping (UIImage) -> Void) {
            self.onCapture = onCapture
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            if scan.pageCount > 0 {
                onCapture(scan.imageOfPage(at: 0))
            }
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) {
            controller.dismiss(animated: true)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }
    }
}
