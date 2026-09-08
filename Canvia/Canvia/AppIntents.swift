// Siri and Shortcuts: start a design at a size, or open one by name.
// Each intent brings the app forward and leaves a LaunchRequest for it.

import AppIntents
import Foundation

enum DesignSizeChoice: String, AppEnum {
    case instagramPost = "insta-post"
    case instagramStory = "insta-story"
    case presentation
    case youtubeThumbnail = "youtube-thumb"
    case poster
    case flyer

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Design Size")
    static var caseDisplayRepresentations: [DesignSizeChoice: DisplayRepresentation] = [
        .instagramPost: "Instagram Post",
        .instagramStory: "Instagram Story",
        .presentation: "Presentation",
        .youtubeThumbnail: "YouTube Thumbnail",
        .poster: "Poster",
        .flyer: "Flyer",
    ]

    /// The home screen's preset this stands for.
    var preset: SizePreset? { SizePreset.all.first { $0.id == rawValue } }
}

struct NewDesignIntent: AppIntent {
    static var title: LocalizedStringResource = "New Design"
    static var description = IntentDescription("Starts a new design at a chosen size.")
    static var openAppWhenRun = true

    @Parameter(title: "Size", default: .instagramPost)
    var size: DesignSizeChoice

    @Parameter(title: "Title")
    var name: String?

    static var parameterSummary: some ParameterSummary {
        Summary("New \(\.$size) design")
    }

    func perform() async throws -> some IntentResult {
        let preset = size.preset ?? SizePreset.all.first ?? SizePreset(id: "square", name: "Square", w: 1080, h: 1080, icon: "square")
        let title = name?.trimmingCharacters(in: .whitespaces)
        LaunchRequest.set(.newDesign(width: preset.w, height: preset.h,
                                     title: (title?.isEmpty ?? true) ? "Untitled \(preset.name)" : title!))
        return .result()
    }
}

struct DesignEntity: AppEntity {
    var id: String
    var title: String
    var pages: Int

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Design")
    static var defaultQuery = DesignQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(pages) pages")
    }

    init(_ recent: RecentDesign) {
        id = recent.id
        title = recent.title
        pages = recent.pages
    }
}

struct DesignQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [DesignEntity] {
        DesignLibrary.recents().filter { identifiers.contains($0.id) }.map(DesignEntity.init)
    }

    func suggestedEntities() async throws -> [DesignEntity] {
        DesignLibrary.recents().sorted { $0.updatedAt > $1.updatedAt }.prefix(8).map(DesignEntity.init)
    }
}

struct OpenDesignIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Design"
    static var description = IntentDescription("Opens one of your designs in the editor.")
    static var openAppWhenRun = true

    @Parameter(title: "Design")
    var design: DesignEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$design)")
    }

    func perform() async throws -> some IntentResult {
        LaunchRequest.set(.open(id: design.id))
        return .result()
    }
}

struct CanviaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NewDesignIntent(),
                    phrases: ["New design in \(.applicationName)", "Start a \(.applicationName) design"],
                    shortTitle: "New design",
                    systemImageName: "plus.square.on.square")
        AppShortcut(intent: OpenDesignIntent(),
                    phrases: ["Open a design in \(.applicationName)"],
                    shortTitle: "Open design",
                    systemImageName: "folder")
    }
}
