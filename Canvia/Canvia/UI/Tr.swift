// The app's words in the app's language, as the Android twin's Tr.kt has
// them.
//
// SwiftUI looks a literal up by itself — Text("Done"), Button("Done"),
// Label, Toggle, Section, navigationTitle, accessibilityLabel — so those
// stay as they are. Text made as a String at run time (in Content and
// Store, interpolated, from a ternary or a function) is not looked up:
// it goes through tr, or trn when it says a count. User content is never
// looked up: Text(verbatim:).
//
// The words come from Localizable.xcstrings, which Tools/strings/
// generate.py writes from Tools/strings/strings.json, the catalogue both
// phones share, keyed by the English. Its placeholders are %@ for text and
// %d for whole numbers, in the English order; here a %d is read as %lld,
// the key SwiftUI makes for an interpolated Int, so a literal view and tr
// find the same entry. Missing, the English shows.

import Foundation

/// `text` in the app's language — the catalogue's English key, "Page %d
/// of %d" — with its placeholders filled from `args` in order. With no
/// args nothing is formatted, so a % in it shows as it is.
func tr(_ text: String, _ args: CVarArg...) -> String {
    Tr.text(text, args, bundle: .main, locale: Tr.language(of: .main))
}

/// The form of a plural entry, "%d page|%d pages", for `count` by the
/// language's plural rules. The count fills the first placeholder, which
/// is its %d; `args` fill the ones after it, in order.
func trn(_ oneOther: String, _ count: Int, _ args: CVarArg...) -> String {
    Tr.plural(oneOther, count, args, bundle: .main, locale: Tr.language(of: .main))
}

enum Tr {
    /// The key a catalogue entry has here: each %d read as %lld, a %%
    /// left alone.
    static func key(_ text: String) -> String {
        guard text.contains("%d") else { return text }
        return text.components(separatedBy: "%%")
            .map { $0.replacingOccurrences(of: "%d", with: "%lld") }
            .joined(separator: "%%")
    }

    /// The key a plural entry has here: its other form, "%lld pages" for
    /// "%d page|%d pages" (generate.py writes it so).
    static func pluralKey(_ oneOther: String) -> String {
        key(forms(oneOther).other)
    }

    /// The English one and other forms of "<one>|<other>".
    static func forms(_ oneOther: String) -> (one: String, other: String) {
        guard let bar = oneOther.firstIndex(of: "|") else { return (oneOther, oneOther) }
        return (String(oneOther[..<bar]), String(oneOther[oneOther.index(after: bar)...]))
    }

    /// tr, from `bundle`, formatting for `locale`.
    static func text(_ text: String, _ args: [CVarArg], bundle: Bundle, locale: Locale?) -> String {
        let wanted = key(text)
        let found = bundle.localizedString(forKey: wanted, value: wanted, table: nil)
        guard !args.isEmpty else { return found == wanted ? text : found }
        return String(format: found, locale: locale, arguments: args)
    }

    /// trn, from `bundle`; `locale` picks the plural rules. In English, or
    /// for an entry the catalogue does not have, the English one or other.
    static func plural(_ oneOther: String, _ count: Int, _ args: [CVarArg],
                       bundle: Bundle, locale: Locale?) -> String {
        let all: [CVarArg] = [count as CVarArg] + args
        // A string the catalogue cannot hold, to tell a missing entry.
        let missing = "\u{1}"
        let found = locale == nil ? missing
            : bundle.localizedString(forKey: pluralKey(oneOther), value: missing, table: nil)
        guard found != missing else {
            let english = count == 1 ? forms(oneOther).one : forms(oneOther).other
            return String(format: key(english), arguments: all)
        }
        return String(format: found, locale: locale, arguments: all)
    }

    /// The language `bundle` speaks to this person, whose plural rules and
    /// numbers its words follow; nil in English, whose numbers are written
    /// as Swift writes "\(n)", ungrouped, as the app wrote them before.
    static func language(of bundle: Bundle) -> Locale? {
        let code = bundle.preferredLocalizations.first ?? "en"
        return code == "en" ? nil : Locale(identifier: code)
    }
}

/// The languages Canvia speaks, each named in its own words — what
/// Settings ▸ Language shows, never translated.
enum AppLanguage {
    static let names: [(code: String, name: String)] = [
        ("en", "English"), ("es", "Español"), ("fr", "Français"), ("de", "Deutsch"),
        ("pt-BR", "Português (Brasil)"), ("it", "Italiano"), ("ja", "日本語"), ("ar", "العربية"),
    ]

    /// The language the app is in: the one of its own the phone chose,
    /// from the phone's languages or Canvia's own in the Settings app.
    static func current(_ bundle: Bundle = .main) -> String {
        bundle.preferredLocalizations.first ?? "en"
    }

    /// `code`'s own name; English for one Canvia does not speak.
    static func name(_ code: String) -> String {
        names.first(where: { $0.code == code })?.name ?? "English"
    }
}
