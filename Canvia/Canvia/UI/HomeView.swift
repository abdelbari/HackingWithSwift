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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                if !recents.isEmpty {
                    Text("Recent designs")
                        .font(.title3.weight(.bold))
                        .padding(.horizontal)
                    recentsGrid
                }
                Text("Start from a template")
                    .font(.title3.weight(.bold))
                    .padding(.horizontal)
                templatesGrid
            }
            .padding(.bottom, 40)
        }
        .background(Color(hex: "#fafbfc"))
        .onAppear { recents = DesignLibrary.recents() }
        .alert("Rename design", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let target = renaming, var design = DesignLibrary.load(id: target.id) {
                    design.title = renameText.trimmingCharacters(in: .whitespaces)
                    design.updatedAt = Date().timeIntervalSince1970 * 1000
                    DesignLibrary.save(design)
                    recents = DesignLibrary.recents()
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    // MARK: hero

    private var hero: some View {
        VStack(spacing: 18) {
            Text("Canvia")
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("What will you design today?")
                .font(.system(size: 24, weight: .bold))
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
                                    .font(.system(size: 22))
                                Text(preset.name)
                                    .font(.system(size: 11, weight: .bold))
                                    .multilineTextAlignment(.center)
                                Text("\(Int(preset.w)) × \(Int(preset.h))")
                                    .font(.system(size: 9.5))
                                    .opacity(0.85)
                            }
                            .foregroundStyle(.white)
                            .frame(width: 108, height: 104)
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
                TextField("Width", text: $customW)
                    .keyboardType(.numberPad)
                    .frame(width: 76)
                    .padding(8)
                    .background(.white, in: RoundedRectangle(cornerRadius: 9))
                Text("×").foregroundStyle(.white)
                TextField("Height", text: $customH)
                    .keyboardType(.numberPad)
                    .frame(width: 76)
                    .padding(8)
                    .background(.white, in: RoundedRectangle(cornerRadius: 9))
                Button("Create custom") {
                    let w = min(4000, max(40, Double(customW) ?? 1080))
                    let h = min(4000, max(40, Double(customH) ?? 1080))
                    onOpen(Design(title: "Untitled design", width: w, height: h))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#7300e6"))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color(hex: "#00c4cc"), Color(hex: "#7d2ae8"), Color(hex: "#ff5ca8")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26))
    }

    // MARK: recents

    private var recentsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
            ForEach(recents) { recent in
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
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            Text("\(Int(recent.width)) × \(Int(recent.height)) · \(recent.pages) page\(recent.pages > 1 ? "s" : "")")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                    }
                    .background(.background)
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
                            recents = DesignLibrary.recents()
                        }
                    } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button(role: .destructive) {
                        DesignLibrary.delete(id: recent.id)
                        recents = DesignLibrary.recents()
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: templates

    private var templatesGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
            ForEach(ContentLibrary.templates) { template in
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
                                .font(.system(size: 13, weight: .semibold))
                            Text("\(template.category) · \(Int(template.width)) × \(Int(template.height))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }
}
