// The first-run tour: four cards, once, and never again unless asked.

import SwiftUI

enum Onboarding {

    static let key = "canvia.tour.seen"

    struct Card: Identifiable, Equatable {
        var id: String
        var title: String
        var text: String
        var systemImage: String
    }

    static let cards: [Card] = [
        Card(id: "start", title: "Start anywhere",
             text: "Pick a size for a post, a story, a poster or a slide — or a template with the layout already done. Everything saves itself as you go.",
             systemImage: "rectangle.stack.badge.plus"),
        Card(id: "hands", title: "Made for your hands",
             text: "Pinch anywhere to zoom, even over what you just added. Drag on empty page to select several things at once. Rotation and alignment snap, and you feel it when they do.",
             systemImage: "hand.draw"),
        Card(id: "add", title: "Tap + to add",
             text: "Text, photos, shapes, stickers, charts and QR codes. Draw freehand with the pencil, drop pictures in from other apps, or scan a document straight onto the page.",
             systemImage: "plus.circle"),
        Card(id: "share", title: "Take it anywhere",
             text: "Export PNG, JPEG, PDF, SVG, a video or an animated GIF — or a print-ready PDF with bleed and crop marks. Present full screen from the menu.",
             systemImage: "square.and.arrow.up"),
    ]

    /// Shown on the first launch, and skipped when the app is being
    /// photographed or opened straight into a design.
    static func needsTour(defaults: UserDefaults, arguments: [String]) -> Bool {
        guard !arguments.contains("-canviaSkipTour"), !arguments.contains("-canviaOpenTemplate") else { return false }
        return !defaults.bool(forKey: key)
    }

    static var needsTour: Bool {
        needsTour(defaults: .standard, arguments: ProcessInfo.processInfo.arguments)
    }

    static func markSeen(_ defaults: UserDefaults) { defaults.set(true, forKey: key) }
    static func markSeen() { markSeen(.standard) }
    static func reset(_ defaults: UserDefaults) { defaults.removeObject(forKey: key) }
}

struct WelcomeTour: View {
    var onDone: () -> Void
    @State private var index = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $index) {
                ForEach(Array(Onboarding.cards.enumerated()), id: \.element.id) { i, card in
                    VStack(spacing: 18) {
                        Image(systemName: card.systemImage)
                            .font(.system(size: 56, weight: .light))
                            .foregroundStyle(Theme.accent)
                            .padding(.top, 30)
                        Text(card.title)
                            .font(.title2.weight(.bold))
                        Text(card.text)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 28)
                        Spacer(minLength: 0)
                    }
                    .tag(i)
                    .accessibilityElement(children: .combine)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if index < Onboarding.cards.count - 1 {
                    withAnimation { index += 1 }
                } else {
                    onDone()
                }
            } label: {
                Text(index < Onboarding.cards.count - 1 ? "Next" : "Get started")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.horizontal, 28)
            .padding(.bottom, 12)

            Button("Skip") { onDone() }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)
                .opacity(index < Onboarding.cards.count - 1 ? 1 : 0)
                .accessibilityHidden(index >= Onboarding.cards.count - 1)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
