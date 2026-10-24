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
    /// "Bulk create". Nothing when there are no rows. The pages are made
    /// and measured off the main actor, as the Android twin makes them:
    /// there may be 500.
    @MainActor
    @discardableResult
    func bulkCreatePages(_ data: BulkData, pictures: [BulkCreate.Picture] = DesignStore.bulkPictures()) async -> BulkOutcome {
        let template = page
        let (made, overflows) = await bulkPages(data, template: template, pictures: pictures)
        guard !made.isEmpty else { return BulkOutcome(made: 0, overflows: []) }
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
    /// Made and saved off the main actor; each card's picture is rendered
    /// on it, a turn given back between them.
    @MainActor
    func bulkCreateDesigns(_ data: BulkData, pictures: [BulkCreate.Picture] = DesignStore.bulkPictures()) async -> BulkOutcome {
        let source = design
        let (pages, overflows) = await bulkPages(data, template: page, pictures: pictures)
        guard !pages.isEmpty else { return BulkOutcome(made: 0, overflows: []) }
        let titles = BulkCreate.titles(of: data.rows, fallback: source.title,
                                       taken: DesignLibrary.recents().map(\.title))
        let now = Date().timeIntervalSince1970 * 1000
        let saved = await Task.detached(priority: .userInitiated) { () -> [Design] in
            zip(titles, pages).compactMap { pair -> Design? in
                let one = BulkCreate.separate(source, page: pair.1, title: pair.0, now: now)
                return DesignLibrary.save(one) ? one : nil
            }
        }.value
        var made: [Design] = []
        for one in saved {
            DesignLibrary.writeThumbnail(for: one)
            made.append(one)
            await Task.yield()
        }
        if design.bulk != data {
            namedStep = tr("Bulk create")
            apply { $0.bulk = data }
        }
        buzz(made.isEmpty ? .reject : .confirm)
        return BulkOutcome(made: made.count, overflows: overflows, designs: made)
    }

    /// The pages `data` fills from `template`, and what no longer fits on
    /// them, worked out off the main actor.
    @MainActor
    private func bulkPages(_ data: BulkData, template: Page,
                           pictures: [BulkCreate.Picture]) async -> ([Page], [String]) {
        let source = design
        let measure = self.measure
        return await Task.detached(priority: .userInitiated) { () -> ([Page], [String]) in
            let made = BulkCreate.pages(source, pageId: template.id, data: data, pictures: pictures)
            guard !made.isEmpty else { return ([], []) }
            return (made, BulkCreate.overflows(made, template: template, data: data, heightFor: measure))
        }.value
    }
}
