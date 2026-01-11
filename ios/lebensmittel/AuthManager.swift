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

// MARK: - Auth Manager

actor AuthManager {
    enum AuthError: Error, LocalizedError {
        case noRefreshToken
        case refreshFailed
        case notAuthenticated
        case invalidResponse
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
            case .networkError(let msg):
                return "Network error: \(msg)"
            }
        }
    }

    static let shared = AuthManager()

    private let storage = AuthStorage()
    private let baseURL = "http://192.168.1.11:8000/api"
    private var refreshTask: Task<Tokens, Error>?

    // MARK: Public Methods

    func register(username: String, password: String, displayName: String) async throws -> (User, Tokens) {
        guard let url = URL(string: "\(baseURL)/register") else {
            throw AuthError.invalidResponse
        }

        let request = RegisterRequest(username: username, password: password, displayName: displayName)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMsg = try? JSONDecoder().decode([String: String].self, from: data)["error"] ?? "Unknown error"
                throw AuthError.networkError(errorMsg ?? "HTTP \(httpResponse.statusCode)")
            }

            let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
            let tokens = Tokens(
                accessToken: authResponse.accessToken,
                refreshToken: authResponse.refreshToken,
                expiresAt: authResponse.expiresAt
            )

            if let user = authResponse.user {
                try await storage.saveUser(user)
                try await storage.saveTokens(tokens)
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
        guard let url = URL(string: "\(baseURL)/login") else {
            throw AuthError.invalidResponse
        }

        let request = LoginRequest(username: username, password: password)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMsg = try? JSONDecoder().decode([String: String].self, from: data)["error"] ?? "Unknown error"
                throw AuthError.networkError(errorMsg ?? "HTTP \(httpResponse.statusCode)")
            }

            let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
            let tokens = Tokens(
                accessToken: authResponse.accessToken,
                refreshToken: authResponse.refreshToken,
                expiresAt: authResponse.expiresAt
            )

            if let user = authResponse.user {
                try await storage.saveUser(user)
                try await storage.saveTokens(tokens)
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
        if let tokens = try await storage.loadTokens(), !isTokenExpired(tokens.accessToken) {
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

            guard let url = URL(string: "\(self.baseURL)/refresh") else {
                throw AuthError.invalidResponse
            }

            let request = RefreshRequest(refreshToken: currentTokens.refreshToken)
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try JSONEncoder().encode(request)

            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                // If refresh fails, clear tokens and force logout
                try await self.storage.clearTokens()
                throw AuthError.refreshFailed
            }

            let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
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
        if let tokens = try await storage.loadTokens(), !isTokenExpired(tokens.accessToken) {
            return true
        }
        return false
    }

    /// Get current user
    func getCurrentUser() async throws -> User? {
        return try await storage.loadUser()
    }

    // MARK: - Group Management

    func getUserGroups() async throws -> [AuthGroup] {
        let token = try await accessToken()
        guard let url = URL(string: "\(baseURL)/users/me/groups") else {
            throw AuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.invalidResponse
        }

        return try JSONDecoder().decode([AuthGroup].self, from: data)
    }

    func getActiveGroupId() async throws -> String {
        if let localId = try await storage.loadActiveGroupId() {
            return localId
        }

        let token = try await accessToken()
        guard let url = URL(string: "\(baseURL)/users/me/active-group") else {
            throw AuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.invalidResponse
        }

        let result = try JSONDecoder().decode([String: String].self, from: data)
        guard let groupId = result["groupId"] else {
            throw AuthError.invalidResponse
        }

        try await storage.saveActiveGroupId(groupId)
        return groupId
    }

    func setActiveGroup(_ groupId: String) async throws {
        try await storage.saveActiveGroupId(groupId)
    }

    func addUserToGroup(groupId: String, userId: String) async throws {
        let token = try await accessToken()
        guard let url = URL(string: "\(baseURL)/groups/\(groupId)/users") else {
            throw AuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body = ["userId": userId]
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.invalidResponse
        }
    }

    func removeUserFromGroup(groupId: String, userId: String) async throws {
        let token = try await accessToken()
        guard let url = URL(string: "\(baseURL)/groups/\(groupId)/users/\(userId)") else {
            throw AuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.invalidResponse
        }
    }

    func joinGroup(groupId: String) async throws {
        guard let user = try await getCurrentUser() else { throw AuthError.notAuthenticated }
        try await addUserToGroup(groupId: groupId, userId: user.id)
    }

    func leaveGroup(groupId: String) async throws {
        try await removeUserFromGroup(groupId: groupId, userId: "me")
    }

    func renameGroup(groupId: String, newName: String) async throws {
        let token = try await accessToken()
        guard let url = URL(string: "\(baseURL)/groups/\(groupId)") else {
            throw AuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body = ["name": newName]
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.invalidResponse
        }
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

struct NetworkClient {
    private let auth: AuthManager
    private let session: URLSession

    init(authManager: AuthManager = .shared, session: URLSession = .shared) {
        self.auth = authManager
        self.session = session
    }

    /// Send a request with automatic token injection and 401 retry
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var req = request

        do {
            let token = try await auth.accessToken()
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            if let groupId = try? await auth.getActiveGroupId() {
                req.setValue(groupId, forHTTPHeaderField: "X-Group-ID")
            }
        } catch {
            // If we can't get a token, try anyway (server will reject with 401)
        }

        let (data, response) = try await session.data(for: req)

        // Handle 401 by refreshing and retrying once
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            do {
                _ = try await auth.refresh()
                let newToken = try await auth.accessToken()
                var retry = request
                retry.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                return try await session.data(for: retry)
            } catch {
                // Refresh failed, propagate original error
                throw error
            }
        }

        return (data, response)
    }
}
