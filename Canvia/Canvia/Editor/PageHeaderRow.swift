// Scrolling through pages: the row over each page in the column, and the
// button under the last one — as the Android twin draws them. Each button
// makes its page the one worked, then does what the pages bar does to it,
// through the store's own page functions.

import SwiftUI

struct PageHeaderRow: View {
    @Bindable var store: DesignStore
    let index: Int
    /// While crop, typing, the pen, the eraser or a preview holds the view
    /// to its page, the rows only say which page is which.
    let pinned: Bool
    /// Delete asks first when the page has something on it.
    var onDelete: () -> Void
    var onNotes: () -> Void

    /// The page, or a blank one for the moment a deleted page's row is
    /// still drawn.
    private var page: Page { store.design.pages.indices.contains(index) ? store.design.pages[index] : Page() }
    private var current: Bool { index == store.pageIndex }

    var body: some View {
        HStack(spacing: 0) {
            title
            Spacer(minLength: 4)
            if !pinned { actions }
        }
        .frame(height: PageColumn.header)
        // A row of a fixed height: Larger Text up to accessibility2.
        .chromeTypeSize()
    }

    /// "Page 2 · Intro", the eye struck through on a hidden page and the
    /// padlock on a locked one.
    private var title: some View {
        HStack(spacing: 4) {
            Text(PageTitles.named(index + 1, title: page.title))
                .font(.footnote.weight(current ? .semibold : .regular))
                .foregroundStyle(current ? Color.primary : Color.secondary)
                .lineLimit(1)
            if page.hidden == true {
                Image(systemName: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if PageLocks.isLocked(page) {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(PagesBar.spokenThumb(number: index + 1, title: page.title, current: current,
                                                 hidden: page.hidden == true, locked: PageLocks.isLocked(page)))
        .accessibilityAddTraits(.isHeader)
    }

    /// Add page below, Duplicate page, Delete page — never the only page —
    /// and More.
    @ViewBuilder
    private var actions: some View {
        button("plus.square", tr("Add page below")) { store.addPage() }
        button("plus.square.on.square", tr("Duplicate page")) { store.duplicatePage() }
        if store.design.pages.count > 1 {
            button("trash", tr("Delete page")) { onDelete() }
        }
        moreMenu
    }

    /// Hide or show, Lock or unlock, Copy page, and the page's title and
    /// notes. Hiding the only page is not offered, as in the pages bar.
    private var moreMenu: some View {
        Menu {
            if store.design.pages.count > 1 || page.hidden == true {
                Button { onPage { store.setPageHidden(store.page.hidden != true) } } label: {
                    Label(page.hidden == true ? tr("Show page") : tr("Hide page"),
                          systemImage: page.hidden == true ? "eye" : "eye.slash")
                }
            }
            Button { onPage { store.setPageLocked(!store.isPageLocked) } } label: {
                Label(PageLocks.isLocked(page) ? tr("Unlock page") : tr("Lock page"),
                      systemImage: PageLocks.isLocked(page) ? "lock.open" : "lock")
            }
            Button { onPage { store.copyPage() } } label: {
                Label("Copy page", systemImage: "doc.on.doc")
            }
            Button { onPage { onNotes() } } label: {
                Label("Notes…", systemImage: "note.text")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
    }

    private func button(_ symbol: String, _ name: String, action: @escaping () -> Void) -> some View {
        Button { onPage(action) } label: {
            Image(systemName: symbol)
                .font(.subheadline)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(name)
        .accessibilityValue("Page \(index + 1)")
    }

    /// This page made the one worked, then `action` on it.
    private func onPage(_ action: () -> Void) {
        store.setPage(index)
        action()
    }
}

/// "+ Add page" under the last page: a page after it, as the pages bar's +.
struct AddPageRow: View {
    @Bindable var store: DesignStore

    var body: some View {
        Button {
            store.setPage(store.design.pages.count - 1)
            store.addPage()
        } label: {
            Label("Add page", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                    .foregroundStyle(.secondary))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add page")
        .chromeTypeSize()
    }
}
