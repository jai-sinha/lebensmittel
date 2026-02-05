//
//  LoginView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 01/05/26.
//

import SwiftUI
import Foundation

struct LoginView: View {
    @State private var model = LoginModel()
    @Bindable var authManager: AuthStateManager

    var body: some View {
        NavigationStack {
            VStack {
                if model.isShowingRegister {
                    RegisterForm(model: model, authManager: authManager)
                } else {
                    LoginForm(model: model, authManager: authManager)
                }
            }
            .navigationTitle(model.isShowingRegister ? "Create Account" : "Login")
        }
    }
}

struct LoginForm: View {
    @Bindable var model: LoginModel
    @Bindable var authManager: AuthStateManager

    var body: some View {
        VStack(spacing: 16) {
            TextField("Username", text: $model.username)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Password", text: $model.password)
                .textFieldStyle(.roundedBorder)

            if let error = authManager.errorMessage, error != "No refresh token available" {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Button("Login") {
                model.login(authManager: authManager)
            }
            .disabled(model.username.isEmpty || model.password.isEmpty || model.isLoading)

            Button("Don't have an account? Sign up") {
                model.isShowingRegister = true
            }
            .foregroundColor(.blue)

            Spacer()
        }
        .padding()
    }
}

struct RegisterForm: View {
    @Bindable var model: LoginModel
    @Bindable var authManager: AuthStateManager

    var body: some View {
        VStack(spacing: 16) {
            TextField("Display Name", text: $model.displayName)
                .textFieldStyle(.roundedBorder)

            TextField("Email", text: $model.email)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .overlay(
                    HStack {
                        Spacer()
                        if !model.email.isEmpty && !model.isValidEmail {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.red)
                                .padding(.trailing, 8)
                        }
                    }
                )

            TextField("Username", text: $model.username)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Password", text: $model.password)
                .textFieldStyle(.roundedBorder)

            if let error = authManager.errorMessage, error != "No refresh token available" {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Button("Create Account") {
                model.register(authManager: authManager)
            }
            .disabled(model.username.isEmpty || !model.isValidEmail || model.password.isEmpty || model.displayName.isEmpty || model.isLoading)

            Button("Already have an account? Login") {
                model.isShowingRegister = false
            }
            .foregroundColor(.blue)

            Spacer()
        }
        .padding()
    }
}
