// Export's "Choose…": every page as a thumbnail with a tick, Select all and
// Select none, and hidden pages shown dimmed — unticked at first, though
// they can be ticked. The pages are kept by id, so a page moved meanwhile is
// still the page chosen. The Android twin's PagePickerSheet.

import SwiftUI

struct PagePickerSheet: View {
    let design: Design
    @Binding var chosen: [String]
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Array(design.pages.enumerated()), id: \.element.id) { index, page in
                        pageCell(index: index, page: page)
                    }
                }
                .padding(16)
            }
            .background(Theme.workspace)
            .navigationTitle(ExportChoices.countText(chosen.count, of: design.pages.count))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu("Select") {
                        Button("Select all") { chosen = design.pages.map(\.id) }
                        Button("Select none") { chosen = [] }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func pageCell(index: Int, page: Page) -> some View {
        let on = chosen.contains(page.id)
        let hidden = page.hidden == true
        let size = design.size(for: page)
        return Button {
            chosen = ExportChoices.toggled(chosen, page.id, in: design)
        } label: {
            VStack(spacing: 6) {
                PageThumbnail(design: design, page: page)
                    .aspectRatio(size.width / max(size.height, 1), contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 120)
                    .opacity(hidden ? 0.4 : 1)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(on ? Theme.accent : Theme.hairline, lineWidth: on ? 2.5 : 1))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white, on ? Theme.accent : Color.gray)
                            .padding(4)
                    }
                HStack(spacing: 3) {
                    Text("\(index + 1)")
                    if hidden { Image(systemName: "eye.slash") }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(hidden ? Color.secondary : Theme.ink)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hidden ? "Page \(index + 1), hidden" : "Page \(index + 1)")
        .accessibilityValue(on ? "chosen" : "not chosen")
        .accessibilityAddTraits(.isButton)
    }
}
