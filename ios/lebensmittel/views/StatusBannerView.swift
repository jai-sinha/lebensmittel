//
//  StatusBannerView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 05/04/26.
//

import SwiftUI

struct StatusBannerView: View {
	let systemImage: String
	let message: String
	let backgroundColor: Color

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: systemImage)
			Text(message)
		}
		.font(.footnote)
		.fontWeight(.medium)
		.foregroundStyle(.white)
		.frame(maxWidth: .infinity)
		.padding(.horizontal, 16)
		.padding(.vertical, 10)
		.background(backgroundColor)
	}
}

enum StatusBannerKind {
	case offline
	case syncing
	case reconnecting

	var systemImage: String {
		switch self {
		case .offline: "wifi.slash"
		case .syncing: "arrow.triangle.2.circlepath"
		case .reconnecting: "arrow.clockwise"
		}
	}

	var message: String {
		switch self {
		case .offline: "You're offline. Changes will sync when you're back online."
		case .syncing: "Syncing..."
		case .reconnecting: "Reconnecting..."
		}
	}

	var backgroundColor: Color {
		switch self {
		case .offline: .red
		case .syncing: .blue
		case .reconnecting: .gray
		}
	}
}
