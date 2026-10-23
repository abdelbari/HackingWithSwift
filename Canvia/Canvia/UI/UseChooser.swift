// "What will you use Canvia for?" — the first launch's one screen, before
// the welcome tour: a large chip per use, each said to VoiceOver as what
// choosing it does, and Skip, which keeps Home as it always was. However it
// is closed it is not asked again (UseProfile.set). The Android twin's
// UseChooser.

import SwiftUI

struct UseChooser: View {
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("What will you use Canvia for?")
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("We'll put the designs and templates you're likely to want first. You can change this in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(UseProfile.all) { use in
                            chip(use)
                        }
                    }
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { choose(nil) }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func chip(_ use: UseCase) -> some View {
        Button { choose(use.id) } label: {
            Text(use.label)
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 64)
                .padding(.horizontal, 8)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline))
                .foregroundStyle(Theme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("I'll use Canvia for: %@", use.label))
    }

    private func choose(_ id: String?) {
        UseProfile.set(id)
        onDone()
    }
}
