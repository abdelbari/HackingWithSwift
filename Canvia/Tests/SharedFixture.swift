// The fixtures both phones read (Tests/Fixtures, the Android twin's
// core/src/test/resources/fixtures): from the test bundle, or beside this
// file when the folder is not copied into it.

import XCTest

enum SharedFixture {

    final class Anchor {}

    static func data(_ name: String, ext: String = "json", file: StaticString = #filePath) throws -> Data {
        if let url = Bundle(for: Anchor.self).url(forResource: name, withExtension: ext) {
            return try Data(contentsOf: url)
        }
        let here = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        return try Data(contentsOf: here.appendingPathComponent("Fixtures/\(name).\(ext)"))
    }

    static func object(_ name: String, file: StaticString = #filePath) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data(name, file: file)) as? [String: Any])
    }

    static func text(_ name: String, ext: String, file: StaticString = #filePath) throws -> String {
        String(decoding: try data(name, ext: ext, file: file), as: UTF8.self)
    }

    /// A part of a fixture as JSON again, to decode as a model.
    static func encoded(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value)
    }
}
