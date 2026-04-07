//
//  AuthManager.swift
//  lebensmittel
//
//  Created by Jai Sinha on 01/02/26.
//

import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case server(statusCode: Int, message: String?)
    case transport(Error)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid server response"
        case .unauthorized:
            return "Unauthorized"
        case .server(let statusCode, let message):
            return message ?? "Server returned status \(statusCode)"
        case .transport(let error):
            return error.localizedDescription
        case .encodingFailed:
            return "Failed to encode request body"
        }
    }
}

enum HTTPMethod: String {
    case GET
    case POST
    case PATCH
    case DELETE
}


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

    // MARK: Public Methods

    func register(username: String, email: String, password: String, displayName: String) async throws -> (User, Tokens) {
        let request = RegisterRequest(username: username, password: password, displayName: displayName, email: email)

        do {
            let authResponse: AuthResponse = try await APIClient(authManager: self).send(
                path: "/register",
                method: .POST,
                body: request,
                requiresAuth: false,
                includeGroupHeader: false
            )
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
            let authResponse: AuthResponse = try await APIClient(authManager: self).send(
                path: "/login",
                method: .POST,
                body: request,
                requiresAuth: false,
                includeGroupHeader: false
            )
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
                authResponse = try await APIClient(authManager: self).send(
                    path: "/refresh",
                    method: .POST,
                    body: request,
                    requiresAuth: false,
                    includeGroupHeader: false
                )
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
		let token = try await accessToken()
		guard let id = try await storage.loadUser()?.id else {
			throw AuthError.invalidResponse
		}
		guard let url = URL(string: "\(baseURL)/users/\(id)") else {
			throw AuthError.invalidResponse
		}

		var request = URLRequest(url: url)
		request.httpMethod = "DELETE"
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

		let (_, response) = try await URLSession.shared.data(for: request)

		guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
			throw AuthError.invalidResponse
		}

		try await logout()
	}

    // MARK: - Group Management

    func getUserGroups() async throws -> [AuthGroup] {
        _ = try await accessToken()
        return try await APIClient(authManager: self).send(path: "/users/me/groups")
    }

    func getUsersInGroup() async throws -> [GroupUser] {
		let groupId = try await getActiveGroupId()
		return try await APIClient(authManager: self).send(path: "/groups/\(groupId)/users")
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
            let result: [String: String] = try await APIClient(authManager: self).send(path: "/users/me/active-group")
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
        try await APIClient(authManager: self).sendWithoutResponse(path: "/groups/\(groupId)/users/\(userId)", method: .DELETE)
    }

    func getGroupInviteCode(groupId: String) async throws -> String {
    	_ = try await accessToken()
		let result: [String: String] = try await APIClient(authManager: self).send(path: "/groups/\(groupId)/invite", method: .POST)
		guard let inviteCode = result["code"] else {
			throw AuthError.invalidResponse
		}

		return inviteCode
    }

    func createGroup(groupName: String) async throws {
        _ = try await accessToken()
        let body = ["name": groupName]
        let group: AuthGroup = try await APIClient(authManager: self).send(path: "/groups", method: .POST, body: body)
        try await self.setActiveGroup(group.id)
    }

    func joinGroup(code: String) async throws {
        _ = try await accessToken()
        let body = ["code": code]

        struct JoinResponse: Decodable {
            let groupId: String
        }

        let result: JoinResponse = try await APIClient(authManager: self).send(path: "/groups/join", method: .POST, body: body)
        try await self.setActiveGroup(result.groupId)
    }

    func leaveGroup(groupId: String) async throws {
        try await removeUserFromGroup(groupId: groupId, userId: "me")
    }

    func renameGroup(groupId: String, newName: String) async throws {
        _ = try await accessToken()
        let body = ["name": newName]
        try await APIClient(authManager: self).sendWithoutResponse(path: "/groups/\(groupId)", method: .PATCH, body: body)
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

// MARK: - Network Client

struct APIClient {
    private let auth: AuthManager
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(authManager: AuthManager, session: URLSession = .shared) {
        self.auth = authManager
        self.session = session
    }

    func send<Response: Decodable>(
        path: String,
        method: HTTPMethod = .GET,
        body: (any Encodable)? = nil,
        requiresAuth: Bool = true,
        includeGroupHeader: Bool = true
    ) async throws -> Response {
        let request = try await makeRequest(
            path: path,
            method: method,
            body: body,
            requiresAuth: requiresAuth,
            includeGroupHeader: includeGroupHeader
        )
        let (data, response) = try await perform(request)
        return try decode(Response.self, from: data, response: response)
    }

    func sendWithoutResponse(
        path: String,
        method: HTTPMethod,
        body: (any Encodable)? = nil,
        requiresAuth: Bool = true,
        includeGroupHeader: Bool = true
    ) async throws {
        let request = try await makeRequest(
            path: path,
            method: method,
            body: body,
            requiresAuth: requiresAuth,
            includeGroupHeader: includeGroupHeader
        )
        let (_, response) = try await perform(request)
        try validate(response: response)
    }

    private func makeRequest(
        path: String,
        method: HTTPMethod,
        body: (any Encodable)?,
        requiresAuth: Bool,
        includeGroupHeader: Bool
    ) async throws -> URLRequest {
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = AppConfig.apiBaseURL.appendingPathComponent(trimmedPath)
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encode(body)
        }

        if requiresAuth {
            let token = try await auth.accessToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if includeGroupHeader, let groupId = try? await auth.getActiveGroupId(), !groupId.isEmpty {
            request.setValue(groupId, forHTTPHeaderField: "X-Group-ID")
        }

        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            let (data, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                _ = try await auth.refresh()

                let retry = try await remakeRequestWithFreshAuth(from: request)
                return try await session.data(for: retry)
            }

            return (data, response)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error)
        }
    }

    private func remakeRequestWithFreshAuth(from request: URLRequest) async throws -> URLRequest {
        var retry = request
        let newToken = try await auth.accessToken()
        retry.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")

        if let groupId = try? await auth.getActiveGroupId(), !groupId.isEmpty {
            retry.setValue(groupId, forHTTPHeaderField: "X-Group-ID")
        }

        return retry
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.server(statusCode: httpResponse.statusCode, message: nil)
        }
    }

    private func decode<Response: Decodable>(
        _ type: Response.Type,
        from data: Data,
        response: URLResponse
    ) throws -> Response {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 409 {
            throw AuthManager.AuthError.usernameTaken
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = (try? decoder.decode([String: String].self, from: data))?["error"]
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.server(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }

    private func encode(_ value: any Encodable) throws -> Data {
        let wrapped = AnyEncodable(value)
        do {
            return try encoder.encode(wrapped)
        } catch {
            throw APIError.encodingFailed
        }
    }
}

private struct AnyEncodable: Encodable {
    private let encodeImpl: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        self.encodeImpl = wrapped.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeImpl(encoder)
    }
}

typealias NetworkClient = APIClient
