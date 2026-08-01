// InfoBadge.swift
// Reusable small "i" info button with popover for contextual help.

import SwiftUI

public struct InfoBadge: View {
    public let message: String
    @State private var showInfo = false

    public init(message: String) { self.message = message }

    public var body: some View {
        Button {
            showInfo.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Learn more")
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showInfo, arrowEdge: .bottom) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: 260)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        Text("Level 3 • 120 pts")
        HStack(spacing: 8) {
            Text("Level 3")
                .font(.subheadline.weight(.semibold))
            InfoBadge(message: "Levels are earned by accumulating points from completed shifts, peer reviews, and training. Higher levels unlock priority access to premium shifts.")
        }
    }
    .padding()
}
