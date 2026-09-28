// Changing a shape into another in place: a rectangle into a circle, a star
// into a heart, keeping where it is, its size, its colours, border, shadow
// and everything else — as Canva's shape swap does, and as the Android
// twin's Change shape does. The same library the shape tool draws from.

import SwiftUI

struct ShapeSwapSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 10)]

    private var current: String? { store.singleSelection?.shapeId }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ContentLibrary.shapeCategories, id: \.self) { category in
                        let shapes = ContentLibrary.shapes.filter { $0.category == category }
                        if !shapes.isEmpty {
                            Text(ContentLibrary.shapeGroupName(category))
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(shapes) { shape in
                                    tile(shape)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Change shape")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    private func tile(_ shape: ShapeDef) -> some View {
        Button {
            store.swapShape(to: shape.id)
        } label: {
            LibraryShape(definition: shape, cornerRadius: 0)
                .fill(Theme.inkSecondary)
                .padding(10)
                .frame(width: 72, height: 72)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
                .background(RoundedRectangle(cornerRadius: 10)
                    .stroke(current == shape.id ? Theme.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shape.name)
        .accessibilityAddTraits(current == shape.id ? .isSelected : [])
    }
}

extension DesignStore {

    /// Whether `el` is a library shape that can become another one: not a
    /// drawn stroke, and not geometry of its own — a traced outline, a chart
    /// slice — which the swap would throw away.
    static func swapsShape(_ el: Element) -> Bool {
        el.type == .shape && el.pathData == nil && !Freehand.isStroke(el)
    }

    /// Every selected, unlocked library shape made shape `id`, as one step;
    /// nothing is recorded when none changes.
    func swapShape(to id: String) {
        let targets = selectedElements.filter { !$0.locked && Self.swapsShape($0) && $0.shapeId != id }
        guard !targets.isEmpty else { return }
        updateSelected { el in
            guard Self.swapsShape(el) else { return }
            el.shapeId = id
        }
    }
}
