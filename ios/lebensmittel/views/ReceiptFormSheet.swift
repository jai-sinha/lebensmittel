//
//  ReceiptFormSheet.swift
//  lebensmittel
//
//  Created by Jai Sinha on 06/13/26.
//

import SwiftUI

/// A reusable form sheet for creating or editing a receipt.
/// Handles the common fields (cost, purchaser, notes) and validation.
struct ReceiptFormSheet: View {
	let title: String
	@Binding var cost: String
	@Binding var purchaser: String
	@Binding var notes: String
	@Binding var error: String
	let purchaserOptions: [String]
	var onCancel: () -> Void
	var onSubmit: (_ price: Double, _ purchaser: String, _ notes: String) -> Void

	var body: some View {
		VStack(spacing: 25) {
			Text(title)
				.font(.title)
				.bold()

			VStack(alignment: .leading, spacing: 12) {
				Text("Total Cost (€)")
					.font(.headline)
				TextField("", text: $cost)
					.keyboardType(.decimalPad)
					.textFieldStyle(RoundedBorderTextFieldStyle())
					.font(.body)
			}

			VStack(alignment: .leading, spacing: 12) {
				Text("Purchased by")
					.font(.headline)
				Picker("Purchased by", selection: $purchaser) {
					ForEach(purchaserOptions, id: \.self) { option in
						Text(option).tag(option)
					}
				}
				.pickerStyle(SegmentedPickerStyle())
			}

			VStack(alignment: .leading, spacing: 12) {
				Text("Notes (optional)")
					.font(.headline)
				TextEditor(text: $notes)
					.frame(minHeight: 40, maxHeight: 120)
					.font(.body)
					.background(Color(.systemGray6))
					.clipShape(.rect(cornerRadius: 8))
			}

			if !error.isEmpty {
				Text(error)
					.foregroundStyle(.red)
					.font(.callout)
			}

			HStack(spacing: 20) {
				Button("Cancel") {
					onCancel()
				}
				.padding(.horizontal, 20)
				.padding(.vertical, 10)
				.background(Color.red.opacity(0.8))
				.foregroundStyle(.white)
				.clipShape(.rect(cornerRadius: 8))

				Spacer()

				Button("Submit") {
					submit()
				}
				.padding(.horizontal, 20)
				.padding(.vertical, 10)
				.background(Color.blue)
				.foregroundStyle(.white)
				.clipShape(.rect(cornerRadius: 8))
			}
		}
		.padding(30)
		.presentationDetents([.medium])
	}

	private func submit() {
		// accept both "." and "," as decimal separators for euro/us standards
		let normalized = cost.replacingOccurrences(of: ",", with: ".")
		guard let price = Double(normalized), price >= 0 else {
			error = "Please enter a valid cost."
			return
		}
		guard !purchaser.trimmingCharacters(in: .whitespaces).isEmpty else {
			error = "Please enter who purchased."
			return
		}
		onSubmit(price, purchaser, notes)
	}
}
