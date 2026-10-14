// The presenter's console's page grid, to go straight to a page, and its
// pointer: a press and hold on the page up draws a red dot on the second
// screen at the same place on the page, which follows the finger and goes
// when it lifts.

import SwiftUI

/// The pointer: a press and hold on the page, then a drag, moves the red
/// dot with the finger; letting go takes it away.
enum PresenterPointing {
    @MainActor
    static func gesture(session: PresentSession, in size: CGSize) -> some Gesture {
        // The drag alongside knows where the finger is from the moment it
        // lands, so a hold that has not moved yet shows the dot at once, as
        // on the Android twin; the sequence only says the hold is long enough.
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .simultaneously(with: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, _)? = value.first, let drag = value.second else { return }
                session.pointer = Presenter.pagePoint(drag.location, in: size,
                                                      page: session.design.size(for: session.page))
            }
            .onEnded { _ in session.pointer = nil }
    }
}

/// The console's page grid, Pages: the pages shown, hidden pages left out,
/// numbered as the counter numbers them; a tap goes to the page.
struct PresenterPagesSheet: View {
    let design: Design
    /// The page up, by index.
    let current: Int
    let pick: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Array(Presenter.gridPages(design).enumerated()), id: \.element) { number, index in
                        cell(number: number + 1, index: index)
                    }
                }
                .padding(16)
            }
            .background(Theme.workspace)
            .navigationTitle("Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func cell(number: Int, index: Int) -> some View {
        let page = design.pages[index]
        let size = design.size(for: page)
        let here = index == current
        let name = PageTitles.named(number, title: page.title)
        return Button {
            pick(index)
            dismiss()
        } label: {
            VStack(spacing: 6) {
                PageThumbnail(design: design, page: page)
                    .aspectRatio(size.width / max(size.height, 1), contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(here ? Theme.accent : Theme.hairline, lineWidth: here ? 2.5 : 1))
                Text(name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(Theme.ink)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityValue(here ? tr("showing") : "")
    }
}
