import XCTest
import DockCore
@testable import ProfileShelf

private final class CooldownProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data, [String: String]))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data, headers) = Self.handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class CooldownClock: @unchecked Sendable {
    private let lock = NSLock(); private var date = Date(timeIntervalSince1970: 1800000000)
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return date }
    func advance(_ seconds: Double) { lock.lock(); defer { lock.unlock() }; date.addTimeInterval(seconds) }
}
final class UsageCooldownTests: XCTestCase {
    func session() -> URLSession { let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [CooldownProtocol.self]; return URLSession(configuration: c) }
    func testRetryAfterSecondsHTTPDateAndFallback() {
        let now = Date(timeIntervalSince1970: 1800000000)
        XCTAssertEqual(UsageCooldowns.retryDate("7200", now: now), now.addingTimeInterval(7200), "Never truncate a valid long pause")
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        XCTAssertEqual(UsageCooldowns.retryDate(f.string(from: now.addingTimeInterval(120)), now: now), now.addingTimeInterval(120))
        XCTAssertEqual(UsageCooldowns.retryDate("invalid", now: now), now.addingTimeInterval(300))
        XCTAssertEqual(UsageCooldowns.retryDate(nil, now: now), now.addingTimeInterval(300))
        XCTAssertEqual(UsageCooldowns.retryDate("0", now: now), now.addingTimeInterval(1))
    }
    func testPersistenceIsolationPrivacyAndExpiry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("limits/data.json"), now = Date()
        let response = HTTPURLResponse(url: URL(string: "https://example.test/usage")!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After":"600"])!
        let first = UsageCooldowns(file: file)
        first.record("claude:private-account:usage", response: response, now: now)
        let restored = UsageCooldowns(file: file)
        XCTAssertThrowsError(try restored.check("claude:private-account:usage", now: now))
        XCTAssertNoThrow(try restored.check("claude:other-account:usage", now: now))
        XCTAssertNoThrow(try restored.check("codex:private-account:usage", now: now))
        XCTAssertNoThrow(try restored.check("claude:private-account:profile", now: now))
        XCTAssertFalse(try String(contentsOf: file, encoding: .utf8).contains("private-account"))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertNoThrow(try restored.check("claude:private-account:usage", now: now.addingTimeInterval(601)))
    }
    func codexFixture(_ profile: Profile, home: URL, account: String = "fictional-account") throws {
        let folder = profile.home(in: home); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let claims = Data(#"{"sub":"fictional-user"}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let data = try JSONSerialization.data(withJSONObject: ["auth_mode":"chatgpt","tokens":["access_token":"fictional-token","account_id":account,"id_token":"e30.\(claims).fixture"]])
        try data.write(to: folder.appendingPathComponent("auth.json"))
    }
    func testCodexPauseSurvivesClientRestartAndThenRecovers() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let profile = Profile(id:"test",name:"Fictional",color:"377CF6"); try codexFixture(profile, home: home)
        let file = home.appendingPathComponent("cooldowns/data.json"), clock = CooldownClock()
        var usageCalls = 0
        let lock = NSLock()
        CooldownProtocol.handler = { request in
            if request.url!.path.hasSuffix("/usage") {
                lock.lock(); usageCalls += 1; let count = usageCalls; lock.unlock()
                if count == 1 { return (429, Data(), ["Retry-After":"600"]) }
                return (200, Data(#"{"account_id":"fictional-account","rate_limit":{"primary_window":{"used_percent":25,"limit_window_seconds":18000}}}"#.utf8), [:])
            }
            return (200, Data(#"{"balance":0}"#.utf8), [:])
        }
        let first = UsageClient(home: home, session: session(), cooldowns: UsageCooldowns(file: file), clock: { clock.now() })
        let identity = try await first.identity(for: profile)
        do { _ = try await first.fetch(profile, expectedIdentity: identity); XCTFail("Expected pause") } catch { guard case .rateLimited = error as? UsageLoadError else { return XCTFail("Wrong error: \(error)") } }
        let restarted = UsageClient(home: home, session: session(), cooldowns: UsageCooldowns(file: file), clock: { clock.now() })
        do { _ = try await restarted.fetch(profile, expectedIdentity: identity); XCTFail("Must honor persisted pause") } catch { guard case .rateLimited = error as? UsageLoadError else { return XCTFail("Wrong error") } }
        XCTAssertEqual(usageCalls, 1)
        clock.advance(601)
        let reading = try await restarted.fetch(profile, expectedIdentity: identity)
        XCTAssertEqual(reading.windows.first?.usedPercent, 25)
        XCTAssertEqual(usageCalls, 2)
    }
    func testClaudePauseSurvivesRestartAndThenRecovers() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("limits/data.json"), clock = CooldownClock()
        var profile = Profile(id:"test",name:"Fictional",color:"377CF6"); profile.provider = .claude
        var usageCalls = 0
        CooldownProtocol.handler = { request in
            if request.url!.path.hasSuffix("profile") { return (200, Data(#"{"account":{"uuid":"11111111-1111-1111-1111-111111111111"},"organization":{"uuid":"22222222-2222-2222-2222-222222222222"}}"#.utf8), [:]) }
            usageCalls += 1
            if usageCalls == 1 { return (429, Data(), ["Retry-After":"600"]) }
            return (200, Data(#"{"five_hour":{"utilization":35,"resets_at":"2027-01-01T00:00:00Z"}}"#.utf8), [:])
        }
        let cred = ClaudeUsageCredential(token:"fixture",fingerprint:"fixture",plan:"max")
        func client() -> ClaudeUsageClient { ClaudeUsageClient(session: session(), credentials: { cred }, clock: { clock.now() }, resetFetcher: { _ in nil }, cooldowns: UsageCooldowns(file: file)) }
        let first = client(); let identity = try await first.identity(for: profile)
        do { _ = try await first.fetch(profile, expectedIdentity: identity); XCTFail("Expected pause") } catch { guard case .rateLimited = error as? UsageLoadError else { return XCTFail("Wrong error") } }
        let restored = client(); let restoredID = try await restored.identity(for: profile)
        do { _ = try await restored.fetch(profile, expectedIdentity: restoredID); XCTFail("Must respect pause") } catch { guard case .rateLimited = error as? UsageLoadError else { return XCTFail("Wrong error") } }
        XCTAssertEqual(usageCalls, 1)
        clock.advance(601)
        let reading = try await restored.fetch(profile, expectedIdentity: restoredID)
        XCTAssertEqual(reading.windows.first?.usedPercent, 35)
        XCTAssertEqual(usageCalls, 2)
    }
    func testCodexAccountsAndOptionalResetEndpointStayIndependent() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let a = Profile(id:"alpha",name:"A",color:"377CF6"), b = Profile(id:"beta",name:"B",color:"377CF6")
        try codexFixture(a, home: home, account: "account-a"); try codexFixture(b, home: home, account: "account-b")
        let clock = CooldownClock(), cooldowns = UsageCooldowns()
        let lock = NSLock(); var calls: [String:Int] = [:]
        CooldownProtocol.handler = { request in
            let account = request.value(forHTTPHeaderField: "ChatGPT-Account-Id")!
            let path = request.url!.lastPathComponent, key = account + ":" + path
            lock.lock(); calls[key, default:0] += 1; lock.unlock()
            if account == "account-a" || path != "usage" { return (429, Data(), ["Retry-After":"600"]) }
            let data = Data("{\"account_id\":\"account-b\",\"rate_limit\":{\"primary_window\":{\"used_percent\":25,\"limit_window_seconds\":18000}}}".utf8)
            return (200, data, [:])
        }
        let client = UsageClient(home: home, session: session(), cooldowns: cooldowns, clock: { clock.now() })
        let idA = try await client.identity(for:a), idB = try await client.identity(for:b)
        for _ in 0..<3 {
            do { _ = try await client.fetch(a, expectedIdentity:idA); XCTFail("A must be paused") }
            catch { guard case .rateLimited = error as? UsageLoadError else { return XCTFail("Wrong error") } }
        }
        for _ in 0..<2 {
            let result = try await client.fetch(b, expectedIdentity:idB)
            XCTAssertEqual(result.windows.first?.usedPercent,25)
            XCTAssertNil(result.bankedResets)
        }
        XCTAssertEqual(calls["account-a:usage"],1)
        XCTAssertEqual(calls["account-b:usage"],2)
        XCTAssertEqual(calls["account-b:rate-limit-reset-credits"],1,"Optional endpoint must honor its own pause without hiding usage")
    }
    @MainActor func testPausedUsageRetainsLastVerifiedReadingAndDoesNotRequestSignIn() async throws {
        let client = FixtureUsageClient(), profile = Profile(id:"a",name:"Fictional",color:"377CF6")
        let store = UsageStore(client:client); defer { store.shutdown() }
        store.configure([profile]); store.refreshAll()
        var deadline = Date().addingTimeInterval(2)
        while store.isRefreshing && Date() < deadline { try await Task.sleep(for:.milliseconds(5)) }
        let reading = try XCTUnwrap(store.menuSnapshot(profile).snapshot)
        await client.setFailure(.rateLimited(Date().addingTimeInterval(600)))
        store.refresh(profile, force:true)
        deadline = Date().addingTimeInterval(2)
        while store.isRefreshing && Date() < deadline { try await Task.sleep(for:.milliseconds(5)) }
        XCTAssertEqual(store.menuSnapshot(profile).snapshot,reading)
        XCTAssertTrue(store.disconnectedProfiles.isEmpty)
        XCTAssertTrue(store.menuQuota(profile).stale)
    }

}
