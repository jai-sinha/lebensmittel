//
//  LoginView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/16/25.
//

import SwiftUI

struct LoginView: View {
    @State private var isShowingRegister = false
    @Bindable var authManager: AuthStateManager

    var body: some View {
        NavigationStack {
            VStack {
                if isShowingRegister {
                    RegisterForm(authManager: authManager, isShowingRegister: $isShowingRegister)
                } else {
                    LoginForm(authManager: authManager, isShowingRegister: $isShowingRegister)
                }
            }
            .navigationTitle(isShowingRegister ? "Create Account" : "Login")
        }
    }
}

struct LoginForm: View {
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @Bindable var authManager: AuthStateManager
    @Binding var isShowingRegister: Bool

    var body: some View {
        VStack(spacing: 16) {
            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)

            if let error = authManager.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Button("Login") {
                isLoading = true
                Task {
                    do {
                        let (user, _) = try await AuthManager.shared.login(
                            username: username,
                            password: password
                        )
                        await MainActor.run {
                            authManager.isAuthenticated = true
                            authManager.currentUser = user
                            authManager.errorMessage = nil
                        }
                    } catch {
                        await MainActor.run {
                            authManager.errorMessage = error.localizedDescription
                            isLoading = false
                        }
                    }
                }
            }
            .disabled(username.isEmpty || password.isEmpty || isLoading)

            Button("Don't have an account? Sign up") {
                isShowingRegister = true
            }
            .foregroundColor(.blue)

            Spacer()
        }
        .padding()
    }
}

struct RegisterForm: View {
    @State private var username = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isLoading = false
    @Bindable var authManager: AuthStateManager
    @Binding var isShowingRegister: Bool

    var body: some View {
        VStack(spacing: 16) {
            TextField("Display Name", text: $displayName)
                .textFieldStyle(.roundedBorder)

            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)

            if let error = authManager.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Button("Create Account") {
                isLoading = true
                Task {
                    do {
                        let (user, _) = try await AuthManager.shared.register(
                            username: username,
                            password: password,
                            displayName: displayName
                        )
                        await MainActor.run {
                            authManager.isAuthenticated = true
                            authManager.currentUser = user
                            authManager.errorMessage = nil
                        }
                    } catch {
                        await MainActor.run {
                            authManager.errorMessage = error.localizedDescription
                            isLoading = false
                        }
                    }
                }
            }
            .disabled(username.isEmpty || password.isEmpty || displayName.isEmpty || isLoading)

            Button("Already have an account? Login") {
                isShowingRegister = false
            }
            .foregroundColor(.blue)

            Spacer()
        }
        .padding()
    }
}
