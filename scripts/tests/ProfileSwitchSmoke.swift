import Foundation

/// Runs against the production policy without XCTest. No apps or accounts opened.
@main struct ProfileSwitchSmoke {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            count += 1
            guard condition() else { fatalError("Switch policy check failed: \(name)") }
        }
        let personal = ProfileSwitchProcess(pid: 10, provider: .codex, profileID: "personal")
        let work = ProfileSwitchProcess(pid: 11, provider: .codex, profileID: "work")
        let claude = ProfileSwitchProcess(pid: 20, provider: .claude, profileID: "claude-personal")
        let unknown = ProfileSwitchProcess(pid: 12, provider: .codex, profileID: nil)
        check(ProfileSwitchPolicy.plan(targetID: "work", provider: .codex, mode: .switchProfile, processes: []) == .open, "open when no app runs")
        check(ProfileSwitchPolicy.plan(targetID: "work", provider: .codex, mode: .switchProfile, processes: [personal, claude]) == .quit([10]), "switch affects only ChatGPT")
        check(ProfileSwitchPolicy.plan(targetID: "claude-work", provider: .claude, mode: .switchProfile, processes: [personal, claude]) == .quit([20]), "switch affects only Claude")
        check(ProfileSwitchPolicy.plan(targetID: "work", provider: .codex, mode: .alongside, processes: [personal, claude]) == .open, "alongside closes nothing")
        check(ProfileSwitchPolicy.plan(targetID: "work", provider: .codex, mode: .switchProfile, processes: [personal, work]) == .focus, "already-open target is focused")
        check(ProfileSwitchPolicy.plan(targetID: "work", provider: .codex, mode: .alongside, processes: [work]) == .focus, "no duplicate target launch")
        check(ProfileSwitchPolicy.plan(targetID: "work", provider: .codex, mode: .switchProfile, processes: [unknown]) == .blocked, "never guess process ownership")
        check(ProfileSwitchPolicy.plan(targetID: "work", provider: .codex, mode: .switchProfile, processes: [personal], unresolved: true) == .blocked, "block unreadable process")
        check(ProfileSwitchPolicy.plan(targetID: "work", provider: .codex, mode: .switchProfile, processes: [personal], pending: true) == .blocked, "avoid another opening or closing action")
        check(ProfileSwitchPolicy.afterQuit(targetID: "work", provider: .codex, originalPIDs: [10], stillRunning: [10], processes: [personal, claude]) == .waiting, "do not launch during quit confirmation")
        check(ProfileSwitchPolicy.afterQuit(targetID: "work", provider: .codex, originalPIDs: [10], stillRunning: [], processes: [claude]) == .ready, "other provider does not block")
        check(ProfileSwitchPolicy.afterQuit(targetID: "work", provider: .codex, originalPIDs: [10], stillRunning: [], processes: [unknown]) == .changed, "new unknown process stops switch")
        check(ProfileSwitchPolicy.afterQuit(targetID: "work", provider: .codex, originalPIDs: [10], stillRunning: [10], processes: []) == .waiting, "wait for captured process even if mapping disappears")
        check(ProfileSwitchPolicy.afterQuit(targetID: "work", provider: .codex, originalPIDs: [10], stillRunning: [], processes: [work]) == .ready, "do not duplicate target opened during wait")
        check(ProfileSwitchPolicy.afterQuit(targetID: "work", provider: .codex, originalPIDs: [10], stillRunning: [10], processes: [ProfileSwitchProcess(pid: 10, provider: .codex, profileID: nil)], unresolved: true) == .waiting, "captured exiting process may briefly lose readable identity")
        check(ProfileSwitchPolicy.afterQuit(targetID: "work", provider: .codex, originalPIDs: [10], stillRunning: [], processes: [], unresolved: true) == .waiting, "unknown snapshot never becomes ready")
        var confirmation = ProfileLaunchConfirmation()
        check(!confirmation.observe(pids: [], readable: true, at: 0), "launcher callback alone is not readiness")
        check(!confirmation.observe(pids: [30], readable: true, at: 1), "first observed PID is not readiness")
        check(!confirmation.observe(pids: [], readable: true, at: 1.5), "startup exit resets confirmation")
        check(!confirmation.observe(pids: [31], readable: true, at: 2), "restart needs a fresh interval")
        check(confirmation.observe(pids: [31], readable: true, at: 3.1), "stable verified target confirms launch")
        check(!confirmation.observe(pids: [31], readable: false, at: 4), "unreadable snapshot cannot confirm")
        check(!confirmation.observe(pids: [31], readable: true, at: 5), "readability recovery restarts interval")
        check(!confirmation.observe(pids: [32], readable: true, at: 7), "PID replacement restarts interval")
        check(confirmation.observe(pids: [32], readable: true, at: 8.1), "replacement confirms after stable interval")
        print("Passed \(count) switch-policy checks (no provider apps launched).")
    }
}
