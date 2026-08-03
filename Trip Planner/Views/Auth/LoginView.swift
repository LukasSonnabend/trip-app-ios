import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var showSignup = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)

                    Text("Trip Planner")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Your travel itinerary, always with you")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 48)

                VStack(spacing: 16) {
                    TextField("Email", text: $authVM.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .textFieldStyle(.roundedBorder)

                    SecureField("Password", text: $authVM.password)
                        .textContentType(.password)
                        .textFieldStyle(.roundedBorder)

                    if let error = authVM.errorMessage {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task { await authVM.login() }
                    } label: {
                        if authVM.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Log In")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(authVM.isLoading)

                    Button("Create Account") {
                        showSignup = true
                    }
                    .font(.callout)
                }
                .padding(.horizontal, 32)

                Spacer()
            }
            .sheet(isPresented: $showSignup) {
                SignupView()
            }
        }
    }
}

struct SignupView: View {
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Create Account")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top, 24)

                VStack(spacing: 12) {
                    TextField("Name (optional)", text: $authVM.name)
                        .textContentType(.name)
                        .textFieldStyle(.roundedBorder)

                    TextField("Email", text: $authVM.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .textFieldStyle(.roundedBorder)

                    SecureField("Password (min 8 characters)", text: $authVM.password)
                        .textContentType(.newPassword)
                        .textFieldStyle(.roundedBorder)

                    if let error = authVM.errorMessage {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task { await authVM.signup() }
                    } label: {
                        if authVM.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Sign Up")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(authVM.isLoading)
                }
                .padding(.horizontal, 32)

                Spacer()
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
}
