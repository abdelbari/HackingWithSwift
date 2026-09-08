// Choosing the shape a photo is clipped to.
//
// The same library the shape tool draws from, so a photo can be a circle, a
// star, a blob or a speech bubble without a second set of geometry to
// maintain.

import SwiftUI

struct FrameSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 10)]

    private var current: String? { store.singleSelection?.maskShapeId }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("A frame clips the photo to a shape. Square frames keep "
                         + "their proportions, so applying one squares the picture.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, spacing: 10) {
                        noneTile
                    }

                    ForEach(ContentLibrary.shapeCategories, id: \.self) { category in
                        let shapes = ContentLibrary.shapes.filter { $0.category == category }
                        if !shapes.isEmpty {
                            Text(category)
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
            .navigationTitle("Frame")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .onDisappear { if store.hasPendingChanges { store.commit() } }
    }

    private var noneTile: some View {
        Button {
            store.updateSelected { $0.maskShapeId = nil }
        } label: {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                .foregroundStyle(.secondary)
                .frame(width: 72, height: 72)
                .overlay(Text("None").font(.caption))
                .background(selection(active: current == nil))
        }
        .buttonStyle(.plain)
    }

    private func tile(_ shape: ShapeDef) -> some View {
        Button {
            apply(shape.id)
        } label: {
            LibraryShape(definition: shape, cornerRadius: 0)
                .fill(Theme.inkSecondary)
                .padding(10)
                .frame(width: 72, height: 72)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
                .background(selection(active: current == shape.id))
        }
        .buttonStyle(.plain)
    }

    private func selection(active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(active ? Theme.accent : .clear, lineWidth: 2)
    }

    /// Applying a frame squares the element about its centre.
    ///
    /// The library path is drawn in a 100x100 box and scaled onto whatever the
    /// element's box is, so a circle frame on the default 480x360 photo would
    /// come out an ellipse — which is exactly the portrait-in-a-circle case
    /// this feature is for. Shapes tolerate that stretch; frames do not.
    private func apply(_ id: String) {
        store.updateSelected { el in
            let wasFramed = el.maskShapeId != nil
            el.maskShapeId = id
            guard !wasFramed, el.w != el.h else { return }
            let centre = el.center
            let side = min(el.w, el.h)
            el.w = side
            el.h = side
            el.x = centre.x - side / 2
            el.y = centre.y - side / 2
        }
    }
}
