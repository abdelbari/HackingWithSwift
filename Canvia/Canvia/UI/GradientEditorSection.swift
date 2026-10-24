// Custom gradient, under the colour sheet's gradients: the gradient there
// now (GradientEditing), edited in place. A bar with a handle per stop to
// drag, the stops as colour chips — tap one for the colour sheet, hold it
// to remove it, + for another — the shape, and for a linear one its angle
// as chips and a dial. Every change shows as it is made; a tap is one step
// and so is each drag. Saved to the brand kit on request; kept among
// Your gradients when the sheet closes.

import SwiftUI

struct GradientEditorSection: View {
    @Bindable var store: DesignStore
    /// A tap's change, as one step.
    var pick: (Paint) -> Void
    /// A drag's change as it goes, left open until it ends; with none, a
    /// drag lands only when it ends.
    var pickLive: ((Paint) -> Void)?
    @State private var paint: Paint
    /// The stop whose colour the colour sheet is changing.
    @State private var recolouring: Int?
    /// Whether anything was changed here, which Your gradients keeps.
    @State private var made = false
    @State private var savedToBrand = false
    /// Whether a drag has changed the gradient since it was last kept.
    @State private var dragged = false

    init(store: DesignStore, start: Paint, pick: @escaping (Paint) -> Void, pickLive: ((Paint) -> Void)?) {
        self.store = store
        self.pick = pick
        self.pickLive = pickLive
        _paint = State(initialValue: start)
    }

    private var stops: [GradientStop] { paint.stops ?? [] }
    private static let space = "gradientBar"
    private var kind: String { GradientPreset.kind(of: paint) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Custom gradient").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
            stopBar
            chipRow
            kindRow
            if kind == "linear" { angleControls }
            saveButton
        }
        .sheet(isPresented: Binding(get: { recolouring != nil }, set: { if !$0 { recolouring = nil } }),
               onDismiss: { endDrag() }) {
            stopColourSheet
        }
        .onDisappear { if made { GradientRecents.record(paint) } }
    }

    // MARK: changes

    /// A change as one step.
    private func commit(_ next: Paint) {
        guard next != paint else { return }
        paint = next
        made = true
        pick(next)
        store.buzz(.tick)
    }

    /// A change while a finger is down.
    private func live(_ next: Paint) {
        guard next != paint else { return }
        paint = next
        made = true
        dragged = true
        pickLive?(next)
    }

    /// A drag let go, or the stop's colour sheet closed: its last change
    /// kept as one step.
    private func endDrag() {
        guard dragged else { return }
        dragged = false
        if pickLive != nil {
            if store.hasPendingChanges { store.commit() }
        } else {
            pick(paint)
        }
    }

    // MARK: stops

    /// The gradient left to right with a handle per stop, dragged along it.
    private var stopBar: some View {
        GeometryReader { geo in
            let width = max(Double(geo.size.width), 1)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(stops: paint.swiftUIStops, startPoint: .leading, endPoint: .trailing))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
                    .frame(height: 28)
                ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                    handle(index, stop, width: width)
                }
            }
            .frame(height: 36)
            .coordinateSpace(name: Self.space)
        }
        .frame(height: 36)
        .padding(.horizontal, 10)
        .designDirection()
    }

    private func handle(_ index: Int, _ stop: GradientStop, width: Double) -> some View {
        Circle()
            .fill(Color(hex: stop.color))
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.3), radius: 2)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle().inset(by: -8))
            .offset(x: stop.offset * width - 11)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                .onChanged { drag in
                    live(GradientEditing.moved(paint, at: index, to: Double(drag.location.x) / width))
                }
                .onEnded { _ in endDrag() })
            .accessibilityElement()
            .accessibilityLabel(tr("Stop %d", index + 1))
            .accessibilityValue("\(Int((stop.offset * 100).rounded()))%")
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 0.05 : -0.05
                commit(GradientEditing.moved(paint, at: index, to: stop.offset + step))
            }
    }

    /// The stops as colour chips, then +.
    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                    stopChip(index, stop)
                }
                if GradientEditing.canAdd(paint) {
                    Button {
                        commit(GradientEditing.adding(paint))
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color(.systemGray6)))
                    }
                    .accessibilityLabel("Add a stop")
                }
            }
            .padding(4)
        }
    }

    private func stopChip(_ index: Int, _ stop: GradientStop) -> some View {
        Button {
            recolouring = index
        } label: {
            Circle()
                .fill(Color(hex: stop.color))
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(Theme.hairline))
        }
        .contextMenu {
            if GradientEditing.canRemove(paint) {
                Button(role: .destructive) {
                    commit(GradientEditing.removing(paint, at: index))
                } label: {
                    Label("Remove stop", systemImage: "trash")
                }
            }
        }
        .accessibilityLabel(tr("Stop %d, %@", index + 1, ElementNames.spokenColour(stop.color)))
        .accessibilityHint("Changes this colour")
        .accessibilityActions {
            if GradientEditing.canRemove(paint) {
                Button("Remove stop") { commit(GradientEditing.removing(paint, at: index)) }
            }
        }
    }

    /// The colour sheet for the stop being recoloured: every colour it
    /// offers — brand, the design's, recent, your own, the eyedropper.
    @ViewBuilder
    private var stopColourSheet: some View {
        if let index = recolouring, stops.indices.contains(index) {
            ColorPickerSheet(store: store, title: tr("Stop %d", index + 1), current: stops[index].color,
                             onPick: { hex in commit(GradientEditing.recoloured(paint, at: index, hex)) },
                             onPickTransient: { hex in live(GradientEditing.recoloured(paint, at: index, hex)) })
        }
    }

    // MARK: shape and angle

    private var kindRow: some View {
        Picker("Style", selection: Binding(get: { kind }, set: { commit(GradientEditing.shaped(paint, $0)) })) {
            Text("Linear").tag("linear")
            Text("Radial").tag("radial")
            Text("Angular").tag("angular")
        }
        .pickerStyle(.segmented)
    }

    private var angleControls: some View {
        let angle = paint.angle ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GradientEditing.angles, id: \.self) { degrees in
                        angleChip(degrees, chosen: angle == degrees)
                    }
                }
            }
            HStack {
                Text("Angle").font(.subheadline)
                Slider(value: Binding(get: { angle }, set: { live(GradientEditing.angled(paint, $0)) }),
                       in: 0...359, onEditingChanged: { editing in if !editing { endDrag() } })
                    .accessibilityLabel(tr("Gradient angle"))
                    .accessibilityValue("\(Int(angle))°")
                Text("\(Int(angle))°").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
    }

    private func angleChip(_ degrees: Double, chosen: Bool) -> some View {
        Button {
            commit(GradientEditing.angled(paint, degrees))
        } label: {
            Text("\(Int(degrees))°")
                .font(.caption.monospacedDigit())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(chosen ? Theme.accentSubtle : Color(.systemGray6)))
                .overlay(Capsule().stroke(chosen ? Theme.accent : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private var saveButton: some View {
        Button {
            var kit = BrandKit.load()
            if kit.addGradient(paint) { kit.save() }
            savedToBrand = true
            store.buzz(.tick)
        } label: {
            Label(savedToBrand ? tr("Saved to brand kit") : tr("Save to brand kit"),
                  systemImage: savedToBrand ? "checkmark" : "briefcase")
                .font(.subheadline)
        }
        .disabled(savedToBrand)
        .onChange(of: paint) { savedToBrand = false }
    }
}

/// A row of gradients to pick from — Your gradients, the brand kit's —
/// each a tile, ringed when it is the fill there now.
struct GradientTileRow: View {
    var title: String
    var paints: [Paint]
    var current: Paint?
    var pick: (Paint) -> Void
    /// Offered on a long press, when set: "Remove from brand kit".
    var remove: ((Paint) -> Void)?

    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote.weight(.bold)).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(paints.enumerated()), id: \.offset) { index, paint in
                    tile(paint, number: index + 1)
                }
            }
        }
    }

    private func tile(_ paint: Paint, number: Int) -> some View {
        let chosen = FillChoices.isGradient(current, paint)
        return Button {
            guard !chosen else { return }
            pick(paint)
        } label: {
            RoundedRectangle(cornerRadius: 9)
                .fill(paint.gradientStyle())
                .frame(height: 40)
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .stroke(chosen ? Theme.accent : Theme.hairline, lineWidth: chosen ? 3 : 1))
        }
        .contextMenu {
            if let remove {
                Button(role: .destructive) { remove(paint) } label: {
                    Label("Remove from brand kit", systemImage: "trash")
                }
            }
        }
        .accessibilityLabel(tr("Gradient %d", number))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
