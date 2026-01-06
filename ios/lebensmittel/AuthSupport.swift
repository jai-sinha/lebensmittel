//
//  AuthSupport.swift
//  lebensmittel
//
//  Created by Jai Sinha on 01/02/26.
//

import Foundation
import Security

// MARK: - Models

struct Tokens: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
    }
}

struct User: Codable, Sendable {
    let username: String
    let displayName: String
}

struct LoginRequest: Codable, Sendable {
    let username: String
    let password: String
}

struct RegisterRequest: Codable, Sendable {
    let username: String
    let password: String
    let displayName: String
}

struct RefreshRequest: Codable, Sendable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

struct AuthResponse: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date?
    let user: User?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case user
    }
}

// MARK: - Keychain Service

struct KeychainService: Sendable {
    enum KeychainError: Error {
        case osStatus(OSStatus)
        case encodingFailed
        case decodingFailed
        case itemNotFound
    }

    private let serviceName = "com.lebensmittel.auth"

    func save<T: Codable>(_ value: T, forKey key: String) throws {
        let data = try JSONEncoder().encode(value)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Try to delete existing item first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.osStatus(status)
        }
    }

    func read<T: Codable>(_ type: T.Type, forKey key: String) throws -> T? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: key,
            kSecReturnData: kCFBooleanTrue!,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.osStatus(status)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    func delete(forKey key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }
    }
}

// MARK: - JWT Utilities

func jwtExpiry(_ jwt: String) -> Int? {
    let parts = jwt.split(separator: ".")
    guard parts.count >= 2 else { return nil }

    var payload = String(parts[1])
    payload = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while payload.count % 4 != 0 { payload += "=" }

    guard let data = Data(base64Encoded: payload),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let exp = obj["exp"] as? Int else {
        return nil
    }
    return exp
}

func isTokenExpired(_ token: String, bufferSeconds: Int = 60) -> Bool {
    guard let exp = jwtExpiry(token) else { return true }
    return Date() > Date(timeIntervalSince1970: TimeInterval(exp - bufferSeconds))
}
