import Foundation

/// Premium kuralları: ücretsiz kullanıcı ömür boyu 2 seyahat oluşturabilir; silmek hakkı geri vermez.
public enum PremiumRules {
    public static let freeTripLimit = 2
    public static let yearlyID = "gezzy.premium.yearly"
    public static let monthlyID = "gezzy.premium.monthly"
    /// Paywall sırası: yıllık önce.
    public static let productIDs = [yearlyID, monthlyID]

    public static func canCreateTrip(created: Int, isPremium: Bool) -> Bool {
        isPremium || created < freeTripLimit
    }

    /// Kalıcı sayaç ile cihazdaki sahipli seyahatlerin büyüğü.
    public static func tripsCreated(stored: Int, owned: Int) -> Int {
        max(stored, owned)
    }

    public static func remainingFreeTrips(created: Int) -> Int {
        max(0, freeTripLimit - created)
    }
}
