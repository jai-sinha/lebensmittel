//
//  ReceiptsModel.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/20/25.
//


import Foundation
import Combine

struct ReceiptsResponse: Codable {
    let count: Int
    let receipts: [Receipt]
}

class ReceiptsModel: ObservableObject {
    @Published var receipts: [Receipt] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    
    var currentMonth: String {
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM yyyy"
        return monthFormatter.string(from: Date())
    }
    
    func fetchReceipts() {
        isLoading = true
        errorMessage = nil
        guard let url = URL(string: "http://192.168.2.113:8000/api/receipts") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let data = data else {
                    self.errorMessage = "No data"
                    return
                }
                do {
                    let response = try JSONDecoder().decode(ReceiptsResponse.self, from: data)
                    // Sort receipts by date ascending (oldest at top, newest at bottom)
                    self.receipts = response.receipts.sorted { $0.date < $1.date }
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
        }.resume()
    }
    
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
}
