//
//  ReceiptsService.swift
//  lebensmittel
//
//  Created by Jai Sinha on 04/10/26.
//

import Foundation

struct ReceiptsService {
    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func fetchReceipts() async throws -> [Receipt] {
        let response: ReceiptsResponse = try await client.send(path: "/receipts")
        return response.receipts.sorted { $0.date < $1.date }
    }

    func updateReceipt(
        id: String,
        price: Double,
        purchasedBy: String,
        notes: String
    ) async throws {
        try await client.sendWithoutResponse(
            path: "/receipts/\(id)",
            method: .PATCH,
            body: ReceiptUpdatePayload(
                totalAmount: price,
                purchasedBy: purchasedBy,
                notes: notes
            )
        )
    }

    func deleteReceipt(id: String) async throws {
        try await client.sendWithoutResponse(
            path: "/receipts/\(id)",
            method: .DELETE
        )
    }
}

private struct ReceiptUpdatePayload: Encodable {
    let totalAmount: Double
    let purchasedBy: String
    let notes: String?
}
