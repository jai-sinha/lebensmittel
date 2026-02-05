//
//  LoginModel.swift
//  lebensmittel
//
//  Created by Jai Sinha on 02/04/26.
//

import Foundation

@Observable
class LoginModel {
    var username = ""
    var password = ""
    var email = ""
    var displayName = ""
    var isLoading = false
    var isShowingRegister = false

    var isValidEmail: Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: email)
    }

    func login(authManager: AuthStateManager) {
        isLoading = true

        Task {
            do {
                _ = try await AuthManager.shared.login(
                    username: username,
                    password: password
                )
                await authManager.refreshState()
                await MainActor.run {
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    authManager.errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    func register(authManager: AuthStateManager) {
        isLoading = true

        Task {
            do {
                _ = try await AuthManager.shared.register(
                    username: username,
                    email: email,
                    password: password,
                    displayName: displayName
                )
                await authManager.refreshState()
                await MainActor.run {
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    authManager.errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}
