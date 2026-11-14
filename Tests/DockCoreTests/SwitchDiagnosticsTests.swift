import XCTest
@testable import DockCore

final class SwitchDiagnosticsTests: XCTestCase {
    private func root() -> URL { FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString) }
    func testRecordsCannotExposeCallerNamesPathsOrTokens() throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        let log = SwitchDiagnosticLog(directory: folder)
        let secret = "person@example.com /Users/private auth_token=SECRET"
        try log.append(profileKey: secret, provider: .codex, stage: .launching, attempt: 1, exitStatus: 17)
        try log.append(profileKey: secret, provider: .codex, stage: .confirmed)
        let bytes = try Data(contentsOf: folder.appendingPathComponent("switch-events.jsonl"))
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        for privateValue in [secret, "example.com", "private", "SECRET", "auth_token"] { XCTAssertFalse(text.contains(privateValue)) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let records = try text.split(separator: "\n").map { try decoder.decode(SwitchDiagnosticRecord.self, from: Data($0.utf8)) }
        XCTAssertEqual(records[0].account, records[1].account)
        XCTAssertEqual(records[0].exitStatus, 17)
        XCTAssertEqual(records.map(\.stage), [.launching, .confirmed])
    }
    func testAccountsAndSessionsUseSeparateRandomReferences() throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        let first = SwitchDiagnosticLog(directory: folder)
        try first.append(profileKey: "same", provider: .codex, stage: .requested)
        try first.append(profileKey: "other", provider: .codex, stage: .requested)
        try SwitchDiagnosticLog(directory: folder).append(profileKey: "same", provider: .codex, stage: .requested)
        let data = try Data(contentsOf: folder.appendingPathComponent("switch-events.jsonl"))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let rows = try data.split(separator: 10).map { try decoder.decode(SwitchDiagnosticRecord.self, from: Data($0)) }
        XCTAssertNotEqual(rows[0].account, rows[1].account)
        XCTAssertNotEqual(rows[0].account, rows[2].account)
        XCTAssertNotEqual(rows[0].session, rows[2].session)
    }
    func testRotationIsBoundedAndPrivate() throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        let log = SwitchDiagnosticLog(directory: folder, maximumBytes: 1024)
        for _ in 0..<100 { try log.append(profileKey: "work", provider: .claude, stage: .confirmed) }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        XCTAssertEqual(Set(files.map(\.lastPathComponent)), ["switch-events.jsonl", "switch-events.previous.jsonl"])
        for file in files {
            XCTAssertLessThanOrEqual(try Data(contentsOf: file).count, 1024)
            let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
            XCTAssertEqual((mode?.intValue ?? 0) & 0o777, 0o600)
        }
    }
    func testSymlinkDestinationDoesNotOverwriteAnotherFile() throws {
        let folder = root(); let outside = root()
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("preserved".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("switch-events.jsonl"), withDestinationURL: outside)
        XCTAssertThrowsError(try SwitchDiagnosticLog(directory: folder).append(profileKey: "work", provider: .codex, stage: .requested))
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "preserved")
    }
    func testDanglingSymlinkAndOversizeExistingLogAreRejected() throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("switch-events.jsonl")
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: folder.appendingPathComponent("missing"))
        let log = SwitchDiagnosticLog(directory: folder, maximumBytes: 1024)
        XCTAssertThrowsError(try log.append(profileKey: "work", provider: .codex, stage: .requested))
        try FileManager.default.removeItem(at: file)
        try Data(repeating: 65, count: 2048).write(to: file)
        XCTAssertThrowsError(try log.append(profileKey: "work", provider: .codex, stage: .requested))
    }
}
