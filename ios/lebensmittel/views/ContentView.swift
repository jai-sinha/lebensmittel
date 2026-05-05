//
//  ContentView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct ContentView: View {
	@Environment(SessionManager.self) var sessionManager

	var body: some View {
		VStack(spacing: 0) {
			if !ConnectivityMonitor.shared.isOnline {
				StatusBannerView(
					systemImage: StatusBannerKind.offline.systemImage,
					message: StatusBannerKind.offline.message,
					backgroundColor: StatusBannerKind.offline.backgroundColor
				)
			} else if SocketService.shared.bannerState == .reconnecting {
				StatusBannerView(
					systemImage: StatusBannerKind.reconnecting.systemImage,
					message: StatusBannerKind.reconnecting.message,
					backgroundColor: StatusBannerKind.reconnecting.backgroundColor
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
