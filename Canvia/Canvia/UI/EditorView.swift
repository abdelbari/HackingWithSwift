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
    case history, proofread, theme, help, contrast, brand
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
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var tip: Tip?
    @State private var presenting = false
    @State private var namingComponent = false
    @State private var componentName = ""
    @State private var tipTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let tip { tipBanner(tip) }
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
        .overlay(alignment: .bottom) { undoToast }
        .onChange(of: store.announcement) { _, text in
            guard let text else { return }
            store.announcement = nil
            show(toast: text)
        }
        .onChange(of: store.tipEvent) { _, event in
            guard let event else { return }
            store.tipEvent = nil
            if let next = TipEngine.shared.tip(for: event) { show(tip: next) }
        }
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
        .fullScreenCover(isPresented: $presenting) {
            PresentationView(design: store.design, startPage: store.pageIndex)
        }
        .alert("Name this component", isPresented: $namingComponent) {
            TextField("Footer, Price tag, Call-out…", text: $componentName)
            Button("Save") {
                let name = componentName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { store.saveSelectionAsComponent(named: name) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Components appear in the Elements tab of Add, in every design, and drop in at half the page's width.")
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
                shortcut("z", [.command], "Undo") { store.undo() }
                shortcut("z", [.command, .shift], "Redo") { store.redo() }
                shortcut("c", [.command], "Copy") { store.copySelected() }
                shortcut("x", [.command], "Cut") { store.cutSelected() }
                shortcut("v", [.command], "Paste") { store.paste() }
                shortcut("d", [.command], "Duplicate") { store.duplicateSelected() }
                shortcut("a", [.command], "Select all") { store.selectAll() }
                shortcut(.delete, [.command], "Delete") { store.deleteSelected() }
                shortcut(.escape, [], "Deselect") { store.select(nil) }
            }
            // Arrow keys nudge a page unit, ten with Shift — only while no
            // text field has the keyboard, or the arrows would never reach
            // the caret.
            if store.editingTextId == nil && !titleFocused {
                Group {
                    shortcut(.leftArrow, [], "Nudge left") { store.nudgeSelected(dx: -1, dy: 0) }
                    shortcut(.rightArrow, [], "Nudge right") { store.nudgeSelected(dx: 1, dy: 0) }
                    shortcut(.upArrow, [], "Nudge up") { store.nudgeSelected(dx: 0, dy: -1) }
                    shortcut(.downArrow, [], "Nudge down") { store.nudgeSelected(dx: 0, dy: 1) }
                    shortcut(.leftArrow, [.shift], "Nudge left by 10") { store.nudgeSelected(dx: -10, dy: 0) }
                    shortcut(.rightArrow, [.shift], "Nudge right by 10") { store.nudgeSelected(dx: 10, dy: 0) }
                    shortcut(.upArrow, [.shift], "Nudge up by 10") { store.nudgeSelected(dx: 0, dy: -10) }
                    shortcut(.downArrow, [.shift], "Nudge down by 10") { store.nudgeSelected(dx: 0, dy: 10) }
                }
            }
            Group {
                shortcut("g", [.command], "Group") { store.groupSelected() }
                shortcut("g", [.command, .shift], "Ungroup") { store.ungroupSelected() }
                shortcut("]", [.command], "Bring forward") { store.reorderSelected(.forward) }
                shortcut("[", [.command], "Send backward") { store.reorderSelected(.backward) }
                shortcut("]", [.command, .shift], "Bring to front") { store.reorderSelected(.front) }
                shortcut("[", [.command, .shift], "Send to back") { store.reorderSelected(.back) }
                shortcut("l", [.command, .shift], "Lock or unlock") { store.toggleLockSelected() }
            }
            Group {
                shortcut("f", [.command], "Find and replace") { activeSheet = .find }
                shortcut("e", [.command], "Export") { activeSheet = .export }
                shortcut("k", [.command], "Layers") { activeSheet = .layers }
                shortcut("p", [.command, .shift], "Present") { presenting = true }
                shortcut("/", [.command], "Help") { activeSheet = .help }
                shortcut("n", [.command, .shift], "New page") { store.addPage() }
            }
        }
    }

    /// A zero-size button carrying a shortcut. It has a real title, unseen
    /// here, because holding ⌘ on an iPad lists every shortcut by the title
    /// of its button — an empty title made the list a column of blanks.
    private func shortcut(_ key: KeyEquivalent, _ modifiers: EventModifiers, _ title: String,
                          action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .keyboardShortcut(key, modifiers: modifiers)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
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
                    presenting = true
                } label: { Label("Present", systemImage: "play.rectangle") }

                Button {
                    store.toggleMasterPage()
                } label: {
                    Label(store.isOnMasterPage ? "Stop using this page as master" : "Use this page as master",
                          systemImage: "rectangle.on.rectangle")
                }
                if store.design.masterPage != nil && !store.isOnMasterPage {
                    Button {
                        store.toggleUsesMaster()
                    } label: {
                        Label(store.page.usesMaster == false ? "Show master on this page" : "Hide master on this page",
                              systemImage: "rectangle.on.rectangle.slash")
                    }
                }
            }

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

                Button {
                    activeSheet = .proofread
                } label: { Label("Check spelling", systemImage: "textformat.abc.dottedunderline") }

                Button {
                    activeSheet = .theme
                } label: { Label("Document theme", systemImage: "paintpalette") }

                Button {
                    activeSheet = .contrast
                } label: { Label("Check contrast", systemImage: "circle.lefthalf.striped.horizontal") }

                Button {
                    activeSheet = .brand
                } label: { Label("Brand kit", systemImage: "briefcase") }

                Button {
                    activeSheet = .help
                } label: { Label("Help", systemImage: "questionmark.circle") }

                Button {
                    // Whatever is on screen now is the newest version, so
                    // the list never starts with a state you cannot get back
                    // to.
                    DesignLibrary.snapshot(store.design)
                    activeSheet = .history
                } label: { Label("Version history", systemImage: "clock.arrow.circlepath") }
            }

            Section {
                Button {
                    componentName = ""
                    namingComponent = true
                } label: { Label("Save selection as component…", systemImage: "square.grid.3x1.folder.badge.plus") }
                    .disabled(store.selection.isEmpty)
                snappingMenu
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
            // A gradient on text is a fill, not a colour, so it lives in its
            // own field; picking a plain colour clears it.
            ColorPickerSheet(store: store, title: "Text color",
                             current: store.singleSelection?.color,
                             allowGradients: true,
                             onPick: { c in store.updateSelected { $0.color = c; $0.textFill = nil } },
                             onPickGradient: { p in store.updateSelected { $0.textFill = p } },
                             onPickTransient: { c in
                                 store.updateSelectedTransient { $0.color = c; $0.textFill = nil }
                             })
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
        case .history:
            VersionHistorySheet(store: store)
        case .proofread:
            ProofreadSheet(store: store)
        case .theme:
            ThemeSheet(store: store)
        case .contrast:
            ContrastSheet(store: store)
        case .brand:
            BrandKitSheet(store: store)
        case .help:
            // The help sheet is itself presented; the one it opens has to
            // wait for it to be gone, or SwiftUI drops the second present.
            HelpSheet { sheet in
                activeSheet = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    activeSheet = sheet
                }
            }
        }
    }

    // MARK: undo toast

    /// A brief line after a destructive edit — delete, restore, replace all —
    /// with an Undo button on it. The edits are already undoable from the
    /// toolbar; the toast is for the moment right after, when you have not
    /// yet looked for the button and are not sure the thing is gone.
    @ViewBuilder
    private var undoToast: some View {
        if let toast {
            HStack(spacing: 12) {
                Text(toast)
                    .font(.subheadline)
                    .lineLimit(1)
                Button("Undo") {
                    store.undo()
                    dismissToast()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            // Clear of the pages bar and the context toolbar, both of which
            // live at the bottom of the stack.
            .padding(.bottom, store.selection.isEmpty ? 96 : 150)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: tips

    /// One line under the top bar, with a way to close it, gone on its own
    /// after a while. Above the canvas rather than over it: a tip must never
    /// cover the thing it is talking about.
    private func tipBanner(_ tip: Tip) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tip.systemImage)
                .foregroundStyle(Theme.accent)
                .padding(.top, 1)
            Text(tip.text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                dismissTip()
            } label: { Image(systemName: "xmark").font(.footnote.weight(.semibold)) }
                .accessibilityLabel("Dismiss tip")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.accentSubtle)
        .overlay(alignment: .bottom) { Divider() }
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }

    private func show(tip next: Tip) {
        tipTask?.cancel()
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) { tip = next }
        tipTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(9))
            guard !Task.isCancelled else { return }
            dismissTip()
        }
    }

    private func dismissTip() {
        tipTask?.cancel()
        tipTask = nil
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { tip = nil }
    }

    private func show(toast text: String) {
        toastTask?.cancel()
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) { toast = text }
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            dismissToast()
        }
    }

    private func dismissToast() {
        toastTask?.cancel()
        toastTask = nil
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { toast = nil }
    }

    /// Snapping switches and the grid, in a submenu so the overflow stays a
    /// list of verbs. Toggles rather than a sheet: each is one tap and you
    /// are back on the canvas, which is where you want to be when you are
    /// deciding whether the snapping is helping.
    private var snappingMenu: some View {
        Menu {
            Toggle("Snap to elements", isOn: $store.snapping.toElements)
            Toggle("Snap to page", isOn: $store.snapping.toPage)
            Picker("Grid", selection: $store.snapping.grid) {
                Text("No grid").tag(0.0)
                ForEach(SnapSettings.gridChoices.filter { $0 > 0 }, id: \.self) { step in
                    Text("Every \(Int(step)) px").tag(step)
                }
            }
            Toggle("Show grid", isOn: $store.snapping.showGrid)
                .disabled(!store.snapping.gridEnabled)
            Picker("Margins", selection: $store.snapping.margin) {
                Text("No margins").tag(0.0)
                ForEach(SnapSettings.marginChoices.filter { $0 > 0 }, id: \.self) { m in
                    Text("\(Int((m * 100).rounded()))% of the short side").tag(m)
                }
            }
            Toggle("Show margins", isOn: $store.snapping.showMargins)
                .disabled(!store.snapping.marginEnabled)
            Divider()
            Button { store.addGuide(vertical: true) } label: { Label("Add vertical guide", systemImage: "line.vertical") }
            Button { store.addGuide(vertical: false) } label: { Label("Add horizontal guide", systemImage: "line.horizontal") }
            Button(role: .destructive) { store.clearGuides() } label: { Label("Remove all guides", systemImage: "trash") }
                .disabled(store.design.guides.isEmpty)
        } label: {
            Label("Snapping", systemImage: "square.grid.3x3")
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
        // Rate-limited inside, so this is free most of the time.
        DesignLibrary.snapshot(store.design)
    }

    /// Document plus a refreshed thumbnail. Only worth doing on the way back
    /// to the home screen, which is the only place the thumbnail is ever
    /// shown — and which cannot be on screen while the editor is. Rendering
    /// it on the debounce meant a full ImageRenderer pass over page one after
    /// every single edit, for an image nobody could see yet.
    @MainActor
    private func saveNow() {
        saveDocument()
        // Leaving the editor is a moment worth keeping whatever the timer says.
        DesignLibrary.snapshot(store.design, force: true)
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
