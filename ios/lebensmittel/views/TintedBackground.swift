//
//  TintedBackground.swift
//  lebensmittel
//
//  Created by Jai Sinha on 08/08/26.
//

import SwiftUI

/// A backdrop colored with a soft wash of a view's accent hue
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
	/// A soft wash of `color` as the screen backdrop. White content surfaces
	/// (lists, cards) remain system-colored on top.
	///
	/// - Parameter color: the hue to wash across the backdrop in light mode.
	/// - Parameter extendsSafeArea: when true, the wash runs edge-to-edge
	///   behind the navigation and tab bars.
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
