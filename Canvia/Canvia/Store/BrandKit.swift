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
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: url) }
    }

    mutating func addColor(_ hex: String) {
        let h = RecentColors.normalise(hex)
        colors.removeAll { $0 == h }
        colors.insert(h, at: 0)
        colors = Array(colors.prefix(Self.limit))
    }
}
