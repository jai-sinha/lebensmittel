//
//  ErrorHandling.swift
//  lebensmittel
//
//  Created by Jai Sinha on 04/09/26.
//

import Foundation

enum UserFacingError {
	static func message(for error: Error) -> String {
		if let apiError = error as? APIError {
			return message(for: apiError)
		}

		if let authError = error as? AuthManager.AuthError {
			return message(for: authError)
		}

		let nsError = error as NSError
		if nsError.domain == NSURLErrorDomain {
			return message(for: nsError)
		}

		let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
		return description.isEmpty ? "Something went wrong. Please try again." : description
	}

	static func message(for error: APIError) -> String {
		switch error {
		case .invalidURL, .invalidResponse, .encodingFailed:
			return "Something went wrong. Please try again."
		case .unauthorized:
			return "Your session expired. Please sign in again."
		case .server(_, let message):
			let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
			return trimmed.isEmpty ? "Something went wrong. Please try again." : trimmed
		case .transport(let underlyingError):
			return message(for: underlyingError)
		}
	}

	static func message(for error: AuthManager.AuthError) -> String {
		switch error {
		case .noRefreshToken, .notAuthenticated:
			return "Please sign in to continue."
		case .refreshFailed:
			return "Your session expired. Please sign in again."
		case .invalidResponse:
			return "Something went wrong. Please try again."
		case .usernameTaken:
			return "That username is already taken."
		case .networkError(let message):
			let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
			return trimmed.isEmpty ? "Something went wrong. Please try again." : trimmed
		}
	}

	private static func message(for error: NSError) -> String {
		switch error.code {
		case NSURLErrorNotConnectedToInternet:
			return "You're offline. Check your internet connection and try again."
		case NSURLErrorTimedOut:
			return "The request timed out. Please try again."
		case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost,
			NSURLErrorNetworkConnectionLost:
			return "Couldn't reach the server. Please try again."
		case NSURLErrorUserAuthenticationRequired, NSURLErrorUserCancelledAuthentication:
			return "Please sign in to continue."
		default:
			return "Something went wrong. Please try again."
		}
	}
}

enum DebugLogger {
	static let isEnabled = true

	static func log(_ message: @autoclosure () -> String) {
		guard isEnabled else { return }
		print(message())
	}

	static func log(error: Error, context: String) {
		guard isEnabled else { return }
		print("[\(context)] \(error)")
	}
}
