// What Home's search offers before anything is typed, as Canva's does: the
// searches made lately, newest first — a tap searches again, the × (or
// VoiceOver's Remove) takes one away and Clear takes them all — then the
// templates used lately. Kept on this phone (RecentSearches). The Android
// twin's RecentSearchUi.

import SwiftUI

/// "Recent": the searches made lately, each a row.
struct RecentSearchRows: View {
    let searches: [String]
    var onSearch: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Clear") { RecentSearches.setSearches([]) }
                    .font(.subheadline)
            }
            ForEach(searches, id: \.self) { query in
                row(query)
            }
        }
        .padding(.horizontal)
    }

    private func row(_ query: String) -> some View {
        HStack(spacing: 12) {
            Button {
                onSearch(query)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(query)
                        .lineLimit(1)
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAction(named: Text("Remove")) { RecentSearches.forget(query) }
            Button {
                RecentSearches.forget(query)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("Remove “%@”", query))
        }
    }
}

/// "Recently used": the templates used lately, newest first, a strip of
/// cards — on Home under an empty search, first in its templates, and first
/// in a size's Start sheet. A tap looks at one, as any card's does.
struct RecentTemplatesRow: View {
    let templates: [Template]
    /// The room on either side, the screen's own margin where there is one.
    var inset: CGFloat = 16
    var onTemplate: (Template) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recently used")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, inset)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(templates) { template in
                        card(template)
                    }
                }
                .padding(.horizontal, inset)
            }
        }
    }

    private func card(_ template: Template) -> some View {
        Button {
            onTemplate(template)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                TemplateThumb(template: template)
                    .frame(height: 110)
                Text(template.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            .frame(width: 120)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("%@, %@", template.name, Templates.caption(template)))
    }
}
