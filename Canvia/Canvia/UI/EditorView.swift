// Editor screen: top bar (back, undo/redo, title, shuffle, export), canvas,
// contextual toolbar, pages bar, insert button, and sheet routing.
// Autosaves after every commit (debounced).

import SwiftUI

enum EditorSheet: String, Identifiable {
    case insert, colorFill, colorText, colorLine, colorStroke, background
    case fonts, effects, spacing, filters, crop, position, layers, export, resize
    var id: String { rawValue }
}

struct EditorView: View {
    @Bindable var store: DesignStore
    var onHome: () -> Void

    @State private var activeSheet: EditorSheet?
    @State private var saveTask: Task<Void, Never>?
    @State private var paletteIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack(alignment: .bottomTrailing) {
                CanvasView(store: store)
                insertButton
                    .padding(18)
            }
            if !store.selection.isEmpty {
                ContextToolbar(store: store, activeSheet: $activeSheet)
            }
            PagesBar(store: store)
        }
        .background(Color(hex: "#ebecf0"))
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
            Button { store.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!store.canRedo)

            Spacer()

            TextField("Untitled design", text: $store.design.title)
                .multilineTextAlignment(.center)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: 180)
                .onSubmit { store.commit() }

            Spacer()

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
        .background(.background)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var insertButton: some View {
        Button {
            activeSheet = .insert
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Circle().fill(Color(hex: "#8b3dff")))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        }
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
                             onPickGradient: { p in store.updateSelected { $0.fill = p } })
        case .colorText:
            ColorPickerSheet(store: store, title: "Text color",
                             current: store.singleSelection?.color,
                             onPick: { c in store.updateSelected { $0.color = c } })
        case .colorLine:
            ColorPickerSheet(store: store, title: "Line color",
                             current: store.singleSelection?.color,
                             onPick: { c in store.updateSelected { $0.color = c } })
        case .colorStroke:
            ColorPickerSheet(store: store, title: "Border color",
                             current: store.singleSelection?.stroke,
                             onPick: { c in
                                 store.updateSelected {
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
            saveNow()
        }
    }

    @MainActor
    private func saveNow() {
        DesignLibrary.save(store.design)
        // Thumbnail from page 1.
        let design = store.design
        let renderer = ImageRenderer(content: PageRenderView(design: design, page: design.pages[0]))
        renderer.scale = 300 / max(design.width, 1)
        if let ui = renderer.uiImage {
            DesignLibrary.saveThumbnail(ui, for: design.id)
        }
    }
}
