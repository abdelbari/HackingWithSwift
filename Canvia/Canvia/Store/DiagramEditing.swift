// Diagrams on the page (Diagrams): a new one from Add, made across the
// middle of the page in the page's colours — else the brand's — and Edit
// diagram's every change, the diagram made again where it stands, its
// colours staying with its items. Each is one undo step, refused on a
// locked page, as the Android twin's addDiagram and updateDiagram.

import CoreGraphics
import Foundation

extension DesignStore {

    /// The diagram the selection is part of, when it is one Edit diagram
    /// can make again; nil for anything else.
    var selectedDiagram: DiagramSpec? {
        Diagrams.of(selectedElements)
    }

    /// Whether any part of diagram `id` on the page is locked: Edit diagram
    /// then only says how to unlock it.
    func diagramIsLocked(_ id: String) -> Bool {
        page.elements.contains { $0.locked && $0.diagram?.id == id }
    }

    /// A new diagram of `kind` (Diagrams.starter) across the middle of the
    /// page, as a chart is added: in the page's colours, else the brand's
    /// (newChartPalette), grouped, selected, one undo step — onto the next
    /// unlocked page when this one is locked. Whether it went on.
    @discardableResult
    func addDiagram(_ kind: DiagramKind) -> Bool {
        guard landsOnUnlockedPage() else { return false }
        let w = pageWidth, h = pageHeight
        let frame = CGRect(x: (w * 0.1).rounded(), y: (h * 0.2).rounded(), width: (w * 0.8).rounded(),
                           height: (h * 0.6).rounded())
        let made = Diagrams.make(Diagrams.starter(kind), in: frame, palette: newChartPalette,
                                 ink: DataGraphics.ink(for: page))
        guard !made.isEmpty else { return false }
        applyToPage { $0.elements.append(contentsOf: made) }
        selection = Set(made.map(\.id))
        buzz(.confirm)
        return true
    }

    /// The diagram `spec` names, made again where it stands from `spec` —
    /// an item added, taken away, moved, indented or reworded, its kind,
    /// style or colours — as one undo step, selected. Its colours stay with
    /// its items (Diagrams.pinned) unless `repaint`. False when it is gone,
    /// or its page or one of its parts is locked.
    @discardableResult
    func updateDiagram(_ spec: DiagramSpec, repaint: Bool = false) -> Bool {
        guard !refusesLockedPage() else { return false }
        let members = Diagrams.members(page, id: spec.id)
        guard !members.isEmpty, !members.contains(where: \.locked) else { return false }
        let kept = repaint ? spec : Diagrams.pinned(spec, members: members)
        guard let made = Diagrams.remade(on: page, kept, palette: newChartPalette, ink: DataGraphics.ink(for: page)),
              !made.isEmpty else { return false }
        applyToPage { $0 = Diagrams.replacing($0, id: spec.id, with: made) }
        selection = Set(made.map(\.id))
        return true
    }
}
