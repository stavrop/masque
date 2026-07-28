import Foundation

/// A single Hide My Email address as returned by the iCloud HME `list` endpoint.
///
/// Field names mirror the private `.../v1/hme/list` JSON. Anything optional is
/// tolerated because Apple has changed this shape over time.
struct HMEAddress: Codable, Identifiable, Hashable {
    /// Stable id used by activate/deactivate/delete/update calls.
    let anonymousId: String
    /// The generated address, e.g. `foo.bar@icloud.com`.
    let hme: String
    /// Where mail to this address is forwarded (the user's real inbox).
    let forwardToEmail: String?
    /// User-supplied label (usually the site/app name).
    var label: String?
    /// User-supplied free-form note.
    var note: String?
    /// The domain portion, e.g. `icloud.com`.
    let domain: String?
    /// Creation time in milliseconds since the Unix epoch.
    let createTimestamp: Double?
    /// Whether the address currently forwards mail.
    var isActive: Bool

    var id: String { anonymousId }

    var createdDate: Date? {
        guard let ms = createTimestamp else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    /// Case-insensitive match across the fields a user would search by.
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let q = query.lowercased()
        return hme.lowercased().contains(q)
            || (label?.lowercased().contains(q) ?? false)
            || (note?.lowercased().contains(q) ?? false)
            || (forwardToEmail?.lowercased().contains(q) ?? false)
    }
}
