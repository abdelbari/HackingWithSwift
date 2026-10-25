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

/// Up to five ways to finish what is being typed, from the templates' words
/// (TemplateSearch.completions), under the field and above the recent
/// searches: a tap searches it.
struct CompletionRows: View {
    let completions: [String]
    var onSearch: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(completions, id: \.self) { completion in
                Button {
                    onSearch(completion)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(completion)
                            .lineLimit(1)
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }
}

/// Over a search corrected for a typo: "Showing results for “birthday”",
/// and "Search instead for “brithday”" to search the words as typed.
struct CorrectedSearch: View {
    let corrected: String
    let typed: String
    var onSearchInstead: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TemplateSearch.showingFor(corrected))
                .font(.subheadline)
            Button(TemplateSearch.searchInstead(typed), action: onSearchInstead)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .onAppear { AccessibilityNotification.Announcement(TemplateSearch.showingFor(corrected)).post() }
    }
}

/// "Coming up: Halloween · 6 days": the nearest occasion's templates, a
/// strip of cards under Home's sizes, with See all — the templates filtered
/// by that occasion. Hidden in Settings ▸ Home ("homeSeasonal").
struct ComingUpRow: View {
    let title: String
    let templates: [Template]
    var onSeeAll: () -> Void
    var onTemplate: (Template) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("See all", action: onSeeAll)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(templates) { template in
                        card(template)
                    }
                }
                .padding(.horizontal)
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
