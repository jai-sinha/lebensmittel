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
	static let shared = ReceiptsModel()

	var receipts: [Receipt] = []
	var isLoading = false
	var errorMessage: String? = nil

	var currentMonth: String {
		let monthFormatter = DateFormatter()
		monthFormatter.dateFormat = "MMMM yyyy"
		return monthFormatter.string(from: Date())
	}

	// MARK: UI update methods

	func addReceipt(_ receipt: Receipt) {
		if let index = receipts.firstIndex(where: { $0.id == receipt.id }) {
			receipts[index] = receipt
		} else {
			receipts.append(receipt)
		}
	}

	func deleteReceipt(withId id: UUID) {
		receipts.removeAll { $0.id == id }
	}

	func replaceAll(with receipts: [Receipt]) {
		self.receipts = receipts
	}

	// MARK: CRUD

	func fetchReceipts() async {
		errorMessage = nil

		guard ConnectivityMonitor.shared.isOnline else { return }

		isLoading = true
		defer { isLoading = false }

		do {
			try await SyncEngine.shared.reconcile(forceSnapshot: true)
		} catch {
			errorMessage = UserFacingError.message(for: error)
		}
	}

	func updateReceipt(receipt: Receipt, price: Double, purchasedBy: String, notes: String) {
		errorMessage = nil
		if let updatedReceipt = SyncEngine.shared.enqueueReceiptUpdate(
			receiptID: receipt.id,
			totalAmount: price,
			purchasedBy: purchasedBy,
			notes: notes
		) {
			if let index = receipts.firstIndex(where: { $0.id == updatedReceipt.id }) {
				receipts[index] = updatedReceipt
			}
		}
	}

	func deleteReceipt(receiptId: UUID) {
		errorMessage = nil
		SyncEngine.shared.enqueueReceiptDelete(receiptID: receiptId)
		deleteReceipt(withId: receiptId)
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
