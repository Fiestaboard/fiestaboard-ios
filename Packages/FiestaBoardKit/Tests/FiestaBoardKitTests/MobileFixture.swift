import Foundation

/// Synthetic transport control, separate from byte-exact recorded contracts.
enum MobileFixture {
    static func reply(_ name: String = "remembered") -> Data {
        try! JSONSerialization.data(withJSONObject: ["access_token":"fb_mob_" + name,
            "token_type":"Bearer", "expires_in":3600, "session_id":"fixture-" + name, "scope":"control"] as [String: Any])
    }
}
