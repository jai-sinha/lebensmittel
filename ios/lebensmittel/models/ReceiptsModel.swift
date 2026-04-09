//
//  ReceiptsModel.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/20/25.
//

import Foundation

@MainActor
@Observable
class ReceiptsModel {
	var receipts: [Receipt] = []
	var isLoading = false
	var errorMessage: String? = nil

	var currentMonth: String {
		let monthFormatter = DateFormatter()
		monthFormatter.dateFormat = "MMMM yyyy"
		return monthFormatter.string(from: Date())
	}

	// MARK: UI Update Methods, used for WebSocket updates

	func addReceipt(_ receipt: Receipt) {
		receipts.append(receipt)
	}

	func updateReceipt(_ receipt: Receipt) {
		if let index = receipts.firstIndex(where: { $0.id == receipt.id }) {
			receipts[index] = receipt
		}
	}

	func deleteReceipt(withId id: String) {
		receipts.removeAll { $0.id == id }
	}

	// MARK: CRUD Operations

	func fetchReceipts() {
		isLoading = true
		errorMessage = nil

		let client = APIClient()

		Task {
			do {
				let response: ReceiptsResponse = try await client.send(path: "/receipts")
				let sortedReceipts = response.receipts.sorted { $0.date < $1.date }
				await MainActor.run {
					self.receipts = sortedReceipts
					self.isLoading = false
				}
			} catch {
				await MainActor.run {
					self.errorMessage = UserFacingError.message(for: error)
					self.isLoading = false
				}
			}
		}
	}

	func updateReceipt(receipt: Receipt, price: Double, purchasedBy: String, notes: String) {
		errorMessage = nil

		let updatePayload = ReceiptUpdatePayload(
			totalAmount: price,
			purchasedBy: purchasedBy,
			notes: notes
		)

		let client = APIClient()

		Task {
			do {
				try await client.sendWithoutResponse(
					path: "/receipts/\(receipt.id)",
					method: .PATCH,
					body: updatePayload
				)
			} catch {
				await MainActor.run {
					self.errorMessage = "Couldn't update that receipt. Please try again."
				}
			}
		}
	}

	func deleteReceipt(receiptId: String) {
		errorMessage = nil
		let client = APIClient()

		Task {
			do {
				try await client.sendWithoutResponse(
					path: "/receipts/\(receiptId)",
					method: .DELETE
				)
			} catch {
				await MainActor.run {
					self.errorMessage = "Couldn't delete that receipt. Please try again."
				}
			}
		}
	}

	// MARK: Grouping Helpers

	func groupReceiptsByMonth() -> [(month: String, receipts: [Receipt])] {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd"
		let monthFormatter = DateFormatter()
		monthFormatter.dateFormat = "MMMM yyyy"
		var groups: [String: [Receipt]] = [:]
		for receipt in receipts {
			if let date = formatter.date(from: receipt.date) {
				let month = monthFormatter.string(from: date)
				groups[month, default: []].append(receipt)
			}
		}
		// Sort months chronologically
		let sortedMonths = groups.keys.sorted { lhs, rhs in
			monthFormatter.date(from: lhs)! < monthFormatter.date(from: rhs)!
		}
		return sortedMonths.map { ($0, groups[$0]!.sorted { $0.date < $1.date }) }
	}

	func groupReceiptsByMonthWithPersonTotals() -> [MonthlyReceiptsGroup] {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd"
		let monthFormatter = DateFormatter()
		monthFormatter.dateFormat = "MMMM yyyy"
		var groups: [String: [Receipt]] = [:]
		for receipt in receipts {
			if let date = formatter.date(from: receipt.date) {
				let month = monthFormatter.string(from: date)
				groups[month, default: []].append(receipt)
			}
		}
		let sortedMonths = groups.keys.sorted { lhs, rhs in
			monthFormatter.date(from: lhs)! < monthFormatter.date(from: rhs)!
		}
		return sortedMonths.map { month in
			let monthReceipts = groups[month]!.sorted { $0.date < $1.date }
			var userTotals: [String: Double] = [:]
			for receipt in monthReceipts {
				userTotals[receipt.purchasedBy, default: 0] += receipt.totalAmount
			}
			return MonthlyReceiptsGroup(
				month: month, receipts: monthReceipts, userTotals: userTotals)
		}
	}
}

private struct ReceiptUpdatePayload: Encodable {
	let totalAmount: Double
	let purchasedBy: String
	let notes: String?
}
