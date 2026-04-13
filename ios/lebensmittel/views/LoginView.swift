//
//  LoginView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 01/05/26.
//

import Foundation
import SwiftUI

struct LoginView: View {
	@State private var model: LoginModel
	@Bindable var sessionManager: SessionManager
	@Environment(\.dismiss) private var dismiss

	init(sessionManager: SessionManager, startWithRegister: Bool = false) {
		self.sessionManager = sessionManager
		let m = LoginModel()
		m.isShowingRegister = startWithRegister
		_model = State(initialValue: m)
	}

	var body: some View {
		NavigationStack {
			VStack {
				if model.isShowingRegister {
					RegisterForm(
						model: model, sessionManager: sessionManager, onSuccess: { dismiss() })
				} else {
					LoginForm(
						model: model, sessionManager: sessionManager, onSuccess: { dismiss() })
				}
			}
			.navigationTitle(model.isShowingRegister ? "Create Account" : "Sign In")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					Button("Cancel") {
						dismiss()
					}
				}
			}
		}
	}
}

struct LoginForm: View {
	@Bindable var model: LoginModel
	@Bindable var sessionManager: SessionManager
	var onSuccess: (() -> Void)? = nil

	var body: some View {
		VStack(spacing: 16) {
			TextField("Username", text: $model.username)
				.textFieldStyle(.roundedBorder)
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled()

			SecureField("Password", text: $model.password)
				.textFieldStyle(.roundedBorder)

			if let error = sessionManager.errorMessage, error != "No refresh token available" {
				Text(error)
					.foregroundColor(.red)
					.font(.caption)
			}

			Button("Sign In") {
				model.login(sessionManager: sessionManager, onSuccess: onSuccess)
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
	@Bindable var sessionManager: SessionManager
	var onSuccess: (() -> Void)? = nil

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

			if let error = sessionManager.errorMessage, error != "No refresh token available" {
				Text(error)
					.foregroundColor(.red)
					.font(.caption)
			}

			Button("Create Account") {
				model.register(sessionManager: sessionManager, onSuccess: onSuccess)
			}
			.disabled(
				model.username.isEmpty || !model.isValidEmail || model.password.isEmpty
					|| model.displayName.isEmpty || model.isLoading)

			Button("Already have an account? Sign in") {
				model.isShowingRegister = false
			}
			.foregroundColor(.blue)

			Spacer()
		}
		.padding()
	}
}
