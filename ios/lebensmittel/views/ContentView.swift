//
//  ContentView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct ContentView: View {
	@Environment(AuthStateManager.self) var authManager

	var body: some View {
		TabView {
			Tab("Groceries", systemImage: "list.bullet") {
				if authManager.isAuthenticated {
					GroceriesView()
				} else {
					SignInPromptView(
						icon: "list.bullet",
						title: "Grocery List",
						reason: "Sign in and join a household group to manage your shared grocery list."
					)
				}
			}

			Tab("Meals", systemImage: "calendar") {
				if authManager.isAuthenticated {
					MealsView()
				} else {
					SignInPromptView(
						icon: "calendar",
						title: "Meal Planning",
						reason: "Sign in and join a household group to plan meals together."
					)
				}
			}

			Tab("Shopping", systemImage: "cart") {
				if authManager.isAuthenticated {
					ShoppingView()
				} else {
					SignInPromptView(
						icon: "cart",
						title: "Shopping List",
						reason: "Sign in and join a household group to see your shared shopping list and submit receipts."
					)
				}
			}

			Tab("Receipts", systemImage: "receipt") {
				if authManager.isAuthenticated {
					ReceiptsView()
				} else {
					SignInPromptView(
						icon: "receipt",
						title: "Receipts",
						reason: "Sign in and join a household group to track shared household spending."
					)
				}
			}
		}
	}
}

// MARK: - Sign-In Prompt

struct SignInPromptView: View {
	@Environment(AuthStateManager.self) var authManager
	@State private var showLoginSheet = false

	let icon: String
	let title: String
	let reason: String

	var body: some View {
		NavigationStack {
			VStack(spacing: 24) {
				Spacer()

				Image(systemName: icon)
					.font(.system(size: 56))
					.foregroundStyle(.blue.opacity(0.8))

				VStack(spacing: 8) {
					Text(title)
						.font(.title2)
						.fontWeight(.semibold)

					Text(reason)
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
						.padding(.horizontal, 40)
				}

				VStack(spacing: 12) {
					Button {
						showLoginSheet = true
					} label: {
						Text("Sign In")
							.font(.headline)
							.frame(maxWidth: .infinity)
							.padding()
							.background(Color.blue)
							.foregroundStyle(.white)
							.clipShape(.rect(cornerRadius: 12))
					}
					.padding(.horizontal, 40)

					Button {
						showLoginSheet = true
					} label: {
						Text("Create Account")
							.font(.subheadline)
							.foregroundStyle(.blue)
					}
				}

				Spacer()

				Text("An account and household group are required\nto create or edit any data.")
					.font(.caption)
					.foregroundStyle(.tertiary)
					.multilineTextAlignment(.center)
					.padding(.bottom, 24)
			}
			.navigationTitle(title)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					AuthMenuView()
				}
			}
		}
		.sheet(isPresented: $showLoginSheet) {
			LoginView(authManager: authManager)
		}
	}
}
