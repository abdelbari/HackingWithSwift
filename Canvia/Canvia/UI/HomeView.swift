// Home screen: gradient hero with size presets + custom size, recent
// designs, and the template gallery.

import SwiftUI

struct HomeView: View {
    var onOpen: (Design) -> Void

    @State private var recents: [RecentDesign] = []
    @State private var customW = "1080"
    @State private var customH = "1080"
    @State private var renaming: RecentDesign?
    @State private var renameText = ""
    @State private var query = ""
    @State private var sort = DesignLibrary.Sort.recent
    @State private var trashed: [RecentDesign] = []
    @State private var showingTrash = false
    @State private var importing = false
    @State private var favoritesVersion = 0
    @State private var importError: String?
    @State private var templateCategory: String?
    @State private var folder: String?
    @State private var filingInto: RecentDesign?
    @State private var newFolderName = ""
    @State private var touring = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                if !recents.isEmpty || !trashed.isEmpty {
                    searchBar
                }
                if recents.isEmpty && trashed.isEmpty {
                    firstRunCard
                }
                importRow
                if !recents.isEmpty {
                    HStack {
                        Text("Recent designs")
                            .font(.title3.weight(.bold))
                        Spacer()
                        sortMenu
                    }
                    .padding(.horizontal)
                    if !folders.isEmpty { folderChips }
                    if shownRecents.isEmpty {
                        Text("No design matches “\(query)”.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    } else {
                        recentsGrid
                    }
                }
                if !trashed.isEmpty {
                    trashSection
                }
                Text("Start from a template")
                    .font(.title3.weight(.bold))
                    .padding(.horizontal)
                templateCategoryChips
                if shownTemplates.isEmpty {
                    Text("No template matches “\(query)”.")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                } else {
                    templatesGrid
                }
            }
            .padding(.bottom, 40)
        }
        // Was a hardcoded near-white, which in dark mode left primary-coloured
        // text — white by then — on an almost white page.
        .background(Theme.workspace)
        .onAppear {
            reload()
            if Onboarding.needsTour { touring = true }
        }
        .sheet(isPresented: $touring, onDismiss: { Onboarding.markSeen() }) {
            WelcomeTour { touring = false }
        }
        .alert("New folder", isPresented: Binding(
            get: { filingInto != nil },
            set: { if !$0 { filingInto = nil } })) {
            TextField("Folder name", text: $newFolderName)
            Button("Move") {
                if let target = filingInto {
                    DesignLibrary.move(id: target.id, toFolder: newFolderName)
                    reload()
                }
                filingInto = nil
            }
            Button("Cancel", role: .cancel) { filingInto = nil }
        }
        .alert("Rename design", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let target = renaming, var design = DesignLibrary.load(id: target.id) {
                    design.title = renameText.trimmingCharacters(in: .whitespaces)
                    design.updatedAt = Date().timeIntervalSince1970 * 1000
                    DesignLibrary.save(design)
                    reload()
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private func reload() {
        recents = DesignLibrary.recents()
        trashed = DesignLibrary.trashed()
    }

    /// A design file made by Export on another device (or this one, as a
    /// backup) comes back in through here.
    private var importRow: some View {
        HStack {
            Button {
                importing = true
            } label: {
                Label("Open a Canvia design file", systemImage: "square.and.arrow.down")
                    .font(.subheadline)
            }
            Spacer()
        }
        .padding(.horizontal)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let design = try DesignPackage.import(try Data(contentsOf: url))
                onOpen(design)
            } catch {
                importError = error.localizedDescription
            }
        }
        .alert("Couldn't open that file", isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var shownRecents: [RecentDesign] {
        DesignLibrary.filter(recents, query: query, sort: sort, folder: folder)
    }

    private var folders: [String] { DesignLibrary.folders(in: recents) }

    private var shownTemplates: [Template] {
        let matching = ContentLibrary.filteredTemplates(in: templateCategory, matching: query)
        // Starred templates first.
        let starred = Set(Favorites.ids(of: "template"))
        return matching.filter { starred.contains($0.id) } + matching.filter { !starred.contains($0.id) }
    }

    // MARK: chips

    /// One row of categories over the templates, so browsing is a tap
    /// rather than a scroll through everything.
    private var templateCategoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: templateCategory == nil) { templateCategory = nil }
                ForEach(ContentLibrary.templateCategories, id: \.self) { category in
                    chip(category, selected: templateCategory == category) {
                        templateCategory = templateCategory == category ? nil : category
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var folderChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: folder == nil) { folder = nil }
                ForEach(folders, id: \.self) { name in
                    chip(name, selected: folder == name, systemImage: "folder") {
                        folder = folder == name ? nil : name
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func chip(_ title: String, selected: Bool, systemImage: String? = nil,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage).font(.caption) }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(selected ? Theme.accent : Theme.card, in: Capsule())
            .foregroundStyle(selected ? Color.white : Theme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// What the home screen says before there is anything on it. A blank
    /// space under the hero reads as a broken list; this says where things
    /// will go and what to do first.
    private var firstRunCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.title)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Your designs will show up here")
                    .font(.subheadline.weight(.semibold))
                Text("Pick a size above or a template below to start. Everything saves itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: search and sort

    /// One field for both lists. Twenty designs is where scrolling stops
    /// finding things; a search box is what finds them after that.
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search designs and templates", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sort) {
                ForEach(DesignLibrary.Sort.allCases) { Text($0.label).tag($0) }
            }
        } label: {
            Label(sort.label, systemImage: "arrow.up.arrow.down")
                .font(.subheadline)
        }
    }

    // MARK: trash

    /// Collapsed by default: what was deleted is not what the home screen is
    /// for, but it has to be findable for the thirty days it is kept.
    private var trashSection: some View {
        DisclosureGroup(isExpanded: $showingTrash) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(trashed) { entry in
                    HStack(spacing: 12) {
                        Group {
                            if let thumb = entry.thumbnail {
                                Image(uiImage: thumb).resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Color(.systemGray5)
                            }
                        }
                        .frame(width: 56, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text("Deleted \(Date(timeIntervalSince1970: entry.updatedAt / 1000), style: .relative) ago")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore") {
                            DesignLibrary.restore(id: entry.id)
                            reload()
                        }
                        .buttonStyle(.bordered)
                        Button(role: .destructive) {
                            DesignLibrary.delete(id: entry.id)
                            reload()
                        } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Delete forever")
                    }
                }
                Text("Designs in the trash are removed after 30 days.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        } label: {
            Text(trashed.count == 1 ? "Recently deleted (1)" : "Recently deleted (\(trashed.count))")
                .font(.title3.weight(.bold))
        }
        .padding(.horizontal)
    }

    // MARK: hero

    private var hero: some View {
        VStack(spacing: 18) {
            Text("Canvia")
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("What will you design today?")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(SizePreset.all) { preset in
                        Button {
                            onOpen(Design(title: "Untitled \(preset.name)",
                                          width: preset.w, height: preset.h))
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: preset.icon)
                                    .font(.title2)
                                Text(preset.name)
                                    .font(.caption.weight(.bold))
                                    .multilineTextAlignment(.center)
                                Text("\(Int(preset.w)) × \(Int(preset.h))")
                                    .font(.caption2)
                                    .opacity(0.85)
                            }
                            .foregroundStyle(.white)
                            // Relative styles above, so the tile has to grow
                            // with them: a fixed 104pt box clipped the size
                            // label off at the larger accessibility sizes.
                            .frame(width: 108)
                            .frame(minHeight: 104)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 14)
                                .fill(.white.opacity(0.16))
                                .overlay(RoundedRectangle(cornerRadius: 14)
                                    .stroke(.white.opacity(0.25))))
                        }
                    }
                }
                .padding(.horizontal, 2)
            }

            HStack(spacing: 8) {
                sizeField("Width", text: $customW)
                Text("×").foregroundStyle(.white)
                sizeField("Height", text: $customH)
                // White on the purple slab, not purple on purple: a brand
                // -tinted button sits at 1.8:1 against the bottom of the
                // gradient, which is under the 3:1 a control needs just to
                // have a visible edge.
                Button {
                    let w = min(4000, max(40, Double(customW) ?? 1080))
                    let h = min(4000, max(40, Double(customH) ?? 1080))
                    onOpen(Design(title: "Untitled design", width: w, height: h))
                } label: {
                    Text("Create custom")
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.brand)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Theme.heroGradient)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26))
    }

    /// The field is a fixed white pill, so it has to be told it is a light
    /// surface. Without that its text took the app's appearance and went
    /// white-on-white in dark mode: the size you had typed was invisible, and
    /// so was the placeholder telling you what the box was for.
    private func sizeField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .keyboardType(.numberPad)
            .frame(width: 76)
            .padding(8)
            .background(.white, in: RoundedRectangle(cornerRadius: 9))
            .environment(\.colorScheme, .light)
    }

    // MARK: recents

    private var recentsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
            ForEach(shownRecents) { recent in
                Button {
                    if let design = DesignLibrary.load(id: recent.id) {
                        onOpen(design)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Group {
                            if let thumb = recent.thumbnail {
                                Image(uiImage: thumb)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Color(.systemGray5)
                            }
                        }
                        .frame(height: 120)
                        .clipped()

                        VStack(alignment: .leading, spacing: 2) {
                            Text(recent.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("\(Int(recent.width)) × \(Int(recent.height)) · \(recent.pages) page\(recent.pages > 1 ? "s" : "")"
                                 + (folder == nil ? (recent.folder.map { " · \($0)" } ?? "") : ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(10)
                    }
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        renameText = recent.title
                        renaming = recent
                    } label: { Label("Rename", systemImage: "pencil") }
                    Button {
                        if var design = DesignLibrary.load(id: recent.id) {
                            let sourceId = design.id
                            design.id = UID.make("doc")
                            design.title += " (copy)"
                            design.updatedAt = Date().timeIntervalSince1970 * 1000
                            DesignLibrary.save(design)
                            DesignLibrary.copyThumbnail(from: sourceId, to: design.id)
                            reload()
                        }
                    } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Menu {
                        ForEach(folders.filter { $0 != recent.folder }, id: \.self) { name in
                            Button(name) {
                                DesignLibrary.move(id: recent.id, toFolder: name)
                                reload()
                            }
                        }
                        Button {
                            newFolderName = ""
                            filingInto = recent
                        } label: { Label("New folder…", systemImage: "folder.badge.plus") }
                        if recent.folder != nil {
                            Button(role: .destructive) {
                                DesignLibrary.move(id: recent.id, toFolder: nil)
                                reload()
                            } label: { Label("Remove from folder", systemImage: "folder.badge.minus") }
                        }
                    } label: { Label("Move to folder", systemImage: "folder") }
                    if supportsMultipleWindows {
                        Button {
                            openWindow(value: recent.id)
                        } label: { Label("Open in new window", systemImage: "macwindow.badge.plus") }
                    }
                    Button(role: .destructive) {
                        // To the trash, not gone: thirty days to change
                        // your mind, in the section below.
                        DesignLibrary.trash(id: recent.id)
                        reload()
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: templates

    private var templatesGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
            ForEach(shownTemplates) { template in
                Button {
                    onOpen(template.instantiate())
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        TemplateThumb(template: template)
                            .frame(height: 150)
                            .frame(maxWidth: .infinity)
                            .clipped()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                                .font(.subheadline.weight(.semibold))
                            Text("\(template.category) · \(Int(template.width)) × \(Int(template.height))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
                    .overlay(alignment: .topTrailing) {
                        if Favorites.isFavorite("template", template.id) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                                .padding(6)
                                .accessibilityLabel("Favourite")
                        }
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    let on = Favorites.isFavorite("template", template.id)
                    Button {
                        Favorites.toggle("template", template.id)
                        favoritesVersion += 1
                    } label: {
                        Label(on ? "Remove from favourites" : "Add to favourites", systemImage: on ? "star.slash" : "star")
                    }
                }
            }
        }
        .padding(.horizontal)
        .id(favoritesVersion)
    }
}
