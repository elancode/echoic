import Foundation

/// Generates ULIDs (Universally Unique Lexicographically Sortable Identifiers).
/// Time-sortable, string-sortable in SQLite, 26 characters.
enum ULID {
    private static let encodingChars = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// Generate a new ULID string.
    static func generate() -> String {
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        var chars = [Character](repeating: "0", count: 26)

        // Encode 48-bit timestamp into first 10 characters (Crockford's Base32)
        var t = timestamp
        for i in stride(from: 9, through: 0, by: -1) {
            chars[i] = encodingChars[Int(t & 0x1F)]
            t >>= 5
        }

        // Encode 80 bits of randomness into last 16 characters
        for i in 10..<26 {
            chars[i] = encodingChars[Int.random(in: 0..<32)]
        }

        return String(chars)
    }
}
