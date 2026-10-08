//
//  TintedBackground.swift
//  lebensmittel
//
//  Created by Jai Sinha on 08/08/26.
//

import SwiftUI

struct TintedBackgroundModifier: ViewModifier {
	let color: Color
	let darkColor: Color?
	let extendsSafeArea: Bool
	@Environment(\.colorScheme) var colorScheme

	func body(content: Content) -> some View {
		let active = colorScheme == .dark ? (darkColor ?? color) : color
		let fill = active.opacity(0.28)
		return content.background(
			fill.ignoresSafeArea(edges: extendsSafeArea ? .all : [])
		)
	}
}

extension View {
	func tintedBackground(
		_ color: Color,
		dark: Color? = nil,
		extendsSafeArea: Bool = false
	) -> some View {
		modifier(
			TintedBackgroundModifier(
				color: color,
				darkColor: dark,
				extendsSafeArea: extendsSafeArea
			)
		)
	}
}
