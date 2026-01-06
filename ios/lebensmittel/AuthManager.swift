//
//  AuthManager.swift
//  lebensmittel
//
//  Created by Jai Sinha on 01/02/25.
//

import Foundation


// MARK: - Auth Storage (Actor)

actor AuthStorage {
    private let keychain = KeychainService()
    private let tokensKey = "tokens"
    private let userKey = "user"
    private var cachedTokens: Tokens?
    private var cachedUser: User?

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

    /// Logout (clear tokens and user data)
    func logout() async throws {
        try await storage.clearTokens()
        try await storage.clearUser()
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
