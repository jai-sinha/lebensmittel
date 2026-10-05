//
//  ClientIdentity.swift
//  lebensmittel
//
//  Created by Jai Sinha on 08/04/26.
//

import Foundation

/// Per-install preferences
enum ClientIdentity {
	private static let userDefaultsKey = "installClientID"
	static let preferredCurrencyDefaultsKey = "preferredCurrencyCode"

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

	static var preferredCurrency: Currency {
		get {
			guard let stored = UserDefaults.standard.string(forKey: preferredCurrencyDefaultsKey),
				let currency = Currency(rawValue: stored)
			else { return .eur }
			return currency
		}
		set {
			UserDefaults.standard.set(newValue.rawValue, forKey: preferredCurrencyDefaultsKey)
		}
	}
}

/// Currencies offered for receipt display, persisted per install.
enum Currency: String, CaseIterable {
	case eur = "EUR"
	case usd = "USD"
	case gbp = "GBP"
	case chf = "CHF"

	var displayName: String {
		Locale.current.localizedString(forCurrencyCode: rawValue) ?? rawValue
	}
}
