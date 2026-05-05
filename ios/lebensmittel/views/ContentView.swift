//
//  ContentView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct ContentView: View {
	@Environment(SessionManager.self) var sessionManager

	var statusBanner: StatusBannerKind? {
		guard sessionManager.isAuthenticated else { return nil }

		switch (
			ConnectivityMonitor.shared.isOnline, SocketService.shared.isConnectedForSync,
			SyncEngine.shared.isSyncing
		) {
		case (false, _, _):
			return .offline
		case (true, true, true):
			return .syncing
		case (true, false, _):
			return .reconnecting
		default:
			return nil
		}
	}

	var body: some View {
		VStack(spacing: 0) {
			if let banner = statusBanner {
				StatusBannerView(
					systemImage: banner.systemImage,
					message: banner.message,
					backgroundColor: banner.backgroundColor
				)
			}

			TabView {
				Tab("Groceries", systemImage: "list.bullet") {
					GroceriesView()
				}

				Tab("Meals", systemImage: "calendar") {
					MealsView()
				}

				Tab("Shopping", systemImage: "cart") {
					ShoppingView()
				}

				Tab("Receipts", systemImage: "receipt") {
					ReceiptsView()
				}
			}
		}
	}
}
