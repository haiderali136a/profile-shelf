import Foundation

/// The expanded notch's content density, independent of its grid and placement.
public enum NotchLayout: String, Codable, CaseIterable, Sendable {
    case full, compact
    public var label: String { self == .full ? "Full" : "Compact" }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .full
    }
}
