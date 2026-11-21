import Foundation

/// A number the user typed, read in whatever digits their keyboard produced.
///
/// `Double(_:)` reads ASCII digits only. A number pad set to Arabic-Indic or
/// Persian digits types "١٨٥" or "۱۸۵" for 185, which it turned into nothing.
public enum TypedNumber {
    /// The value of `text`, or nil when it is not a number. ASCII input reads
    /// exactly as `Double(_:)` reads it; a whole number in any other decimal
    /// digits reads by each digit's value.
    public static func value(of text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let ascii = Double(trimmed) { return ascii }
        guard !trimmed.isEmpty, trimmed.unicodeScalars.count <= 6 else { return nil }
        var value = 0
        for scalar in trimmed.unicodeScalars {
            guard scalar.properties.numericType == .decimal,
                  let digit = scalar.properties.numericValue
            else { return nil }
            value = value * 10 + Int(digit)
        }
        return Double(value)
    }
}
