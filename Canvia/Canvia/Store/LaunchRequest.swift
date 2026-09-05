// What an App Intent asks the app to do once it is in front: start a
// design at a size, or open one. Written by the intent, read and cleared
// by the app when a scene becomes active — small enough for UserDefaults,
// and it has to survive the app being launched to serve it.

import Foundation

enum LaunchRequest {

    enum Request: Equatable {
        case newDesign(width: Double, height: Double, title: String)
        case open(id: String)
    }

    static let key = "canvia.launchRequest"

    static func set(_ request: Request, defaults: UserDefaults) {
        switch request {
        case .newDesign(let w, let h, let title):
            defaults.set(["kind": "new", "width": w, "height": h, "title": title] as [String: Any], forKey: key)
        case .open(let id):
            defaults.set(["kind": "open", "id": id] as [String: Any], forKey: key)
        }
    }

    static func set(_ request: Request) { set(request, defaults: .standard) }

    /// The pending request, cleared so it is served once.
    static func take(_ defaults: UserDefaults) -> Request? {
        guard let dict = defaults.dictionary(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        switch dict["kind"] as? String {
        case "new":
            guard let w = dict["width"] as? Double, let h = dict["height"] as? Double, w > 0, h > 0 else { return nil }
            return .newDesign(width: w, height: h, title: dict["title"] as? String ?? "Untitled design")
        case "open":
            guard let id = dict["id"] as? String, !id.isEmpty else { return nil }
            return .open(id: id)
        default:
            return nil
        }
    }

    static func take() -> Request? { take(.standard) }
}
