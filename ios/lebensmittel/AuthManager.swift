//
//  AuthManager.swift
//  lebensmittel
//
//  Created by Jai Sinha on 01/02/26.
//

import Foundation

// MARK: - Auth Storage

actor AuthStorage {
	private let keychain = KeychainService()
	private let tokensKey = "tokens"
	private let userKey = "user"

	private var cachedTokens: Tokens?
	private var cachedUser: User?

	func loadTokens() throws -> Tokens? {
		if let cachedTokens {
			return cachedTokens
		}

		let tokens = try keychain.read(Tokens.self, forKey: tokensKey)
		cachedTokens = tokens
		return tokens
	}

	func loadUser() throws -> User? {
		if let cachedUser {
			return cachedUser
		}

		let user = try keychain.read(User.self, forKey: userKey)
		cachedUser = user
		return user
	}

	func saveTokens(_ tokens: Tokens) throws {
		cachedTokens = tokens
		try keychain.save(tokens, forKey: tokensKey)
	}

	func saveUser(_ user: User) throws {
		cachedUser = user
		try keychain.save(user, forKey: userKey)
	}

	func clearTokens() throws {
		cachedTokens = nil
		try keychain.delete(forKey: tokensKey)
	}

	func clearUser() throws {
		cachedUser = nil
		try keychain.delete(forKey: userKey)
	}
}

// MARK: - Auth API

struct AuthAPI {
	private let client: APIClient

	nonisolated init(client: APIClient) {
		self.client = client
	}

	func register(_ request: RegisterRequest) async throws -> AuthResponse {
		try await client.send(
			path: "/register",
			method: .POST,
			body: request,
			requiresAuth: false,
			includeGroupHeader: false
		)
	}

	func login(_ request: LoginRequest) async throws -> AuthResponse {
		try await client.send(
			path: "/login",
			method: .POST,
			body: request,
			requiresAuth: false,
			includeGroupHeader: false
		)
	}

	func refresh(_ request: RefreshRequest) async throws -> AuthResponse {
		try await client.send(
			path: "/refresh",
			method: .POST,
			body: request,
			requiresAuth: false,
			includeGroupHeader: false
		)
	}
}

// MARK: - Auth Manager

actor AuthManager {
	enum AuthError: Error, LocalizedError {
		case noRefreshToken
		case refreshFailed
		case notAuthenticated
		case invalidResponse
		case usernameTaken
		case networkError(String)

		var errorDescription: String? {
			switch self {
			case .noRefreshToken:
				return "No refresh token available"
			case .refreshFailed:
				return "Failed to refresh access token"
			case .notAuthenticated:
				return "User is not authenticated"
			case .invalidResponse:
				return "Invalid server response"
			case .usernameTaken:
				return "Username already taken"
			case .networkError(let msg):
				return "Network error: \(msg)"
			}
		}
	}

	static let shared = AuthManager()

	private let storage = AuthStorage()
	private var refreshTask: Task<Tokens, Error>?

	private var apiClient: APIClient {
		APIClient(authService: self)
	}

	private var authAPI: AuthAPI {
		AuthAPI(client: apiClient)
	}

	func register(username: String, email: String, password: String, displayName: String)
		async throws -> (User, Tokens)
	{
		let request = RegisterRequest(
			username: username,
			password: password,
			displayName: displayName,
			email: email
		)

		do {
			let authResponse = try await authAPI.register(request)
			let tokens = Tokens(
				accessToken: authResponse.accessToken,
				refreshToken: authResponse.refreshToken,
				expiresAt: authResponse.expiresAt
			)

			guard let user = authResponse.user else {
				throw AuthError.invalidResponse
			}

			try await storage.saveUser(user)
			try await storage.saveTokens(tokens)
			await GroupService.shared.clearActiveGroup()
			return (user, tokens)
		} catch let error as AuthError {
			throw error
		} catch {
			throw AuthError.networkError(error.localizedDescription)
		}
	}

	func login(username: String, password: String) async throws -> (User, Tokens) {
		let request = LoginRequest(username: username, password: password)

		do {
			let authResponse = try await authAPI.login(request)
			let tokens = Tokens(
				accessToken: authResponse.accessToken,
				refreshToken: authResponse.refreshToken,
				expiresAt: authResponse.expiresAt
			)

			guard let user = authResponse.user else {
				throw AuthError.invalidResponse
			}

			try await storage.saveUser(user)
			try await storage.saveTokens(tokens)
			await GroupService.shared.clearActiveGroup()
			return (user, tokens)
		} catch let error as AuthError {
			throw error
		} catch {
			throw AuthError.networkError(error.localizedDescription)
		}
	}

	func accessToken() async throws -> String {
		if let tokens = try await storage.loadTokens(),
			!TokenUtils.isTokenExpired(tokens.accessToken)
		{
			return tokens.accessToken
		}

		let newTokens = try await refresh()
		return newTokens.accessToken
	}

	func refresh() async throws -> Tokens {
		if let refreshTask {
			return try await refreshTask.value
		}

		let task = Task<Tokens, Error> {
			defer { self.clearRefreshTask() }

			guard let currentTokens = try await self.storage.loadTokens(),
				!currentTokens.refreshToken.isEmpty
			else {
				throw AuthError.noRefreshToken
			}

			let request = RefreshRequest(refreshToken: currentTokens.refreshToken)

			let authResponse: AuthResponse
			do {
				authResponse = try await authAPI.refresh(request)
			} catch {
				try await self.storage.clearTokens()
				try await self.storage.clearUser()
				await GroupService.shared.clearActiveGroup()
				throw AuthError.refreshFailed
			}

			let newTokens = Tokens(
				accessToken: authResponse.accessToken,
				refreshToken: authResponse.refreshToken,
				expiresAt: authResponse.expiresAt
			)

			try await self.storage.saveTokens(newTokens)

			if let user = authResponse.user {
				try await self.storage.saveUser(user)
			}

			return newTokens
		}

		refreshTask = task
		return try await task.value
	}

	func ensureAuthenticated() async throws -> User {
		_ = try await accessToken()

		guard let user = try await storage.loadUser() else {
			throw AuthError.notAuthenticated
		}

		return user
	}

	func isAuthenticated() async throws -> Bool {
		do {
			_ = try await ensureAuthenticated()
			return true
		} catch {
			return false
		}
	}

	func getCurrentUser() async throws -> User? {
		try await storage.loadUser()
	}

	func deleteAccount() async throws {
		_ = try await accessToken()

		guard let id = try await storage.loadUser()?.id else {
			throw AuthError.invalidResponse
		}

		try await apiClient.sendWithoutResponse(
			path: "/users/\(id)",
			method: .DELETE,
			includeGroupHeader: false
		)

		try await logout()
	}

	func logout() async throws {
		try await storage.clearTokens()
		try await storage.clearUser()
		await GroupService.shared.clearActiveGroup()
		refreshTask = nil
	}

	private func clearRefreshTask() {
		refreshTask = nil
	}
}
