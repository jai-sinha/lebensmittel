//
//  InlineErrorView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 04/09/26.
//

import SwiftUI

struct InlineErrorView: View {
    let message: String

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Error: \(message)")
                    .foregroundStyle(.red)
                Text("Pull down to retry")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 100)
        }
        .background(Color(.systemBackground))
    }
}

#Preview {
    InlineErrorView(message: "Something went wrong. Please try again.")
}
