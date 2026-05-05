//
//  GuestHomeView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 03/06/26.
//

import SwiftUI

struct GuestHomeView: View {
	@Bindable var sessionManager: SessionManager
	@State private var showLoginSheet = false
	@State private var startWithRegister = false

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 12) {
					// MARK: - App Introduction
					Text("Lebensmittel")
						.font(.largeTitle)
						.fontWeight(.bold)
                        .padding(.vertical, 8)

					// MARK: - Feature Highlights
					VStack(spacing: 12) {
						FeatureRow(
							icon: "cart",
							color: .yellow,
							title: "Shared Grocery Lists",
							description:
								"Keep track of what your household needs by category."
						)
						FeatureRow(
							icon: "calendar",
							color: .orange,
							title: "Meal Planning",
							description:
								"Plan meals together so everyone knows what's for dinner."
						)
						FeatureRow(
							icon: "list.bullet",
							color: .green,
							title: "Smart Shopping",
							description:
								"Check off items as you shop, then submit a receipt in one tap."
						)
						FeatureRow(
							icon: "receipt",
							color: .purple,
							title: "Receipt Tracking",
							description:
								"See who spent what each month and keep bills in one place."
						)
					}
					.padding(.horizontal, 20)

					// MARK: - Account Notice
					VStack(spacing: 8) {
						Text(
							"An account and household group are required to create or edit any data, since all content is shared and synced with your group in real time."
						)
						.font(.footnote)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
						.padding(.horizontal, 32)
						if let url = URL(string: "https://ls.jsinha.com/privacy") {
							Link("Privacy Policy", destination: url)
								.font(.footnote)
								.foregroundStyle(.blue)
						}
					}
					.padding(.vertical, 8)

					// MARK: - CTAs
					VStack(spacing: 12) {
						Button {
							startWithRegister = false
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

						Button {
							startWithRegister = true
							showLoginSheet = true
						} label: {
							Text("Create Account")
								.font(.headline)
								.frame(maxWidth: .infinity)
								.padding()
								.background(Color(.secondarySystemBackground))
								.foregroundStyle(.blue)
								.clipShape(.rect(cornerRadius: 12))
								.overlay(
									RoundedRectangle(cornerRadius: 12)
										.stroke(Color.blue.opacity(0.4), lineWidth: 1)
								)
						}
					}
                    .padding(.horizontal, 24)

					// MARK: - Guest Bypass
					Button {
						sessionManager.continueAsGuest()
					} label: {
						Text("Continue without signing in")
							.font(.subheadline)
							.foregroundStyle(.blue)
					}
                    .padding(.vertical, 4)

					Spacer().frame(height: 32)
				}
			}
			.navigationBarTitleDisplayMode(.inline)
		}
		.sheet(isPresented: $showLoginSheet) {
			LoginView(sessionManager: sessionManager, startWithRegister: startWithRegister)
		}
	}
}

// MARK: - Supporting Views

struct FeatureRow: View {
	let icon: String
	let color: Color
	let title: String
	let description: String

	var body: some View {
		HStack(alignment: .center, spacing: 16) {
			Image(systemName: icon)
				.font(.title2)
				.foregroundStyle(color)
				.frame(width: 36)

			VStack(alignment: .leading, spacing: 4) {
				Text(title)
					.font(.headline)
				Text(description)
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}

			Spacer()
		}
		.padding(16)
		.background(Color(.secondarySystemBackground))
		.clipShape(.rect(cornerRadius: 12))
	}
}

#Preview {
	GuestHomeView(sessionManager: SessionManager())
}
