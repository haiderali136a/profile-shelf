import Foundation

public enum AppIconAppearance: String, Codable, CaseIterable, Sendable {
    case auto, dark, light, tinted, clear
    // Retain the old stored value without offering a duplicate icon choice.
    public static let selectableCases: [Self] = [.auto, .dark, .light, .clear]
    public var effectiveAppearance: Self { self == .tinted ? .auto : self }
    public var label: String { rawValue.capitalized }
}
