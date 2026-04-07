//
//  AuthManager.swift
//  lebensmittel
//
//  Created by Jai Sinha on 01/02/26.
//

import Foundation

// MARK: - Auth Storage (Actor)

actor AuthStorage {
    private let keychain = KeychainService()
    private let tokensKey = "tokens"
    private let userKey = "user"
    private let activeGroupKey = "activeGroupId"
    private var cachedTokens: Tokens?
    private var cachedUser: User?
    private var cachedActiveGroupId: String?

    func loadTokens() throws -> Tokens? {
        if let cached = cachedTokens {
            return cached
        }
        let tokens = try keychain.read(Tokens.self, forKey: tokensKey)
        cachedTokens = tokens
        return tokens
    }

    func loadUser() throws -> User? {
        if let cached = cachedUser {
            return cached
        }
        let user = try keychain.read(User.self, forKey: userKey)
        cachedUser = user
        return user
    }

    func loadActiveGroupId() throws -> String? {
        if let cached = cachedActiveGroupId {
            return cached
        }
        let groupId = try keychain.read(String.self, forKey: activeGroupKey)
        cachedActiveGroupId = groupId
        return groupId
    }

    func saveTokens(_ tokens: Tokens) throws {
        cachedTokens = tokens
        try keychain.save(tokens, forKey: tokensKey)
    }

    func saveUser(_ user: User) throws {
        cachedUser = user
        try keychain.save(user, forKey: userKey)
    }

    func saveActiveGroupId(_ id: String) throws {
        cachedActiveGroupId = id
        try keychain.save(id, forKey: activeGroupKey)
    }

    func clearTokens() throws {
        cachedTokens = nil
        try keychain.delete(forKey: tokensKey)
    }

    func clearUser() throws {
        cachedUser = nil
        try keychain.delete(forKey: userKey)
    }

    func clearActiveGroupId() throws {
        cachedActiveGroupId = nil
        try keychain.delete(forKey: activeGroupKey)
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
    private var activeGroupTask: Task<String, Error>?

    private var apiClient: APIClient {
        APIClient(authManager: self)
    }

    private var authAPI: AuthAPI {
        AuthAPI(client: apiClient)
    }

    // MARK: Public Methods

    func register(username: String, email: String, password: String, displayName: String) async throws -> (User, Tokens) {
        let request = RegisterRequest(username: username, password: password, displayName: displayName, email: email)

        do {
            let authResponse = try await authAPI.register(request)
            let tokens = Tokens(
                accessToken: authResponse.accessToken,
                refreshToken: authResponse.refreshToken,
                expiresAt: authResponse.expiresAt
            )

            if let user = authResponse.user {
                try await storage.saveUser(user)
                try await storage.saveTokens(tokens)
                try await storage.clearActiveGroupId()
                activeGroupTask = nil
                return (user, tokens)
            }

            throw AuthError.invalidResponse
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

            if let user = authResponse.user {
                try await storage.saveUser(user)
                try await storage.saveTokens(tokens)
                try await storage.clearActiveGroupId()
                activeGroupTask = nil
                return (user, tokens)
            }

            throw AuthError.invalidResponse
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.networkError(error.localizedDescription)
        }
    }

    /// Get a valid access token, refreshing if necessary
    func accessToken() async throws -> String {
        if let tokens = try await storage.loadTokens(), !TokenUtils.isTokenExpired(tokens.accessToken) {
            return tokens.accessToken
        }

        let newTokens = try await refresh()
        return newTokens.accessToken
    }

    /// Refresh access token using refresh token (single-flight)
    func refresh() async throws -> Tokens {
        if let task = refreshTask {
            return try await task.value
        }

        let task = Task<Tokens, Error> {
            defer { self.clearRefreshTask() }

            guard let currentTokens = try await self.storage.loadTokens(),
                  !currentTokens.refreshToken.isEmpty else {
                throw AuthError.noRefreshToken
            }

            let request = RefreshRequest(refreshToken: currentTokens.refreshToken)

            let authResponse: AuthResponse
            do {
                authResponse = try await authAPI.refresh(request)
            } catch {
                // If refresh fails, clear tokens and force logout
                try await self.storage.clearTokens()
                throw AuthError.refreshFailed
            }
            let newTokens = Tokens(
                accessToken: authResponse.accessToken,
                refreshToken: authResponse.refreshToken,
                expiresAt: authResponse.expiresAt
            )

            try await self.storage.saveTokens(newTokens)
            return newTokens
        }

        refreshTask = task
        return try await task.value
    }

    /// Check if user is currently authenticated
    func isAuthenticated() async throws -> Bool {
        if let tokens = try await storage.loadTokens(), !TokenUtils.isTokenExpired(tokens.accessToken) {
            return true
        }
        // Access token expired — try refreshing with the refresh token
        do {
            _ = try await refresh()
            return true
        } catch {
            return false
        }
    }

    /// Get current user
    func getCurrentUser() async throws -> User? {
        return try await storage.loadUser()
    }

    /// Delete user account
    // Note: This will also invalidate tokens and log the user out
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

    // MARK: - Group Management

    func getUserGroups() async throws -> [AuthGroup] {
        _ = try await accessToken()
        return try await apiClient.send(path: "/users/me/groups")
    }

    func getUsersInGroup() async throws -> [GroupUser] {
		let groupId = try await getActiveGroupId()
		return try await apiClient.send(path: "/groups/\(groupId)/users")
	}

    func getActiveGroupId() async throws -> String {
        if let localId = try await storage.loadActiveGroupId() {
            return localId
        }

        if let task = activeGroupTask {
            return try await task.value
        }

        let task = Task<String, Error> {
            _ = try await self.accessToken()
            let result: [String: String] = try await apiClient.send(path: "/users/me/active-group")
            guard let groupId = result["groupId"] else {
                throw AuthError.invalidResponse
            }

            try await self.storage.saveActiveGroupId(groupId)
            return groupId
        }

        activeGroupTask = task

        do {
            let result = try await task.value
            activeGroupTask = nil
            return result
        } catch {
            activeGroupTask = nil
            throw error
        }
    }

    func setActiveGroup(_ groupId: String) async throws {
        try await storage.saveActiveGroupId(groupId)
    }

    func removeUserFromGroup(groupId: String, userId: String) async throws {
        _ = try await accessToken()
        try await apiClient.sendWithoutResponse(path: "/groups/\(groupId)/users/\(userId)", method: .DELETE)
    }

    func getGroupInviteCode(groupId: String) async throws -> String {
    	_ = try await accessToken()
		let result: [String: String] = try await apiClient.send(path: "/groups/\(groupId)/invite", method: .POST)
		guard let inviteCode = result["code"] else {
			throw AuthError.invalidResponse
		}

		return inviteCode
    }

    func createGroup(groupName: String) async throws {
        _ = try await accessToken()
        let body = ["name": groupName]
        let group: AuthGroup = try await apiClient.send(path: "/groups", method: .POST, body: body)
        try await self.setActiveGroup(group.id)
    }

    func joinGroup(code: String) async throws {
        _ = try await accessToken()
        let body = ["code": code]

        struct JoinResponse: Decodable {
            let groupId: String
        }

        let result: JoinResponse = try await apiClient.send(path: "/groups/join", method: .POST, body: body)
        try await self.setActiveGroup(result.groupId)
    }

    func leaveGroup(groupId: String) async throws {
        try await removeUserFromGroup(groupId: groupId, userId: "me")
    }

    func renameGroup(groupId: String, newName: String) async throws {
        _ = try await accessToken()
        let body = ["name": newName]
        try await apiClient.sendWithoutResponse(path: "/groups/\(groupId)", method: .PATCH, body: body)
    }

    /// Logout (clear tokens and user data)
    func logout() async throws {
        try await storage.clearTokens()
        try await storage.clearUser()
        try await storage.clearActiveGroupId()
        refreshTask = nil
    }

    private func clearRefreshTask() {
        refreshTask = nil
    }
}
