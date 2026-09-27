// The Home Screen's quick actions: press and hold the app's icon for "New
// post", "New story" and the latest designs, each going straight into the
// editor — the Android twin's launcher shortcuts (data/Shortcuts.kt).
//
// iOS shows four at most, so two go to starting something new and two to
// picking up where you left off, where Android lists three. The designs'
// own thumbnails cannot be icons here — a quick action takes a symbol, not
// a picture — so each wears the same document symbol.
//
// A chosen action becomes a LaunchRequest, the same hand-off Siri's intents
// use, so the app serves both in one place.

import UIKit

enum QuickActions {

    static let newType = "app.canvia.new-design"
    static let openType = "app.canvia.open-design"
    static let presetKey = "presetId"
    static let designKey = "designId"
    /// The latest designs listed, after the two ways to start.
    static let recentCount = 2
    /// Posted when an action has left a request, so an app already in
    /// front serves it without waiting to be made active again.
    static let requested = Notification.Name("canvia.quickActionRequested")

    struct Item: Equatable {
        var type: String
        var title: String
        var subtitle: String?
        var symbol: String
        var info: [String: String]
    }

    /// Every action, in the order the menu lists them: New post, New story,
    /// then the most recently touched designs.
    static func items(recents: [RecentDesign]) -> [Item] {
        var items = [
            Item(type: newType, title: "New post", subtitle: "New Instagram post", symbol: "plus.square",
                 info: [presetKey: "insta-post"]),
            Item(type: newType, title: "New story", subtitle: "New Instagram story", symbol: "plus.rectangle.portrait",
                 info: [presetKey: "insta-story"]),
        ]
        let latest = recents.sorted { $0.updatedAt > $1.updatedAt }.prefix(recentCount)
        for recent in latest {
            let title = recent.title.trimmingCharacters(in: .whitespacesAndNewlines)
            items.append(Item(type: openType, title: title.isEmpty ? "Untitled design" : title, subtitle: nil,
                              symbol: "doc.richtext", info: [designKey: recent.id]))
        }
        return items
    }

    /// What an action asks for, or nil for one this app does not know. A
    /// new design is named after its size, as the Android twin names it; a
    /// size it does not know is the first size. An id that could reach
    /// outside the designs folder is refused.
    static func request(type: String, info: [String: String]) -> LaunchRequest.Request? {
        switch type {
        case newType:
            let id = info[presetKey] ?? "insta-post"
            guard let preset = SizePreset.all.first(where: { $0.id == id }) ?? SizePreset.all.first else { return nil }
            return .newDesign(width: preset.w, height: preset.h, title: preset.name)
        case openType:
            guard let id = info[designKey], isSafeId(id) else { return nil }
            return .open(id: id)
        default:
            return nil
        }
    }

    /// Letters, digits, "-" and "_" only, as the Android twin checks a
    /// shortcut's design id.
    static func isSafeId(_ id: String) -> Bool {
        !id.isEmpty && id.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_")
        }
    }

    /// Leave the action's request for the app, and say so. False when it is
    /// not one this app knows.
    @MainActor
    @discardableResult
    static func handle(_ item: UIApplicationShortcutItem) -> Bool {
        var info: [String: String] = [:]
        for (key, value) in item.userInfo ?? [:] {
            if let text = value as? String { info[key] = text }
        }
        guard let request = request(type: item.type, info: info) else { return false }
        LaunchRequest.set(request)
        NotificationCenter.default.post(name: requested, object: nil)
        return true
    }

    /// The menu brought up to date with the shelf.
    @MainActor
    static func publish(recents: [RecentDesign]) {
        UIApplication.shared.shortcutItems = items(recents: recents).map { item in
            var info: [String: NSSecureCoding] = [:]
            for (key, value) in item.info { info[key] = value as NSString }
            return UIApplicationShortcutItem(type: item.type, localizedTitle: item.title,
                                             localizedSubtitle: item.subtitle,
                                             icon: UIApplicationShortcutIcon(systemImageName: item.symbol),
                                             userInfo: info)
        }
    }
}

/// Only here to hand the window scene a delegate that hears quick actions:
/// SwiftUI has no modifier for them.
@MainActor
final class CanviaAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = CanviaSceneDelegate.self
        return configuration
    }
}

/// A quick action chosen with the app closed arrives as the scene
/// connects; one chosen with it in the background arrives here directly.
@MainActor
final class CanviaSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem { QuickActions.handle(item) }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(QuickActions.handle(shortcutItem))
    }
}
