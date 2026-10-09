// The words in a shape, and their look.
//
// What the toolbar gives a text box, for the one shape selected: its face,
// size and colour, bold, italic and underline, and how the lines sit. The
// words themselves are typed on the canvas — Add words here, or a double
// tap on the shape. Each change is one undo step, and words that no longer
// fit grow the shape down. Effects, curves and paths are a text box's. The
// Android twin's text panel, scoped to a shape's words, sets the same keys.

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
                            Label(ShapeText.words(of: el) == nil ? "Add words" : "Edit words",
                                  systemImage: "character.cursor.ibeam")
                        }
                    }
                    Section("Type") {
                        Button { choosingFont = true } label: {
                            HStack {
                                Text("Font").foregroundStyle(.primary)
                                Spacer()
                                Text(FontLibrary.stack(words.fontFamily).name)
                                    .font(FontLibrary.font(family: words.fontFamily, size: 17, weight: 500, italic: false))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityLabel("Font")
                        .accessibilityValue(FontLibrary.stack(words.fontFamily).name)
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
                            styleToggle(.bold, "Bold", symbol: "bold", words: words)
                            styleToggle(.italic, "Italic", symbol: "italic", words: words)
                            styleToggle(.underline, "Underline", symbol: "underline", words: words)
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
                }
            }
            .navigationTitle("Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $choosingFont) { FontSheet(store: store) }
            .sheet(isPresented: $choosingColour) {
                ColorPickerSheet(store: store, title: "Text colour",
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

    /// Bold, italic or underline for the shape's words, on or off, lit when
    /// they have it.
    private func styleToggle(_ style: TextToggle, _ name: String, symbol: String, words: Element) -> some View {
        let on = style.isOn(words)
        let turnOn = !on
        return Button {
            write { el in style.apply(turnOn, to: &el) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: Touch.minTarget)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background(RoundedRectangle(cornerRadius: 8).fill(on ? Theme.accent : Color(.systemGray6)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? .isSelected : [])
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
