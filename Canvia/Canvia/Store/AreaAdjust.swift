// Adjustments on part of a photo: Filters ▸ Adjust's Apply to row sends
// the dials to the whole photo, as ever, or to an adjust layer of its own
// (RetouchLayer, kind "adjust") — over a painted area, brushed on the
// canvas first (BrushMode, kind .adjust), over the subject Cut out finds,
// or over everything but it. Up to four such layers a photo, each listed
// with a delete button; each dial a step as the photo's own are.

import Foundation

/// Where Filters ▸ Adjust's dials go.
enum AdjustArea: String, CaseIterable, Identifiable {
    case whole, painted, subject, background

    var id: String { rawValue }

    /// What the Apply to row calls it.
    var name: String {
        switch self {
        case .whole: return tr("Whole photo")
        case .painted: return tr("Painted area")
        case .subject: return tr("Subject", context: "photo area")
        case .background: return tr("Background")
        }
    }

    /// The adjust layer's area it is; nil for the whole photo.
    var layerArea: String? {
        switch self {
        case .whole: return nil
        case .painted: return RetouchLayer.brushArea
        case .subject: return RetouchLayer.subjectArea
        case .background: return RetouchLayer.backgroundArea
        }
    }

    /// The choice an adjust layer over `area` is.
    static func of(_ area: String?) -> AdjustArea {
        if area == RetouchLayer.subjectArea { return .subject }
        if area == RetouchLayer.backgroundArea { return .background }
        return .painted
    }
}

extension DesignStore {

    /// What is said when a photo has all the adjusted areas it takes.
    static let adjustAreasFullNote = tr("A photo takes up to 4 adjusted areas. Delete one to add another.")

    /// The selected photo's adjust layers, each with its place in its
    /// retouch list.
    var adjustLayers: [(index: Int, layer: RetouchLayer)] {
        guard let photo = singleSelection, photo.type == .image else { return [] }
        return (photo.retouch ?? []).enumerated().compactMap { entry -> (index: Int, layer: RetouchLayer)? in
            entry.element.adjusts ? (index: entry.offset, layer: entry.element) : nil
        }
    }

    /// The adjust layer of `el` the dials set now, by its place; nil for the
    /// whole photo, and once the layer is gone.
    func adjustTargetIndex(of el: Element) -> Int? {
        guard let at = adjustTarget, let layers = el.retouch, layers.indices.contains(at), layers[at].adjusts else {
            return nil
        }
        return at
    }

    /// The dials Filters ▸ Adjust shows: the chosen layer's, else the
    /// photo's own.
    var dialsShown: Adjustments? {
        guard let photo = singleSelection else { return nil }
        if let at = adjustTargetIndex(of: photo) { return photo.retouch?[at].adjust }
        return photo.adjustments
    }

    /// Which choice of the Apply to row is lit.
    var adjustAreaShown: AdjustArea {
        guard let photo = singleSelection, let at = adjustTargetIndex(of: photo) else { return .whole }
        return AdjustArea.of(photo.retouch?[at].area)
    }

    /// The Apply to row: the whole photo; the subject's or the background's
    /// layer — made, dials at rest, as one step when there is none; or a
    /// painted area, whose brush is taken up on the canvas (`true`: the
    /// sheet goes), its layer made by the first stroke.
    @discardableResult
    func applyAdjust(to choice: AdjustArea) -> Bool {
        guard let photo = singleSelection, photo.type == .image else { return false }
        switch choice {
        case .whole:
            adjustTarget = nil
            return false
        case .painted:
            guard adjustLayers.count < RetouchLayer.maxAdjust else { return refuseAdjustArea() }
            return beginBrush(photo.id, kind: .adjust)
        case .subject, .background:
            let area = choice.layerArea ?? RetouchLayer.subjectArea
            if let found = adjustLayers.first(where: { $0.layer.area == area }) {
                adjustTarget = found.index
                return false
            }
            guard adjustLayers.count < RetouchLayer.maxAdjust else { return refuseAdjustArea() }
            guard !refusesLockedPage() else { return false }
            let at = (photo.retouch ?? []).count
            updateSelected { el in
                guard el.type == .image else { return }
                el.retouch = (el.retouch ?? []) + [RetouchLayer(adjustOver: area)]
            }
            adjustTarget = at
            return false
        }
    }

    /// Paint more: the brush taken up again on the chosen painted area,
    /// its strokes added to that layer's (`true`: the sheet goes) — the
    /// Android twin's Paint more.
    @discardableResult
    func paintMoreOnAdjustArea() -> Bool {
        guard let photo = singleSelection, let at = adjustTargetIndex(of: photo),
              photo.retouch?[at].paintsArea == true, beginBrush(photo.id, kind: .adjust) else { return false }
        brushing?.layer = at
        return true
    }

    private func refuseAdjustArea() -> Bool {
        buzz(.reject)
        announce(Self.adjustAreasFullNote, undoable: false)
        return false
    }

    /// One dial set — on the chosen layer, else the photo itself — live
    /// while dragged, or as a step of its own.
    func setDial(_ key: WritableKeyPath<Adjustments, Double>, to value: Double, live: Bool) {
        changeDials(live: live) { $0[keyPath: key] = value }
    }

    /// Every dial back at rest, as one step: the chosen layer's, or the
    /// photo's own — its curve and selective colour too.
    func resetAllDials() {
        updateSelected { [self] el in
            guard el.type == .image else { return }
            if let at = adjustTargetIndex(of: el), var layers = el.retouch {
                layers[at].adjust = .neutral
                el.retouch = layers
            } else {
                el.adjustments = nil
            }
        }
    }

    /// A group of dials back at rest (DialPrecision.cleared), as one step.
    func resetDials(_ group: DialPrecision.DialGroup) {
        changeDials(live: false) { dials in
            dials = DialPrecision.cleared(dials, group) ?? .neutral
        }
    }

    /// `change` made to the dials the sheet shows: the chosen layer's —
    /// selective colour and the vignette never kept on it — or the photo's own, back to none
    /// when they are all at rest.
    private func changeDials(live: Bool, _ change: @escaping (inout Adjustments) -> Void) {
        let edit: (inout Element) -> Void = { [self] el in
            guard el.type == .image else { return }
            if let at = adjustTargetIndex(of: el), var layers = el.retouch {
                var dials = layers[at].adjust ?? .neutral
                change(&dials)
                layers[at].adjust = RetouchLayer.areaDials(dials)
                el.retouch = layers
            } else {
                var dials = el.adjustments ?? .neutral
                change(&dials)
                el.adjustments = dials.isNeutral ? nil : dials
            }
        }
        if live { updateSelectedTransient(edit) } else { updateSelected(edit) }
    }

    /// An adjust layer taken off the photo, as one step; the dials go back
    /// to the whole photo when it was the one they set.
    func removeAdjustLayer(at index: Int) {
        guard let photo = singleSelection, let layers = photo.retouch, layers.indices.contains(index),
              layers[index].adjusts else { return }
        if adjustTarget == index {
            adjustTarget = nil
        } else if let target = adjustTarget, target > index {
            adjustTarget = target - 1
        }
        updateSelected { el in
            guard el.type == .image, var kept = el.retouch, kept.indices.contains(index) else { return }
            kept.remove(at: index)
            el.retouch = RetouchLayer.kept(kept)
        }
    }

    /// What a listed adjust layer is called: its area, numbered among the
    /// painted ones.
    func adjustLayerName(_ index: Int) -> String {
        let layers = adjustLayers
        guard let entry = layers.first(where: { $0.index == index }) else { return "" }
        let choice = AdjustArea.of(entry.layer.area)
        guard choice == .painted else { return choice.name }
        let painted = layers.filter { AdjustArea.of($0.layer.area) == .painted }
        let n = (painted.firstIndex { $0.index == index } ?? 0) + 1
        return tr("Painted area %d", n)
    }
}
