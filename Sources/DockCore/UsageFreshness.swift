import Foundation

public enum UsageFreshness {
    public static func label(fetchedAt: Date, now: Date = Date()) -> String {
        let age = now.timeIntervalSince(fetchedAt)
        guard age.isFinite, age >= -60, age <= 366 * 86400 else { return "Reading time unavailable" }
        if age < 60 { return "Updated just now" }
        if age < 3600 { return "Updated \(Int(age / 60))m ago" }
        if age < 86400 { return "Updated \(Int(age / 3600))h ago" }
        return "Updated \(Int(age / 86400))d ago"
    }
}
