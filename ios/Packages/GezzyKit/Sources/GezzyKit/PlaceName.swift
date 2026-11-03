import Foundation

/// Sunucudaki `isPlausibleName` (server/src/community.ts) ile aynı kural; tutmayan adlar sunucuda reddedilir.
public enum PlaceName {
    private static let linkPattern = try! NSRegularExpression(
        pattern: #"https?:|www\.|\.(com|net|org|io|ru|xyz)\b|@|t\.me/"#, options: [.caseInsensitive])
    private static let repeatPattern = try! NSRegularExpression(pattern: #"(.)\1{5,}"#)
    private static let letterCategories: Set<Unicode.GeneralCategory> = [
        .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
    ]

    /// Yer adı gibi görünüyor mu: bağlantı, e-posta, telefon numarası ya da yalnızca rakam/simge değil.
    public static func isPlausible(_ name: String) -> Bool {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // JS `length` UTF-16 birimi sayar.
        let length = text.utf16.count
        guard length >= 2, length <= 80,
              text.unicodeScalars.contains(where: { letterCategories.contains($0.properties.generalCategory) })
        else { return false }
        let range = NSRange(text.startIndex..., in: text)
        if linkPattern.firstMatch(in: text, range: range) != nil { return false }
        if text.unicodeScalars.filter({ ("0"..."9").contains($0) }).count >= 7 { return false } // telefon numarası
        return repeatPattern.firstMatch(in: text, range: range) == nil // "!!!!!!", "aaaaaa"
    }
}
