import Foundation

extension String {
    /// Normalizes "fancy" Unicode text — like 𝘽𝙚𝙨𝙩 𝙥𝙖𝙧𝙩 or 𝓼𝓵𝓸𝔀𝓮𝓭 — back to
    /// plain, consistent letters for display. Common in bootleg "slowed +
    /// reverb" song titles, which use special Unicode look-alike characters
    /// to fake bold/italic styling in a plain text field. Those are
    /// genuinely different characters, not a font/weight difference, so no
    /// amount of app styling can make them match normal text — this maps
    /// them back to standard Latin letters instead. Purely cosmetic for
    /// display; never touches the actual file or its tags.
    var normalizedForDisplay: String {
        precomposedStringWithCompatibilityMapping
    }
}
