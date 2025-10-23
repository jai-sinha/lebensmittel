//
//  ReceiptsModel.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/20/25.
//

import Foundation
import Combine

class ReceiptsModel: ObservableObject {
    @Published var receipts: [Receipt] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    
    var currentMonth: String {
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM yyyy"
        return monthFormatter.string(from: Date())
    }
    
    // MARK: UI Update Methods
    func addReceipt(_ receipt: Receipt) {
        DispatchQueue.main.async {
            self.receipts.append(receipt)
        }
    }
    
    func updateReceipt(_ receipt: Receipt) {
        DispatchQueue.main.async {
            if let index = self.receipts.firstIndex(where: { $0.id == receipt.id }) {
                self.receipts[index] = receipt
            }
        }
    }
    
    func deleteReceipt(withId id: String) {
        DispatchQueue.main.async {
            self.receipts.removeAll { $0.id == id }
        }
    }
    
    // MARK: CRUD Operations
    
    func fetchReceipts() {
        isLoading = true
        errorMessage = nil
        guard let url = URL(string: "http://35.237.202.74/api/receipts") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(ReceiptsResponse.self, from: data)
                let sortedReceipts = response.receipts.sorted { $0.date < $1.date }
                await MainActor.run {
                    self.receipts = sortedReceipts
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    func updateReceipt(receipt: Receipt, price: Double, purchasedBy: String, notes: String) {
        guard let url = URL(string: "http://35.237.202.74/api/receipts/\(receipt.id)") else {
            self.errorMessage = "Invalid URL"
            return
        }
        
        let updatedReceipt = Receipt(
            id: receipt.id,
            date: receipt.date,
            totalAmount: price,
            purchasedBy: purchasedBy,
            items: receipt.items,
            notes: notes,
        )
        
        // Optimistically update locally
        updateReceipt(updatedReceipt)
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(updatedReceipt)
        } catch {
            self.errorMessage = "Failed to encode receipt"
            return
        }
        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    await MainActor.run {
                        if let idx = self.receipts.firstIndex(where: { $0.id == receipt.id }) {
                            self.receipts[idx] = updatedReceipt
                        }
                    }
                } else {
                    await MainActor.run {
                        self.errorMessage = "Failed to update receipt"
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    func deleteReceipt(receiptId: String) {
        guard let url = URL(string: "http://35.237.202.74/api/receipts/\(receiptId)") else {
            self.errorMessage = "Invalid URL"
            return
        }
        
        // Optimistically remove locally
        deleteReceipt(withId: receiptId)
        
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    await MainActor.run {
                        self.errorMessage = "Server returned status \(http.statusCode)"
                        self.fetchReceipts()
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.fetchReceipts()
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
            let jaiTotal = monthReceipts.filter { $0.purchasedBy == "Jai" }.reduce(into: 0) { $0 += $1.totalAmount }
            let hannaTotal = monthReceipts.filter { $0.purchasedBy == "Hanna" }.reduce(into: 0) { $0 += $1.totalAmount }
            return MonthlyReceiptsGroup(month: month, receipts: monthReceipts, jaiTotal: jaiTotal, hannaTotal: hannaTotal)
        }
    }
}
