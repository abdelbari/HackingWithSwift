// Favourites: the library items a person reaches for again and again.
//
// Any shape, template, photo, sticker or gradient can be starred; starred
// items lead their tab. A flat set of keys in UserDefaults — "shape:heart",
// "sticker:🎉" — because a favourite is a pointer to a library item, not a
// copy of it.

import Foundation

enum Favorites {

    static let key = "canvia.favorites"

    static func keyFor(_ kind: String, _ id: String) -> String { "\(kind):\(id)" }

    static func all(from defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    static func isFavorite(_ kind: String, _ id: String, defaults: UserDefaults = .standard) -> Bool {
        all(from: defaults).contains(keyFor(kind, id))
    }

    static func toggle(_ kind: String, _ id: String, defaults: UserDefaults = .standard) {
        var set = all(from: defaults)
        let k = keyFor(kind, id)
        if set.contains(k) { set.remove(k) } else { set.insert(k) }
        defaults.set(Array(set).sorted(), forKey: key)
    }

    /// The ids starred under one kind, in a stable order.
    static func ids(of kind: String, defaults: UserDefaults = .standard) -> [String] {
        all(from: defaults).filter { $0.hasPrefix(kind + ":") }
            .map { String($0.dropFirst(kind.count + 1)) }
            .sorted()
    }
}
