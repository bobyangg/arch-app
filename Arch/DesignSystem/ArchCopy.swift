import Foundation

/// Words the interface counts in.
///
/// Arch writes small numbers out. "Add 2 photos" is a receipt; "Add two photos" is
/// a sentence, and the whole app is trying to sound like a sentence. Past six there
/// is nothing to count that way, so it falls back to the digit.
///
/// This lives here rather than in each screen because three different places were
/// independently mapping five to "five", and they would eventually have disagreed.
enum ArchCopy {
    private static let words = [
        "zero", "one", "two", "three", "four", "five",
        "six", "seven", "eight", "nine", "ten"
    ]

    /// "three". Digits past ten.
    static func word(_ number: Int) -> String {
        words.indices.contains(number) ? words[number] : "\(number)"
    }

    /// "Three". For the start of a sentence.
    static func capitalisedWord(_ number: Int) -> String {
        let text = word(number)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private static let ordinals = [
        "", "first", "second", "third", "fourth", "fifth",
        "sixth", "seventh", "eighth", "ninth", "tenth"
    ]

    /// "third". Used by VoiceOver, where "chosen 3" reads as a quantity.
    static func ordinal(_ number: Int) -> String {
        ordinals.indices.contains(number) ? ordinals[number] : "\(number)"
    }
}
