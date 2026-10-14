// A built-in template of several pages — a deck, a card's front and back, a
// resume's two pages — as the Templates panel and Home open it: a strip of
// its pages, the one picked shown larger, with "Apply all N pages" and "Use
// this page". The page count rides on the template's picture everywhere it
// is shown (PageCountBadge), as on your own templates'.

import SwiftUI

/// "10" in a dark pill at a picture's corner: how many pages a template
/// has. Nothing for one page.
struct PageCountBadge: View {
    let count: Int

    var body: some View {
        if count > 1 {
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .padding(5)
                .accessibilityHidden(true)
        }
    }
}

struct TemplateSetSheet: View {
    let template: Template
    /// Every page: into an empty design, or after the page open.
    var applyAll: () -> Void
    /// The page picked, by index, on its own.
    var usePage: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    /// The template made once, at its own size, for the pictures.
    @State private var design: Design
    @State private var picked = 0

    init(template: Template, applyAll: @escaping () -> Void, usePage: @escaping (Int) -> Void) {
        self.template = template
        self.applyAll = applyAll
        self.usePage = usePage
        _design = State(initialValue: template.instantiate())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                preview
                strip
                buttons
            }
            .padding(.vertical, 12)
            .background(Theme.workspace)
            .navigationTitle(template.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// The page picked, larger, and which it is.
    private var preview: some View {
        let page = design.pages[min(picked, design.pages.count - 1)]
        let size = design.size(for: page)
        return VStack(spacing: 6) {
            PageThumbnail(design: design, page: page)
                .id(page.id)
                .aspectRatio(size.width / max(size.height, 1), contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline))
            Text(PageTitles.counter(picked + 1, of: design.pages.count, title: page.title))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }

    /// Every page small, in a row to scroll; a tap picks one.
    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(Array(design.pages.enumerated()), id: \.element.id) { index, page in
                    stripTile(index, page)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 78)
    }

    private func stripTile(_ index: Int, _ page: Page) -> some View {
        let size = design.size(for: page)
        return Button { picked = index } label: {
            PageThumbnail(design: design, page: page)
                .aspectRatio(size.width / max(size.height, 1), contentMode: .fit)
                .frame(height: 70)
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .stroke(index == picked ? Theme.accent : Theme.hairline, lineWidth: index == picked ? 3 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PageTitles.named(index + 1, title: page.title))
        .accessibilityAddTraits(index == picked ? .isSelected : [])
    }

    private var buttons: some View {
        VStack(spacing: 8) {
            Button {
                dismiss()
                applyAll()
            } label: {
                Text("Apply all \(design.pages.count) pages").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            Button {
                dismiss()
                usePage(picked)
            } label: {
                Text("Use this page").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
    }
}
