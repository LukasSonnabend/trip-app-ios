import Combine
import SwiftUI

struct InvitePreviewView: View {
    let code: String

    @StateObject private var viewModel = InvitePreviewViewModel()
    @State private var showHasAccepted = false
    @State private var showError = false
    @State private var errorDetail = ""

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading invite...")
                } else if let preview = viewModel.preview {
                    VStack(spacing: 24) {
                        Image(systemName: "envelope.badge.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.tint)

                        Text("You've been invited to")
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        Text(preview.tripName)
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        HStack {
                            Label("\(preview.memberCount) member\(preview.memberCount == 1 ? "" : "s")", systemImage: "person.2")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        if preview.alreadyAMember {
                            Text("You're already a member of this trip")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                        } else {
                            Button {
                                Task { await viewModel.acceptInvite(code: code) }
                            } label: {
                                if viewModel.isAccepting {
                                    ProgressView()
                                } else {
                                    Text("Join Trip")
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .padding(.horizontal, 48)
                            .disabled(viewModel.isAccepting)
                        }
                    }
                    .padding()
                } else if let error = viewModel.errorMessage {
                    ContentUnavailableView(
                        "Couldn't Load Invite",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                }
            }
            .navigationTitle("Invite")
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Joined!", isPresented: $showHasAccepted) {
                Button("OK") { }
            } message: {
                if let name = viewModel.acceptedTripName {
                    Text("You're now a member of \(name)")
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorDetail)
            }
            .onChange(of: viewModel.hasAccepted) { _, accepted in
                if accepted { showHasAccepted = true }
            }
            .onChange(of: viewModel.errorMessage) { _, error in
                if let error {
                    errorDetail = error
                    showError = true
                }
            }
            .task { await viewModel.loadPreview(code: code) }
        }
    }
}

@MainActor
final class InvitePreviewViewModel: ObservableObject {
    @Published var preview: InvitePreview?
    @Published var isLoading = true
    @Published var isAccepting = false
    @Published var errorMessage: String?
    @Published var hasAccepted = false
    @Published var acceptedTripName: String?

    private let client = APIClient.shared

    func loadPreview(code: String) async {
        isLoading = true
        errorMessage = nil
        do {
            preview = try await client.request("GET", "invites/\(code)")
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func acceptInvite(code: String) async {
        isAccepting = true
        do {
            let response: AcceptInviteResponse = try await client.request("POST", "invites/\(code)/accept")
            acceptedTripName = response.tripName
            hasAccepted = true
            preview?.alreadyAMember = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isAccepting = false
    }
}

#Preview {
    InvitePreviewView(code: "ABC123")
}
