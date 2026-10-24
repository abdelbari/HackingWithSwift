// The words in a shape, and their look.
//
// What the toolbar gives a text box, for the one shape selected: its face,
// size and colour, bold, italic, underline and capitals, and how the lines
// sit. The words themselves are typed on the canvas — Add words here, or a
// double tap on the shape — and until there are some, Add words and a note
// are all there is: the look comes with the first words, so a shape with
// none is given none of its keys. Each change is one undo step, and words
// that no longer fit grow the shape down. Spacing — line, letter and
// paragraph — and lists with their indent are a text box's too, written to
// the same keys; effects, curves and paths stay a text box's. The Android
// twin's text panel, scoped to a shape's words, offers the same, in the same
// words.

import SwiftUI

struct ShapeTextSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var choosingFont = false
    @State private var choosingColour = false

    private static let alignments = ["left", "center", "right", "justify"]

    /// The shape selected, while it is one that takes words and is not
    /// locked.
    private var shape: Element? {
        guard let el = store.singleSelection, ShapeText.takesText(el), !el.locked else { return nil }
        return el
    }

    var body: some View {
        NavigationStack {
            Form {
                if let el = shape {
                    // The words as they are drawn: the shape's own look, and
                    // what its first words would take where it has none.
                    let words = ShapeText.textElement(for: el)
                    let worded = ShapeText.words(of: el) != nil
                    Section {
                        Button {
                            // On the canvas once the sheet has gone, so the
                            // field there can take the keyboard.
                            let id = el.id
                            dismiss()
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(400))
                                store.startTyping(id)
                            }
                        } label: {
                            Label(worded ? tr("Edit words") : tr("Add words"),
                                  systemImage: "character.cursor.ibeam")
                        }
                    } footer: {
                        if !worded { Text(ShapeText.wordsNote) }
                    }
                    if worded {
                        let fontName = FontStore.displayName(words.fontFamily, in: store.design)
                        let missing = FontStore.missingNote(words.fontFamily, in: store.design)
                        Section {
                            Button { choosingFont = true } label: {
                                HStack {
                                    Text("Font").foregroundStyle(.primary)
                                    Spacer()
                                    Text(fontName)
                                        .font(FontLibrary.font(family: words.fontFamily, size: 17, weight: 500, italic: false))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityLabel("Font")
                            .accessibilityValue(fontName)
                            // A font of your own this phone does not have:
                            // the words are in Modern Sans meanwhile.
                            if let missing {
                                Label(missing, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                            Stepper(value: Binding(get: { words.fontSize ?? 42 },
                                                   set: { size in write { $0.fontSize = TypeReadouts.wholeSize(size) } }),
                                    in: TypeReadouts.sizeRange, step: 2) {
                                Text("Size \(TypeReadouts.fontSize(words.fontSize))").monospacedDigit()
                            }
                            Button { choosingColour = true } label: {
                                HStack {
                                    Text("Colour").foregroundStyle(.primary)
                                    Spacer()
                                    Circle()
                                        .fill(Color(hex: words.color ?? ShapeText.darkInk))
                                        .frame(width: 26, height: 26)
                                        .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                                }
                            }
                            .accessibilityLabel("Colour")
                            .accessibilityValue(ElementNames.spokenColour(words.color))
                        }
                        Section("Style") {
                            HStack(spacing: 12) {
                                styleToggle(.bold, tr("Bold"), glyph: Image(systemName: "bold"), words: words)
                                styleToggle(.italic, tr("Italic"), glyph: Image(systemName: "italic"), words: words)
                                styleToggle(.underline, tr("Underline"), glyph: Image(systemName: "underline"), words: words)
                                styleToggle(.strike, tr("Strikethrough"), glyph: Image(systemName: "strikethrough"), words: words)
                                // Capitals have no symbol; "aA" says what they do.
                                styleToggle(.uppercase, tr("Uppercase"), glyph: Text(verbatim: "aA"), words: words)
                            }
                            Picker("Align", selection: Binding(get: { words.align ?? "center" },
                                                               set: { align in write { $0.align = align } })) {
                                ForEach(Self.alignments, id: \.self) { align in
                                    Image(systemName: Self.alignIcon(align))
                                        .accessibilityLabel(TypeReadouts.alignment(align))
                                        .tag(align)
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityValue(TypeReadouts.alignment(words.align))
                        }
                        spacingSection(el, words: words)
                        listSection(el)
                    }
                }
            }
            .navigationTitle("Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $choosingFont) { FontSheet(store: store) }
            .sheet(isPresented: $choosingColour) {
                ColorPickerSheet(store: store, title: tr("Colour"),
                                 current: shape.map { ShapeText.textElement(for: $0).color ?? ShapeText.darkInk },
                                 onPick: { c in write { $0.color = c } },
                                 onPickTransient: { c in
                                     store.updateSelectedTransient { e in
                                         guard ShapeText.takesText(e) else { return }
                                         e = ShapeText.starting(e)
                                         e.color = c
                                     }
                                 })
            }
        }
        .presentationDetents(sheetDetents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    /// Bold, italic, underline, strikethrough or capitals for the shape's
    /// words, on or off, lit when they have it.
    private func styleToggle<Glyph: View>(_ style: TextToggle, _ name: String, glyph: Glyph, words: Element) -> some View {
        let on = style.isOn(words)
        let turnOn = !on
        return Button {
            write { el in style.apply(turnOn, to: &el) }
        } label: {
            glyph
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: Touch.minTarget)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background(RoundedRectangle(cornerRadius: 8).fill(on ? Theme.accent : Color(.systemGray6)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Line height, letter spacing — a share of the words' type size — and
    /// paragraph spacing, in a text box's ranges: live as a slider moves,
    /// the shape grown down when the words need it, one step a drag.
    private func spacingSection(_ el: Element, words: Element) -> some View {
        let line = words.lineHeight ?? 1.25
        let letter = TextSelection.letterPercent(el)
        let paragraph = min(el.paragraphSpacing ?? 0, TypeReadouts.paragraphSpacingRange.upperBound)
        let share = TypeReadouts.letterSpacingShare
        return Section("Spacing") {
            spacingSlider(tr("Line height"), value: line, in: TypeReadouts.lineHeightRange,
                          readout: TypeReadouts.lineHeight(line)) { v, e in e.lineHeight = v }
            spacingSlider(tr("Letter spacing"), value: letter, in: share.lowerBound * 100...share.upperBound * 100,
                          readout: "\(Int(letter.rounded()))%") { v, e in
                e.letterSpacing = TextSelection.letterSpacing(percent: v, for: e)
            }
            spacingSlider(tr("Paragraph spacing"), value: paragraph, in: TypeReadouts.paragraphSpacingRange,
                          readout: TypeReadouts.paragraphSpacing(paragraph)) { v, e in
                e.paragraphSpacing = v < 0.01 ? nil : v
            }
        }
    }

    /// A spacing's name over its slider, its value beside it, named and
    /// valued for VoiceOver.
    private func spacingSlider(_ name: String, value: Double, in range: ClosedRange<Double>, readout: String,
                               _ set: @escaping (Double, inout Element) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name).font(.subheadline)
                Spacer()
                Text(readout).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            Slider(value: Binding(get: { value }, set: { v in
                store.formatTextsLive(.spacing) { e in
                    e = ShapeText.starting(e)
                    set(v, &e)
                }
            }), in: range, onEditingChanged: { editing in
                if !editing { store.commit() }
            })
            .accessibilityLabel(name)
            .accessibilityValue(readout)
        }
    }

    /// No list, bullets, numbers or letters on every paragraph, and Outdent
    /// and Indent for them all — the keys a text box's list writes.
    private func listSection(_ el: Element) -> some View {
        let lines = TextLists.lines(el)
        let shared = TypeReadouts.shared(lines.map(\.list))
        let deepest = lines.map(\.level).max() ?? 0
        let shallowest = lines.map(\.level).min() ?? 0
        return Section("List") {
            Picker("List", selection: Binding(get: { shared ?? TypeReadouts.mixed },
                                              set: { style in writeList { $0.setListStyle(style) } })) {
                ForEach(Self.lists, id: \.self) { style in
                    Image(systemName: Self.listIcon(style))
                        .accessibilityLabel(TypeReadouts.listStyle(style))
                        .tag(style)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityValue(shared.map { TypeReadouts.listStyle($0) } ?? TypeReadouts.mixed)
            HStack(spacing: 12) {
                Button { writeList { $0.stepIndent(by: -1) } } label: {
                    Label("Outdent", systemImage: "decrease.indent")
                }
                .disabled(deepest == 0)
                Spacer()
                Button { writeList { $0.stepIndent(by: 1) } } label: {
                    Label("Indent", systemImage: "increase.indent")
                }
                .disabled(shallowest >= FontLibrary.maxIndent)
            }
            .buttonStyle(.borderless)
        }
    }

    private static let lists = ["none", "bullet", "number", "letter"]

    static func listIcon(_ style: String) -> String {
        switch style {
        case "bullet": return "list.bullet"
        case "number": return "list.number"
        case "letter": return "character"
        default: return "text.alignleft"
        }
    }

    /// A list change to the words as one step, the shape grown to them.
    private func writeList(_ change: (inout Element) -> Void) {
        store.formatTexts(.list) { e in
            e = ShapeText.starting(e)
            change(&e)
        }
    }

    /// One change to the words' look as one step, on a shape that has taken
    /// the look its first words would (ShapeText.starting) — so whatever is
    /// not changed stays as the sheet showed it.
    private func write(_ change: (inout Element) -> Void) {
        store.updateSelected { e in
            guard ShapeText.takesText(e) else { return }
            e = ShapeText.starting(e)
            change(&e)
        }
    }

    static func alignIcon(_ align: String) -> String {
        switch align {
        case "left": return "text.alignleft"
        case "right": return "text.alignright"
        case "justify": return "text.justify"
        default: return "text.aligncenter"
        }
    }
}
