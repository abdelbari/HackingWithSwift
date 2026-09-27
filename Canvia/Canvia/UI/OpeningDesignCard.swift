// "Opening the design…": what shows while a design file is read in, its
// photos stored and its clips written out — a few seconds for a file full of
// clips, in which the screen used to sit frozen with no sign of why.

import SwiftUI

struct OpeningDesignCard: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.15)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Opening the design…")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
        .onAppear {
            AccessibilityNotification.Announcement("Opening the design").post()
        }
    }
}
