//
//  ContentView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct ContentView: View {
	@Environment(GroupModel.self) var groupModel

	var statusBanner: StatusBannerKind? {
		guard groupModel.hasActiveGroup else { return nil }

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
		ZStack(alignment: .top) {
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

			if let banner = statusBanner {
				StatusBannerView(
					systemImage: banner.systemImage,
					message: banner.message,
					backgroundColor: banner.backgroundColor
				)
			}
		}
	}
}
