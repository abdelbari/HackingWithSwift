// Editor screen: top bar (back, undo/redo, title, shuffle, export), canvas,
// contextual toolbar, pages bar, insert button, and sheet routing.
// Autosaves after every commit (debounced).

import SwiftUI
import UIKit

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
    case insert, colorFill, colorText, colorLine, colorStroke, colorSelection, colorWords, background
    case fonts, effects, spacing, filters, crop, position, layers, export, resize, find, frame, shadow
    case history, proofread, theme, help, accessibility, brand, shapes, clip, shapeText, table
    /// Edit chart: the chart sheet again, filled in from the selected chart.
    case chart
    /// Opened by Help's "Show me": the page organiser, and the snapping
    /// switches as a sheet (a Menu cannot be opened from code).
    case pages, snapping
    /// The Snapping menu's "Add guides…".
    case addGuides
    /// More's "Copy & resize…": the Resize sheet, opened on its copies.
    case copyResize
    case settings
    /// More's "Audio": the design's tracks, and a voice-over.
    case audio
    /// Page animations: every element on the page arriving, leaving or both.
    case pageAnimation
    /// The typing bar's Aa: the font sheet for the words chosen.
    case fontWords
    /// Adjust photo: the picture in a text's letters (PhotoInLetters).
    case photoInLetters
    /// More like this, for a selected icon, sticker, graphic or shape.
    case similar
    /// The typing bar's highlighter: marker colours for the words chosen.
    case highlightWords
    /// More's "Bulk create…": a page, or a design, for each row of a table.
    case bulk
    var id: String { rawValue }
}

struct EditorView: View {
    @Bindable var store: DesignStore
    var onHome: () -> Void

    @State private var activeSheet: EditorSheet?
    @State private var saveTask: Task<Void, Never>?
    @State private var paletteIndex = 0
    @FocusState private var titleFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var titleBeforeEdit = ""
    @State private var toast: String?
    /// Whether the toast on screen offers Undo.
    @State private var toastUndoes = true
    /// The history's step when the toast offered its Undo.
    @State private var toastVersion = 0
    /// The copies Copy & resize just made, which the toast offers to Open
    /// in place of an Undo.
    @State private var toastOpens: [String] = []
    /// The locked page the toast offers to unlock, when it says a page is
    /// locked (DesignStore.refusesLockedPage).
    @State private var toastUnlocks: String?
    /// Whether the toast offers to unlock the guides (refusesLockedGuides).
    @State private var toastUnlocksGuides = false
    @State private var toastTask: Task<Void, Never>?
    @State private var tip: Tip?
    @State private var presenting = false
    /// Present and record: the studio over the design, and its talks.
    @State private var talkRecording: Design?
    @State private var talkReviewing: Design?
    /// The Vibration switch, shared with Home.
    @AppStorage(Haptics.key) private var haptics = true
    /// Quick actions at the selection, on unless turned off (SelectionBubble).
    @AppStorage(SelectionBubble.key) private var quickActions = true
    /// Scroll through pages: every page down one column on the canvas, on
    /// unless turned off (PageColumn).
    @AppStorage(PageColumn.key) private var pageScroll = true
    /// Rulers along the canvas's top and left, off unless turned on
    /// (RulersView).
    @AppStorage(Guides.rulersKey) private var rulers = false
    /// The timeline above the pages, off unless turned on (TimelineStrip).
    @AppStorage(TimelineStrip.key) private var timeline = false
    /// Shape assist, on the Draw bar: on unless turned off (ShapeAssist).
    @AppStorage(ShapeAssist.key) private var shapeAssist = true
    @State private var namingComponent = false
    /// More's "Save as template…" asking for a name and a category.
    @State private var savingTemplate = false
    /// More's "Save a named version…" asking for a name.
    @State private var namingVersion = false
    /// The Snapping menu's Grid "Custom…" asking for a spacing.
    @State private var askingCustomGrid = false
    @State private var componentName = ""
    @State private var tipTask: Task<Void, Never>?
    /// The crop slider's end while it is being dragged, held still.
    @State private var cropCeiling = Crop.maxZoom
    @State private var cropSliding = false
    /// The pen's own colour, from the colour sheet, being chosen.
    @State private var choosingInk = false
    /// Undo's rewind while it is held, whether one happened in this press,
    /// and how often it has run out of steps (for the thud).
    @State private var rewindTask: Task<Void, Never>?
    @State private var rewound = false
    /// Whether a finger is on Undo — reset by SwiftUI however the press ends.
    @GestureState private var undoHeld = false
    @State private var rewindExhausted = 0
    /// Set while the design on screen could not be written, and cleared by
    /// the next save that could.
    @State private var saveFailed = false
    /// Counted up each time the editor is the one to answer the system's
    /// undo gestures again (UndoHost): as it appears, and as typing, the
    /// title, a sheet or an alert lets the keyboard go.
    @State private var undoClaim = 0
    @Environment(\.accessibilityReduceMotion) private var systemReducesMotion
    /// Settings ▸ Accessibility's Reduce motion, over the phone's own
    /// (AccessibilityPrefs).
    @AppStorage(AccessibilityPrefs.reduceMotionKey) private var reduceMotionChoice = AccessibilityPrefs.system
    private var reduceMotion: Bool {
        AccessibilityPrefs.reducesMotion(reduceMotionChoice, systemReduces: systemReducesMotion)
    }

    /// What the banner says while saves are failing; the Android twin says
    /// the same.
    static var saveFailedMessage: String {
        tr("Couldn't save your changes. Your phone may be out of space. Canvia will keep trying.")
    }

    /// The page background panel — on a locked page, which keeps its
    /// background, the refusal, with Unlock, instead.
    private func openBackground() {
        if !store.refusesLockedPage() { activeSheet = .background }
    }

    /// The editor's stack and the modifiers that answer the canvas — split
    /// from `body`'s sheets, alerts and lifecycle so the type checker takes
    /// each chain in reasonable time.
    private var editorStack: some View {
        VStack(spacing: 0) {
            topBar
            if saveFailed { saveFailedBanner }
            if let tip { tipBanner(tip) }
            ZStack(alignment: .bottomTrailing) {
                CanvasView(store: store, onBackground: openBackground)
                    .overlay { if rulers { RulersView(store: store).allowsHitTesting(!pageTaken) } }
                    .overlay { SelectionBubble(store: store) { activeSheet = .similar } }
                    .overlay { HoldMenuPill(store: store, openBackground: openBackground) }
                    .overlay(alignment: .top) {
                        CanvasChips(store: store).padding(.top, CGFloat(rulers ? Guides.rulerThickness : 0))
                    }
                if let tool = store.drawing {
                    drawingBar(tool)
                        // Never quite to the screen's edges.
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 14)
                } else if store.erasing != nil {
                    eraserBar
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 14)
                } else if let brush = store.brushing {
                    BrushBar(store: store, session: brush)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 14)
                } else if store.cropping != nil {
                    cropBar
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 14)
                } else if store.graphicCropping != nil {
                    graphicCropBar
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 14)
                } else if let recording = store.motionRecording {
                    MotionBar(store: store, recording: recording)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 14)
                } else {
                    insertButton
                        .padding(18)
                }
            }
            // An export running in the app's queue, just above the toolbar
            // and beside the insert button — out of the way of the pen's,
            // the eraser's and the crop's bars: a tap opens the sheet on its
            // progress.
            .overlay(alignment: .bottomLeading) {
                if store.drawing == nil && store.erasing == nil && !cropMode && store.brushing == nil
                    && store.motionRecording == nil {
                    ExportPill { activeSheet = .export }
                        .padding(.trailing, 72)
                        .padding(.bottom, 26)
                }
            }
            // Always rendered, never inserted. Adding and removing this from
            // the stack resized the canvas on every selection — and by a
            // different amount for a text selection than a shape one, so the
            // page jumped under your finger at the exact moment you were
            // trying to look at it.
            // Still there in crop mode, so the canvas keeps its size, but
            // resting: the crop bar is where the photo is worked then.
            // Select multiple lays its banner over the bar, in the bar's own
            // room, so the canvas keeps its size as the mode comes and goes.
            ContextToolbar(store: store, activeSheet: $activeSheet)
                .frame(height: store.selection.isEmpty && !store.selectingMultiple ? 0 : nil)
                .opacity(store.selection.isEmpty ? 0 : !cropMode ? 1 : 0.35)
                .clipped()
                .allowsHitTesting(!store.selection.isEmpty && !cropMode && !store.selectingMultiple)
                .overlay {
                    if store.selectingMultiple { selectMultipleBanner }
                }
            // Rows with no room to grow: Larger Text up to accessibility2.
            if timeline { TimelineStrip(store: store).chromeTypeSize() }
            PagesBar(store: store).chromeTypeSize()
        }
        .background(keyboardCommands)
        .background(UndoHost(store: store, live: undoHostLive, claim: undoClaim))
        .onChange(of: undoHostLive, initial: true) { _, live in
            if live { undoClaim += 1 }
        }
        .overlay(alignment: .bottom) { undoToast }
        // A toast's Undo is withdrawn once anything else is done, as the
        // Android twin's snackbar is: held open for VoiceOver, it would
        // otherwise take back a later edit than the one it names.
        .onChange(of: store.historyVersion) { _, version in
            if toast != nil && toastUndoes && version != toastVersion { dismissToast() }
        }
        .onChange(of: store.announcement) { _, text in
            guard let text else { return }
            store.announcement = nil
            let unlocks = store.announcementUnlocks
            let unlocksGuides = store.announcementUnlocksGuides
            store.announcementUnlocks = nil
            store.announcementUnlocksGuides = false
            show(toast: text, undoable: store.announcementUndoes)
            toastUnlocks = unlocks
            toastUnlocksGuides = unlocksGuides
        }
        .onChange(of: store.tipEvent) { _, event in
            guard let event else { return }
            store.tipEvent = nil
            if let next = TipEngine.shared.tip(for: event) { show(tip: next) }
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.86),
                   value: store.selection.isEmpty)
        // The whole point of a design tool is that it answers your hands.
        // All of it through the Vibration switch.
        .feel(.selection, trigger: store.selection)
        .feel(.alignment, trigger: SnapSignal(x: store.guideX, y: store.guideY))
        .feel(.impact(weight: .heavy), trigger: store.page.elements.count)
        .feel(trigger: store.rotationSnapped) { _, snapped in snapped ? .alignment : nil }
        .feel(trigger: store.spacingSnapped) { _, spaced in spaced ? .alignment : nil }
        .feel(trigger: store.haptic) { _, event in event.feedback }
        .background(Theme.workspace)
    }

    /// A photo's or a graphic's crop mode is on.
    private var cropMode: Bool { store.cropping != nil || store.graphicCropping != nil }

    /// Crop, typing, the pen, the eraser or a brush has the page.
    private var pageTaken: Bool {
        cropMode || store.editingTextId != nil || store.drawing != nil || store.erasing != nil
            || store.brushing != nil || store.motionRecording != nil
    }

    var body: some View {
        editorStack
        .sheet(item: $activeSheet) { sheet in
            // The canvas, the quick actions and the keys still take Delete
            // under a sheet: its question is asked from the sheet, since the
            // editor beneath cannot present while the sheet is up.
            sheetView(sheet)
                .asksBeforeLockedDelete(Binding(get: { store.askingDelete && activeSheet != nil },
                                                set: { store.askingDelete = $0 }),
                                        several: deletesSeveral, store: store)
        }
        // A sheet rises over the lower half of the canvas: the selection is
        // kept in the half still showing — as the sheet opens, and as the
        // selection changes under it, a Layers row picked, say.
        .onChange(of: activeSheet) { _, sheet in
            // A question left from before is not asked out of place.
            store.askingDelete = false
            // The edge scroll stops at a panel's top; the hold menu goes.
            store.panelOpen = sheet != nil
            store.holdMenuAt = nil
            if sheet != nil {
                // A panel opening ends Select multiple; the selection stays.
                store.endSelectingMultiple()
                revealSelection()
            }
            if sheet != .colorWords, store.wordColourTarget != nil { store.wordColourTarget = nil }
            if sheet != .fontWords, store.wordFontTarget != nil { store.wordFontTarget = nil }
            if sheet != .highlightWords, store.wordHighlightTarget != nil { store.wordHighlightTarget = nil }
            if sheet != .photoInLetters, store.photoAdjustTarget != nil { store.photoAdjustTarget = nil }
        }
        // Crop, typing, the pen or the eraser taking the page ends Select
        // multiple as a panel does, the selection kept — as on the Android
        // twin.
        .onChange(of: pageTaken) { _, busy in
            if busy { store.endSelectingMultiple() }
        }
        // The typing bar's colour well, Aa and Link ask for the colour sheet,
        // the font sheet and the link prompt for the words chosen.
        .modifier(WordRequests(store: store, activeSheet: $activeSheet))
        .modifier(PageAnimationRequest(store: store, activeSheet: $activeSheet))
        .onChange(of: store.selection) { _, _ in
            if activeSheet != nil { revealSelection() }
        }
        .fullScreenCover(isPresented: $presenting) {
            // Loop turned on or off in Present is the design's own, kept
            // for next time, as one step Undo takes back.
            PresentationView(design: store.design, startPage: store.pageIndex) { on in
                store.apply { $0.presentLoops = on }
            }
        }
        // A page playing in place stops as the talk begins, so the two are
        // never heard at once.
        .onChange(of: presenting) { _, on in
            if on { store.stopPreview() }
        }
        // A talk kept is the design's own, as one step Undo takes back.
        .modifier(TalkSheets(recording: $talkRecording, reviewing: $talkReviewing) { next in
            store.apply { $0.recordings = next.recordings }
        })
        .customGridAlert(isPresented: $askingCustomGrid, store: store)
        .saveTemplateAlert(isPresented: $savingTemplate, store: store) { text in show(toast: text, undoable: false) }
        .namedVersionAlert(isPresented: $namingVersion, store: store) { text in show(toast: text, undoable: false) }
        .asksBeforeLockedDelete(Binding(get: { store.askingDelete && activeSheet == nil },
                                        set: { store.askingDelete = $0 }),
                                several: deletesSeveral, store: store)
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
            // Made with "Start with my brand": the kit's look is its first
            // step.
            if BrandStart.take(store.design.id) { store.applyBrandKit(BrandKit.load()) }
        }
        // Into the background, the design is saved as it stands — notes or
        // words still being typed included, whose steps are not closed yet
        // and so have not been saved; the system may end the app there.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            saveDocument()
            // A page playing in place falls silent, and stops.
            store.stopPreview()
        }
        .onDisappear {
            // The voice and the microphone belong to this design: leaving it
            // stops both, as the Android twin's editor releases its reader.
            ReadAloud.shared.stop()
            if Dictation.shared.isListening { Dictation.shared.stop() }
            store.stopPreview()
            // The page's clips' players go with it, as the Android twin's
            // canvas lets its readers go as it leaves the screen.
            ClipPlayers.shared.close(elements: store.clipElements(onPage: store.pageIndex))
            store.finishDictation()
            store.endTextEdit()
            // A drawing under way is put down first, so its strokes are
            // saved as one drawing, as the Android twin's editor does.
            store.drawing = nil
            closeRename()
            saveNow()
        }
        // The design being edited, for Siri suggestions and Handoff.
        .userActivity(DesignActivity.type, element: store.design.id) { _, activity in
            DesignActivity.configure(activity, design: store.design)
        }
    }

    // MARK: top bar

    /// Hardware-keyboard shortcuts. Every operation here already existed on
    /// the store and was reachable only by tapping — which on an iPad with a
    /// Magic Keyboard makes a design tool feel like a toy. Zero-sized buttons
    /// in a background layer is the standard way to register shortcuts
    /// without drawing anything.
    ///
    /// Plain Delete and Forward Delete remove the selection, as they do on
    /// the Android twin and in every design tool — but only while nothing
    /// is being typed: not in the inline text editor, the title, a sheet or
    /// an alert, where a shortcut with no modifier would swallow backspace.
    private var keyboardCommands: some View {
        Group {
            if presenting {
                // None while presenting, as on the Android twin: the slides
                // take their own keys, and a ⌘ key or Delete that fell
                // through to here would edit the design out of sight.
                EmptyView()
            } else if store.cropping != nil {
                // Crop mode has its own two keys; the rest wait, since the
                // photo is the only thing being worked.
                shortcut(.return, [], tr("Done cropping")) { store.finishCrop() }
                shortcut(.escape, [], tr("Cancel crop")) { store.cancelCrop() }
            } else if store.graphicCropping != nil {
                shortcut(.return, [], tr("Done cropping")) { store.finishGraphicCrop() }
                shortcut(.escape, [], tr("Cancel crop")) { store.cancelGraphicCrop() }
            } else if store.brushing != nil {
                // So has a brush, and ⌘Z takes back the last stroke, as the
                // bar's Undo stroke does.
                shortcut(.return, [], tr("Done")) { store.finishBrush() }
                shortcut(.escape, [], tr("Cancel")) { store.cancelBrush() }
                shortcut("z", [.command], tr("Undo stroke")) { store.undoBrushStroke() }
            } else if store.editingTextId != nil {
                // While words are typed in place, the ⌘ keys are the text's —
                // ⌘A selects its words, ⌘V pastes text, ⌘Z takes back typing —
                // as on the Android twin. Escape is Done: the typing kept as
                // its own step, an emptied box removed, the box still chosen.
                shortcut(.escape, [], tr("Done typing")) { store.endTextEdit() }
            } else if !titleFocused && !store.textFieldOpen {
                editingCommands
            }
        }
    }

    private var editingCommands: some View {
        Group {
            Group {
                if store.erasing != nil {
                    // Under the eraser, ⌘Z takes back the last stroke painted,
                    // as the eraser bar's Undo does; the design behind it is
                    // left alone until the eraser is put down, as on Android.
                    shortcut("z", [.command], tr("Undo stroke")) {
                        if !store.eraserBusy, !store.eraserStrokes.isEmpty { store.eraserStrokes.removeLast() }
                    }
                } else {
                    shortcut("z", [.command], tr("Undo")) { store.undo() }
                    shortcut("z", [.command, .shift], tr("Redo")) { store.redo() }
                    // As well as ⇧⌘Z: the redo a keyboard used to Windows or
                    // Android reaches for, as the Android twin takes Ctrl+Y.
                    shortcut("y", [.command], tr("Redo")) { store.redo() }
                }
                shortcut("c", [.command], tr("Copy")) { store.copySelected() }
                shortcut("x", [.command], tr("Cut")) { store.cutSelected() }
                shortcut("v", [.command], tr("Paste")) { store.paste() }
                shortcut("d", [.command], tr("Duplicate")) { store.duplicateSelected() }
                shortcut("a", [.command], tr("Select all")) { store.selectAll() }
                shortcut(.delete, [.command], tr("Delete")) { store.deleteSelected() }
                // Escape ends paint mode or Select multiple first, keeping
                // the selection.
                shortcut(.escape, [], store.selectingMultiple || store.stylePainting ? tr("Done") : tr("Deselect")) {
                    if store.stylePainting {
                        store.stylePainting = false
                    } else if store.selectingMultiple {
                        store.endSelectingMultiple()
                    } else {
                        store.select(nil)
                    }
                }
            }
            // Arrow keys nudge by the smallest of Position's steps, the
            // middle one with Shift — a pixel or ten, a tenth of a
            // millimetre or one (Units.arrowStep) — only while no text field
            // has the keyboard, or the arrows would never reach the caret.
            if deleteKeysLive {
                shortcut(.delete, [], tr("Delete")) { store.deleteSelected() }
                shortcut(.deleteForward, [], tr("Forward delete")) { store.deleteSelected() }
            }
            if store.editingTextId == nil && !titleFocused {
                let step = Units.arrowStep(store.design, shift: false)
                let big = Units.arrowStep(store.design, shift: true)
                let bigName = Units.readout(big, store.design) + Units.suffix(store.design)
                Group {
                    shortcut(.leftArrow, [], tr("Nudge left")) { store.nudgeSelected(dx: -step, dy: 0) }
                    shortcut(.rightArrow, [], tr("Nudge right")) { store.nudgeSelected(dx: step, dy: 0) }
                    shortcut(.upArrow, [], tr("Nudge up")) { store.nudgeSelected(dx: 0, dy: -step) }
                    shortcut(.downArrow, [], tr("Nudge down")) { store.nudgeSelected(dx: 0, dy: step) }
                    shortcut(.leftArrow, [.shift], tr("Nudge left by %@", bigName)) { store.nudgeSelected(dx: -big, dy: 0) }
                    shortcut(.rightArrow, [.shift], tr("Nudge right by %@", bigName)) { store.nudgeSelected(dx: big, dy: 0) }
                    shortcut(.upArrow, [.shift], tr("Nudge up by %@", bigName)) { store.nudgeSelected(dx: 0, dy: -big) }
                    shortcut(.downArrow, [.shift], tr("Nudge down by %@", bigName)) { store.nudgeSelected(dx: 0, dy: big) }
                }
            }
            Group {
                shortcut("g", [.command], tr("Group")) { store.groupSelected() }
                shortcut("g", [.command, .shift], tr("Ungroup")) { store.ungroupSelected() }
                shortcut("]", [.command], tr("Bring forward")) { store.reorderSelected(.forward) }
                shortcut("[", [.command], tr("Send backward")) { store.reorderSelected(.backward) }
                shortcut("]", [.command, .shift], tr("Bring to front")) { store.reorderSelected(.front) }
                shortcut("[", [.command, .shift], tr("Send to back")) { store.reorderSelected(.back) }
                shortcut("l", [.command, .shift], tr("Lock or unlock")) { store.toggleLockSelected() }
            }
            Group {
                shortcut("f", [.command], tr("Find and replace")) { activeSheet = .find }
                shortcut("e", [.command], tr("Export")) { activeSheet = .export }
                shortcut("k", [.command], tr("Layers")) { activeSheet = .layers }
                shortcut("p", [.command, .shift], tr("Present")) { present() }
                shortcut("/", [.command], tr("Help")) { activeSheet = .help }
                shortcut("n", [.command, .shift], tr("New page")) { store.addPage() }
                // The style painter's keys, as on the Android twin's Ctrl+Alt.
                shortcut("c", [.command, .option], tr("Copy style")) { store.copyStyle() }
                shortcut("v", [.command, .option], tr("Paste style")) { store.pasteStyle() }
            }
            // The view's keys too wait while any text field has the keyboard
            // — ⌥↓ is the end of a paragraph there, and ⌥⇧ letters type
            // characters on many layouts — or a pen is out, as the Android
            // twin keeps only Undo and Redo under it.
            if plainKeysLive {
                viewCommands
                plainCommands
            }
        }
    }

    /// The view's keys, as Canva has them: ⌘= and ⌘- a quarter in and out
    /// about the middle of the screen, ⌘0 the whole page, ⌘1 actual size,
    /// ⌘2 the selection framed, and ⌥↑ and ⌥↓ the page before and after,
    /// which the canvas settles on as it brings it up.
    private var viewCommands: some View {
        Group {
            Group {
                shortcut("=", [.command], tr("Zoom in")) { store.requestCanvas(.zoom(store.zoom * 1.25)) }
                shortcut("-", [.command], tr("Zoom out")) { store.requestCanvas(.zoom(store.zoom / 1.25)) }
                shortcut("0", [.command], tr("Fit the page")) { store.requestCanvas(.fit) }
                shortcut("1", [.command], tr("Actual size")) { store.requestCanvas(.zoom(1)) }
                shortcut(.upArrow, [.option], tr("Previous page")) { store.setPage(store.pageIndex - 1) }
                shortcut(.downArrow, [.option], tr("Next page")) { store.setPage(store.pageIndex + 1) }
                // Position's aligning: to the page, or to each other, as it does.
                shortcut("l", [.option, .shift], tr("Align left")) { store.alignSelected(.left) }
                shortcut("c", [.option, .shift], tr("Align centre")) { store.alignSelected(.centerX) }
                shortcut("r", [.option, .shift], tr("Align right")) { store.alignSelected(.right) }
                shortcut("t", [.option, .shift], tr("Align top")) { store.alignSelected(.top) }
            }
            shortcut("m", [.option, .shift], tr("Align middle")) { store.alignSelected(.centerY) }
            shortcut("b", [.option, .shift], tr("Align bottom")) { store.alignSelected(.bottom) }
            // ⌘2 frames what is selected; ⌘0 fits the page again.
            shortcut("2", [.command], tr("Zoom to selection")) { store.zoomToSelection() }
        }
    }

    /// Keys with no ⌘ to them, only while no text field anywhere could
    /// want them (plainKeysLive): Page Up and Page Down, Tab and Shift-Tab
    /// through what is on the page, front-most last, Shift-H and Shift-V
    /// flipping, and T, a text box in the middle of the page.
    private var plainCommands: some View {
        Group {
            shortcut(.pageUp, [], tr("Previous page")) { store.setPage(store.pageIndex - 1) }
            shortcut(.pageDown, [], tr("Next page")) { store.setPage(store.pageIndex + 1) }
            shortcut(.tab, [], tr("Select next")) { store.selectNeighbour(forward: true) }
            shortcut(.tab, [.shift], tr("Select previous")) { store.selectNeighbour(forward: false) }
            shortcut("h", [.shift], tr("Flip horizontally")) { store.flipSelected(horizontal: true) }
            shortcut("v", [.shift], tr("Flip vertically")) { store.flipSelected(horizontal: false) }
            // T is Add text: the box centred and selected, not opened for
            // typing, onto the next unlocked page from a locked one — the
            // Android twin's rule (EditorKeys).
            shortcut("t", [], tr("Add a text box")) { store.addTextBox() }
        }
    }

    /// Whether there is nothing for Present to show.
    private var everyPageHidden: Bool { store.design.visiblePageIndices.isEmpty }

    /// Present from the keyboard — or, with every page hidden, say why not,
    /// as the menu item does.
    private func present() {
        guard !everyPageHidden else {
            store.announce(PageVisibility.everyPageHidden, undoable: false)
            return
        }
        // The pen is put down, as the menu's Present puts it down.
        store.drawing = nil
        presenting = true
    }

    /// Whether plain Delete can safely mean "delete the selection": something
    /// is selected, and no text field anywhere has the keyboard.
    private var deleteKeysLive: Bool {
        !store.selection.isEmpty && plainKeysLive
    }

    /// Whether the editor answers the system's undo gestures and shake
    /// (UndoHost): no text field anywhere has the keyboard — typing in
    /// place keeps its own undo (TypingUndo) — and nothing is presented.
    private var undoHostLive: Bool {
        store.editingTextId == nil && !titleFocused && activeSheet == nil && !namingComponent
            && !savingTemplate && !namingVersion && !askingCustomGrid && !store.textFieldOpen && !presenting
    }

    /// Whether a key with no modifier can mean anything but typing: no
    /// text field anywhere has the keyboard, and no pen, eraser or brush
    /// is out.
    private var plainKeysLive: Bool {
        store.editingTextId == nil && !titleFocused && activeSheet == nil
            && !namingComponent && !savingTemplate && !namingVersion && !store.textFieldOpen && store.drawing == nil
            && store.erasing == nil && store.brushing == nil
    }

    /// Undo, and — held — a rewind: after a moment it takes back a step
    /// every eighth of a second for as long as the finger stays down, the
    /// Android twin's pace, quickening after thirty, with a thud when there
    /// is nothing left to take back. Each step lands on Redo as a tap's
    /// would. A tap is still one Undo, and letting go of a rewind adds none.
    private var undoButton: some View {
        Button {
            // The release that ends a rewind is not a tap.
            if rewound { rewound = false; return }
            store.undo()
        } label: { Image(systemName: "arrow.uturn.backward") }
            .disabled(!store.canUndo)
            // Alongside the button's own tap: the finger landing starts the
            // wait for a hold, and lifting ends the rewind.
            .simultaneousGesture(
                DragGesture(minimumDistance: 0).updating($undoHeld) { _, held, _ in held = true }
            )
            .onChange(of: undoHeld) { _, held in
                if held {
                    startRewind()
                } else {
                    rewindTask?.cancel()
                    rewindTask = nil
                    // What the rewind came back to, brought into view once,
                    // as it lets go.
                    if rewound { store.revealSelection() }
                    // After the release's own tap has been read and skipped.
                    DispatchQueue.main.async { rewound = false }
                }
            }
            .feel(.error, trigger: rewindExhausted)
            .overlay(alignment: .bottom) { rewindCaption }
            .help(History.undoTitle(store.undoLabel))
            .accessibilityLabel(store.canUndo ? History.undoTitle(store.undoLabel) : tr("Undo, nothing to undo"))
            .accessibilityHint(store.canUndo ? tr("Hold to rewind") : "")
    }

    /// While Undo is held to rewind: the step about to go, in a word, in a
    /// small caption just under the button — the top bar has no room above
    /// it — following the rewind step by step.
    @ViewBuilder
    private var rewindCaption: some View {
        if undoHeld, rewound, let label = store.undoLabel {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.accent))
                .offset(y: 26)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func startRewind() {
        rewound = false
        rewindTask?.cancel()
        rewindTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            rewound = true
            var steps = 0
            while store.canUndo && !Task.isCancelled {
                store.undo(reveal: false)
                steps += 1
                try? await Task.sleep(for: .milliseconds(steps < 30 ? 120 : 60))
            }
            if !Task.isCancelled { rewindExhausted += 1 }
        }
    }

    /// A zero-size button carrying a shortcut. It has a real title, unseen
    /// here, because holding ⌘ on an iPad lists every shortcut by the title
    /// of its button — an empty title made the list a column of blanks.
    private func shortcut(_ key: KeyEquivalent, _ modifiers: EventModifiers, _ title: String,
                          action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            // Never mirrored: the arrows nudge across a design, which is
            // left to right in any language (ReadingDirection).
            .keyboardShortcut(key, modifiers: modifiers, localization: .withoutMirroring)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                closeRename()
                store.endSelectingMultiple()
                // The pen is put down first: the session's strokes go home
                // as one drawing.
                store.drawing = nil
                saveNow()
                onHome()
            } label: {
                Image(systemName: "chevron.backward")
                    .fontWeight(.semibold)
            }
            .accessibilityLabel("Home")

            undoButton
            Button { store.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!store.canRedo)
                .help(History.redoTitle(store.redoLabel))
                .accessibilityLabel(History.redoTitle(store.canRedo ? store.redoLabel : nil))

            Spacer()

            titleField

            Spacer()

            Group {
                overflowMenu
                Button { store.toggleDrawing() } label: {
                    Image(systemName: store.drawing == nil ? "pencil.tip" : "pencil.tip.crop.circle.fill")
                }
                .accessibilityLabel(store.drawing == nil ? tr("Draw") : tr("Stop drawing"))
                .accessibilityAddTraits(store.drawing == nil ? [] : .isSelected)
            }

            Button { shuffleColors() } label: { Image(systemName: "sparkles") }
                .accessibilityLabel("Shuffle colours")
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

    /// The name, and under it the page's own size and where it sits in the
    /// deck — "1080 × 1920 · Page 2 of 5", as the Android twin's top bar
    /// reads — so the size of the thing being made is always in sight.
    private var titleField: some View {
        VStack(spacing: 1) {
            TextField("Untitled design", text: $store.design.title)
                .multilineTextAlignment(.center)
                .font(.subheadline.weight(.semibold))
                .focused($titleFocused)
                // Record the rename atomically when editing ends. Holding the
                // store's single pending slot for the whole session was
                // fragile: any other commit while the keyboard was still up
                // consumed it, so the rename reached neither undo nor autosave.
                .onChange(of: titleFocused) { _, focused in
                    if focused {
                        titleBeforeEdit = store.design.title
                    } else {
                        finishRename()
                    }
                }
                .onSubmit { titleFocused = false }
            Text(EditorCaption.text(width: store.pageWidth, height: store.pageHeight,
                                    unit: store.design.physicalUnit, dpi: store.design.dpi,
                                    page: store.pageIndex, of: store.design.pages.count))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: 180)
    }

    /// A rename ends: trimmed, and recorded as one step — or undone without
    /// a step when nothing is left of it, since a design with no name shows
    /// as a blank card on Home and exports as "design". The Android twin
    /// keeps the old name the same way.
    private func finishRename() {
        guard let renamed = EditorCaption.renamed(store.design.title, was: titleBeforeEdit) else {
            store.design.title = titleBeforeEdit
            return
        }
        store.design.title = titleBeforeEdit    // rewind…
        store.apply {                           // …and apply as one step
            $0.title = renamed
            $0.titleAuto = false                // a person chose this name
        }
        // Finished: the focus change that follows finds nothing more to do.
        titleBeforeEdit = renamed
    }

    /// A rename still being typed, finished before the design is saved and
    /// left: a button tap does not end the title's focus, so without this
    /// Home saved the raw words — an empty name, or one the headline would
    /// later write over.
    private func closeRename() {
        guard titleFocused else { return }
        finishRename()
        titleFocused = false
    }

    /// "Show print bleed": on while the design has a bleed (Bleed).
    private var printBleed: Binding<Bool> {
        Binding(get: { Bleed.shown(store.design) }, set: { store.setBleed($0) })
    }

    /// Show guides, the design's own: one step each way.
    private var guidesShown: Binding<Bool> {
        Binding(get: { store.guidesShown }, set: { store.setGuidesShown($0) })
    }

    private var overflowMenu: some View {
        Menu {
            // Sections rather than a flat list with dividers: a ViewBuilder
            // block takes ten children and this menu is past that, and menu
            // sections draw the same separators for free.
            Section {
                Button {
                    // A crop or typing under way is kept as its own step
                    // first, as on the Android twin.
                    store.finishCrop()
                    store.endTextEdit()
                    store.drawing = nil
                    presenting = true
                } label: {
                    Label("Present", systemImage: "play.rectangle")
                    // Under the item, why it cannot be chosen.
                    if everyPageHidden { Text(PageVisibility.everyPageHidden) }
                }
                .disabled(everyPageHidden)
                .accessibilityHint(everyPageHidden ? PageVisibility.everyPageHidden : "")

                Button {
                    store.finishCrop()
                    store.endTextEdit()
                    store.drawing = nil
                    store.stopPreview()
                    talkRecording = store.design
                } label: { Label("Present and record", systemImage: "record.circle") }
                .disabled(everyPageHidden)
                if !Recordings.of(store.design).isEmpty {
                    Button { talkReviewing = store.design } label: { Label("Recordings", systemImage: "waveform") }
                }

                Button {
                    if ReadAloud.shared.isSpeaking {
                        ReadAloud.shared.stop()
                    } else {
                        ReadAloud.shared.speak(ReadAloud.script(for: store.page, in: store.design),
                                               language: store.design.language)
                    }
                } label: {
                    Label(ReadAloud.shared.isSpeaking ? tr("Stop reading") : tr("Read page aloud"),
                          systemImage: ReadAloud.shared.isSpeaking ? "speaker.slash" : "speaker.wave.2")
                }

                Button {
                    store.toggleMasterPage()
                } label: {
                    Label(store.isOnMasterPage ? tr("Stop using this page as master") : tr("Use this page as master"),
                          systemImage: "rectangle.on.rectangle")
                }
                if store.design.masterPage != nil && !store.isOnMasterPage {
                    Button {
                        store.toggleUsesMaster()
                    } label: {
                        Label(store.page.usesMaster == false ? tr("Show master on this page") : tr("Hide master on this page"),
                              systemImage: "rectangle.on.rectangle.slash")
                    }
                }
            }

            Section {
                Button {
                    activeSheet = .layers
                } label: { Label("Layers", systemImage: "square.3.layers.3d") }

                Button {
                    openBackground()
                } label: { Label("Page background", systemImage: "photo.artframe") }

                Group {
                    Button {
                        activeSheet = .audio
                    } label: { Label("Audio", systemImage: "waveform") }

                    Button {
                        activeSheet = .pageAnimation
                    } label: { Label("Page animations", systemImage: "sparkles.rectangle.stack") }
                }

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
                    activeSheet = .accessibility
                } label: { Label("Check accessibility", systemImage: "accessibility") }

                Button {
                    activeSheet = .brand
                } label: { Label("Brand kit", systemImage: "briefcase") }

                Button {
                    activeSheet = .help
                } label: { Label("Help", systemImage: "questionmark.circle") }

                // Grouped, as a ViewBuilder block takes ten children.
                Group {
                    Button {
                        // Whatever is on screen now is the newest version, so
                        // the list never starts with a state you cannot get back
                        // to.
                        DesignLibrary.snapshot(store.design)
                        activeSheet = .history
                    } label: { Label("Version history", systemImage: "clock.arrow.circlepath") }

                    Button {
                        namingVersion = true
                    } label: { Label("Save a named version…", systemImage: "pin") }
                }
            }

            Section {
                Button {
                    activeSheet = .copyResize
                } label: { Label("Copy & resize…", systemImage: "rectangle.on.rectangle.angled") }

                Button {
                    makeCopy()
                } label: { Label("Make a copy", systemImage: "plus.square.on.square") }

                Button {
                    activeSheet = .bulk
                } label: { Label("Bulk create…", systemImage: "tablecells.badge.ellipsis") }

                Button {
                    // Typing under way is kept first, so the template has it.
                    store.finishCrop()
                    store.endTextEdit()
                    savingTemplate = true
                } label: { Label("Save as template…", systemImage: "rectangle.stack.badge.plus") }
            }

            Section {
                Button {
                    componentName = ""
                    namingComponent = true
                } label: { Label("Save selection as component…", systemImage: "square.grid.3x1.folder.badge.plus") }
                    .disabled(store.selection.isEmpty)
                snappingMenu
                // The design's own setting, so one step; the rulers are
                // this phone's.
                Toggle(isOn: printBleed) { Label("Show print bleed", systemImage: "rectangle.dashed") }
                Toggle(isOn: $rulers) { Label("Rulers", systemImage: "ruler") }
                Toggle(isOn: guidesShown) { Label("Guides", systemImage: "squareshape.split.3x3") }
                Toggle(isOn: $haptics) { Label("Vibration", systemImage: "iphone.radiowaves.left.and.right") }
                Toggle(isOn: $quickActions) { Label("Quick actions at the selection", systemImage: "capsule") }
                Toggle(isOn: $pageScroll) { Label("Scroll through pages", systemImage: "rectangle.stack") }
                Button {
                    activeSheet = .settings
                } label: { Label("Settings", systemImage: "gearshape") }
            }

            // The timeline is this phone's; Split page cuts the page on
            // screen at its playhead.
            Section {
                Toggle(isOn: $timeline) { Label("Timeline", systemImage: "timeline.selection") }
                Button {
                    store.splitPage()
                } label: { Label("Split page", systemImage: "scissors") }
                    .disabled(!store.canSplitPage)
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
                    startSelectingMultiple()
                } label: { Label("Select multiple", systemImage: "checklist") }

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

                // Another app's words as they read, as the Android twin's menu.
                if UIPasteboard.general.hasStrings {
                    Button {
                        store.paste(at: nil, plain: true)
                    } label: { Label("Paste as plain text", systemImage: "doc.plaintext") }
                }

                // The selection carried to another page, where it sat.
                Menu {
                    ForEach(store.moveTargets) { target in
                        Button(target.name) { store.moveSelectedToPage(target.index) }
                    }
                } label: { Label("Move to page…", systemImage: "rectangle.portrait.and.arrow.right") }
                    .disabled(store.selection.isEmpty || store.design.pages.count < 2)
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
                // Something a tap a level deeper took inside a group: out
                // of it, the rest of the group kept.
                if store.canRemoveFromGroup {
                    Button {
                        store.removeSelectedFromGroup()
                    } label: { Label("Remove from group", systemImage: "rectangle.portrait.and.arrow.right") }
                }
                // A frame's or a grid cell's picture, taken out as a photo
                // of its own, the frame left empty.
                if store.canDetachImage {
                    Button {
                        store.detachImage()
                    } label: { Label("Detach image", systemImage: "photo.on.rectangle") }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More actions")
    }

    /// Whether the Delete being asked about takes more than one thing.
    private var deletesSeveral: Bool {
        store.selectedElements.filter { !$0.locked }.count > 1
    }

    /// Select multiple on, said to VoiceOver as TalkBack says it on the
    /// Android twin.
    private func startSelectingMultiple() {
        store.startSelectingMultiple()
        AccessibilityNotification.Announcement(DesignStore.selectMultipleOn).post()
    }

    /// Select multiple's banner, over the toolbar while the mode is on: what
    /// a tap does now, how many are selected, Select all, and Done, which
    /// ends the mode and keeps the selection — the Android twin's words.
    private var selectMultipleBanner: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Select multiple — tap to add or remove")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(trn("%d selected|%d selected", store.selection.count))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            Button("Select all") { store.selectAll() }
            Button("Done") { store.endSelectingMultiple() }
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: Touch.minTarget)
        .background(Theme.chrome)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Select multiple")
    }

    /// The pen's colour and width, floating over the canvas while drawing.
    /// Undo takes back the last stroke; the pencil in the top bar (or Done)
    /// puts the pen away.
    private func drawingBar(_ tool: Freehand.Tool) -> some View {
        VStack(spacing: 6) {
            // How the pen in hand is used, over the bar rather than in it:
            // the capsule has no room left on a phone held upright. Beside
            // it, for a pen with ink, the Shape assist switch.
            HStack(spacing: 8) {
                Text(tool.pen.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if tool.pen.hasInk {
                    Toggle("Shape assist", isOn: $shapeAssist)
                        .toggleStyle(.button)
                        .font(.caption)
                        .accessibilityHint("Rest your finger at the end of a stroke to make it a clean shape")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            penSliders(tool)
            drawingControls(tool)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// The pen's size, from 1 to 60 and settling on the old six widths,
    /// and how see-through it draws; the eraser's size, and whether it
    /// takes the part of a stroke it passes over or the whole stroke.
    private func penSliders(_ tool: Freehand.Tool) -> some View {
        HStack(spacing: 14) {
            penSlider(tr("Size"), value: tool.width, in: Freehand.widthRange, readout: "\(Int(tool.width))") { v in
                let width = Freehand.snappedWidth(v)
                if store.drawing?.width != width { store.drawing?.width = width }
            }
            // A marker's ink is opaque, so it has no transparency to set.
            if tool.pen == .marker {
                EmptyView()
            } else if tool.pen.hasInk {
                penSlider(tr("Transparency"), value: tool.transparency, in: 0...Freehand.maxTransparency,
                          readout: "\(Int(tool.transparency))%") { v in
                    store.drawing?.transparency = Freehand.keptTransparency(v)
                }
            } else {
                Picker("Eraser", selection: Binding(get: { tool.eraseWhole }, set: { store.drawing?.eraseWhole = $0 })) {
                    Text("Part").tag(false)
                    Text("Whole stroke").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }

    /// A slider of the pen's, its name and value under it.
    private func penSlider(_ label: String, value: Double, in range: ClosedRange<Double>, readout: String,
                           set: @escaping (Double) -> Void) -> some View {
        VStack(spacing: 0) {
            Slider(value: Binding(get: { value }, set: set), in: range)
                .frame(width: 110)
                .accessibilityLabel(label)
                .accessibilityValue(readout)
            Text(verbatim: "\(label) \(readout)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private func drawingControls(_ tool: Freehand.Tool) -> some View {
        HStack(spacing: 10) {
            // What the pen lays down — ink, a highlighter, a glow — or the
            // eraser, which takes strokes away.
            Menu {
                ForEach(Freehand.Pen.allCases) { kind in
                    Button {
                        store.drawing?.pen = kind
                    } label: {
                        Label(kind.label, systemImage: tool.pen == kind ? "checkmark" : kind.symbol)
                    }
                }
            } label: {
                Image(systemName: tool.pen.symbol)
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("Pen, \(tool.pen.label)")
            // Only the colours scroll. With the pen menu the bar came to some
            // 446 pt, wider than any phone held upright, so Done was cut to
            // an ellipsis and the ends ran off a 375 pt screen; now the pen,
            // width, undo and Done stay put and the swatches take what room
            // is left — all of them, where there is room for all.
            // The eraser has no ink, so no inks are offered with it.
            if tool.pen.hasInk {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Freehand.colors, id: \.self) { hex in
                            swatch(hex, selected: tool.color == hex)
                        }
                        inkOfYourOwn(tool)
                    }
                    // Room for the selected swatch's ring, which the scroll
                    // view would otherwise clip.
                    .padding(4)
                }
                .frame(maxWidth: Self.swatchRowWidth)
            }
            Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 30, height: 30) }
                .disabled(!store.canUndo)
                .accessibilityLabel("Undo stroke")
            Button("Done") { store.drawing = nil }
                .fontWeight(.semibold)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }

    /// Every pen colour side by side, with room for the ring round the one
    /// chosen: as wide as the colours' scroll view ever needs to be.
    private static let swatchRowWidth: CGFloat = {
        // The eight inks and the one of your own.
        let count = CGFloat(Freehand.colors.count + 1)
        return count * 22 + max(count - 1, 0) * 10 + 8
    }()

    /// After the eight inks, any colour at all — the document's, the brand
    /// kit's, one typed or picked from the page — through the colour sheet.
    /// It shows the pen's ink when that is none of the eight.
    private func inkOfYourOwn(_ tool: Freehand.Tool) -> some View {
        let own = !Freehand.colors.contains(tool.color)
        return Button {
            choosingInk = true
        } label: {
            Circle()
                .fill(own ? AnyShapeStyle(Color(hex: tool.color))
                      : AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red],
                                                      center: .center)))
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(Theme.hairline))
                .overlay {
                    Image(systemName: "plus")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(own && UIColor(hex: tool.color).isLight ? Color.black : Color.white)
                }
                .overlay { if own { Circle().stroke(Theme.accent, lineWidth: 2).padding(-3) } }
        }
        .accessibilityLabel(own ? tr("%@ ink, choose another colour", ElementNames.spokenColour(tool.color))
                            : tr("More ink colours"))
        .accessibilityAddTraits(own ? .isSelected : [])
        .sheet(isPresented: $choosingInk) {
            ColorPickerSheet(store: store, title: tr("Ink colour"), current: store.drawing?.color,
                             onPick: { hex in store.drawing?.color = hex })
        }
    }

    private func swatch(_ hex: String, selected: Bool) -> some View {
        Button {
            store.drawing?.color = hex
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(Theme.hairline))
                .overlay {
                    if selected {
                        Circle().stroke(Theme.accent, lineWidth: 2).padding(-3)
                    }
                }
        }
        .accessibilityLabel("\(ElementNames.spokenColour(hex)) ink")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Crop mode's bar, in place of the insert button: how far in the
    /// picture is, the frame's shape, a straighten dial, a quarter turn and
    /// a flip, and the ways out — all inside the one open crop step, so
    /// Done keeps them as one Undo and Cancel puts every one of them back.
    /// Reset centres the picture and lets it just cover the frame again,
    /// and More opens the sheet for fit and the Ken Burns drift. The zoom
    /// slider does what a pinch does, for anyone who cannot pinch, and
    /// carries four moves for VoiceOver.
    private var cropBar: some View {
        let photo = store.cropElement
        return VStack(spacing: 6) {
            cropZoomRow(photo)
            cropAspectRow(photo)
            cropStraightenRow(photo)
            cropWaysOut(photo)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func cropZoomRow(_ photo: Element?) -> some View {
        let zoom = max(1, photo?.cropScale ?? 1)
        let percent = "\(Int((zoom * 100).rounded()))%"
        // A trim can leave a picture further in than a zoom may take it; the
        // slider's end moves out to meet it rather than snapping it back —
        // but not mid-drag, when a moving range would pull the thumb about.
        let ceiling = cropSliding ? cropCeiling : max(Crop.maxZoom, zoom)
        return HStack(spacing: 10) {
            Text("Zoom").font(.subheadline.weight(.semibold))
            Slider(value: Binding(get: { zoom }, set: { store.setCropZoom($0) }),
                   in: 1...ceiling,
                   onEditingChanged: { editing in
                       if editing { cropCeiling = max(Crop.maxZoom, zoom) }
                       cropSliding = editing
                   })
            .accessibilityLabel("Zoom the picture")
            .accessibilityValue(percent)
            .accessibilityAction(named: "Move the picture left") { store.nudgeCrop(dx: -1, dy: 0) }
            .accessibilityAction(named: "Move the picture right") { store.nudgeCrop(dx: 1, dy: 0) }
            .accessibilityAction(named: "Move the picture up") { store.nudgeCrop(dx: 0, dy: -1) }
            .accessibilityAction(named: "Move the picture down") { store.nudgeCrop(dx: 0, dy: 1) }
            Text(percent)
                .font(.subheadline.monospacedDigit())
                .frame(minWidth: 48, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    /// The frame's shape: Free, the picture's own, the orientation chip,
    /// the usual ratios (CropAspect) and Custom…, the one the frame has lit
    /// (CropRatioChips). Each trims the frame inside itself
    /// (Crop.trimmedToRatio); a frame locked in position keeps its shape, so
    /// its chips wait.
    private func cropAspectRow(_ photo: Element?) -> some View {
        CropRatioChips(match: store.cropMatch, portrait: (photo.map { $0.h > $0.w }) ?? false,
                       onAspect: { aspect, turned in store.setCropAspect(aspect, turned: turned) },
                       onTurn: { store.turnCropAspect() },
                       onCustom: { ratio in store.setCropRatio(ratio) })
            .disabled(photo?.holdsPlace ?? true)
    }

    /// The straighten dial: −45 to 45 degrees in half steps, a tick at
    /// level, writing the photo's straighten live. To VoiceOver one
    /// adjustable control, a degree a swipe.
    private func cropStraightenRow(_ photo: Element?) -> some View {
        let degrees = photo?.straighten ?? 0
        let readout = Crop.straightenReadout(photo?.straighten)
        return HStack(spacing: 10) {
            Text("Straighten").font(.subheadline.weight(.semibold))
            Slider(value: Binding(get: { degrees }, set: { store.setCropStraighten($0) }),
                   in: -Crop.straightenReach...Crop.straightenReach, step: Crop.straightenStep,
                   onEditingChanged: { store.cropDialHeld = $0 })
            .overlay(alignment: .top) {
                // The tick at level.
                Rectangle().fill(.secondary).frame(width: 1, height: 6)
            }
            Text(readout)
                .font(.subheadline.monospacedDigit())
                .frame(minWidth: 64, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Straighten")
        .accessibilityValue(readout)
        .accessibilityAdjustableAction { direction in
            store.setCropStraighten(degrees + (direction == .increment ? 1 : -1))
        }
    }

    /// Cancel, Reset, a quarter turn, a flip, More and Done.
    private func cropWaysOut(_ photo: Element?) -> some View {
        HStack(spacing: 12) {
            Button("Cancel") { store.cancelCrop() }
            Spacer(minLength: 0)
            Button("Reset") { store.resetCrop() }
                .disabled(!(photo.map(Crop.isAdjusted) ?? false))
            Spacer(minLength: 0)
            Button { store.rotateCrop90() } label: { Image(systemName: "rotate.right").frame(width: 30, height: 30) }
                .accessibilityLabel("Rotate 90")
                .disabled(photo?.holdsPlace ?? true)
            Button { store.flipCrop() } label: { Image(systemName: "flip.horizontal").frame(width: 30, height: 30) }
                .accessibilityLabel("Flip")
                .accessibilityAddTraits(photo?.flipH == true ? .isSelected : [])
            Button {
                store.finishCrop()
                activeSheet = .crop
            } label: { Image(systemName: "slider.horizontal.3").frame(width: 30, height: 30) }
                .accessibilityLabel("Fit and drift")
            Button("Done") { store.finishCrop() }
                .fontWeight(.semibold)
                .buttonStyle(.borderedProminent)
        }
    }

    /// A graphic's crop bar: the ratios, and Cancel, Reset and Done — no
    /// zoom or straighten, which a vector has nothing to give.
    private var graphicCropBar: some View {
        VStack(spacing: 6) {
            graphicAspectRow
            HStack(spacing: 12) {
                Button("Cancel") { store.cancelGraphicCrop() }
                Spacer(minLength: 0)
                Button("Reset") { store.resetGraphicCrop() }
                    .disabled(!graphicCropped)
                Spacer(minLength: 0)
                Button("Done") { store.finishGraphicCrop() }
                    .fontWeight(.semibold)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Whether the graphic being cropped shows less than its whole.
    private var graphicCropped: Bool {
        store.graphicCropping?.ids.first.flatMap(store.element)?.clipBox != nil
    }

    /// The window's shape, as a photo's frame has them — the orientation
    /// chip and Custom… too; Original is the graphic's own.
    private var graphicAspectRow: some View {
        let window = store.graphicCropWindow
        return CropRatioChips(match: store.graphicCropMatch,
                              portrait: window.map { $0.height > $0.width } ?? false,
                              onAspect: { aspect, turned in store.setGraphicCropAspect(aspect, turned: turned) },
                              onTurn: { store.turnGraphicCropAspect() },
                              onCustom: { ratio in store.setGraphicCropRatio(ratio) })
    }

    /// Brush size, the strokes so far, and the two ways out.
    private var eraserBar: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach([20.0, 40, 70, 110], id: \.self) { w in
                    Button {
                        store.eraserWidth = w
                    } label: { Label("\(Int(w)) px", systemImage: store.eraserWidth == w ? "checkmark" : "circle") }
                }
            } label: {
                Label("Brush", systemImage: "circle.dashed")
            }
            Button {
                if !store.eraserStrokes.isEmpty { store.eraserStrokes.removeLast() }
            } label: { Image(systemName: "arrow.uturn.backward").frame(width: 30, height: 30) }
                .disabled(store.eraserStrokes.isEmpty || store.eraserBusy)
                .accessibilityLabel("Undo stroke")
            // Not while it works: the result would land after a Cancel.
            Button("Cancel") { store.cancelErasing() }
                .disabled(store.eraserBusy)
            Button {
                store.applyEraser()
            } label: {
                if store.eraserBusy {
                    ProgressView()
                        .accessibilityLabel("Erasing")
                } else {
                    Text("Erase").fontWeight(.semibold)
                }
            }
            .disabled(store.eraserStrokes.isEmpty || store.eraserBusy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var insertButton: some View {
        Button {
            activeSheet = .insert
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
        }
        .buttonStyle(AccentButtonStyle())
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .accessibilityLabel("Add element")
        // Its glyph grows to accessibility2 in its fixed disc; its name is
        // in the large content viewer a long press brings up.
        .chromeTypeSize()
        .toolLargeContent("plus", tr("Add element"))
    }

    // MARK: sheets

    @ViewBuilder
    private func sheetView(_ sheet: EditorSheet) -> some View {
        switch sheet {
        case .insert:
            InsertSheet(store: store)
        case .colorFill:
            // An SVG's line or outline part takes a colour as its ink.
            ColorPickerSheet(store: store, title: tr("Fill colour"),
                             current: store.singleSelection.flatMap(Freehand.fillColour),
                             allowGradients: true,
                             allowPatterns: true,
                             currentPaint: store.singleSelection?.fill,
                             onPick: { c in store.updateSelected { $0 = Freehand.coloured($0, c) } },
                             onPickGradient: { p in store.updateSelected { $0.fill = p } },
                             onPickTransient: { c in store.updateSelectedTransient { $0 = Freehand.coloured($0, c) } },
                             swapsColours: true)
        case .colorText:
            // A gradient on text is a fill, not a colour, so it lives in its
            // own field; picking a plain colour clears it.
            // Colours, gradients and photo fills (a photo in the letters,
            // PhotoFills): text draws no pattern. Several texts ring what
            // they share, and nothing when they differ.
            ColorPickerSheet(store: store, title: tr("Text colour"),
                             current: store.sharedText { $0.color ?? "#1f2430" },
                             allowGradients: true,
                             allowPatterns: false,
                             allowPhotos: true,
                             currentPaint: store.sharedText { $0.textFill } ?? nil,
                             onPick: { c in store.updateSelected { $0.color = c; $0.textFill = nil } },
                             onPickGradient: { p in store.updateSelected { $0.textFill = p } },
                             onPickTransient: { c in
                                 store.updateSelectedTransient { $0.color = c; $0.textFill = nil }
                             },
                             swapsColours: true)
        case .colorLine:
            ColorPickerSheet(store: store, title: tr("Line colour"),
                             current: store.singleSelection?.color,
                             onPick: { c in store.updateSelected { $0.color = c } },
                             onPickTransient: { c in store.updateSelectedTransient { $0.color = c } },
                             swapsColours: true)
        case .colorStroke:
            ColorPickerSheet(store: store,
                             title: store.singleSelection.map(Freehand.isStroke) == true ? tr("Ink colour") : tr("Border colour"),
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
                             },
                             swapsColours: true)
        case .colorWords:
            // The words chosen while typing, from the bar's colour well:
            // the text colour sheet's title, as Android has no heading of
            // its own for them, and the note both phones show.
            ColorPickerSheet(store: store, title: tr("Text colour"),
                             current: store.wordColour,
                             note: DesignStore.wordColourNote,
                             onPick: { c in store.colourWords(c) },
                             onPickTransient: { c in store.colourWordsTransient(c) })
        case .colorSelection:
            // Several things at once: each takes the colour its own way.
            ColorPickerSheet(store: store, title: tr("Colour"),
                             current: nil,
                             allowGradients: store.selectionTakesGradient,
                             allowPatterns: FillChoices.offersPatterns(for: store.selectedElements),
                             onPick: { c in store.recolourSelection(c) },
                             onPickGradient: { p in store.recolourSelection(gradient: p) },
                             onPickTransient: { c in store.recolourSelectionTransient(c) },
                             swapsColours: true)
        case .background:
            BackgroundSheet(store: store)
        case .fonts:
            FontSheet(store: store)
        case .fontWords:
            FontSheet(store: store, words: true)
        case .highlightWords:
            HighlightSheet(store: store)
        case .photoInLetters:
            PhotoInLettersSheet(store: store)
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
            LayersSheet(store: store) { activeSheet = .position }
        case .export:
            ExportSheet(store: store)
        case .resize:
            ResizeSheet(store: store) { made in showCopies(made) }
        case .copyResize:
            ResizeSheet(store: store, copying: true) { made in showCopies(made) }
        case .bulk:
            BulkCreateSheet(store: store) { made in showMade(made) }
        case .find:
            FindReplaceSheet(store: store)
        case .frame:
            FrameSheet(store: store)
        case .shapes:
            ShapeSwapSheet(store: store)
        case .similar:
            SimilarSheet(store: store)
        case .shadow:
            ShadowSheet(store: store)
        case .clip:
            ClipSheet(store: store)
        case .shapeText:
            ShapeTextSheet(store: store)
        case .table:
            TableSheet(store: store)
        case .chart:
            if let spec = store.selectedChart {
                DataSheet(store: store, editing: spec)
            }
        case .history:
            VersionHistorySheet(store: store)
        case .proofread:
            ProofreadSheet(store: store)
        case .theme:
            ThemeSheet(store: store)
        case .accessibility:
            AccessibilitySheet(store: store)
        case .brand:
            BrandKitSheet(store: store, onGuidelines: { openGuidelines($0) })
        case .settings:
            SettingsSheet(store: store)
        case .audio:
            AudioSheet(store: store)
        case .pageAnimation:
            PageAnimationSheet(store: store)
        case .pages:
            PageOrganizerSheet(store: store)
        case .snapping:
            SnappingSheet(store: store)
        case .addGuides:
            NavigationStack {
                AddGuidesView(store: store)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { activeSheet = nil }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
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
                if let id = toastUnlocks {
                    Button("Unlock") {
                        dismissToast()
                        store.unlockPage(id)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                } else if toastUnlocksGuides {
                    Button("Unlock") {
                        dismissToast()
                        store.setGuidesLocked(false)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                } else if !toastOpens.isEmpty {
                    Button("Open") {
                        let ids = toastOpens
                        dismissToast()
                        openCopies(ids)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                } else if toastUndoes {
                    Button("Undo") {
                        // Only while what it names is still the newest step:
                        // after anything else, Undo would take back that.
                        if store.historyVersion == toastVersion && !store.hasPendingChanges { store.undo() }
                        dismissToast()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                }
                // A way to close it: with VoiceOver on it stays until it is
                // closed, as Home's Recently deleted toast does.
                Button {
                    dismissToast()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            // Clear of the pages bar and the context toolbar, both of which
            // live at the bottom of the stack.
            .padding(.bottom, store.selection.isEmpty ? 96 : 150)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            // Children kept apart, so Undo and Dismiss are each reachable;
            // the words are read out as the toast arrives.
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: saving

    /// Up for as long as the design on screen is not safely on disk, and
    /// gone with the first save that goes through — the next edit's, or
    /// Try again's. Where tips go, under the top bar, so it never covers
    /// the page; a tip that arrives meanwhile shows under it.
    private var saveFailedBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(Self.saveFailedMessage)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Try again") { saveDocument() }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.14))
        .overlay(alignment: .bottom) { Divider() }
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .contain)
    }

    /// Shows or clears the banner as the last save went. Said as it
    /// arrives, as a tip is, since a failed save changes nothing on screen;
    /// only when it changes, so a banner already up is not read out again
    /// at every failed save.
    @MainActor
    private func noteSave(succeeded: Bool) {
        guard succeeded == saveFailed else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
            saveFailed = !succeeded
        }
        if !succeeded { AccessibilityNotification.Announcement(Self.saveFailedMessage).post() }
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

    /// Read out as it arrives, as the Android twin's tip is a live region,
    /// and held longer while VoiceOver runs.
    private func show(tip next: Tip) {
        tipTask?.cancel()
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) { tip = next }
        AccessibilityNotification.Announcement(next.text).post()
        let seconds = ToastTiming.tip(voiceOver: UIAccessibility.isVoiceOverRunning)
        tipTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            dismissTip()
        }
    }

    private func dismissTip() {
        tipTask?.cancel()
        tipTask = nil
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { tip = nil }
    }

    /// Keeps the selection in the part of the canvas a medium sheet leaves
    /// showing, by the least pan — never while a finger is on the canvas,
    /// never while typing (which keeps its own box above the keyboard), and
    /// not at all when it is already in sight. The Android twin's
    /// keepSelectionVisible.
    private func revealSelection() {
        guard !store.canvasTouchActive, store.editingTextId == nil, let box = store.selectionBox else { return }
        store.requestCanvas(.reveal(box, covered: 0.5))
    }

    /// Read out as it arrives — "Deleted page 3" means nothing to someone
    /// who cannot see it appear — and kept up until closed while VoiceOver
    /// or Switch Control runs, so its Undo can be reached.
    private func show(toast text: String, undoable: Bool) {
        toastTask?.cancel()
        toastOpens = []
        toastUnlocks = nil
        toastUnlocksGuides = false
        toastUndoes = undoable
        toastVersion = store.historyVersion
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) { toast = text }
        AccessibilityNotification.Announcement(undoable ? tr("%@. Undo available.", text) : text).post()
        // Held open only when there is an Undo to reach; a toast with none
        // goes in the usual time.
        let assisted = UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
        guard let seconds = ToastTiming.undoToast(voiceOver: undoable && assisted) else {
            toastTask = nil
            return
        }
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            dismissToast()
        }
    }

    private func dismissToast() {
        toastTask?.cancel()
        toastTask = nil
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { toast = nil }
    }

    // MARK: copies

    /// The designs Bulk create made, said, with Open.
    private func showMade(_ made: [Design]) {
        guard !made.isEmpty else { return }
        show(toast: trn("Made %d design on Home|Made %d designs on Home", made.count), undoable: false)
        toastOpens = made.map(\.id)
    }

    /// "Made 3 resized copies", with Open: straight into the copy when there
    /// is one, else to Home with them highlighted. Nothing here changed, so
    /// there is nothing to undo.
    private func showCopies(_ made: [Design]) {
        guard !made.isEmpty else { return }
        show(toast: CopyResize.doneText(count: made.count), undoable: false)
        toastOpens = made.map(\.id)
    }

    @MainActor
    private func openCopies(_ ids: [String]) {
        closeRename()
        saveNow()
        if ids.count == 1, let id = ids.first {
            openDesign(id)
        } else {
            HomeHighlight.ids = ids
            onHome()
        }
    }

    /// More's Make a copy: this design saved, then copied whole under
    /// "<title> copy" with fresh ids, and the copy opened in its place.
    @MainActor
    private func makeCopy() {
        closeRename()
        store.finishCrop()
        store.endTextEdit()
        saveNow()
        let copy = CopyResize.madeCopy(of: store.design, taken: DesignLibrary.recents().map(\.title))
        guard DesignLibrary.save(copy) else {
            show(toast: tr("Couldn't make a copy"), undoable: false)
            return
        }
        DesignLibrary.writeThumbnail(for: copy)
        openDesign(copy.id)
    }

    /// Make brand guidelines from the kit sheet: this design saved, the
    /// guidelines saved as a new design, and opened in its place.
    @MainActor
    private func openGuidelines(_ design: Design) {
        closeRename()
        saveNow()
        var named = design
        named.title = Titles.unique(design.title, taken: DesignLibrary.recents().map(\.title))
        guard DesignLibrary.save(named) else {
            show(toast: tr("Couldn't do that"), undoable: false)
            return
        }
        DesignLibrary.writeThumbnail(for: named)
        openDesign(named.id)
    }

    /// Another design opened over this one — saved already — through the
    /// app's launch request, as a quick action opens one.
    private func openDesign(_ id: String) {
        LaunchRequest.set(.open(id: id))
        NotificationCenter.default.post(name: QuickActions.requested, object: nil)
    }

    /// Snapping switches and the grid, in a submenu so the overflow stays a
    /// list of verbs. Toggles rather than a sheet: each is one tap and you
    /// are back on the canvas, which is where you want to be when you are
    /// deciding whether the snapping is helping.
    private var snappingMenu: some View {
        Menu {
            Toggle("Snap to elements", isOn: $store.snapping.toElements)
            Toggle("Snap to page", isOn: $store.snapping.toPage)
            SnappingSheet.gridPicker(store: store, askingCustom: $askingCustomGrid)
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
            // A section, so the guides sit apart from the switches as the
            // divider set them apart.
            Section {
                Button { store.addGuide(vertical: true) } label: { Label("Add vertical guide", systemImage: "line.vertical") }
                Button { store.addGuide(vertical: false) } label: { Label("Add horizontal guide", systemImage: "line.horizontal") }
                Button { activeSheet = .addGuides } label: { Label("Add guides…", systemImage: "rectangle.split.3x1") }
                Button(role: .destructive) { store.clearGuides() } label: { Label("Remove all guides", systemImage: "trash") }
                    .disabled(store.design.guides.isEmpty)
            }
        } label: {
            Label("Snapping", systemImage: "square.grid.3x3")
        }
    }

    // MARK: actions

    private func shuffleColors() {
        // A locked page says so, with Unlock, before a palette is used up —
        // as on the Android twin; nothing is announced over it.
        guard !store.refusesLockedPage() else { return }
        let palettes = ContentLibrary.palettes
        guard !palettes.isEmpty else { return }
        let palette = palettes[paletteIndex % palettes.count]
        paletteIndex += 1
        // Faint colours keep their place, as a theme leaves them.
        let colors = ColorTools.documentColors(store.design, limit: 24).filter { !ContrastAudit.isFaint($0) }
        guard !colors.isEmpty else { return }
        store.applyToPage { page in
            ColorTools.shuffle(page: &page, docColors: colors, palette: palette.colors)
        }
        // Which palette it was, said and felt, as on the Android twin.
        store.buzz(.confirm)
        store.announce(tr("Colours: %@", palette.name))
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
        // Said, not swallowed: out of space, every save failed in silence
        // and the design came back hours old at the next launch. The
        // banner stays until one goes through; the next edit tries again.
        noteSave(succeeded: DesignLibrary.save(store.design))
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
        DesignLibrary.writeThumbnail(for: store.design)
    }
}

private extension View {
    /// Delete with something locked in position selected asks first, in
    /// the Android twin's words; Delete there goes ahead. Shown from the
    /// editor, or from the sheet over it while one is up.
    func asksBeforeLockedDelete(_ isPresented: Binding<Bool>, several: Bool, store: DesignStore) -> some View {
        alert(several ? tr("Delete these?") : tr("Delete this?"), isPresented: isPresented) {
            Button("Delete", role: .destructive) { store.deleteSelected(confirmed: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(several ? tr("Some of them have their position locked.") : tr("Its position is locked."))
        }
    }
}

/// The typing bar's requests for the words chosen: its colour well opens the
/// colour sheet, Aa the font sheet, and Link asks for a link (WordLinkPrompt).
private struct WordRequests: ViewModifier {
    @Bindable var store: DesignStore
    @Binding var activeSheet: EditorSheet?

    func body(content: Content) -> some View {
        content
            .onChange(of: store.wordColourTarget) { _, target in
                if target != nil { activeSheet = .colorWords }
            }
            .onChange(of: store.wordFontTarget) { _, target in
                if target != nil { activeSheet = .fontWords }
            }
            .onChange(of: store.wordHighlightTarget) { _, target in
                if target != nil { activeSheet = .highlightWords }
            }
            .onChange(of: store.chartEditRequested) { _, asked in
                guard asked else { return }
                store.chartEditRequested = false
                if store.selectedChart != nil { activeSheet = .chart }
            }
            .modifier(WordLinkPrompt(store: store))
            .modifier(PhotoInLettersPrompts(store: store, openAdjust: { activeSheet = .photoInLetters }))
            .modifier(AltTextPrompt(store: store))
    }
}

/// The hold menu's Animate asks for Page animations.
private struct PageAnimationRequest: ViewModifier {
    @Bindable var store: DesignStore
    @Binding var activeSheet: EditorSheet?

    func body(content: Content) -> some View {
        content
            .onChange(of: store.asksPageAnimation) { _, asked in
                guard asked else { return }
                store.asksPageAnimation = false
                activeSheet = .pageAnimation
            }
    }
}
