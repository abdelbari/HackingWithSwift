// This phone's own dictionary: the words the spelling check's Add to
// dictionary has added, passed over in every design here. Kept in
// Documents as dictionary.json — a sorted JSON array of lower-cased words,
// the Android twin's very file — and carried by Settings backup. Each word
// is taught to the system's checker too (UITextChecker.learnWord), so the
// red underline the keyboard draws while typing passes over it as well.

import UIKit

enum SpellingDictionary {

    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Proofreader.dictionaryFile)
    }

    /// The words, lower-cased and sorted; none when there is no file.
    static func load(from url: URL = fileURL) -> [String] {
        Proofreader.decodeDictionary(try? Data(contentsOf: url))
    }

    /// `words` added — taught to the system's checker as well, with `learn`
    /// — and how many were new. A word is never taken away.
    @discardableResult
    static func add(_ words: [String], to url: URL = fileURL, learn: Bool = true) -> Int {
        let had = load(from: url)
        let now = Proofreader.tidied(had + words)
        if now.count != had.count {
            try? Proofreader.encodeDictionary(now).write(to: url, options: .atomic)
        }
        if learn {
            // As written and lower-cased, so "Canvia" passes at the start of
            // a sentence and inside one.
            let written = words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            for word in Set(written + Proofreader.tidied(words)) where !UITextChecker.hasLearnedWord(word) {
                UITextChecker.learnWord(word)
            }
        }
        return now.count - had.count
    }
}

extension DesignStore {

    /// The spelling check's Ignore: `word` passed over in this design from
    /// now on, in its Ignore list, as one step. Nothing when it is there
    /// already.
    func ignoreSpelling(_ word: String) {
        let next = Proofreader.ignoring(design, word)
        guard next.spellIgnore != design.spellIgnore else { return }
        apply { $0.spellIgnore = next.spellIgnore }
    }

    /// The design's language — which the spelling check, Read aloud and
    /// dictation follow — or the phone's own for nil, as one step.
    func setLanguage(_ language: String?) {
        let tag = Proofreader.languageTag(language)
        guard tag != design.language else { return }
        apply { $0.language = tag }
    }
}
