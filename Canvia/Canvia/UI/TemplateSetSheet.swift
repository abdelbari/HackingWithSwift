// A template of several pages — a deck, a card's front and back, a resume's
// two pages, or one of your own — as the Templates panel, Home and the Start
// sheet open it: a strip of its pages, the one picked shown larger, with
// "Apply all N pages" and "Use this page" — and, in the editor, "Add as
// new page". The page count rides on the template's picture everywhere it
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
    /// The template's name, for the title.
    let name: String
    /// What each button does where it is asked, as the Android twin's strip
    /// says it: on Home a new design, in the editor this one.
    let note: String
    /// Every page: into an empty design, or after the page open.
    var applyAll: () -> Void
    /// The page picked, by index, on its own.
    var usePage: (Int) -> Void
    /// In the editor, the page picked, by index, on a new page after this
    /// one; none elsewhere.
    var addPage: ((Int) -> Void)?
    @Environment(\.dismiss) private var dismiss
    /// The template made once, at its own size, for the pictures.
    @State private var design: Design
    @State private var picked = 0

    /// A built-in template of several pages.
    init(template: Template, note: String, applyAll: @escaping () -> Void, usePage: @escaping (Int) -> Void,
         addPage: ((Int) -> Void)? = nil) {
        self.init(name: template.name, design: template.instantiate(), note: note, applyAll: applyAll,
                  usePage: usePage, addPage: addPage)
    }

    /// Any template of several pages — one of your own too — as `design`,
    /// at its own size.
    init(name: String, design: Design, note: String, applyAll: @escaping () -> Void, usePage: @escaping (Int) -> Void,
         addPage: ((Int) -> Void)? = nil) {
        self.name = name
        self.note = note
        self.applyAll = applyAll
        self.usePage = usePage
        self.addPage = addPage
        _design = State(initialValue: design)
    }

    /// On Home and in the Start sheet: a new design.
    static let startNote = tr("Start a design with all of them, or with the page picked alone.")

    /// In the editor: all of them in place of a design with nothing on it,
    /// else after this page; or the page picked on this page.
    static func editorNote(empty: Bool) -> String {
        empty ? tr("Apply all of them in place of this empty design, or use the page picked on this page.")
              : tr("Apply all of them after this page, or use the page picked on this page.")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                preview
                strip
                buttons
            }
            .padding(.vertical, 12)
            .background(Theme.workspace)
            .navigationTitle(name)
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
                Text(trn("Apply all %d page|Apply all %d pages", design.pages.count)).frame(maxWidth: .infinity)
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
            if let addPage {
                Button {
                    dismiss()
                    addPage(picked)
                } label: {
                    Text("Add as new page").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
    }
}
