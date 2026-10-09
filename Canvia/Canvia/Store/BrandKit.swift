// The brand kit: the colours, faces and logos a person uses in everything.
//
// One kit, stored in Documents, offered first in every colour picker, as a
// type pairing in the theme sheet, and as insertable logos. Not per design:
// a brand is the thing that is the same across designs.

import Foundation

struct BrandKit: Codable, Equatable {
    var colors: [String] = []
    var headingFamily: String?
    var headingWeight: Int = 700
    var bodyFamily: String?
    var bodyWeight: Int = 400
    /// Media or asset sources of logos.
    var logos: [String] = []

    var isEmpty: Bool { colors.isEmpty && headingFamily == nil && bodyFamily == nil && logos.isEmpty }

    /// The kit's faces as a pairing the theme sheet can apply.
    var pairing: FontPairing? {
        guard headingFamily != nil || bodyFamily != nil else { return nil }
        return FontPairing(
            name: "Brand kit",
            heading: PairingSpec(fontFamily: headingFamily ?? bodyFamily ?? "sans", fontWeight: headingWeight,
                                 fontSize: 48, letterSpacing: nil, text: "Brand heading"),
            body: PairingSpec(fontFamily: bodyFamily ?? headingFamily ?? "sans", fontWeight: bodyWeight,
                              fontSize: 18, letterSpacing: nil, text: "Brand body text"))
    }

    /// The kit's colours as a palette for the theme sheet, in kit order —
    /// first there, as on the Android twin — once there are two of them to
    /// map a design onto.
    var palette: Palette? {
        colors.count >= 2 ? Palette(id: "brand-kit", name: "Brand kit", colors: colors) : nil
    }

    static let limit = 12

    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("brandkit.json")
    }

    static func load(from url: URL = fileURL) -> BrandKit {
        guard let data = try? Data(contentsOf: url),
              let kit = try? JSONDecoder().decode(BrandKit.self, from: data) else { return BrandKit() }
        return kit
    }

    func save(to url: URL = BrandKit.fileURL) {
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: url, options: .atomic) }
    }

    /// The pictures the Logos list offers, once each: the logos the sheet
    /// opened with — kept listed when switched off, so a slip can be taken
    /// back — then this design's pictures, then any other logo since added.
    /// A picture switched on stays where it was, so the next tap in the same
    /// place never lands on another. Codes are not logos. As the Android
    /// twin lists them.
    static func logoCandidates(openedWith: [String], current: [String], design: Design) -> [String] {
        let pictures = design.pages.flatMap(\.elements)
            .filter { $0.type == .image }
            .compactMap(\.src)
            .filter { CodeGenerator.payload(from: $0) == nil }
        var seen = Set<String>()
        return (openedWith + pictures + current).filter { seen.insert($0).inserted }
    }

    mutating func addColor(_ hex: String) {
        let h = RecentColors.normalise(hex)
        colors.removeAll { $0 == h }
        colors.insert(h, at: 0)
        colors = Array(colors.prefix(Self.limit))
    }
}
