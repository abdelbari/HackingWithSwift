// A template's own page, as a tap on one opens it on Home, in the Start
// sheet and in the editor's Templates panel: every page large, to swipe
// through; what it is — "Business · 1920 × 1080 · 10 pages"; its star; and
// "Customize this template", which for several pages still asks all of them
// or the page shown. Under it, "More like this" (Templates.similar); a tap
// on one shows that one here instead. Pressing and holding a card still
// opens its menu where it is. The Android twin's TemplatePreviewSheet.

import SwiftUI

struct TemplatePreviewSheet: View {
    /// What the button does where the sheet was opened, as the page strip
    /// says it: a new design on Home, this design in the editor.
    let note: String
    /// The template chosen, and the page shown alone — nil for every page.
    var onUse: (Template, Int?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var template: Template
    /// The template made once, at its own size, for the pictures.
    @State private var design: Design
    @State private var shown = 0
    @State private var starred: Bool
    @State private var similar: [Template]
    /// Customize asked of several pages: all, or the one shown.
    @State private var choosing = false

    init(template: Template, note: String, onUse: @escaping (Template, Int?) -> Void) {
        self.note = note
        self.onUse = onUse
        _template = State(initialValue: template)
        _design = State(initialValue: template.instantiate())
        _starred = State(initialValue: Favorites.isFavorite("template", template.id))
        _similar = State(initialValue: Templates.similar(template))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        pager.id(Self.top)
                        header
                        customizeButton
                        moreLikeThis(proxy)
                    }
                    .padding(.vertical, 12)
                }
            }
            .background(Theme.workspace)
            .navigationTitle(template.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.large])
        .confirmationDialog(template.name, isPresented: $choosing, titleVisibility: .visible) {
            Button(trn("Use all %d page|Use all %d pages", design.pages.count)) { use(nil) }
            Button("Use this page") { use(shown) }
        } message: {
            Text(note)
        }
    }

    private static let top = "top"

    /// Every page at the sheet's width, drawn by the page renderer and
    /// kept as the page strip's are (ThumbnailCache); swiped through.
    private var pager: some View {
        let first = design.pages[0]
        let size = design.size(for: first)
        let ratio = min(max(size.width / max(size.height, 1), 0.4), 3)
        return TabView(selection: $shown) {
            ForEach(Array(design.pages.enumerated()), id: \.element.id) { index, page in
                pagePicture(page)
                    .padding(.horizontal, 16)
                    .tag(index)
                    .accessibilityElement()
                    .accessibilityLabel(tr("Page %d of %d", index + 1, design.pages.count))
                    .accessibilityAddTraits(.isImage)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: design.pages.count > 1 ? .always : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .aspectRatio(ratio, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: 460)
    }

    private func pagePicture(_ page: Page) -> some View {
        let size = design.size(for: page)
        return PageThumbnail(design: design, page: page, pixelWidth: 720)
            .aspectRatio(size.width / max(size.height, 1), contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "Business · 1920 × 1080 · 10 pages", and the star.
    private var header: some View {
        HStack(spacing: 12) {
            Text(Templates.caption(template))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Favorites.toggle("template", template.id)
                starred = Favorites.isFavorite("template", template.id)
            } label: {
                Image(systemName: starred ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(starred ? Color.yellow : Theme.ink)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(starred ? tr("Remove from favourites") : tr("Add to favourites"))
        }
        .padding(.horizontal, 16)
    }

    private var customizeButton: some View {
        Button {
            if design.pages.count > 1 { choosing = true } else { use(nil) }
        } label: {
            Text("Customize this template").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .controlSize(.large)
        .padding(.horizontal, 16)
    }

    /// Eight like it; a tap shows that one here, from the top.
    @ViewBuilder
    private func moreLikeThis(_ proxy: ScrollViewProxy) -> some View {
        if !similar.isEmpty {
            Text("More like this")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(similar) { other in
                    similarCard(other) {
                        show(other)
                        withAnimation { proxy.scrollTo(Self.top, anchor: .top) }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func similarCard(_ other: Template, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                TemplateThumb(template: other)
                Text(other.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("%@, %@", other.name, Templates.caption(other)))
    }

    private func show(_ other: Template) {
        template = other
        design = other.instantiate()
        shown = 0
        starred = Favorites.isFavorite("template", other.id)
        similar = Templates.similar(other)
    }

    private func use(_ page: Int?) {
        let chosen = template
        dismiss()
        onUse(chosen, page)
    }
}
