import Cocoa
import Core

/// macOS のスペルチェッカーで英単語かを判定する（日本語と英語の混在入力に使う）
struct SpellCheckerEnglishWordChecker: EnglishWordChecker {
    func isEnglishWord(_ word: String) -> Bool {
        let misspelled = NSSpellChecker.shared.checkSpelling(
            of: word,
            startingAt: 0,
            language: "en",
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        return misspelled.location == NSNotFound
    }
}
