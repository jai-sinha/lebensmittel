//
//  ClientIdentity.swift
//  lebensmittel
//
//  Created by Jai Sinha on 08/04/26.
//

import Foundation

/// A stable per-install identifier sent on every request and echoed back by the
/// server on websocket broadcasts, so the client can ignore echoes of its own
/// mutations. Install-scoped (not account-scoped): it identifies the client
/// device connection, independent of who is signed in.
enum ClientIdentity {
	private static let userDefaultsKey = "installClientID"

	static let id: String = {
		if let stored = UserDefaults.standard.string(forKey: userDefaultsKey),
			!stored.isEmpty
		{
			return stored
		}
		let newID = UUID().uuidString
		UserDefaults.standard.set(newID, forKey: userDefaultsKey)
		return newID
	}()
}
