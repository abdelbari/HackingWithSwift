// Animate's Create bar, in place of the insert button while a motion path is
// recorded (MotionEditing.swift): before a path, what to do; after, Smooth,
// Orient to path and Speed (0.25x to 4x), Play, Re-record and Done — each
// change one Undo, played as it is made. As the Android twin's bar.

import SwiftUI

struct MotionBar: View {
    @Bindable var store: DesignStore
    let recording: MotionRecording
    @State private var draftSpeed: Double?

    private var path: ElementAnimation? {
        store.motionElement?.animation.flatMap { $0.kind == ElementAnimation.pathKind ? $0 : nil }
    }

    var body: some View {
        VStack(spacing: 8) {
            if recording.recorded, let path {
                options(path)
            } else {
                Text("Hold the element and drag it along the path it should take")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            controls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder
    private func options(_ path: ElementAnimation) -> some View {
        HStack(spacing: 14) {
            Toggle("Smooth", isOn: Binding(get: { path.smooth },
                                           set: { on in store.updateMotionPath { $0.smooth = on } }))
            Toggle("Orient to path", isOn: Binding(get: { path.orient },
                                                   set: { on in store.updateMotionPath { $0.orient = on } }))
        }
        .font(.subheadline)
        StepSlider(label: tr("Speed"), stored: min(max(path.speed, MotionPath.minSpeed), MotionPath.maxSpeed),
                   range: MotionPath.minSpeed...MotionPath.maxSpeed, step: 0.25, draft: $draftSpeed,
                   readout: { MotionPath.speedLabel(MotionPath.speed($0)) }) { v in
            store.updateMotionPath { $0.speed = MotionPath.speed(v) }
        }
        .font(.subheadline)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if recording.recorded {
                Button { store.playPreview() } label: {
                    Image(systemName: "play.fill").frame(width: 30, height: 30)
                }
                .accessibilityLabel("Play this page")
                Button("Re-record") { store.rerecordMotion() }
            }
            Spacer(minLength: 0)
            Button("Done") { store.finishMotionRecord() }
                .fontWeight(.semibold)
                .buttonStyle(.borderedProminent)
        }
    }
}
