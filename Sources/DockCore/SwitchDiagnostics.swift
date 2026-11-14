import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum SwitchDiagnosticStage: String, Codable, Sendable {
    case requested, blocked, prepared, quitting, settled, launching, launcherFinished, retrying, confirmed, failed
    public var label: String {
        switch self {
        case .requested, .prepared: return "Preparing…"
        case .quitting: return "Waiting for quit…"
        case .settled, .launching, .launcherFinished: return "Opening…"
        case .retrying: return "Retrying once…"
        case .confirmed: return "Process detected"
        case .blocked, .failed: return "Needs attention"
        }
    }
}
public enum SwitchFailureCode: String, Codable, Sendable {
    case busy, identityUnknown, launchRejected, observationTimeout, operationFailed
}

/// Deliberately no free-text field: names, emails, paths, arguments, error
/// descriptions, OAuth tokens, usage identities and process IDs cannot be logged.
public struct SwitchDiagnosticRecord: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let session: UUID
    public let account: UUID
    public let provider: DesktopProfileApp
    public let stage: SwitchDiagnosticStage
    public let attempt: Int?
    public let code: SwitchFailureCode?
    public let exitStatus: Int32?
}

/// Bounded local-only journal. File IO belongs on the caller's serial worker.
/// IDs are random per process session, not hashes of email/profile identifiers.
public final class SwitchDiagnosticLog: @unchecked Sendable {
    public let directory: URL
    private let maximumBytes: Int
    private let session = UUID()
    private var accounts: [String: UUID] = [:]
    private let lock = NSLock()
    public init(directory: URL, maximumBytes: Int = 65_536) {
        self.directory = directory.standardizedFileURL
        self.maximumBytes = max(1024, min(maximumBytes, 1_048_576))
    }
    public func append(profileKey: String, provider: DesktopProfileApp, stage: SwitchDiagnosticStage,
                       attempt: Int? = nil, code: SwitchFailureCode? = nil, exitStatus: Int32? = nil, now: Date = Date()) throws {
        lock.lock(); defer { lock.unlock() }
        try prepare()
        let account = accounts[profileKey] ?? UUID()
        accounts[profileKey] = account
        let row = SwitchDiagnosticRecord(timestamp: now, session: session, account: account,
            provider: provider, stage: stage, attempt: attempt.map { max(0, min(2, $0)) }, code: code, exitStatus: exitStatus)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let line = try encoder.encode(row) + Data([10])
        let current = directory.appendingPathComponent("switch-events.jsonl")
        let previous = directory.appendingPathComponent("switch-events.previous.jsonl")
        try verifyLeaf(current); try verifyLeaf(previous)
        var existing = Data()
        if FileManager.default.fileExists(atPath: current.path) {
            let size = try FileManager.default.attributesOfItem(atPath: current.path)[.size] as? NSNumber
            guard (size?.intValue ?? Int.max) <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
            existing = try Data(contentsOf: current)
        }
        if existing.count + line.count > maximumBytes {
            // Atomically update each bounded file; the journal is diagnostic,
            // never part of authentication or switch transaction correctness.
            try existing.write(to: previous, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: previous.path)
            existing = Data()
        }
        try (existing + line).write(to: current, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: current.path)
    }
    private func prepare() throws {
        let fm = FileManager.default
        guard directory.resolvingSymlinksInPath().path == directory.path else { throw CocoaError(.fileWriteNoPermission) }
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let attributes = try fm.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw CocoaError(.fileWriteNoPermission) }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
    private func verifyLeaf(_ url: URL) throws {
        let fm = FileManager.default
        // attributesOfItem does not follow the leaf symlink; dangling links must
        // also fail closed rather than becoming an output destination.
        if let attributes = try? fm.attributesOfItem(atPath: url.path) {
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  (attributes[.referenceCount] as? NSNumber)?.intValue == 1 else { throw CocoaError(.fileWriteNoPermission) }
        }
    }
}
