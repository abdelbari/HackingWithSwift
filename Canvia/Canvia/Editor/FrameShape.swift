// The outline a photo is clipped to.
//
// A rounded rectangle is the default and stays the default; anything else is
// a frame the user picked from the shape library. Delegating to LibraryShape
// rather than re-deriving the path keeps frame geometry and shape-element
// geometry literally the same code, including the rounded-rect branch for
// rect-like shapes — two implementations of "what does a scalloped square
// look like" would drift.

import SwiftUI

struct FrameShape: Shape {
    /// nil is the plain rounded rectangle every image had before frames.
    let definition: ShapeDef?
    let cornerRadius: Double

    func path(in rect: CGRect) -> Path {
        guard let definition else {
            let r = max(0, min(cornerRadius, rect.width / 2, rect.height / 2))
            return Path(roundedRect: rect, cornerRadius: r)
        }
        return LibraryShape(definition: definition, cornerRadius: cornerRadius).path(in: rect)
    }
}
