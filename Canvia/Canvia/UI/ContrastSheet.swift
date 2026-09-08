// Text that cannot be read on what is behind it, with a one-tap fix.

import SwiftUI

struct ContrastSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var findings: [ContrastAudit.Finding] = []

    var body: some View {
        NavigationStack {
            Group {
                if findings.isEmpty {
                    ContentUnavailableView("Every text reads clearly",
                                           systemImage: "checkmark.seal",
                                           description: Text("All text meets WCAG AA contrast against what is behind it."))
                } else {
                    List(findings) { f in
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6).fill(Color(hex: f.backdrop))
                                Text("Aa").font(.headline).foregroundStyle(Color(hex: store.element(f.elementId)?.color ?? "#000000"))
                            }
                            .frame(width: 44, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.text.isEmpty ? "(empty)" : f.text).lineLimit(1).font(.subheadline.weight(.semibold))
                                Text(String(format: "%.1f:1 — needs %.1f:1 · page %d", f.ratio, f.required, f.pageIndex + 1))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Fix") { fix(f) }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                    }
                }
            }
            .navigationTitle(findings.isEmpty ? "Contrast" : (findings.count == 1 ? "1 hard-to-read text" : "\(findings.count) hard-to-read texts"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if findings.count > 1 {
                    ToolbarItem(placement: .cancellationAction) { Button("Fix all") { fixAll() } }
                }
            }
        }
        .presentationDetents(sheetDetents)
        .onAppear { refresh() }
    }

    private func refresh() { findings = ContrastAudit.audit(store.design) }

    private func fix(_ f: ContrastAudit.Finding) {
        store.apply { design in
            if let i = design.pages[f.pageIndex].elements.firstIndex(where: { $0.id == f.elementId }) {
                design.pages[f.pageIndex].elements[i].color = f.suggestion
            }
        }
        refresh()
    }

    private func fixAll() {
        let all = findings
        store.apply { design in
            for f in all {
                if let i = design.pages[f.pageIndex].elements.firstIndex(where: { $0.id == f.elementId }) {
                    design.pages[f.pageIndex].elements[i].color = f.suggestion
                }
            }
        }
        refresh()
    }
}
