// What's new on Home and in Settings ▸ Help (WhatsNew): the card shown
// once for each version of the notes newer than the one last closed, and
// every version's notes on a sheet. As the Android twin's WhatsNewUi.

import SwiftUI

/// Home's What's new card: the newest items' titles — each opening its
/// place on Home, where it has one — See all, and a close button that marks
/// them seen.
struct WhatsNewCard: View {
    var items: [WhatsNew.Note]
    var onOpen: (String) -> Void
    var onSeeAll: () -> Void
    var onDismiss: () -> Void

    /// The card's items: the newest few.
    static let cardItems = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("What's new")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Close What's new")
            }
            ForEach(items.prefix(Self.cardItems)) { item in itemRow(item) }
            Button("See all", action: onSeeAll)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
        .tint(Theme.accent)
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentSubtle, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    @ViewBuilder
    private func itemRow(_ item: WhatsNew.Note) -> some View {
        if let place = item.opens {
            Button(item.title) { onOpen(place) }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 40)
        } else {
            Text(item.title)
                .font(.subheadline)
                .frame(minHeight: 40)
        }
    }
}

/// Every version's notes, newest first, from the card's See all or
/// Settings ▸ Help ▸ What's new: each item's title and what it does, and
/// Show me on one with a place on Home to go — `onOpen`, when there is a
/// Home to go to.
struct WhatsNewSheet: View {
    var onOpen: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(WhatsNew.all, id: \.version) { version in
                    Section(tr("Version %@", version.version)) {
                        ForEach(version.items) { item in itemRow(item) }
                    }
                }
            }
            .navigationTitle("What's new")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func itemRow(_ item: WhatsNew.Note) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title).font(.headline)
            Text(item.body).font(.subheadline).foregroundStyle(.secondary)
            if let place = item.opens, let onOpen {
                Button("Show me") {
                    dismiss()
                    onOpen(place)
                }
                .font(.subheadline.weight(.semibold))
                .tint(Theme.accent)
            }
        }
        .padding(.vertical, 4)
    }
}
