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
	private let service: ReceiptsService

	var receipts: [Receipt] = []
	var isLoading = false
	var errorMessage: String? = nil

	init(service: ReceiptsService = ReceiptsService()) {
		self.service = service
	}

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

		Task {
			do {
				let receipts = try await service.fetchReceipts()
				await MainActor.run {
					self.receipts = receipts
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

		Task {
			do {
				try await service.updateReceipt(
					id: receipt.id,
					price: price,
					purchasedBy: purchasedBy,
					notes: notes
				)
			} catch {
				await MainActor.run {
					self.errorMessage = UserFacingError.message(for: error)
				}
			}
		}
	}

	func deleteReceipt(receiptId: String) {
		errorMessage = nil

		Task {
			do {
				try await service.deleteReceipt(id: receiptId)
			} catch {
				await MainActor.run {
					self.errorMessage = UserFacingError.message(for: error)
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
