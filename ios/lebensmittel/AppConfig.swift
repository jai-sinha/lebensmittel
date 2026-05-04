//
//  AppConfig.swift
//  lebensmittel
//
//  Created by Jai Sinha on 04/07/26.
//

import Foundation

enum AppConfig {
	private static func requiredValue(forKey key: String) -> String {
		guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty
		else {
			fatalError("Missing Info.plist key: \(key)")
		}

		return value
	}

	static let apiBaseURL = URL(string: requiredValue(forKey: "API_BASE_URL"))!
	static let webSocketURL = URL(string: requiredValue(forKey: "WEB_SOCKET_URL"))!
}
