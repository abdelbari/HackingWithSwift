// Home's quick file tools, one sheet: the tools to choose from, then the
// chosen one's files — picked from Files, or pictures from Photos — its
// options, about how big the result is, and Share, whose sheet saves to
// Files or Photos too, or Open as a design. Share runs on the export queue
// under the export pill (QuickToolRunner); Open as a design makes the files
// here and lands them as files shared in are — the only way anything here
// becomes a design. As the Android twin's QuickToolsSheet.

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Home's Tools row: each quick file tool by name, opening its sheet.
struct QuickToolsRow: View {
    var onTool: (QuickTools.Tool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tools")
                .font(.title3.weight(.bold))
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(QuickTools.Tool.allCases) { tool in chip(tool) }
                }
                .padding(.horizontal)
            }
        }
    }

    private func chip(_ tool: QuickTools.Tool) -> some View {
        Button { onTool(tool) } label: {
            Label(tool.title, systemImage: tool.systemImage)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().stroke(Theme.hairline))
                .foregroundStyle(Theme.ink)
        }
        .buttonStyle(.plain)
    }
}

struct QuickToolsSheet: View {
    /// The tool it opens on; nil for the list of them.
    var initial: QuickTools.Tool?
    /// What a tool made, to land as files shared in, as a new design.
    var onOpen: ([URL]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tool: QuickTools.Tool?
    @State private var picked: [QuickToolRunner.Picked] = []
    @State private var choices = QuickToolRunner.Choices()
    @State private var reading = false
    @State private var problem: String?
    @State private var choosingFiles = false
    @State private var photoItems: [PhotosPickerItem] = []

    init(initial: QuickTools.Tool?, onOpen: @escaping ([URL]) -> Void) {
        self.initial = initial
        self.onOpen = onOpen
        _tool = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(tool?.title ?? tr("Tools"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .presentationDetents([.large])
        .fileImporter(isPresented: $choosingFiles, allowedContentTypes: allowedTypes,
                      allowsMultipleSelection: gathers || tool == .compress) { result in
            if case .success(let urls) = result { take(urls) }
        }
        .onChange(of: photoItems) { _, items in takePhotos(items) }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if tool != nil && initial == nil {
                Button("Back") {
                    tool = nil
                    picked = []
                }
            }
        }
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
    }

    @ViewBuilder
    private var content: some View {
        if let tool {
            Form {
                filesSection(tool)
                if !picked.isEmpty {
                    QuickToolOptions(tool: tool, picked: picked, choices: $choices)
                    resultSection(tool)
                }
            }
        } else {
            toolList
        }
    }

    private var toolList: some View {
        List {
            Section {
                ForEach(QuickTools.Tool.allCases) { each in
                    Button {
                        tool = each
                        choices = QuickToolRunner.Choices()
                    } label: {
                        Label(each.title, systemImage: each.systemImage)
                    }
                }
            } footer: {
                Text("Work on files without making a design.")
            }
        }
    }

    // MARK: files

    /// Merge and Photos to PDF gather what is picked; the rest work on
    /// what was just picked.
    private var gathers: Bool { tool == .merge || tool == .photosToPdf }

    private var allowedTypes: [UTType] {
        switch tool {
        case .merge, .split, .pdfToPictures: return [.pdf]
        case .compress: return [.pdf, .image]
        default: return [.image]
        }
    }

    /// A tool of pictures takes them from Photos too.
    private var takesPhotos: Bool {
        guard let tool else { return false }
        return ![.merge, .split, .pdfToPictures].contains(tool)
    }

    private func filesSection(_ tool: QuickTools.Tool) -> some View {
        Section {
            ForEach(picked) { file in fileRow(file) }
            Button(chooseLabel) { choosingFiles = true }
                .disabled(reading)
            if takesPhotos {
                PhotosPicker(selection: $photoItems, maxSelectionCount: gathers ? nil : 1, matching: .images) {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }
                .disabled(reading)
            }
            if reading { ProgressView() }
            if let problem {
                Text(problem).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private var chooseLabel: String {
        if picked.isEmpty { return tr("Choose files") }
        return gathers ? tr("Add more") : tr("Choose another")
    }

    private func fileRow(_ file: QuickToolRunner.Picked) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).lineLimit(1)
                Text(file.isPdf ? trn("%d page|%d pages", file.pages) : tr("%d × %d px", file.width, file.height))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                picked.removeAll { $0.id == file.id }
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("Remove %@", file.name))
        }
    }

    /// Files from Files, read away from the main thread.
    private func take(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        reading = true
        Task { @MainActor in
            let read = await Task.detached(priority: .userInitiated) { QuickToolRunner.pick(urls) }.value
            took(read, of: urls.count)
        }
    }

    /// Pictures from Photos, written out as files first.
    private func takePhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photoItems = []
        reading = true
        Task { @MainActor in
            var urls: [URL] = []
            for (n, item) in items.enumerated() {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(tr("Photo")) \(n + 1).\(ext)")
                if (try? data.write(to: url, options: .atomic)) != nil { urls.append(url) }
            }
            let read = await Task.detached(priority: .userInitiated) { QuickToolRunner.pick(urls) }.value
            took(read, of: items.count)
        }
    }

    private func took(_ read: [QuickToolRunner.Picked], of asked: Int) {
        reading = false
        picked = gathers ? picked + read : read
        problem = read.count < asked
            ? trn("%d file couldn't be read.|%d files couldn't be read.", asked - read.count) : nil
    }

    // MARK: what it makes

    @ViewBuilder
    private func resultSection(_ tool: QuickTools.Tool) -> some View {
        let plan = QuickTools.plan(tool, picked.map(\.input), choices.options)
        if plan.outputs.isEmpty {
            Section { Text("Choose at least one page.") }
        } else {
            Section {
                Text(plan.zip ?? (plan.outputs.count == 1 ? plan.outputs[0].name : trn("%d file|%d files", plan.outputs.count)))
                    .lineLimit(2)
                Text(ExportChoices.sizeText(QuickToolRunner.estimate(tool, picked, choices)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    QuickToolRunner.run(tool, picked, choices)
                    dismiss()
                } label: {
                    Label(choices.toPhotos && tool == .pdfToPictures ? tr("To Photos") : tr("Share"),
                          systemImage: "square.and.arrow.up")
                }
                Button("Open as a design") { openAsDesign(tool) }
            }
        }
    }

    /// The files made here, then landed as a new design; a ZIP is no
    /// design — its pictures are.
    private func openAsDesign(_ tool: QuickTools.Tool) {
        var asked = choices
        asked.options.zip = false
        let files = picked
        Task { @MainActor in
            let made = (try? await QuickToolRunner.make(tool, files, asked)) ?? []
            let usable = made.filter { $0.pathExtension.lowercased() != "zip" }
            guard !usable.isEmpty else {
                problem = tr("Couldn't make the file")
                return
            }
            onOpen(usable)
        }
    }
}

/// The chosen tool's options.
private struct QuickToolOptions: View {
    var tool: QuickTools.Tool
    var picked: [QuickToolRunner.Picked]
    @Binding var choices: QuickToolRunner.Choices

    var body: some View {
        switch tool {
        case .merge:
            Section { Text("In the order shown.").font(.footnote).foregroundStyle(.secondary) }
        case .split:
            pagesSection
            Section { Toggle("Each page as its own PDF", isOn: $choices.options.each) }
        case .pdfToPictures:
            pagesSection
            Section {
                formatPicker
                Picker("Save", selection: picturesWhere) {
                    Text("Separate files").tag(0)
                    Text("One ZIP").tag(1)
                    Text("To Photos").tag(2)
                }
                .pickerStyle(.segmented)
            }
        case .photosToPdf:
            PhotosToPdfOptions(choices: $choices)
        case .resize:
            QuickResizeOptions(resize: $choices.resize)
        case .convert:
            Section("Convert to") { formatPicker }
        case .compress:
            compressSection
        }
    }

    /// PNG or JPG.
    private var formatPicker: some View {
        Picker("Convert to", selection: Binding(get: { choices.options.format == "jpg" ? "jpg" : "png" },
                                                set: { choices.options.format = $0 })) {
            Text(verbatim: "PNG").tag("png")
            Text(verbatim: "JPG").tag("jpg")
        }
        .pickerStyle(.segmented)
    }

    /// Separate files, one ZIP, or into Photos.
    private var picturesWhere: Binding<Int> {
        Binding(get: { choices.toPhotos ? 2 : (choices.options.zip ? 1 : 0) }, set: { where_ in
            choices.options.zip = where_ == 1
            choices.toPhotos = where_ == 2
        })
    }

    /// The one PDF's pages, each a chip to leave in or out.
    private var pagesSection: some View {
        let total = picked.first?.pages ?? 0
        let chosen = choices.options.pages ?? Array(0..<total)
        return Section("Pages") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
                ForEach(0..<total, id: \.self) { p in
                    Button {
                        let next = chosen.contains(p) ? chosen.filter { $0 != p } : (chosen + [p]).sorted()
                        choices.options.pages = next
                    } label: {
                        Text(verbatim: "\(p + 1)")
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(chosen.contains(p) ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(chosen.contains(p) ? Color.white : Theme.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chosen.contains(p) ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder
    private var compressSection: some View {
        if picked.contains(where: { !$0.isPdf }) {
            Section {
                Picker("Compress", selection: Binding(get: { choices.colours256 }, set: { on in
                    choices.colours256 = on
                    choices.options.format = on ? "png" : "jpg"
                })) {
                    Text("JPEG quality").tag(false)
                    Text("256 colours (PNG)").tag(true)
                }
                .pickerStyle(.segmented)
                if !choices.colours256 {
                    Text(verbatim: "\(tr("Quality")) \(Int((choices.quality * 100).rounded()))%")
                    Slider(value: $choices.quality, in: 0.3...0.95)
                }
            }
        } else {
            Section {
                Text("Photos in the PDF are brought down to 150 dpi.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// Photos to PDF: the paper, and the margins.
private struct PhotosToPdfOptions: View {
    @Binding var choices: QuickToolRunner.Choices

    var body: some View {
        Section {
            Picker("Paper", selection: $choices.paper) {
                ForEach(QuickTools.PhotoPaper.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Margins", selection: $choices.margin) {
                Text("None").tag(QuickTools.margins[0])
                Text("Small").tag(QuickTools.margins[1])
                Text("Large").tag(QuickTools.margins[2])
            }
            .pickerStyle(.segmented)
        }
    }
}

/// Resize: by the longer edge, by a percentage, or to a design type's size,
/// its shape kept or filled and cut.
private struct QuickResizeOptions: View {
    @Binding var resize: QuickTools.Resize

    /// The design types sized in pixels, which a picture can be resized to.
    private static var presets: [SizePreset] { Array(SizePreset.all.filter { $0.unit == nil }.prefix(12)) }

    private var mode: Int { resize.percent != nil ? 1 : (resize.size != nil ? 2 : 0) }

    var body: some View {
        Section {
            Picker("Resize a picture", selection: Binding(get: { mode }, set: { pick($0) })) {
                Text("Long edge").tag(0)
                Text("Percent").tag(1)
                Text("Design size").tag(2)
            }
            .pickerStyle(.segmented)
            switch mode {
            case 0: longEdges
            case 1: percent
            default: designSizes
            }
        }
    }

    private func pick(_ mode: Int) {
        switch mode {
        case 0: resize = QuickTools.Resize(longEdge: 1080)
        case 1: resize = QuickTools.Resize(percent: 50)
        default: resize = QuickTools.Resize(size: Self.presets.first.map(Self.size) ?? QuickTools.Size(width: 1080, height: 1080))
        }
    }

    private static func size(_ preset: SizePreset) -> QuickTools.Size {
        QuickTools.Size(width: Int(preset.w.rounded()), height: Int(preset.h.rounded()))
    }

    private var longEdges: some View {
        Picker("Long edge", selection: Binding(get: { resize.longEdge ?? 1080 },
                                               set: { resize = QuickTools.Resize(longEdge: $0) })) {
            ForEach([512, 1080, 1920, 2048, 4096], id: \.self) { edge in Text(verbatim: "\(edge) px").tag(edge) }
        }
    }

    private var percent: some View {
        VStack(alignment: .leading) {
            Text(verbatim: "\(Int((resize.percent ?? 50).rounded()))%")
            Slider(value: Binding(get: { resize.percent ?? 50 },
                                  set: { resize = QuickTools.Resize(percent: $0.rounded()) }), in: 10...200)
        }
    }

    @ViewBuilder
    private var designSizes: some View {
        Picker("Design size", selection: Binding(get: { resize.size ?? QuickTools.Size(width: 1080, height: 1080) },
                                                 set: { resize.size = $0 })) {
            ForEach(Self.presets) { preset in Text(preset.name).tag(Self.size(preset)) }
        }
        Picker("Fill and crop", selection: $resize.cover) {
            Text("Keep shape").tag(false)
            Text("Fill and crop").tag(true)
        }
        .pickerStyle(.segmented)
    }
}
