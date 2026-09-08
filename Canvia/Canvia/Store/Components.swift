// Reusable components: a selection saved once, dropped into any design.
//
// A footer with a logo and three lines of text, a price tag, a call-out box:
// things that are built once and needed in every design after. A component
// is the elements, normalised to their own box, and inserting one scales
// the whole to the target design and hands out fresh ids.

import Foundation

struct Component: Codable, Identifiable, Equatable {
    var id: String = UID.make("cmp")
    var name: String
    var width: Double
    var height: Double
    var elements: [Element]
}

enum Components {

    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("components.json")
    }

    static func load(from url: URL = fileURL) -> [Component] {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Component].self, from: data) else { return [] }
        return list
    }

    static func save(_ list: [Component], to url: URL = fileURL) {
        if let data = try? JSONEncoder().encode(list) { try? data.write(to: url) }
    }

    /// The elements moved so their union sits at the origin.
    static func make(named name: String, from elements: [Element]) -> Component? {
        guard !elements.isEmpty else { return nil }
        let box = Geometry.union(elements.map(Geometry.aabb))
        let moved = elements.map { el in
            var e = el
            e.x -= box.minX
            e.y -= box.minY
            e.locked = false
            return e
        }
        return Component(name: name, width: box.width, height: box.height, elements: moved)
    }

    @discardableResult
    static func add(named name: String, from elements: [Element], url: URL = fileURL) -> Component? {
        guard let component = make(named: name, from: elements) else { return nil }
        var list = load(from: url)
        list.append(component)
        save(list, to: url)
        return component
    }

    static func remove(_ id: String, url: URL = fileURL) {
        save(load(from: url).filter { $0.id != id }, to: url)
    }

    /// A copy of the component sized to `width` across (height follows),
    /// placed with its top-left at `origin`, with fresh ids and one fresh
    /// group so it moves as a unit.
    static func instance(of component: Component, width: Double, at origin: CGPoint) -> [Element] {
        guard component.width > 0, component.height > 0 else { return [] }
        let from = CGRect(x: 0, y: 0, width: component.width, height: component.height)
        let to = CGRect(x: origin.x, y: origin.y, width: width, height: width * component.height / component.width)
        let group = UID.make("grp")
        return Geometry.scale(component.elements, from: from, to: to).map { el in
            var e = el
            e.id = UID.make()
            e.group = group
            return e
        }
    }
}
