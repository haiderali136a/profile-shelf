import Foundation

/// Presentation only. Reuses the existing account-scoped readings and never
/// combines percentages from accounts with different quota denominators.
public struct MenuBarQuota: Equatable, Sendable {
    public let compact: String
    public let detail: String
    public let stale: Bool
}
public enum MenuBarQuotaFormatter {
    public static func format(_ snapshot: UsageSnapshot?, expectedIdentity: String?, validating: Bool = false,
                              hasError: Bool = false, now: Date = Date(), statusLine: Bool = false) -> MenuBarQuota {
        if validating { return MenuBarQuota(compact: "checking", detail: "Checking account identity", stale: false) }
        guard let snapshot, let expectedIdentity, snapshot.identity == expectedIdentity else {
            return MenuBarQuota(compact: "—", detail: "Usage unavailable for this account", stale: false)
        }
        let windows = snapshot.windows.filter { $0.duration.isFinite && $0.duration > 0 && $0.duration <= 366 * 86400 && $0.usedPercent.isFinite && $0.usedPercent >= 0 }
            .sorted { $0.duration < $1.duration }
        guard !windows.isEmpty else { return MenuBarQuota(compact: "—", detail: "No supported quota windows", stale: false) }
        // Always keep short/session and seven-day windows visible; model-specific
        // or other windows remain in the detailed view.
        let week = windows.first { $0.duration == 604800 }
        let short = windows.first { $0.duration < 604800 }
        let selected = [short, week].compactMap { $0 }
        let compactWindows = selected.isEmpty ? Array(windows.prefix(2)) : selected
        let age = now.timeIntervalSince(snapshot.fetchedAt)
        let stale = hasError || age > 360 || age < -60
        let prefix = statusLine ? "†" : stale ? "~" : ""
        let text = compactWindows.map { "\(duration($0.duration)) \(percent($0.usedPercent))%" }.joined(separator: "  ")
        let details = windows.map { "\($0.title): \(percent($0.usedPercent))% used, \(percent($0.remainingPercent))% left" }.joined(separator: "\n")
        let updated = "\n" + UsageFreshness.label(fetchedAt: snapshot.fetchedAt, now: now) + " · fetched " + snapshot.fetchedAt.formatted(date: .omitted, time: .shortened)
        return MenuBarQuota(compact: prefix + text + (snapshot.hasUnparsedWindows ? " ?" : ""),
                            detail: details + updated + (statusLine ? "\nSource: local Claude Code status line; not an independently verified account reading" : "\nSource: provider account usage")
                                + (stale ? "\nReading is stale" : ""), stale: stale)
    }
    private static func percent(_ value: Double) -> String { String(format: "%.0f", min(999, max(0, value))) }
    private static func duration(_ seconds: TimeInterval) -> String {
        if seconds == 604800 { return "7d" }
        if seconds.truncatingRemainder(dividingBy: 86400) == 0 { return "\(Int(seconds / 86400))d" }
        if seconds.truncatingRemainder(dividingBy: 3600) == 0 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 60))m"
    }
}
