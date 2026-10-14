// The export pill: "Rendering the video 42%" above the editor's toolbar and
// on Home while an export runs in the app's queue (ExportQueue), with an X
// that stops it — and, once it is done with the sheet gone, what there is
// to say. ExportDelivery, at the app's root, shares or opens what finished
// while the sheet was closed, as the app comes back.

import SwiftUI
import UIKit

struct ExportPill: View {
    /// A tap on the pill: the editor opens the Export sheet on its progress,
    /// Home the design being exported.
    var onTap: () -> Void
    private var queue: ExportQueue { ExportQueue.shared }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let job = queue.current {
                running(job)
            } else if let note = queue.note {
                said(note)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: queue.current?.id)
    }

    private func running(_ job: ExportQueue.Job) -> some View {
        let text = queue.paused ? ExportChoices.paused : ExportChoices.pillText(label: job.label, fraction: queue.progress)
        return HStack(spacing: 10) {
            Button {
                onTap()
            } label: {
                HStack(spacing: 8) {
                    ring
                    Text(text)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(text)
            .accessibilityHint("Shows the export")
            Button {
                queue.cancel(job.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Stop exporting")
        }
        .modifier(PillChrome())
        .accessibilityElement(children: .contain)
    }

    /// How far along, as a ring filling.
    private var ring: some View {
        ZStack {
            Circle().stroke(Theme.hairline, lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.02, queue.progress))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }

    /// What there is to say once an export is done, gone after a while or
    /// with its X.
    private func said(_ note: String) -> some View {
        HStack(spacing: 10) {
            Text(note)
                .font(.subheadline)
                .lineLimit(2)
            Button {
                queue.note = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss")
        }
        .modifier(PillChrome())
        .accessibilityElement(children: .contain)
        .onAppear { AccessibilityNotification.Announcement(note).post() }
        .task(id: note) {
            try? await Task.sleep(for: .seconds(ToastTiming.tip(voiceOver: UIAccessibility.isVoiceOverRunning)))
            if queue.note == note { queue.note = nil }
        }
    }
}

/// The capsule every floating bar in the editor wears.
private struct PillChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .padding(.horizontal)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// At the app's root: what finished with the Export sheet closed is shared —
/// or opened, or printed — once the app is in front, and a paused export
/// carries on as the app comes back. A failure, or what there is to say, goes
/// in the pill, each in its turn once the one before has gone.
struct ExportDelivery: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    private var queue: ExportQueue { ExportQueue.shared }

    func body(content: Content) -> some View {
        content
            .onChange(of: queue.finished.count) { deliverSoon() }
            .onChange(of: queue.requested) { deliverSoon() }
            .onChange(of: queue.delivering) { deliverSoon() }
            .onChange(of: queue.note) { deliverSoon() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                queue.resume()
                deliverSoon()
            }
    }

    /// A moment after, so a notification's Share or Open — which lands just
    /// after the app comes back — decides how; and only with the app in
    /// front, the sheet, which delivers its own, not up, and the last one
    /// delivered gone: several done while away come one after another, and
    /// one only said waits for the pill to be free. The tap is used up even
    /// when what it was for has gone already.
    private func deliverSoon() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            let queue = ExportQueue.shared
            let pillBusy = queue.note != nil && queue.nextIsOnlySaid
            guard UIApplication.shared.applicationState == .active, !queue.sheetOpen, !queue.delivering, !pillBusy,
                  let next = queue.takeRequested() else { return }
            ExportPresenter.deliver(next.finished, request: next.request, queue: queue)
        }
    }
}
