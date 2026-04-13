//
//  ShoppingService.swift
//  lebensmittel
//
//  Created by Jai Sinha on 04/10/26.
//

import Foundation

struct ShoppingService: ShoppingServicing {
    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func createReceipt(
        date: String,
        price: Double,
        purchasedBy: String,
        notes: String
    ) async throws {
        try await client.sendWithoutResponse(
            path: "/receipts",
            method: .POST,
            body: NewReceipt(
                date: date,
                totalAmount: price,
                purchasedBy: purchasedBy,
                notes: notes
            )
        )
    }
}
