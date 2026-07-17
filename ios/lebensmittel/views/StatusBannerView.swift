//
//  StatusBannerView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 05/04/26.
//

import SwiftUI

struct StatusIconView: View {
	private var kind: StatusBannerKind? {
		switch (
			ConnectivityMonitor.shared.isOnline, SocketService.shared.isConnectedForSync,
			SyncEngine.shared.isSyncing
		) {
		case (false, _, _):
			return .offline
		case (true, true, true):
			return .syncing
		case (true, false, _):
			return .connecting
		default:
			return nil
		}
	}

	var body: some View {
		if let kind {
			Image(systemName: kind.systemImage)
				.foregroundStyle(kind.color)
		}
	}
}

enum StatusBannerKind {
	case offline
	case syncing
	case connecting

	var systemImage: String {
		switch self {
		case .offline: "wifi.slash"
		case .syncing: "arrow.triangle.2.circlepath"
		case .connecting: "arrow.clockwise"
		}
	}

	var color: Color {
		switch self {
		case .offline: .red
		case .syncing: .yellow
		case .connecting: .blue
		}
	}
}
