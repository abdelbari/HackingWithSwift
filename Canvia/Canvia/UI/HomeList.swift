// Home's list view: each design a row 56pt high rather than a card — a
// small picture, its title, then its type, size and when it was last
// edited, and its star — as the Android twin's DesignRow. Which of the two
// Home shows is kept on this phone under "homeLayout", the key both phones
// spell the same.

import SwiftUI

enum HomeLayout {
    /// The preference: "grid" (the cards) or "list" (the rows).
    static let key = "homeLayout"
    static let grid = "grid"
    static let list = "list"

    /// Whether a stored value is the list; anything else is the grid.
    static func isList(_ value: String) -> Bool { value == list }

    /// The toggle's label: what a tap shows next.
    static func toggleLabel(showingList: Bool) -> String {
        showingList ? tr("Show as grid") : tr("Show as list")
    }

    /// Its design type's name, when it has a known one.
    static func typeName(_ recent: RecentDesign) -> String? {
        recent.type.flatMap { SizePreset.byId($0)?.name }
    }

    /// A row's second line: "Flyer A5 · 148 × 210 mm · Edited 3 days ago"
    /// — its type when it has one, its size and when it was last edited.
    static func line(_ recent: RecentDesign, edited: String) -> String {
        let when = tr("Edited %@", RelativeTime.lowercasedFirst(edited))
        return ([typeName(recent), recent.sizeText, when] as [String?]).compactMap { $0 }.joined(separator: " · ")
    }

    /// What VoiceOver says of a row, as one element: "Poster, Flyer A5,
    /// edited 3 days ago, starred".
    static func spoken(_ recent: RecentDesign, edited: String) -> String {
        var parts: [String] = [recent.title]
        if let type = typeName(recent) { parts.append(type) }
        parts.append(tr("edited %@", RelativeTime.lowercasedFirst(edited)))
        if recent.starred { parts.append(tr("starred")) }
        return parts.joined(separator: ", ")
    }
}

/// A design as a row of Home's list view. Swiped left it goes to Recently
/// deleted (with Undo, as Delete does); swiped right it is starred or
/// unstarred. Neither while selecting, when a tap picks it. With large
/// type the row grows and its second line wraps.
struct DesignRow: View {
    let recent: RecentDesign
    var snippet: DesignLibrary.Snippet?
    var selecting: Bool
    var picked: Bool
    var highlighted: Bool
    var onTap: () -> Void
    var onDelete: () -> Void
    var onStar: () -> Void

    @ScaledMetric(relativeTo: .body) private var thumb: CGFloat = 40

    var body: some View {
        let edited = RelativeTime.text(ms: recent.updatedAt)
        SwipeActionsRow(enabled: !selecting, onLeft: onDelete, onRight: onStar, starred: recent.starred) {
            Button(action: onTap) { content(edited) }
                .buttonStyle(.plain)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(edited))
        .accessibilityValue(selecting ? (picked ? tr("selected") : tr("not selected")) : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTap() }
        .accessibilityAction(named: Text(recent.starred ? tr("Remove from starred") : tr("Add to starred"))) { onStar() }
        .accessibilityAction(named: Text("Delete")) { onDelete() }
    }

    private func label(_ edited: String) -> String {
        let said = HomeLayout.spoken(recent, edited: edited)
        guard let snippet else { return said }
        return said + ", " + snippet.text
    }

    private func content(_ edited: String) -> some View {
        HStack(spacing: 10) {
            picture
            VStack(alignment: .leading, spacing: 2) {
                Text(recent.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                // Wraps rather than cut off, at the large text sizes.
                Text(HomeLayout.line(recent, edited: edited))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let snippet {
                    Text(DesignLibrary.attributed(snippet))
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if recent.starred {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay { if highlighted { RoundedRectangle(cornerRadius: 10).stroke(Theme.accent, lineWidth: 3) } }
        .contentShape(Rectangle())
    }

    private var picture: some View {
        ShelfThumbnail(id: recent.id, stamp: recent.thumbnailStamp)
            .frame(width: thumb, height: thumb)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                if selecting {
                    Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Theme.accent)
                        .shadow(color: .black.opacity(0.25), radius: 2)
                }
            }
    }
}

/// A row that can be swiped sideways, inside Home's scroll view where a
/// List's swipe actions are not to be had: past `threshold` to the left
/// does `onLeft` (Recently deleted), to the right `onRight` (the star). The
/// row springs back either way. Only a drag mostly sideways moves it, so
/// scrolling up and down is left alone.
struct SwipeActionsRow<Content: View>: View {
    var enabled: Bool
    var onLeft: () -> Void
    var onRight: () -> Void
    var starred: Bool
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far a row must be swiped to act.
    static var threshold: CGFloat { 80 }

    var body: some View {
        ZStack {
            behind
            content()
                .offset(x: offset)
        }
        .simultaneousGesture(drag, including: enabled ? .all : .subviews)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                let dx = value.translation.width
                guard abs(dx) > abs(value.translation.height) * 1.5 else { return }
                offset = dx
            }
            .onEnded { _ in
                let dx = offset
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) { offset = 0 }
                if dx <= -Self.threshold {
                    onLeft()
                } else if dx >= Self.threshold {
                    onRight()
                }
            }
    }

    /// What shows under the row as it moves: the bin on the right, the
    /// star on the left.
    private var behind: some View {
        let deleting = offset < 0
        return HStack {
            if !deleting {
                Image(systemName: starred ? "star.slash.fill" : "star.fill").foregroundStyle(.yellow)
            }
            Spacer()
            if deleting {
                Image(systemName: "trash.fill").foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(deleting ? Color.red : Theme.accent.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        .opacity(offset == 0 ? 0 : 1)
        .accessibilityHidden(true)
    }
}
