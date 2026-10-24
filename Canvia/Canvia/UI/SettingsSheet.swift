// Settings: Appearance, Language, Editing, Export, Help, Storage, Backup
// and About — the same sections, in the same words, as the Android twin's.
// Opened from Home's gear and the editor's More menu.
//
// Language opens Canvia's page in the Settings app, where iOS keeps an
// app's own language; the row shows the one it speaks now, in its own
// words (AppLanguage).

import SwiftUI
import UniformTypeIdentifiers

/// System, Light or Dark, kept under @AppStorage "appearance" and applied
/// with preferredColorScheme to every window.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let key = "appearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return tr("System")
        case .light: return tr("Light")
        case .dark: return tr("Dark")
        }
    }

    /// Nil follows the phone.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// The scheme a stored value asks for; one this build does not know
    /// follows the phone.
    static func scheme(_ raw: String) -> ColorScheme? {
        (Appearance(rawValue: raw) ?? .system).colorScheme
    }
}

/// What Settings sets for new work.
enum AppDefaults {
    /// The picture format Export starts on — its Photos row's, and the
    /// first of its format rows — unless it remembers the last export:
    /// "png" or "jpg", as the Android twin's export sheet starts on one.
    static let exportFormatKey = "canvia.defaultExportFormat"
    static let exportFormats = ["png", "jpg"]

    /// "PNG", "JPG", as the Android twin says them.
    static func formatLabel(_ format: String) -> String {
        format.uppercased()
    }

    /// Export's format rows with the default picture format first, the
    /// rest in their own order; any other changes nothing.
    static func formatOrder(_ first: String) -> [String] {
        let rows = ["png", "jpg", "pdf", "svg"]
        guard exportFormats.contains(first) else { return rows }
        return [first] + rows.filter { $0 != first }
    }

    /// The unit Custom size opens in: "px", "in", "mm" or "cm".
    static let unitKey = "canvia.defaultUnit"

    static func unit(_ defaults: UserDefaults = .standard) -> String {
        let stored = defaults.string(forKey: unitKey) ?? "px"
        return Units.all.contains(stored) ? stored : "px"
    }
}

/// A backup file for the system's Save sheet, read from where it was
/// written.
struct BackupDocument: FileDocument {
    static let contentType = UTType(filenameExtension: Backup.ext, conformingTo: .zip) ?? .zip
    static var readableContentTypes: [UTType] { [contentType] }

    let url: URL

    init(url: URL) { self.url = url }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url, options: [])
    }
}

struct SettingsSheet: View {
    /// The design open, when Settings is opened from the editor: its
    /// snapping changes with the defaults.
    var store: DesignStore?
    /// Asked for from Help: the welcome tour, once Settings has gone.
    var onTour: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(Appearance.key) private var appearance = Appearance.system.rawValue
    @AppStorage(Haptics.key) private var haptics = true
    @AppStorage(SelectionBubble.key) private var quickActions = true
    /// Typing into small words zooms them up to be read (Viewport.typingZoom).
    @AppStorage(Viewport.typingZoomKey) private var typingZoom = true
    /// A typed "- " or "1. " starts a list (TextLists.autoStart).
    @AppStorage(TextLists.autoListsKey) private var autoLists = true
    @AppStorage(AppDefaults.exportFormatKey) private var exportFormat = "png"
    @AppStorage(AppDefaults.unitKey) private var unit = "px"
    /// What Canvia is used for, as the first launch asked; "" for none.
    @AppStorage(UseProfile.key) private var use = ""
    @State private var snapping = SnapSettings.load()
    @State private var storage: StorageReport?
    @State private var clearingCaches = false
    @State private var emptyingTrash = false
    @State private var trashCount = 0
    @State private var tipsReset = false
    /// Fraction done while a backup or restore runs; nil when idle.
    @State private var progress: Double?
    @State private var workingLabel = tr("Backing up")
    @State private var task: Task<Void, Never>?
    @State private var backup: BackupDocument?
    @State private var restoring = false
    @State private var outcome: String?
    /// The brand kit sheet, over Settings.
    @State private var showingBrandKit = false

    var body: some View {
        withDialogs(form)
            .overlay { if let progress { progressCard(progress) } }
            .interactiveDismissDisabled(progress != nil)
            .onDisappear { task?.cancel() }
            .task { await measure() }
    }

    private var form: some View {
        NavigationStack {
            Form {
                appearanceSection
                languageSection
                brandSection
                editingSection
                exportSection
                helpSection
                storageSection
                backupSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.large])
        // The design open, from the editor; none from Home.
        .sheet(isPresented: $showingBrandKit) {
            if let store { BrandKitSheet(store: store) } else { StandaloneBrandKitSheet() }
        }
    }

    // MARK: sections

    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Appearance")
        } footer: {
            Text("System follows your phone's light and dark setting.")
        }
    }

    private var languageSection: some View {
        Section {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                LabeledContent("Language") {
                    Text(verbatim: AppLanguage.name(AppLanguage.current()))
                }
            }
            .foregroundStyle(.primary)
        } footer: {
            Text("Canvia uses your phone's language. To choose another for Canvia alone, open its page in the Settings app.")
        }
    }

    /// The brand kits, whether or not a design is open.
    private var brandSection: some View {
        Section {
            Button {
                showingBrandKit = true
            } label: {
                Label("Brand kit", systemImage: "paintpalette")
            }
        }
    }

    private var editingSection: some View {
        Section("Editing") {
            Toggle("Haptics", isOn: $haptics)
            Toggle("Snap to elements", isOn: $snapping.toElements)
            Toggle("Snap to page", isOn: $snapping.toPage)
            Toggle("Quick actions at the selection", isOn: $quickActions)
            Toggle("Zoom in to type small text", isOn: $typingZoom)
            Toggle("Start lists as you type", isOn: $autoLists)
            Picker("Custom sizes start in", selection: $unit) {
                ForEach(Units.all, id: \.self) { Text($0).tag($0) }
            }
        }
        // The open design snaps as the defaults now say, and keeps them.
        .onChange(of: snapping) { _, next in
            next.save()
            store?.snapping = next
        }
        .onAppear { if let store { snapping = store.snapping } }
    }

    private var exportSection: some View {
        Section {
            Picker("Default export format", selection: $exportFormat) {
                ForEach(AppDefaults.exportFormats, id: \.self) { Text(AppDefaults.formatLabel($0)).tag($0) }
            }
        } header: {
            Text("Export")
        } footer: {
            Text("What the export sheet starts on, unless it remembers your last export.")
        }
    }

    private var helpSection: some View {
        Section("Help") {
            Button(tipsReset ? tr("Tips will show again") : tr("Show tips again")) {
                TipEngine.shared.reset()
                tipsReset = true
            }
            .disabled(tipsReset)
            Button("Show the welcome tour again") {
                Onboarding.reset(.standard)
                if let onTour {
                    onTour()
                } else {
                    dismiss()
                }
            }
            whatYouMake
        }
    }

    /// "What you make": the use chosen, or none, which puts Home back as
    /// it always was.
    private var whatYouMake: some View {
        Picker("What you make", selection: Binding(
            get: { UseProfile.byId(use)?.id ?? "" },
            set: { UseProfile.set($0.isEmpty ? nil : $0) })) {
            Text("Not chosen").tag("")
            ForEach(UseProfile.all) { choice in
                Text(choice.label).tag(choice.id)
            }
        }
    }

    private var storageSection: some View {
        Section {
            storageRow(tr("Designs"), storage?.designs)
            storageRow(tr("Photos & clips"), storage?.photosAndClips)
            storageRow(tr("Your uploads"), storage?.uploads)
            storageRow(tr("Fonts"), storage?.fonts)
            storageRow(tr("Templates"), storage?.templates)
            storageRow(tr("Versions"), storage?.versions)
            storageRow(tr("Recently deleted"), storage?.recentlyDeleted)
            storageRow(tr("Caches"), storage?.caches)
            // Neither while a backup or restore runs: a backup is written
            // among the caches, and a restore fills Recently deleted.
            Button("Clear caches") { clearingCaches = true }
                .disabled(progress != nil)
            Button("Empty Recently deleted", role: .destructive) {
                trashCount = DesignLibrary.trashed().count
                emptyingTrash = true
            }
            .disabled(storage?.recentlyDeleted == 0 || progress != nil)
        } header: {
            Text("Storage")
        } footer: {
            Text("Your uploads are among the photos & clips. Caches are exports already made; they are made again when needed.")
        }
    }

    private func storageRow(_ title: String, _ bytes: Int64?) -> some View {
        LabeledContent(title, value: bytes.map(StorageReport.text) ?? "…")
    }

    private var backupSection: some View {
        Section {
            Button("Back up everything") { startBackup() }
            Button("Restore from backup") { restoring = true }
        } header: {
            Text("Backup")
        } footer: {
            Text("One file with every design, Recently deleted, your uploads, fonts, brand kits and templates, to keep or move to another phone — iPhone or Android. Restoring adds what is missing and never replaces a design with an older copy.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Self.version)
            NavigationLink("Licences") { LicencesView() }
        }
    }

    /// "1.4 (27)", from the app's own bundle.
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    // MARK: work

    private func measure() async {
        storage = await Task.detached(priority: .userInitiated) { StorageReport.measure() }.value
    }

    private func startBackup() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(Backup.fileName(Date()))
        workingLabel = tr("Backing up")
        progress = 0
        task = Task { @MainActor in
            defer { progress = nil }
            do {
                _ = try await Backup.write(to: url) { progress = $0 }
                backup = BackupDocument(url: url)
            } catch is CancellationError {
                // Given up on: nothing to say.
            } catch {
                outcome = Backup.backupFailure(error)
            }
        }
    }

    private func startRestore(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        workingLabel = tr("Restoring")
        progress = 0
        task = Task { @MainActor in
            defer { progress = nil }
            do {
                // The design open in the editor is left as it is: it
                // would be saved over the one restored.
                let report = try await Backup.restore(from: url, open: store?.design.id) { progress = $0 }
                outcome = Backup.summary(report)
                await measure()
            } catch is CancellationError {
                await measure()
            } catch {
                outcome = Backup.restoreFailure(error)
            }
        }
    }

    /// As Export shows its progress: the fraction, and a way out.
    private func progressCard(_ fraction: Double) -> some View {
        VStack(spacing: 14) {
            ProgressView(value: fraction) {
                Text("\(workingLabel)… \(Int((fraction * 100).rounded()))%")
                    .font(.subheadline.weight(.semibold))
            }
            .progressViewStyle(.linear)
            Button("Cancel", role: .cancel) { task?.cancel() }
                .buttonStyle(.bordered)
        }
        .padding(20)
        .frame(width: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
        .accessibilityElement(children: .combine)
    }

    // MARK: dialogs

    /// The save and open panels and the questions, apart from the body so
    /// the type checker takes each chain in reasonable time.
    private func withDialogs<V: View>(_ content: V) -> some View {
        content
            .fileExporter(isPresented: Binding(get: { backup != nil }, set: { if !$0 { backup = nil } }),
                          document: backup, contentType: BackupDocument.contentType,
                          defaultFilename: backup?.url.lastPathComponent) { result in
                if case .failure(let error) = result { outcome = error.localizedDescription }
                if let url = backup?.url { try? FileManager.default.removeItem(at: url) }
                backup = nil
            }
            .fileImporter(isPresented: $restoring,
                          allowedContentTypes: [BackupDocument.contentType, .zip, .data]) { result in
                startRestore(result)
            }
            .modifier(SettingsQuestions(clearingCaches: $clearingCaches, emptyingTrash: $emptyingTrash,
                                        trashCount: trashCount, outcome: $outcome) {
                Task { await measure() }
            })
    }
}

/// Settings' confirmations and the outcome of a backup or restore.
private struct SettingsQuestions: ViewModifier {
    @Binding var clearingCaches: Bool
    @Binding var emptyingTrash: Bool
    var trashCount: Int
    @Binding var outcome: String?
    /// Called once something was cleared.
    var onCleared: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Clear caches?", isPresented: $clearingCaches, titleVisibility: .visible) {
                Button("Clear caches", role: .destructive) {
                    StorageReport.clearCaches()
                    onCleared()
                }
            } message: {
                Text("Exports already made are deleted. Your designs, uploads and fonts stay.")
            }
            .confirmationDialog(DesignLibrary.emptyTrashQuestion(count: trashCount), isPresented: $emptyingTrash,
                                titleVisibility: .visible) {
                Button("Empty Recently deleted", role: .destructive) {
                    DesignLibrary.emptyTrash()
                    onCleared()
                }
            } message: {
                Text(DesignLibrary.cannotBeUndone)
            }
            .alert("Backup", isPresented: Binding(get: { outcome != nil }, set: { if !$0 { outcome = nil } })) {
                Button("OK") { outcome = nil }
            } message: {
                Text(outcome ?? "")
            }
    }
}

/// The licences of what Canvia is made with: the fonts, under the SIL Open
/// Font License, and Material Icons, under the Apache License 2.0 — each
/// licence file bundled with the app, to read in full.
private struct LicencesView: View {
    private var files: [URL] {
        (Bundle.main.urls(forResourcesWithExtension: "txt", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasSuffix("-LICENSE.txt") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    var body: some View {
        List {
            Section {
                Text(licencesNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(files, id: \.self) { url in
                    NavigationLink(url.deletingPathExtension().lastPathComponent
                        .replacingOccurrences(of: "-LICENSE", with: "")) {
                        ScrollView {
                            Text((try? String(contentsOf: url, encoding: .utf8)) ?? "")
                                .font(.footnote.monospaced())
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .navigationTitle("Licences")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var licencesNote: String {
        trn("The %d bundled font family is under the SIL Open Font License 1.1. Material Icons are under the Apache License 2.0."
            + "|The %d bundled font families are under the SIL Open Font License 1.1. Material Icons are under the Apache License 2.0.",
            FontLibrary.all.filter { $0.licence != nil }.count)
    }
}
