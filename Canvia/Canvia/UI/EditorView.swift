// Editor screen: top bar (back, undo/redo, title, shuffle, export), canvas,
// contextual toolbar, pages bar, insert button, and sheet routing.
// Autosaves after every commit (debounced).

import SwiftUI

/// The app's primary action had no pressed state at all: tapping it changed
/// nothing until the sheet arrived, which on a slow frame reads as a button
/// that did not register.
private struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle()
                .fill(configuration.isPressed ? Theme.accentPressed : Theme.accent))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.65),
                       value: configuration.isPressed)
    }
}

enum EditorSheet: String, Identifiable {
    case insert, colorFill, colorText, colorLine, colorStroke, background
    case fonts, effects, spacing, filters, crop, position, layers, export, resize, find, frame, shadow
    var id: String { rawValue }
}

struct EditorView: View {
    @Bindable var store: DesignStore
    var onHome: () -> Void

    @State private var activeSheet: EditorSheet?
    @State private var saveTask: Task<Void, Never>?
    @State private var paletteIndex = 0
    @FocusState private var titleFocused: Bool
    @State private var titleBeforeEdit = ""

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack(alignment: .bottomTrailing) {
                CanvasView(store: store)
                insertButton
                    .padding(18)
            }
            // Always rendered, never inserted. Adding and removing this from
            // the stack resized the canvas on every selection — and by a
            // different amount for a text selection than a shape one, so the
            // page jumped under your finger at the exact moment you were
            // trying to look at it.
            ContextToolbar(store: store, activeSheet: $activeSheet)
                .frame(height: store.selection.isEmpty ? 0 : nil)
                .opacity(store.selection.isEmpty ? 0 : 1)
                .clipped()
                .allowsHitTesting(!store.selection.isEmpty)
            PagesBar(store: store)
        }
        .background(keyboardCommands)
        .animation(.spring(response: 0.30, dampingFraction: 0.86),
                   value: store.selection.isEmpty)
        // The whole point of a design tool is that it answers your hands.
        .sensoryFeedback(.selection, trigger: store.selection)
        .sensoryFeedback(.alignment, trigger: SnapSignal(x: store.guideX, y: store.guideY))
        .sensoryFeedback(.impact(weight: .heavy), trigger: store.page.elements.count)
        .background(Theme.workspace)
        .sheet(item: $activeSheet) { sheet in
            sheetView(sheet)
        }
        .onAppear {
            store.onCommit = { scheduleSave() }
        }
        .onDisappear {
            saveNow()
        }
    }

    // MARK: top bar

    /// Hardware-keyboard shortcuts. Every operation here already existed on
    /// the store and was reachable only by tapping — which on an iPad with a
    /// Magic Keyboard makes a design tool feel like a toy. Zero-sized buttons
    /// in a background layer is the standard way to register shortcuts
    /// without drawing anything.
    ///
    /// Deliberately not bound: plain Delete. The inline text editor is a
    /// TextField, and a shortcut with no modifier would swallow backspace
    /// while typing.
    private var keyboardCommands: some View {
        Group {
            Group {
                shortcut("z", [.command]) { store.undo() }
                shortcut("z", [.command, .shift]) { store.redo() }
                shortcut("c", [.command]) { store.copySelected() }
                shortcut("x", [.command]) { store.cutSelected() }
                shortcut("v", [.command]) { store.paste() }
            }
            Group {
                shortcut("d", [.command]) { store.duplicateSelected() }
                shortcut("a", [.command]) { store.selectAll() }
                shortcut("f", [.command]) { activeSheet = .find }
                shortcut(.delete, [.command]) { store.deleteSelected() }
                shortcut(.escape, []) { store.select(nil) }
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func shortcut(_ key: KeyEquivalent, _ modifiers: EventModifiers,
                          action: @escaping () -> Void) -> some View {
        Button("", action: action)
            .keyboardShortcut(key, modifiers: modifiers)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                saveNow()
                onHome()
            } label: {
                Image(systemName: "chevron.left")
                    .fontWeight(.semibold)
            }
            .accessibilityLabel("Home")

            Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!store.canUndo)
                .accessibilityLabel("Undo")
            Button { store.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!store.canRedo)
                .accessibilityLabel("Redo")

            Spacer()

            TextField("Untitled design", text: $store.design.title)
                .multilineTextAlignment(.center)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: 180)
                .focused($titleFocused)
                // Record the rename atomically when editing ends. Holding the
                // store's single pending slot for the whole session was
                // fragile: any other commit while the keyboard was still up
                // consumed it, so the rename reached neither undo nor autosave.
                .onChange(of: titleFocused) { _, focused in
                    if focused {
                        titleBeforeEdit = store.design.title
                    } else {
                        let renamed = store.design.title
                        guard renamed != titleBeforeEdit else { return }
                        store.design.title = titleBeforeEdit    // rewind…
                        store.apply { $0.title = renamed }      // …and apply as one step
                    }
                }
                .onSubmit { titleFocused = false }

            Spacer()

            overflowMenu

            Button { shuffleColors() } label: { Image(systemName: "sparkles") }
                .accessibilityLabel("Shuffle colors")
            Button { activeSheet = .resize } label: { Image(systemName: "aspectratio") }
                .accessibilityLabel("Resize design")
            Button { activeSheet = .export } label: {
                Image(systemName: "square.and.arrow.up")
                    .fontWeight(.semibold)
            }
            .accessibilityLabel("Export")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.chrome)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var overflowMenu: some View {
        Menu {
            // Sections rather than a flat list with dividers: a ViewBuilder
            // block takes ten children and this menu is past that, and menu
            // sections draw the same separators for free.
            Section {
                Button {
                    activeSheet = .layers
                } label: { Label("Layers", systemImage: "square.3.layers.3d") }

                Button {
                    activeSheet = .background
                } label: { Label("Page background", systemImage: "photo.artframe") }

                Button {
                    activeSheet = .find
                } label: { Label("Find and replace", systemImage: "text.magnifyingglass") }
            }

            Section {
                Button {
                    store.copyStyle()
                } label: { Label("Copy style", systemImage: "paintbrush.pointed") }
                    .disabled(store.singleSelection == nil)

                Button {
                    store.pasteStyle()
                } label: { Label("Paste style", systemImage: "paintbrush") }
                    .disabled(!store.hasCopiedStyle || store.selection.isEmpty)
            }

            Section {
                Button {
                    store.selectAll()
                } label: { Label("Select all", systemImage: "checkmark.circle") }

                Button {
                    store.copySelected()
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .disabled(store.selection.isEmpty)

                Button {
                    store.cutSelected()
                } label: { Label("Cut", systemImage: "scissors") }
                    .disabled(store.selection.isEmpty)

                Button {
                    store.paste()
                } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                    .disabled(!store.hasClipboard)
            }

            Section {
                if store.selectionIsGrouped {
                    Button {
                        store.ungroupSelected()
                    } label: { Label("Ungroup", systemImage: "square.on.square.dashed") }
                } else {
                    Button {
                        store.groupSelected()
                    } label: { Label("Group", systemImage: "square.on.square") }
                        .disabled(!store.canGroup)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More actions")
    }

    private var insertButton: some View {
        Button {
            activeSheet = .insert
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
        }
        .buttonStyle(AccentButtonStyle())
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .accessibilityLabel("Add element")
    }

    // MARK: sheets

    @ViewBuilder
    private func sheetView(_ sheet: EditorSheet) -> some View {
        switch sheet {
        case .insert:
            InsertSheet(store: store)
        case .colorFill:
            ColorPickerSheet(store: store, title: "Fill color",
                             current: store.singleSelection?.fill?.primaryColor,
                             allowGradients: true,
                             onPick: { c in store.updateSelected { $0.fill = .solid(c) } },
                             onPickGradient: { p in store.updateSelected { $0.fill = p } },
                             onPickTransient: { c in store.updateSelectedTransient { $0.fill = .solid(c) } })
        case .colorText:
            ColorPickerSheet(store: store, title: "Text color",
                             current: store.singleSelection?.color,
                             onPick: { c in store.updateSelected { $0.color = c } },
                             onPickTransient: { c in store.updateSelectedTransient { $0.color = c } })
        case .colorLine:
            ColorPickerSheet(store: store, title: "Line color",
                             current: store.singleSelection?.color,
                             onPick: { c in store.updateSelected { $0.color = c } },
                             onPickTransient: { c in store.updateSelectedTransient { $0.color = c } })
        case .colorStroke:
            ColorPickerSheet(store: store, title: "Border color",
                             current: store.singleSelection?.stroke,
                             onPick: { c in
                                 store.updateSelected {
                                     $0.stroke = c
                                     if ($0.strokeWidth ?? 0) == 0 { $0.strokeWidth = 4 }
                                 }
                             },
                             onPickTransient: { c in
                                 store.updateSelectedTransient {
                                     $0.stroke = c
                                     if ($0.strokeWidth ?? 0) == 0 { $0.strokeWidth = 4 }
                                 }
                             })
        case .background:
            BackgroundSheet(store: store)
        case .fonts:
            FontSheet(store: store)
        case .effects:
            EffectsSheet(store: store)
        case .spacing:
            SpacingSheet(store: store)
        case .filters:
            FiltersSheet(store: store)
        case .crop:
            CropSheet(store: store)
        case .position:
            PositionSheet(store: store)
        case .layers:
            LayersSheet(store: store)
        case .export:
            ExportSheet(store: store)
        case .resize:
            ResizeSheet(store: store)
        case .find:
            FindReplaceSheet(store: store)
        case .frame:
            FrameSheet(store: store)
        case .shadow:
            ShadowSheet(store: store)
        }
    }

    // MARK: actions

    private func shuffleColors() {
        let palettes = ContentLibrary.palettes
        guard !palettes.isEmpty else { return }
        let palette = palettes[paletteIndex % palettes.count]
        paletteIndex += 1
        let colors = ColorTools.documentColors(store.design, limit: 24)
        guard !colors.isEmpty else { return }
        store.applyToPage { page in
            ColorTools.shuffle(page: &page, docColors: colors, palette: palette.colors)
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            saveDocument()
        }
    }

    /// The debounced path: persist the document, nothing else. This runs
    /// 900ms after every committed edit, so it must stay cheap.
    @MainActor
    private func saveDocument() {
        // Every explicit save supersedes (and must cancel) the debounced one,
        // or a stale task can resurrect a design deleted after leaving.
        saveTask?.cancel()
        saveTask = nil
        DesignLibrary.save(store.design)
    }

    /// Document plus a refreshed thumbnail. Only worth doing on the way back
    /// to the home screen, which is the only place the thumbnail is ever
    /// shown — and which cannot be on screen while the editor is. Rendering
    /// it on the debounce meant a full ImageRenderer pass over page one after
    /// every single edit, for an image nobody could see yet.
    @MainActor
    private func saveNow() {
        saveDocument()
        let design = store.design
        let renderer = ImageRenderer(content: PageRenderView(design: design, page: design.pages[0]))
        renderer.scale = 300 / max(design.width, 1)
        // The alpha channel is discarded by jpegData when the thumbnail is
        // written, so compositing it is wasted work.
        renderer.isOpaque = true
        if let ui = renderer.uiImage {
            DesignLibrary.saveThumbnail(ui, for: design.id)
        }
    }
}
