// Bulk create in the editor (BulkCreate): an element connected to a column
// as one step, the pages made as one step named "Bulk create" — the rows
// kept on the design, so they are there the next time — or each row made a
// design of its own on the shelf, as the Android twin's view model does.

import Foundation

extension DesignStore {

    /// What making pages or designs came to: how many were made, and the
    /// words that no longer fit (BulkCreate.overflows).
    struct BulkOutcome: Equatable {
        var made: Int
        var overflows: [String]
        /// The designs made, when each row was a design of its own.
        var designs: [Design] = []
    }

    /// Element `id` on the page on screen connected to `column` — none for
    /// nil — as one step. A locked page, or a locked element, keeps what it
    /// had.
    func setBulkField(_ id: String, column: String?) {
        guard let el = page.elements.first(where: { $0.id == id }), !el.locked, el.bulkField != column else { return }
        applyToPage { page in
            guard let i = page.elements.firstIndex(where: { $0.id == id }) else { return }
            page.elements[i].bulkField = column
        }
    }

    /// Every photo upload, as a cell may name it (BulkCreate.picture).
    static func bulkPictures() -> [BulkCreate.Picture] {
        Uploads.all(.image).map { BulkCreate.Picture(id: $0.id, name: $0.fileName, src: "media:\($0.id)") }
    }

    /// One copy of the page on screen for each row of `data`, filled in,
    /// after the last page, and the rows kept on the design — one step,
    /// "Bulk create". Nothing when there are no rows.
    @discardableResult
    func bulkCreatePages(_ data: BulkData, pictures: [BulkCreate.Picture] = DesignStore.bulkPictures()) -> BulkOutcome {
        let template = page
        let made = BulkCreate.pages(design, pageId: template.id, data: data, pictures: pictures)
        guard !made.isEmpty else { return BulkOutcome(made: 0, overflows: []) }
        let overflows = BulkCreate.overflows(made, template: template, data: data, heightFor: measure)
        if hasPendingChanges && (editingTextId != nil || dictationTarget != nil) { commit() }
        namedStep = tr("Bulk create")
        apply { design in
            design.pages.append(contentsOf: made)
            design.bulk = data
        }
        buzz(.confirm)
        return BulkOutcome(made: made.count, overflows: overflows)
    }

    /// Each row of `data` a design of its own on the shelf — the page on
    /// screen filled in from it, titled by its first cell, as no design
    /// there is titled — and the rows kept on this design, as one step.
    @MainActor
    func bulkCreateDesigns(_ data: BulkData, pictures: [BulkCreate.Picture] = DesignStore.bulkPictures()) -> BulkOutcome {
        let template = page
        let pages = BulkCreate.pages(design, pageId: template.id, data: data, pictures: pictures)
        guard !pages.isEmpty else { return BulkOutcome(made: 0, overflows: []) }
        let overflows = BulkCreate.overflows(pages, template: template, data: data, heightFor: measure)
        let titles = BulkCreate.titles(of: data.rows, fallback: design.title,
                                       taken: DesignLibrary.recents().map(\.title))
        var made: [Design] = []
        let now = Date().timeIntervalSince1970 * 1000
        for (title, page) in zip(titles, pages) {
            let one = BulkCreate.separate(design, page: page, title: title, now: now)
            guard DesignLibrary.save(one) else { continue }
            DesignLibrary.writeThumbnail(for: one)
            made.append(one)
        }
        if design.bulk != data {
            namedStep = tr("Bulk create")
            apply { $0.bulk = data }
        }
        buzz(made.isEmpty ? .reject : .confirm)
        return BulkOutcome(made: made.count, overflows: overflows, designs: made)
    }
}
