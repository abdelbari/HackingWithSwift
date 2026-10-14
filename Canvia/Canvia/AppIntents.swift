// Siri and Shortcuts: start a design at a size, or open one by name.
// Each intent brings the app forward and leaves a LaunchRequest for it.

import AppIntents
import Foundation

enum DesignSizeChoice: String, AppEnum, CaseIterable {
    // Every design type in the catalogue, by its id and in its order — the
    // shared sizes.json — so a size Android asks for by id is one here too.
    case instagramPost = "insta-post"
    case instagramStory = "insta-story"
    case presentation
    case youtubeThumbnail = "youtube-thumb"
    case facebookPost = "facebook-post"
    case poster
    case flyer
    case a4
    case businessCard = "business-card"
    case quoteCard = "quote-card"
    case logo
    case usLetter = "us-letter"
    case tiktokVideo = "tiktok-video"
    case instaReel = "insta-reel"
    case youtubeVideo = "youtube-video"
    case youtubeBanner = "youtube-banner"
    case videoCallBackground = "video-call-background"
    case instaPortrait = "insta-portrait"
    case facebookStory = "facebook-story"
    case facebookCover = "facebook-cover"
    case linkedinPost = "linkedin-post"
    case linkedinBanner = "linkedin-banner"
    case xPost = "x-post"
    case xHeader = "x-header"
    case pinterestPin = "pinterest-pin"
    case phoneWallpaper = "phone-wallpaper"
    case desktopWallpaper = "desktop-wallpaper"
    case presentation43 = "presentation-4x3"
    case invitation
    case postcard
    case menu
    case flyerLetter = "flyer-letter"
    case posterA3 = "a3-poster"
    case resumeA4 = "resume-a4"
    case resumeLetter = "resume-letter"
    case certificate
    case infographic
    case emailHeader = "email-header"
    case brochure
    case displayAd = "display-ad"
    case card
    case calendarA4 = "calendar-a4"
    case calendarLetter = "calendar-letter"
    case planner
    case worksheetA4 = "worksheet-a4"
    case worksheetLetter = "worksheet-letter"
    case bookCover = "book-cover"
    case albumCover = "album-cover"
    case label
    case sticker
    case bookmark
    case ticket
    case giftCertificate = "gift-certificate"
    case letterheadA4 = "letterhead-a4"
    case letterheadLetter = "letterhead-letter"
    case newsletter
    case magazine
    case banner
    case facebookEventCover = "facebook-event-cover"
    case instagramAd = "instagram-ad"
    case twitchBanner = "twitch-banner"
    case etsyBanner = "etsy-banner"
    case mobileVideo = "mobile-video"
    case logoAnimated = "logo-animated"
    case gmailHeader = "gmail-header"
    case snapchatGeofilter = "snapchat-geofilter"
    case podcastCover = "podcast-cover"
    case zoomBackground = "zoom-background"
    case etsyShopIcon = "etsy-shop-icon"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Design Size")
    static var caseDisplayRepresentations: [DesignSizeChoice: DisplayRepresentation] = [
        .instagramPost: "Instagram Post",
        .instagramStory: "Instagram Story",
        .presentation: "Presentation",
        .youtubeThumbnail: "YouTube Thumbnail",
        .facebookPost: "Facebook Post",
        .poster: "Poster",
        .flyer: "Flyer",
        .a4: "A4 Document",
        .businessCard: "Business Card",
        .quoteCard: "Quote Card",
        .logo: "Logo",
        .usLetter: "US Letter Document",
        .tiktokVideo: "TikTok Video",
        .instaReel: "Instagram Reel",
        .youtubeVideo: "YouTube Video",
        .youtubeBanner: "YouTube Banner",
        .videoCallBackground: "Video Call Background",
        .instaPortrait: "Instagram Portrait Post",
        .facebookStory: "Facebook Story",
        .facebookCover: "Facebook Cover",
        .linkedinPost: "LinkedIn Post",
        .linkedinBanner: "LinkedIn Banner",
        .xPost: "X Post",
        .xHeader: "X Header",
        .pinterestPin: "Pinterest Pin",
        .phoneWallpaper: "Phone Wallpaper",
        .desktopWallpaper: "Desktop Wallpaper",
        .presentation43: "Presentation (4:3)",
        .invitation: "Invitation",
        .postcard: "Postcard",
        .menu: "Menu",
        .flyerLetter: "Flyer (US Letter)",
        .posterA3: "Poster (A3)",
        .resumeA4: "Resume (A4)",
        .resumeLetter: "Resume (US Letter)",
        .certificate: "Certificate",
        .infographic: "Infographic",
        .emailHeader: "Email Header",
        .brochure: "Brochure",
        .displayAd: "Display Ad",
        .card: "Card",
        .calendarA4: "Calendar (A4)",
        .calendarLetter: "Calendar (US Letter)",
        .planner: "Planner",
        .worksheetA4: "Worksheet (A4)",
        .worksheetLetter: "Worksheet (US Letter)",
        .bookCover: "Book Cover",
        .albumCover: "Album Cover",
        .label: "Label",
        .sticker: "Sticker",
        .bookmark: "Bookmark",
        .ticket: "Ticket",
        .giftCertificate: "Gift Certificate",
        .letterheadA4: "Letterhead (A4)",
        .letterheadLetter: "Letterhead (US Letter)",
        .newsletter: "Newsletter",
        .magazine: "Magazine (A4)",
        .banner: "Banner",
        .facebookEventCover: "Facebook Event Cover",
        .instagramAd: "Instagram Ad",
        .twitchBanner: "Twitch Banner",
        .etsyBanner: "Etsy Banner",
        .mobileVideo: "Mobile Video",
        .logoAnimated: "Animated Logo",
        .gmailHeader: "Gmail Header",
        .snapchatGeofilter: "Snapchat Geofilter",
        .podcastCover: "Podcast Cover",
        .zoomBackground: "Zoom Background",
        .etsyShopIcon: "Etsy Shop Icon",
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
        let typeName = size.preset?.name ?? tr("Design")
        let title = name?.trimmingCharacters(in: .whitespaces)
        // By id, so the design starts in its type's unit; a type this build
        // no longer lists is the first one.
        LaunchRequest.set(.newType(id: size.rawValue,
                                   title: (title?.isEmpty ?? true) ? tr("Untitled %@", typeName) : title!))
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
