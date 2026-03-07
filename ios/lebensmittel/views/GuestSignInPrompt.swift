//
//  GuestSignInPrompt.swift
//  lebensmittel
//
//  Created by Jai Sinha on 03/06/26.
//

import SwiftUI

/// Inline prompt shown inside feature tabs when the user is browsing as a guest.
/// Offers Sign In and Create Account actions, and a way back to the welcome screen.
struct GuestSignInPrompt: View {
    @Environment(AuthStateManager.self) var authManager
    @State private var showLoginSheet = false
    @State private var startWithRegister = false

    let message: String

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.circle")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Sign In Required")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

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
                .padding(.horizontal, 40)

                Button {
                    startWithRegister = true
                    showLoginSheet = true
                } label: {
                    Text("Create Account")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            }

            Spacer()

            Button {
                authManager.exitGuestMode()
            } label: {
                Text("Back to Welcome Screen")
                    .font(.footnote)
                    .foregroundStyle(.blue)
            }
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView(authManager: authManager, startWithRegister: startWithRegister)
        }
    }
}

#Preview {
    GuestSignInPrompt(message: "Sign in and join a household group to manage your shared grocery list.")
        .environment(AuthStateManager())
}
