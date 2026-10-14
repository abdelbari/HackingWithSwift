// A code's words changed where it sits: the same size, place, turn and
// frame, a new code. The Android twin's "QR code" field in its photo panel.
//
// The code on the page follows the typing, keeping the last one that could
// be made while the field is empty or holds more than a code carries, and
// the whole edit is one Undo however much was typed.
//
// Under the words, the code's look, as Canva's generator offers it and the
// Android twin's QR section does: Code colour and Background — the design's
// colours first, then one of your own, and None for a clear background —
// and the Margin round it, 0 to 4 modules. Each change is one undo step,
// and a new link keeps the look. A look that may not scan on what is behind
// it says so (CodeGenerator.scanRisk), and is kept: it is the person's to
// judge.

import SwiftUI

struct QRCodeSheet: View {
    let store: DesignStore
    let id: String
    @State private var draft: String
    /// Which colour the colour sheet is open for.
    @State private var picking: Picking?
    @Environment(\.dismiss) private var dismiss

    enum Picking: String, Identifiable {
        case code, background
        var id: String { rawValue }
    }

    init(store: DesignStore, id: String, payload: String) {
        self.store = store
        self.id = id
        _draft = State(initialValue: payload)
    }

    var body: some View {
        let problem = CodeGenerator.problem(with: draft)
        NavigationStack {
            Form {
                Section {
                    // One line, unless a payload from elsewhere (a contact
                    // card, say) runs to several — then all of it shows.
                    TextField("Link or text", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityHint(problem ?? "")
                } header: {
                    Text("QR code")
                } footer: {
                    Text(problem ?? tr("The code on the page changes as you type."))
                        .foregroundStyle(problem == nil ? Color.secondary : Color(.systemRed))
                }
                QRStyleSections(store: store, id: id, picking: $picking)
            }
            .navigationTitle("Edit code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(item: $picking) { which in
            ColorPickerSheet(store: store, title: which == .code ? tr("Code colour") : tr("Background"),
                             current: which == .code ? style.color : (style.background ?? CodeGenerator.defaultBackground),
                             onPick: { hex in restyle(which, hex) },
                             onPickTransient: { hex in
                                 store.updateSelectedTransient { el in
                                     if el.id == id { el = CodeGenerator.styled(el, Self.with(which, hex, CodeGenerator.style(of: el))) }
                                 }
                             })
        }
        .onChange(of: draft) { _, text in
            guard CodeGenerator.problem(with: text) == nil else { return }
            let source = CodeGenerator.source(for: text)
            guard store.element(id)?.src != source else { return }
            store.updateSelectedTransient { el in
                if el.id == id { el.src = source }
            }
        }
        // However it closes, the typing is one step.
        .onDisappear {
            if store.hasPendingChanges { store.commit() }
        }
    }

    /// The code's look as it is now.
    private var style: CodeGenerator.Look {
        store.element(id).map(CodeGenerator.style(of:)) ?? CodeGenerator.Look()
    }

    /// `style` with `hex` as the colour `which` is for.
    static func with(_ which: Picking, _ hex: String, _ style: CodeGenerator.Look) -> CodeGenerator.Look {
        var out = style
        switch which {
        case .code: out.color = hex.lowercased()
        case .background: out.background = hex.lowercased()
        }
        return out
    }

    /// A colour of your own, as one step: the wheel's turn so far, closed,
    /// is that step, and a pick that changes nothing more records none.
    private func restyle(_ which: Picking, _ hex: String) {
        if store.hasPendingChanges { store.commit() }
        QRStyleSections.restyle(store: store, id: id, Self.with(which, hex, style))
    }
}

/// A code's Code colour, Background and Margin, and the word when the look
/// may not scan.
private struct QRStyleSections: View {
    let store: DesignStore
    let id: String
    @Binding var picking: QRCodeSheet.Picking?

    var body: some View {
        let code = store.element(id)
        let style = code.map(CodeGenerator.style(of:)) ?? CodeGenerator.Look()
        // The design's colours first, then the default, each once.
        let inDesign = ColorTools.documentColors(store.design, limit: 8)
        Section("Code colour") {
            QRSwatchRow(colours: Self.offered(inDesign, CodeGenerator.defaultColor), chosen: style.color,
                        allowsNone: false) { hex in
                var next = style
                next.color = hex ?? CodeGenerator.defaultColor
                Self.restyle(store: store, id: id, next)
            }
            ownColour(.code)
        }
        Section("Background") {
            QRSwatchRow(colours: Self.offered(inDesign, CodeGenerator.defaultBackground), chosen: style.background,
                        allowsNone: true) { hex in
                var next = style
                next.background = hex
                Self.restyle(store: store, id: id, next)
            }
            ownColour(.background)
        }
        Section {
            marginStepper(style)
        } footer: {
            // On what shows through a clear background: whatever is behind
            // the code's centre, else the page.
            if let code, let risk = CodeGenerator.scanRisk(color: style.color, background: style.background,
                                                           pageBehind: ContrastAudit.backdrop(for: code, in: store.page)) {
                Label(risk, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(.systemRed))
            }
        }
    }

    /// The Margin, 0 to 4 modules round the code.
    private func marginStepper(_ style: CodeGenerator.Look) -> some View {
        return Stepper(value: Binding(get: { style.margin }, set: { margin in
            var next = style
            next.margin = margin
            Self.restyle(store: store, id: id, next)
        }), in: 0...CodeGenerator.quiet) {
            Text(trn("Margin: %d module|Margin: %d modules", style.margin)).monospacedDigit()
        }
    }

    /// A colour of your own, from the colour sheet.
    private func ownColour(_ which: QRCodeSheet.Picking) -> some View {
        Button {
            // The typing so far is a step of its own.
            if store.hasPendingChanges { store.commit() }
            picking = which
        } label: {
            Label("A colour of your own…", systemImage: "paintpalette")
        }
    }

    /// `colours` lower-cased with `fallback` after them, each once.
    static func offered(_ colours: [String], _ fallback: String) -> [String] {
        var out: [String] = []
        for hex in colours + [fallback] where !out.contains(hex.lowercased()) {
            out.append(hex.lowercased())
        }
        return out
    }

    /// The code in `next`, as one undo step after any typing, which is a
    /// step of its own; nothing when it already looks so.
    static func restyle(store: DesignStore, id: String, _ next: CodeGenerator.Look) {
        guard let code = store.element(id), CodeGenerator.style(of: code) != next else { return }
        if store.hasPendingChanges { store.commit() }
        store.updateSelected { el in
            if el.id == id { el = CodeGenerator.styled(el, next) }
        }
        store.buzz(.tick)
    }
}

/// A row of colours to tap, the chosen one ringed, and None first when the
/// colour can be none (nil).
private struct QRSwatchRow: View {
    let colours: [String]
    let chosen: String?
    let allowsNone: Bool
    let onPick: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if allowsNone { noneSwatch }
                ForEach(colours, id: \.self) { hex in
                    swatch(hex)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var noneSwatch: some View {
        let on = chosen == nil
        return Button { onPick(nil) } label: {
            Circle()
                .fill(Color(.systemBackground))
                .overlay(Image(systemName: "slash.circle").foregroundStyle(.secondary))
                .overlay(Circle().stroke(on ? Theme.accent : Theme.hairline, lineWidth: on ? 3 : 1))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("None")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func swatch(_ hex: String) -> some View {
        let on = chosen?.lowercased() == hex
        return Button { onPick(hex) } label: {
            Circle()
                .fill(Color(hex: hex))
                .overlay(Circle().stroke(on ? Theme.accent : Theme.hairline, lineWidth: on ? 3 : 1))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ElementNames.spokenColour(hex))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
