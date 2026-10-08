//
//  ReceiptsService.swift
//  lebensmittel
//
//  Created by Jai Sinha on 04/10/26.
//

import Foundation

struct ReceiptsService: ReceiptsServicing {
	private let client: APIClient

	init(client: APIClient = .shared) {
		self.client = client
	}

	func createReceipt(_ receipt: NewReceipt) async throws -> Receipt {
		try await client.send(
			path: "/receipts",
			method: .POST,
			body: receipt
		)
	}

	func updateReceipt(
		id: UUID,
		price: Double,
		purchasedBy: String,
		notes: String
	) async throws {
		try await client.sendWithoutResponse(
			path: "/receipts/\(id.uuidString.lowercased())",
			method: .PATCH,
			body: ReceiptUpdatePayload(
				totalAmount: price,
				purchasedBy: purchasedBy,
				notes: notes
			)
		)
	}

	func deleteReceipt(id: UUID) async throws {
		try await client.sendWithoutResponse(
			path: "/receipts/\(id.uuidString.lowercased())",
			method: .DELETE
		)
	}

}

private struct ReceiptUpdatePayload: Encodable {
	let totalAmount: Double
	let purchasedBy: String
	let notes: String?
}
