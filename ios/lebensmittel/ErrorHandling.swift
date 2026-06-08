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

		let nsError = error as NSError
		if nsError.domain == NSURLErrorDomain {
			return message(for: nsError)
		}

		let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
		return description.isEmpty ? "Something went wrong. Please try again." : description
	}

	static func message(for error: APIError) -> String {
		switch error {
		case .invalidURL, .invalidResponse, .encodingFailed, .unauthorized:
			return "Something went wrong. Please try again."
		case .server(_, let message):
			let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
			return trimmed.isEmpty ? "Something went wrong. Please try again." : trimmed
		case .transport(let underlyingError):
			return message(for: underlyingError)
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
