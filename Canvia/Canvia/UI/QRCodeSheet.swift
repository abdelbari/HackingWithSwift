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
// it says so (CodeGenerator.risks), and is kept: it is the person's to
// judge.
//
// A code made from a form (QRForms) opens on its type and fields, each one
// typed making the code again while it can hold it; a barcode on its kind
// and words, made again whenever they are that kind of code, the reason
// said until then. A QR code's look also has its Dots and Eyes, its Error
// correction and a Logo in its middle (which makes the level H); a
// barcode's, whether its words show under the bars.

import SwiftUI

struct QRCodeSheet: View {
    let store: DesignStore
    let id: String
    @State private var draft: String
    /// The code's form, when it was made from one (QRForms): edited in its
    /// fields, each typed making the code again while it can hold it.
    @State private var form: QRForms.Form?
    /// A barcode's kind and words as typed.
    @State private var barcodeKind: Barcodes.Symbology
    @State private var barcodeWords: String
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
        let el = store.element(id)
        _form = State(initialValue: el.flatMap(QRForms.form(of:)))
        let barcode = Barcodes.parse(el?.src)
        _barcodeKind = State(initialValue: barcode?.kind ?? .code128)
        _barcodeWords = State(initialValue: barcode?.payload ?? "")
    }

    /// Whether the element is a barcode rather than a QR code.
    private var isBarcode: Bool { Barcodes.isBarcode(store.element(id)?.src) }

    var body: some View {
        NavigationStack {
            Form {
                content
                QRStyleSections(store: store, id: id, picking: $picking, barcode: isBarcode)
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
        .onChange(of: draft) { _, text in retype(text) }
        .onChange(of: form) { _, next in refill(next) }
        .onChange(of: barcodeWords) { _, _ in rebar() }
        .onChange(of: barcodeKind) { _, _ in rebar() }
        // However it closes, the typing is one step.
        .onDisappear {
            if store.hasPendingChanges { store.commit() }
        }
    }

    /// What the code holds: a barcode's kind and words, a form's type and
    /// fields, or the words typed as they are.
    @ViewBuilder
    private var content: some View {
        if isBarcode {
            Section {
                BarcodeRows(kind: $barcodeKind, text: $barcodeWords)
            } header: {
                Text("Barcode")
            }
        } else if form != nil {
            Section {
                QRFormRows(form: Binding(get: { form ?? QRForms.Form(kind: .link, fields: [:]) }, set: { form = $0 }))
            } header: {
                Text("QR code")
            } footer: {
                if let problem = formProblem { Text(problem).foregroundStyle(Color(.systemRed)) }
            }
        } else {
            typedSection
        }
    }

    private var typedSection: some View {
        let problem = CodeGenerator.problem(with: draft, level: style.level)
        return Section {
            // One line, unless a payload from elsewhere (a contact card,
            // say) runs to several — then all of it shows.
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
    }

    /// Why the form's payload makes no code at the code's level, once it is
    /// filled in.
    private var formProblem: String? {
        guard let form, QRForms.isFilled(form) else { return nil }
        return CodeGenerator.problem(with: QRForms.payload(form), level: style.level)
    }

    /// The code following the words typed, keeping the last it could make.
    private func retype(_ text: String) {
        guard CodeGenerator.problem(with: text, level: style.level) == nil else { return }
        let source = CodeGenerator.source(for: text)
        guard store.element(id)?.src != source else { return }
        store.updateSelectedTransient { el in
            if el.id == id { el.src = source }
        }
    }

    /// The code following its form: its fields kept, and its payload made
    /// again whenever it can hold it.
    private func refill(_ next: QRForms.Form?) {
        guard let next, let el = store.element(id) else { return }
        let payload = QRForms.payload(next)
        let holds = QRForms.isFilled(next) && CodeGenerator.modules(for: payload, level: style.level) != nil
        let source = holds ? CodeGenerator.source(for: payload) : el.src
        guard el.src != source || QRForms.form(of: el) != next else { return }
        store.updateSelectedTransient { el in
            guard el.id == id else { return }
            el = QRForms.with(el, next)
            el.src = source
        }
    }

    /// The barcode following its kind and words whenever they make one,
    /// its payload as the code reads it.
    private func rebar() {
        guard let readable = Barcodes.encode(barcodeKind, barcodeWords).readable else { return }
        let source = Barcodes.source(barcodeKind, readable)
        guard store.element(id)?.src != source else { return }
        store.updateSelectedTransient { el in
            if el.id == id { el.src = source }
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
    /// A barcode's look: its colours, margin and words under the bars,
    /// rather than a QR code's dots, eyes, correction and logo.
    var barcode = false

    var body: some View {
        colourSections
        if barcode {
            Section { wordsToggle }
        } else {
            QRShapeSections(store: store, id: id)
        }
    }

    /// Whether the barcode writes its words under its bars, as one step.
    private var wordsToggle: some View {
        let shown = store.element(id).map(Barcodes.showsText) ?? true
        return Toggle("Words under the bars", isOn: Binding(get: { shown }, set: { on in
            if store.hasPendingChanges { store.commit() }
            store.updateSelected { el in
                if el.id == id { el.barcodeText = on ? nil : false }
            }
            store.buzz(.tick)
        }))
    }

    @ViewBuilder
    private var colourSections: some View {
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
            // A QR code's every risk, a barcode's colours alone.
            if let code {
                let behind = ContrastAudit.backdrop(for: code, in: store.page)
                let risks = barcode
                    ? [CodeGenerator.scanRisk(color: style.color, background: style.background, pageBehind: behind)].compactMap { $0 }
                    : CodeGenerator.risks(code, pageBehind: behind)
                ForEach(risks, id: \.self) { risk in
                    Label(risk, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color(.systemRed))
                }
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

/// A QR code's Dots, Eyes, Error correction and Logo, as the Android twin's
/// QR section offers them: each a pick of one step; the level H, and fixed,
/// while there is a logo, which needs the most correction there is.
private struct QRShapeSections: View {
    let store: DesignStore
    let id: String

    var body: some View {
        let style = store.element(id).map(CodeGenerator.style(of:)) ?? CodeGenerator.Look()
        Section {
            Picker("Dots", selection: pick(style, \.dots)) {
                ForEach(CodeGenerator.dotShapes, id: \.self) { Text(Self.dotsName($0)).tag($0) }
            }
            Picker("Eyes", selection: pick(style, \.eyes)) {
                ForEach(CodeGenerator.eyeShapes, id: \.self) { Text(Self.eyesName($0)).tag($0) }
            }
            Picker("Error correction", selection: Binding(get: { style.level }, set: { level in
                var next = style
                next.ec = level
                QRStyleSections.restyle(store: store, id: id, next)
            })) {
                ForEach(CodeGenerator.levels, id: \.self) { Text(verbatim: $0).tag($0) }
            }
            .disabled(style.logo != nil)
        }
        QRLogoSection(store: store, id: id, style: style)
    }

    /// A binding that sets one of the look's shapes as one step.
    private func pick(_ style: CodeGenerator.Look, _ key: WritableKeyPath<CodeGenerator.Look, String>) -> Binding<String> {
        Binding(get: { style[keyPath: key] }, set: { value in
            var next = style
            next[keyPath: key] = value
            QRStyleSections.restyle(store: store, id: id, next)
        })
    }

    static func dotsName(_ key: String) -> String {
        switch key {
        case "round": return tr("Round")
        case "rounded": return tr("Rounded")
        default: return tr("Square")
        }
    }

    static func eyesName(_ key: String) -> String {
        switch key {
        case "rounded": return tr("Rounded")
        case "circle": return tr("Circle")
        default: return tr("Square")
        }
    }
}

/// Logo: the brand kit's logos and the design's own pictures, each a tile
/// that puts it in the code's middle, and None that takes it away.
private struct QRLogoSection: View {
    let store: DesignStore
    let id: String
    let style: CodeGenerator.Look

    private var candidates: [String] {
        let kit = BrandKit.load().logos.map(BrandKit.mediaSource)
        let pictures = store.design.pages.flatMap(\.elements).compactMap(BrandKit.picture(of:))
        var seen = Set<String>()
        return (kit + pictures).filter { seen.insert($0).inserted }
    }

    var body: some View {
        let all = candidates
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button { pick(nil) } label: {
                        Text("None")
                            .padding(.horizontal, 10)
                            .frame(height: 48)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(style.logo == nil ? Theme.accent : Theme.hairline, lineWidth: style.logo == nil ? 3 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(style.logo == nil ? .isSelected : [])
                    ForEach(Array(all.enumerated()), id: \.element) { i, src in
                        tile(src, number: i + 1, of: all.count)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Logo")
        } footer: {
            if all.isEmpty { Text("Add a picture or a brand logo to use it here.") }
        }
    }

    private func tile(_ src: String, number: Int, of count: Int) -> some View {
        let on = style.logo == src
        return Button { pick(src) } label: {
            Group {
                if let picture = PhotoLibrary.resolve(src) {
                    Image(uiImage: picture).resizable().scaledToFit()
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
            .frame(width: 48, height: 48)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Theme.accent : Theme.hairline, lineWidth: on ? 3 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("Logo %d of %d", number, count))
        .accessibilityHint(tr("Put in the middle of the code"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// The logo put in, or taken away, as one step.
    private func pick(_ src: String?) {
        var next = style
        next.logo = src
        QRStyleSections.restyle(store: store, id: id, next)
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
