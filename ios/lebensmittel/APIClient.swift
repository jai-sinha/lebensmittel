//
//  APIClient.swift
//  lebensmittel
//
//  Created by Jai Sinha on 04/07/26.
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

struct APIClient {
	static let shared = APIClient()

	private let session: URLSession
	private let encoder = JSONEncoder()
	private let decoder = JSONDecoder()

	nonisolated init(session: URLSession = .shared) {
		self.session = session
	}

	func send<Response: Decodable>(
		path: String,
		method: HTTPMethod = .GET,
		body: (any Encodable)? = nil,
		includeGroupHeader: Bool = true
	) async throws -> Response {
		let request = try await makeRequest(
			path: path,
			method: method,
			body: body,
			includeGroupHeader: includeGroupHeader
		)
		let (data, response) = try await perform(request)
		return try decode(Response.self, from: data, response: response)
	}

	func sendWithoutResponse(
		path: String,
		method: HTTPMethod,
		body: (any Encodable)? = nil,
		includeGroupHeader: Bool = true
	) async throws {
		let request = try await makeRequest(
			path: path,
			method: method,
			body: body,
			includeGroupHeader: includeGroupHeader
		)
		let (_, response) = try await perform(request)
		try validate(response: response)
	}

	private func makeRequest(
		path: String,
		method: HTTPMethod,
		body: (any Encodable)?,
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

		if includeGroupHeader,
			let groupId = GroupModel.shared.getActiveGroupId(),
			!groupId.isEmpty
		{
			request.setValue(groupId, forHTTPHeaderField: "X-Group-ID")
		}

		return request
	}

	private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
		do {
			return try await session.data(for: request)
		} catch let error as APIError {
			throw error
		} catch {
			throw APIError.transport(error)
		}
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
