// The export pill: "Rendering the video 42%" above the editor's toolbar and
// on Home while an export runs in the app's queue (ExportQueue) — under it
// whether it keeps going if Canvia is left — with an X that stops it — and, once it is done with the sheet gone, what there is
// to say. ExportDelivery, at the app's root, shares or opens what finished
// while the sheet was closed, as the app comes back.

import SwiftUI
import UIKit

struct ExportPill: View {
    /// A tap on the pill: the editor opens the Export sheet on its progress,
    /// Home the design being exported.
    var onTap: () -> Void
    /// A failure for want of space: Settings, whose Storage clears caches.
    /// None, and the row says so without the way there.
    var onStorage: (() -> Void)? = nil
    private var queue: ExportQueue { ExportQueue.shared }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // An export running, then a clip being made light, then the last
        // export that failed (ExportFailure.pillShows, the Android twin's
        // order), then what there is to say.
        Group {
            if let job = queue.current {
                running(job)
            } else if let clip = ClipOptimiser.shared.running {
                optimising(clip)
            } else if let failed = queue.failedExports.first {
                // Nothing running: the last export that failed, kept to try
                // again.
                FailedExportRow(entry: failed, onStorage: onStorage)
            } else if let note = queue.note {
                said(note)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: queue.current?.id)
    }

    private func running(_ job: ExportQueue.Job) -> some View {
        let text = queue.paused ? ExportChoices.paused : ExportChoices.pillText(label: job.label, fraction: queue.progress)
        let away = ExportChoices.keepsGoing(queue.keepsGoing)
        return HStack(spacing: 10) {
            Button {
                onTap()
            } label: {
                HStack(spacing: 8) {
                    ring
                    VStack(alignment: .leading, spacing: 0) {
                        Text(text)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                        // Whether it goes on once Canvia is left: on iOS 26,
                        // with the system's task granted (ContinuedExport).
                        Text(away)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(text + ", " + away)
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

    /// A clip brought in being made light (ClipOptimiser), with Keep
    /// original, which stops it and keeps the clip as it came.
    private func optimising(_ clip: ClipOptimiser.Running) -> some View {
        let text = tr("Optimising video %d%%", Int((clip.progress * 100).rounded()))
        return HStack(spacing: 10) {
            ProgressView(value: min(max(clip.progress, 0), 1))
                .progressViewStyle(.circular)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .accessibilityLabel(tr("Optimising the video so it plays smoothly"))
                .accessibilityValue(text)
            Button("Keep original") { ClipOptimiser.shared.keepOriginal() }
                .font(.subheadline)
        }
        .modifier(PillChrome())
        .accessibilityElement(children: .contain)
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

/// An export that failed, in the pill's place: what failed and why — a
/// batch's designs that failed listed under it — with Try again (Retry
/// these, for a batch) and, when there is one, the smaller try it suggests
/// ("Try at 1×"), or for a phone out of space a way to Settings' Storage.
/// It stays until tried again or let go with its X, as the Android twin's
/// FailedExportRow.
private struct FailedExportRow: View {
    let entry: ExportQueue.Failed
    var onStorage: (() -> Void)?
    private var queue: ExportQueue { ExportQueue.shared }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.message)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(entry.titles.enumerated()), id: \.offset) { _, title in
                    Text("• " + title).font(.caption).lineLimit(1)
                }
                if noSpace {
                    Text(ExportFailure.freeUpSpace).font(.caption).foregroundStyle(.secondary)
                }
                buttons
            }
            Button {
                queue.dismissFailed(entry.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss")
        }
        // Several lines and buttons: a card rather than the capsule.
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .padding(.horizontal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .onAppear { AccessibilityNotification.Announcement(entry.message).post() }
    }

    private var noSpace: Bool { entry.failure.kind == .noSpace }

    private var buttons: some View {
        HStack(spacing: 14) {
            Button(entry.titles.isEmpty ? ExportFailure.tryAgain : ExportFailure.retryThese) {
                queue.retry(entry.id)
            }
            if let suggestion = entry.suggestion {
                Button(suggestion.label) { queue.retry(entry.id, smaller: true) }
            }
            if noSpace, let onStorage {
                Button(ExportFailure.openSettings) { onStorage() }
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.accent)
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
                // Left with an export running: on iOS 26 it asks to keep
                // going (ContinuedExport), if it has not yet.
                if phase == .background { queue.left() }
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
