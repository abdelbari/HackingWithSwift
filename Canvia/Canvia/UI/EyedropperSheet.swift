// Tap the design to pick a colour from it.

import SwiftUI

struct EyedropperSheet: View {
    let design: Design
    let page: Page
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rendered: CGImage?
    @State private var picked: String?
    @State private var point: CGPoint?

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let fit = min(geo.size.width / max(design.width, 1), (geo.size.height - 80) / max(design.height, 1))
                let size = CGSize(width: design.width * fit, height: design.height * fit)
                VStack(spacing: 14) {
                    ZStack(alignment: .topLeading) {
                        if let rendered {
                            Image(decorative: rendered, scale: 1)
                                .resizable()
                                .frame(width: size.width, height: size.height)
                                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                                    sample(at: value.location, in: size)
                                }.onEnded { value in
                                    sample(at: value.location, in: size)
                                })
                        } else {
                            ProgressView().frame(width: size.width, height: size.height)
                        }
                        if let point, let picked {
                            Circle()
                                .fill(Color(hex: picked))
                                .frame(width: 44, height: 44)
                                .overlay(Circle().stroke(.white, lineWidth: 3))
                                .shadow(radius: 4)
                                .position(x: point.x, y: max(point.y - 40, 22))
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    HStack {
                        if let picked {
                            RoundedRectangle(cornerRadius: 8).fill(Color(hex: picked)).frame(width: 36, height: 36)
                            Text(picked).font(.system(.body, design: .monospaced))
                        } else {
                            Text("Touch the design to sample a colour").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Use") {
                            if let picked { onPick(picked) }
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(picked == nil)
                    }
                    .padding(.horizontal)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top)
            .navigationTitle("Eyedropper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .task {
            rendered = DesignExporter.render(design: design, page: page,
                                             scale: min(1, 1200 / max(design.width, design.height, 1)))
        }
    }

    private func sample(at location: CGPoint, in size: CGSize) {
        guard let rendered else { return }
        let unit = CGPoint(x: min(max(location.x / size.width, 0), 1), y: min(max(location.y / size.height, 0), 1))
        point = CGPoint(x: min(max(location.x, 0), size.width), y: min(max(location.y, 0), size.height))
        picked = Eyedropper.color(in: rendered, at: unit)
    }
}
