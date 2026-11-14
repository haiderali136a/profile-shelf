import Foundation
import CryptoKit

/// Only hashed account/endpoint keys and retry timestamps are stored. No credentials.
final class UsageCooldowns: @unchecked Sendable {
    static let shared = UsageCooldowns(file: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Profile Shelf/RateLimits/cooldowns.json"))
    private let lock = NSLock()
    private let file: URL?
    private var deadlines: [String: Double] = [:]

    init(file: URL? = nil) {
        self.file = file
        if let file, let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 262144,
           let data = try? Data(contentsOf: file), let values = try? JSONDecoder().decode([String: Double].self, from: data) {
            deadlines = values.filter { $0.key.count == 64 && $0.key.allSatisfy { $0.isHexDigit } && $0.value.isFinite }
        }
    }
    private func digest(_ scope: String) -> String {
        SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func check(_ scope: String, now: Date) throws {
        lock.lock(); defer { lock.unlock() }
        let key = digest(scope)
        guard let value = deadlines[key] else { return }
        if value > now.timeIntervalSince1970 { throw UsageLoadError.rateLimited(Date(timeIntervalSince1970: value)) }
        deadlines.removeValue(forKey: key)
        persist()
    }
    @discardableResult func record(_ scope: String, response: HTTPURLResponse, now: Date) -> Date {
        let proposed = Self.retryDate(response.value(forHTTPHeaderField: "Retry-After"), now: now)
        lock.lock(); defer { lock.unlock() }
        deadlines = deadlines.filter { $0.value > now.timeIntervalSince1970 }
        let key = digest(scope)
        let value = max(deadlines[key] ?? 0, proposed.timeIntervalSince1970)
        deadlines[key] = value
        persist()
        return Date(timeIntervalSince1970: value)
    }
    private func persist() {
        guard let file else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(deadlines).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            // Keep the in-memory pause even if a read-only disk prevents persistence.
        }
    }
    static func retryDate(_ value: String?, now: Date) -> Date {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), raw.count <= 128 else { return now.addingTimeInterval(300) }
        if let seconds = Double(raw), seconds.isFinite, seconds >= 0 {
            let until = now.timeIntervalSince1970 + max(1, seconds)
            if until.isFinite { return Date(timeIntervalSince1970: until) }
        }
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz", "EEE MMM d HH:mm:ss yyyy"] {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return max(date, now.addingTimeInterval(1)) }
        }
        return now.addingTimeInterval(300)
    }
}
