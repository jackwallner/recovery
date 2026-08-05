import Foundation
import StoreKit

/// App Store review deep links for Recharge.
public enum AppStoreReviewLinks {
    /// The App Store Connect record for `com.jackwallner.recovery`.
    public static let appStoreID = "6797089337"

    public static let supportEmail = "support@jackwallner.com"

    /// Opens the App Store write-review page in the user's storefront. Apple
    /// routes correctly when the storefront is unknown.
    public static var writeReviewURL: URL {
        URL(string: writeReviewURLString) ?? URL(string: "https://apps.apple.com")!
    }

    private static var writeReviewURLString: String {
        if let country = storefrontCountryCode {
            return "https://apps.apple.com/\(country)/app/id\(appStoreID)?action=write-review"
        }
        return "https://apps.apple.com/app/id\(appStoreID)?action=write-review"
    }

    private static var storefrontCountryCode: String? {
        if let alpha3 = SKPaymentQueue.default().storefront?.countryCode.lowercased(),
           let mapped = alpha3ToAppStoreCountry[alpha3] {
            return mapped
        }
        if let region = Locale.current.region?.identifier.lowercased(), region.count == 2 {
            return region
        }
        return nil
    }

    /// ISO 3166-1 alpha-3 storefront codes → App Store URL country segment.
    private static let alpha3ToAppStoreCountry: [String: String] = [
        "usa": "us", "gbr": "gb", "deu": "de", "fra": "fr", "ita": "it",
        "esp": "es", "can": "ca", "aus": "au", "jpn": "jp", "kor": "kr",
        "chn": "cn", "hkg": "hk", "twn": "tw", "nld": "nl", "bel": "be",
        "che": "ch", "aut": "at", "swe": "se", "nor": "no", "dnk": "dk",
        "fin": "fi", "irl": "ie", "prt": "pt", "pol": "pl", "bra": "br",
        "mex": "mx", "ind": "in", "sgp": "sg", "nzl": "nz", "are": "ae",
        "sau": "sa", "tur": "tr", "rus": "ru", "ukr": "ua", "cze": "cz",
        "rou": "ro", "hun": "hu", "grc": "gr", "isr": "il", "tha": "th",
        "mys": "my", "idn": "id", "phl": "ph", "vnm": "vn", "zaf": "za",
        "arg": "ar", "chl": "cl", "col": "co", "per": "pe",
    ]
}
