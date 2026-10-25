// Choosing a size and choosing something to start from, as one gesture.
//
// The size just named is the filter: an Instagram post opens on a blank
// Instagram post and every template made at exactly that size, never the
// whole library. The blank start is the first cell and never scrolls away;
// topic is a chip row inside the size, and only when the size has enough to
// need one; after them, templates of other sizes near its shape, "Adapted
// from other sizes" (Templates.nearby). Two depths — pick a size, then pick
// a start — swapped in place. Import leads the sizes, and "Start with my
// brand" gives what is made the brand kit's look as its first step. The
// Android twin's StartSheet.

import SwiftUI

struct StartSheet: View {
    /// The size the sheet opened on; nil when it opened on the sizes.
    let initialPresetId: String?
    var onCreate: (Design) -> Void
    var onCustomSize: () -> Void
    /// Import's rows, above the sizes; nil offers none.
    var onImport: ((ImportChoice) -> Void)?
    /// The Tools group's rows, under Import: a quick file tool, which makes
    /// no design; nil offers none.
    var onTool: ((QuickTools.Tool) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var presetId: String?
    @State private var category: String?
    /// "Start with my brand", for what is made here.
    @State private var withBrand = false
    /// The kit in use, read as the sheet opens.
    @State private var kit = BrandKit.load()

    init(initialPresetId: String?, onCreate: @escaping (Design) -> Void, onCustomSize: @escaping () -> Void,
         onImport: ((ImportChoice) -> Void)? = nil, onTool: ((QuickTools.Tool) -> Void)? = nil) {
        self.initialPresetId = initialPresetId
        self.onCreate = onCreate
        self.onCustomSize = onCustomSize
        self.onImport = onImport
        self.onTool = onTool
        _presetId = State(initialValue: initialPresetId)
    }

    private var preset: SizePreset? {
        guard let presetId else { return nil }
        return SizePreset.byId(presetId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let preset {
                    StartGrid(preset: preset, category: $category, withBrand: $withBrand,
                              brandOffered: kit.canStartWith, onCreate: create)
                } else {
                    sizePicker
                }
            }
            .background(Theme.workspace)
            .navigationTitle(preset?.name ?? tr("What are you making?"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { header }
                ToolbarItem(placement: .topBarLeading) {
                    // Only when the sizes were where this began: a way back
                    // to them rather than closing and starting again.
                    if preset != nil && initialPresetId == nil {
                        Button {
                            presetId = nil
                            category = nil
                        } label: {
                            Image(systemName: "chevron.backward")
                        }
                        .accessibilityLabel("Back to sizes")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.large])
    }

    private var header: some View {
        VStack(spacing: 1) {
            Text(preset?.name ?? tr("What are you making?"))
                .font(.headline)
                .lineLimit(1)
            if let preset {
                // In its own unit: "210 × 297 mm".
                Text(preset.unit == nil ? "\(preset.dimensions) px" : preset.dimensions)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// What is made here, with the brand kit asked for: the editor gives
    /// it the kit's look as it opens (BrandStart).
    private func create(_ design: Design) {
        BrandStart.designId = withBrand && kit.canStartWith ? design.id : nil
        onCreate(design)
    }

    /// Import first, then the sizes, Custom size last.
    private var sizePicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let onImport { importGroup(onImport) }
            if let onTool { toolsGroup(onTool) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 12)], alignment: .leading, spacing: 16) {
                ForEach(SizePreset.hero) { preset in
                    SizeTile(preset: preset) { presetId = preset.id }
                }
                CustomSizeTile(action: onCustomSize)
            }
        }
        .padding(20)
    }

    /// The quick file tools: PDFs and pictures worked on, no design made.
    private func toolsGroup(_ action: @escaping (QuickTools.Tool) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tools")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(QuickTools.Tool.allCases) { tool in
                    Button { action(tool) } label: {
                        Label(tool.title, systemImage: tool.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    /// A photo or clip, a PDF, a deck or a design file, each a design.
    private func importGroup(_ action: @escaping (ImportChoice) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ImportChoice.groupTitle)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(ImportChoice.allCases) { choice in
                    Button { action(choice) } label: {
                        Label(choice.title, systemImage: choice.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

/// A size, drawn at the shape it makes with a real design at that size
/// faded behind it, and how many ready-made starts it has.
struct SizeTile: View {
    let preset: SizePreset
    var action: () -> Void

    var body: some View {
        // The output's own shape, 104 tall, within reason either way.
        let ratio = min(max(preset.w / preset.h, 64.0 / 104), 184.0 / 104)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.card)
                    if let preview = ContentLibrary.sizedTemplates(for: preset).first {
                        TemplateThumb(template: preview, badge: false).opacity(0.4)
                    }
                }
                .aspectRatio(ratio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
                // One height for every tile, so the names below line up
                // across a row whatever shape each size is.
                .frame(maxWidth: .infinity, minHeight: 104, maxHeight: 104, alignment: .leading)
                Text(preset.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.top, 4)
                Text(Templates.countText(for: preset))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("%@, %@", preset.name, Templates.spokenCount(for: preset)))
    }
}

/// Any size at all, at the end of the sizes.
struct CustomSizeTile: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.card)
                    .overlay(Image(systemName: "slider.horizontal.3").font(.title2).foregroundStyle(.secondary))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.inkSecondary.opacity(0.5)))
                    .frame(height: 104)
                Text("Custom size")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.top, 4)
                Text("Any dimensions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Custom size")
    }
}

/// The blank start first, then your own templates at exactly this size,
/// then every template of the library's at it.
private struct StartGrid: View {
    let preset: SizePreset
    @Binding var category: String?
    @Binding var withBrand: Bool
    /// Whether the kit in use has a look to give: a palette of two colours
    /// or more, or a face for a text role.
    let brandOffered: Bool
    var onCreate: (Design) -> Void
    @State private var mine: [UserTemplate] = []
    /// A template, while its preview is up.
    @State private var previewing: Template?
    /// One of your own of several pages, while its strip asks which.
    @State private var ownSet: TemplateChoice?
    /// Templates of other sizes near this one's shape, made at it.
    @State private var adapted: [Templates.Adapted] = []
    /// The Doc templates, each laid out as its pages, at the Doc type.
    @State private var docStarts: [DocStart] = []
    /// The Filters sheet's choices, as Home's: kept for the session.
    @State private var filter = TemplateFilter.session
    @State private var filtersOpen = false
    @AppStorage(RecentSearches.templatesKey) private var recentTemplatesText = ""

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let bucket = ContentLibrary.sizedTemplates(for: preset)
        // Each layout once, its colourways in its preview (Templates.grouped).
        let shown = Templates.grouped(bucket.filter {
            (category == nil || $0.category == category) && filter.admits(template: $0)
        })
        VStack(alignment: .leading, spacing: 16) {
            if brandOffered {
                Toggle("Start with my brand", isOn: $withBrand)
                    .font(.subheadline.weight(.semibold))
                    .tint(Theme.accent)
            }
            // A chip row only earns its space when the size has enough that
            // narrowing it helps.
            if ContentLibrary.showsTopics(bucket) || bucket.contains(where: { $0.shownFacets.animated }) {
                topicChips(bucket)
            }
            filterRow(empty: shown.isEmpty)
            // The templates of this size used lately lead, as Home's do.
            if filter.isEmpty && category == nil { recentRow(bucket) }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                BlankCard(preset: preset) {
                    // Named for what it is, as the Android twin names it;
                    // Home makes the name one the shelf does not have yet.
                    onCreate(preset.makeDesign())
                }
                // A Doc's templates: each a new Doc as it is used.
                ForEach(docStarts) { start in
                    DocStartCard(start: start) { onCreate(Docs.fromTemplate(start.template)) }
                }
                if category == nil {
                    ForEach(mine) { entry in
                        StartUserTemplateCard(entry: entry) { use(entry) }
                    }
                }
                ForEach(shown) { template in
                    StartTemplateCard(template: template, showColourways: true) { previewing = template }
                }
            }
            .sheet(item: $ownSet) { own in
                TemplateSetSheet(name: own.name, design: own.design, note: TemplateSetSheet.startNote,
                                 applyAll: { onCreate(sized(UserTemplates.newDesign(from: own.design))) },
                                 usePage: { onCreate(sized(UserTemplates.newDesign(from: own.design, onlyPage: $0))) })
            }
            if category == nil && !adaptedShown.isEmpty { adaptedPart }
        }
        .onChange(of: filter) { _, chosen in TemplateFilter.session = chosen }
        .sheet(isPresented: $filtersOpen) { TemplateFiltersSheet(filter: $filter) }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .onAppear { mine = UserTemplates.sized(UserTemplates.all(), width: preset.w, height: preset.h) }
        // Reflowed off the main thread, as the Android twin does it: every
        // text box of every borrowed template is measured as it re-wraps.
        .task(id: preset.id) {
            let size = preset
            // A Doc starts from Doc templates, never a page reflowed.
            guard size.id != Docs.presetId else {
                let made = await Task.detached(priority: .userInitiated) { DocStart.all() }.value
                if !Task.isCancelled { docStarts = made }
                return
            }
            let made = await Task.detached(priority: .userInitiated) { Templates.nearby(size) }.value
            if !Task.isCancelled { adapted = made }
        }
        // A template's own page first; Customize makes the design — every
        // page, or the one shown — at this size.
        .sheet(item: $previewing) { template in
            TemplatePreviewSheet(template: template, note: TemplateSetSheet.startNote) { chosen, page in
                onCreate(page.map { chosen.instantiate(for: preset, onlyPage: $0) } ?? chosen.instantiate(for: preset))
            }
        }
    }

    /// "Recently used": the templates of this size used lately, when any.
    @ViewBuilder
    private func recentRow(_ bucket: [Template]) -> some View {
        let ids = Set(bucket.map(\.id))
        let ordered = RecentSearches.decode(recentTemplatesText, limit: RecentSearches.templateLimit, searches: false)
        let recent = RecentSearches.templates(ordered).filter { ids.contains($0.id) }
        if !recent.isEmpty {
            RecentTemplatesRow(templates: recent, inset: 0) { previewing = $0 }
        }
    }

    /// "Adapted from other sizes": each made at this size already, so its
    /// card is what a tap starts — a fresh copy of it.
    private var adaptedPart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Adapted from other sizes")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(adaptedShown) { item in
                    AdaptedCard(item: item) { onCreate(CopyResize.freshCopy(of: item.design)) }
                }
            }
        }
        .padding(.top, 8)
    }

    /// Those of other sizes the filter lets through.
    private var adaptedShown: [Templates.Adapted] {
        adapted.filter { filter.admits(template: $0.template) }
    }

    /// The Filters button, what is set, and, when nothing is left, the way
    /// out of it.
    private func filterRow(empty: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TemplateFiltersButton(filter: filter) { filtersOpen = true }
            TemplateFilterChips(filter: $filter)
            if !filter.isEmpty && empty {
                NoTemplatesMatch { filter = TemplateFilter() }
            }
        }
    }

    /// A new design from a fresh copy of the template, in the size's unit:
    /// one of several pages shows its strip first — all of them, or the
    /// page picked alone — as the Android twin's Start sheet asks.
    private func use(_ entry: UserTemplate) {
        guard let template = UserTemplates.load(id: entry.id) else { return }
        if template.pages.count > 1 {
            ownSet = TemplateChoice(id: entry.id, name: entry.name, design: template)
        } else {
            onCreate(sized(UserTemplates.newDesign(from: template)))
        }
    }

    /// `design` in the size's unit.
    private func sized(_ design: Design) -> Design {
        var design = design
        design.unit = preset.unit
        design.dpi = preset.dpi
        return preset.started(design)
    }

    private func topicChips(_ bucket: [Template]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // The Animated topic: the Filters sheet's Animated, a tap away.
                if bucket.contains(where: { $0.shownFacets.animated }) {
                    chip(tr("Animated"), selected: filter.animated == true) {
                        filter.animated = filter.animated == true ? nil : true
                    }
                }
                if ContentLibrary.showsTopics(bucket) {
                    chip(tr("All %d", bucket.count), selected: category == nil) { category = nil }
                    ForEach(ContentLibrary.topics(in: bucket), id: \.self) { name in
                        chip(name, selected: category == name) {
                            category = category == name ? nil : name
                        }
                    }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? Theme.accent : Theme.card, in: Capsule())
                .foregroundStyle(selected ? Color.white : Theme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// "Start with nothing", the same shape as every template beside it, and
/// the one thing on the sheet in the accent colour.
private struct BlankCard: View {
    let preset: SizePreset
    var action: () -> Void

    var body: some View {
        let ratio = min(max(preset.w / preset.h, 0.45), 2.2)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.accentSubtle)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.accent, lineWidth: 2))
                    .overlay(Image(systemName: "plus").font(.title2.weight(.semibold)).foregroundStyle(Theme.accent))
                    .aspectRatio(ratio, contentMode: .fit)
                Text("Blank \(preset.name.lowercased())")
                    .font(.subheadline)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Blank \(preset.name)")
    }
}

private struct StartTemplateCard: View {
    let template: Template
    /// Where each layout shows once, a base says how many colourways it
    /// comes in (Templates.grouped).
    var showColourways = false
    var action: () -> Void

    var body: some View {
        let ratio = min(max(template.width / template.height, 0.45), 2.2)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                TemplateThumb(template: template)
                    .aspectRatio(ratio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
                Text(template.name)
                    .font(.subheadline)
                    .lineLimit(1)
                if showColourways, let colourways = Templates.colourwaysBadge(template) {
                    Text(colourways)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(template.name), \(UserTemplates.shownCategory(template.category)) template")
    }
}

/// A Doc template, shown as its first page laid out.
private struct DocStart: Identifiable {
    let template: DocTemplate
    let shown: Design
    var id: String { template.id }

    /// Every Doc template laid out (templates/docs.json), each block
    /// measured — off the main thread.
    static func all() -> [DocStart] {
        Docs.templates.map { DocStart(template: $0, shown: DocPages.drawn(Docs.fromTemplate($0))) }
    }
}

private struct DocStartCard: View {
    let start: DocStart
    var action: () -> Void

    var body: some View {
        let ratio = start.shown.width / max(start.shown.height, 1)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                PageThumbnail(design: start.shown, page: start.shown.pages[0], pixelWidth: 320)
                    .aspectRatio(ratio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
                Text(tr(start.template.name))
                    .font(.subheadline)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

/// A template of another size, drawn as it is made at this one.
private struct AdaptedCard: View {
    let item: Templates.Adapted
    var action: () -> Void

    var body: some View {
        let ratio = min(max(item.design.width / max(item.design.height, 1), 0.45), 2.2)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                PageThumbnail(design: item.design, page: item.design.pages[0], pixelWidth: 320)
                    .aspectRatio(ratio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
                    .overlay(alignment: .bottomTrailing) { PageCountBadge(count: item.design.pages.count) }
                Text(item.template.name)
                    .font(.subheadline)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("%@, %@", item.template.name, tr("Adapted from other sizes")))
    }
}

/// One of your own templates among a size's starts.
private struct StartUserTemplateCard: View {
    let entry: UserTemplate
    var action: () -> Void

    var body: some View {
        let ratio = min(max(entry.width / max(entry.height, 1), 0.45), 2.2)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                UserTemplateThumb(entry: entry)
                    .aspectRatio(ratio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
                Text(entry.name)
                    .font(.subheadline)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.name), your template")
    }
}

/// A page at whatever size is needed: each side says its range under it
/// and says so again when it is out of it, four ratio shortcuts, and the
/// last few sizes made. Nothing is clamped behind anyone's back — Create
/// waits until both sides are in range.
struct CustomSizeSheet: View {
    var onCreate: (Design) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var width: String
    @State private var height: String
    /// What the sides are typed in: px, in, mm or cm — at first, Settings'
    /// custom size unit.
    @State private var unit: String
    /// Read once as the sheet opens.
    @State private var recent = CustomSizes.recent()

    /// 1080 × 1080 pixels to start, written in Settings' unit, as the
    /// Android twin starts its sides.
    init(onCreate: @escaping (Design) -> Void) {
        self.onCreate = onCreate
        let unit = AppDefaults.unit()
        let side = CustomSizes.convert("1080", from: "px", to: unit)
        _width = State(initialValue: side)
        _height = State(initialValue: side)
        _unit = State(initialValue: unit)
    }

    var body: some View {
        let w = CustomSizes.side(width, unit: unit)
        let h = CustomSizes.side(height, unit: unit)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    UnitPicker(unit: $unit)
                        // The size stays the size: what is typed is
                        // rewritten in the new unit.
                        .onChange(of: unit) { old, new in
                            width = CustomSizes.convert(width, from: old, to: new)
                            height = CustomSizes.convert(height, from: old, to: new)
                        }
                    HStack(alignment: .top, spacing: 12) {
                        sideField(tr("Width"), text: $width, valid: w != nil)
                        sideField(tr("Height"), text: $height, valid: h != nil)
                    }
                    HStack(spacing: 8) {
                        ForEach(CustomSizes.ratios.indices, id: \.self) { i in
                            let item = CustomSizes.ratios[i]
                            chip(item.label) {
                                height = CustomSizes.height(forWidth: width, ratio: item.ratio, unit: unit)
                            }
                            .accessibilityLabel("Ratio \(item.label)")
                        }
                    }
                    if !recent.isEmpty {
                        Text("Recently used")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(recent, id: \.self) { size in
                                chip(size.label) {
                                    // Kept in pixels, written in the unit
                                    // the sides are typed in.
                                    width = CustomSizes.convert(String(size.width), from: "px", to: unit)
                                    height = CustomSizes.convert(String(size.height), from: "px", to: unit)
                                }
                                .accessibilityLabel("\(size.width) by \(size.height)")
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.workspace)
            .navigationTitle("Custom size")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        guard let w, let h else { return }
                        CustomSizes.remember(width: w, height: h)
                        onCreate(CustomSizes.design(width: w, height: h, unit: unit))
                    }
                    .fontWeight(.semibold)
                    .disabled(w == nil || h == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func sideField(_ label: String, text: Binding<String>, valid: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField(label, text: text)
                    .keyboardType(unit == "px" ? .numberPad : .decimalPad)
                    .accessibilityHint(valid ? CustomSizes.rangeText : CustomSizes.outOfRangeText)
                Text(unit).foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(valid ? Theme.hairline : Color(.systemRed), lineWidth: valid ? 1 : 1.5))
            Text(valid ? CustomSizes.rangeText : CustomSizes.outOfRangeText)
                .font(.caption)
                .foregroundStyle(valid ? Color.secondary : Color(.systemRed))
        }
        .frame(maxWidth: .infinity)
        // Digits only, five at most, however they arrive — typed or pasted;
        // and one decimal point in a physical unit.
        .onChange(of: text.wrappedValue) { _, typed in
            let clean = CustomSizes.field(typed, unit: unit)
            if clean != typed { text.wrappedValue = clean }
        }
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
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

/// px | in | mm | cm, for a size typed in Custom size and Resize. A size in
/// a physical unit is made at 300 dpi.
struct UnitPicker: View {
    @Binding var unit: String

    var body: some View {
        Picker("Unit", selection: $unit) {
            ForEach(Units.all, id: \.self) { Text($0).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}
