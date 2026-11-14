import Foundation

public enum DesktopProfileApp: String, Codable, Sendable { case codex, claude }
public enum ProfileOpenMode: String, Sendable { case switchProfile, alongside }
public struct ProfileSwitchProcess: Equatable, Sendable {
    public let pid: Int32
    public let provider: DesktopProfileApp
    public let profileID: String?
    public init(pid: Int32, provider: DesktopProfileApp, profileID: String?) {
        self.pid = pid; self.provider = provider; self.profileID = profileID
    }
}
public enum ProfileSwitchDecision: Equatable, Sendable {
    case focus, open, quit([Int32]), blocked
}
public enum ProfileSwitchWait: Equatable, Sendable { case waiting, ready, changed }

/// Pure decisions only. Runtime termination and launches stay in the
/// RunningProfileApplication and DockModel implementations.
public enum ProfileSwitchPolicy {
    public static func plan(targetID: String, provider: DesktopProfileApp, mode: ProfileOpenMode,
                            processes: [ProfileSwitchProcess], unresolved: Bool = false,
                            pending: Bool = false) -> ProfileSwitchDecision {
        let sameApp = processes.filter { $0.provider == provider }
        // Showing an already-open account never closes intentional parallel work.
        if sameApp.contains(where: { $0.profileID == targetID }) { return .focus }
        if mode == .alongside { return .open }
        guard !unresolved, !pending, sameApp.allSatisfy({ $0.pid > 0 && $0.profileID != nil }) else { return .blocked }
        let pids = Array(Set(sameApp.map(\.pid))).sorted()
        return pids.isEmpty ? .open : .quit(pids)
    }
    public static func afterQuit(targetID: String, provider: DesktopProfileApp,
                                 originalPIDs: Set<Int32>, stillRunning: Set<Int32>,
                                 processes: [ProfileSwitchProcess], unresolved: Bool = false) -> ProfileSwitchWait {
        let opponents = processes.filter { $0.provider == provider && $0.profileID != targetID }
        guard opponents.allSatisfy({ originalPIDs.contains($0.pid) }) else { return .changed }
        // A captured process can lose its readable arguments during normal exit.
        // Wait for resolution; never launch while the snapshot is unreadable.
        guard !unresolved else { return .waiting }
        return stillRunning.isEmpty && opponents.isEmpty ? .ready : .waiting
    }
}

/// A main process appearing once is not proof it survived startup. All times
/// are supplied by the caller so shutdown/startup races have deterministic tests.
public struct ProfileLaunchConfirmation: Sendable {
    private var pids: Set<Int32> = []
    private var firstObserved: TimeInterval?
    public init() {}
    public mutating func observe(pids current: Set<Int32>, readable: Bool, at time: TimeInterval) -> Bool {
        guard readable, !current.isEmpty else {
            pids = []; firstObserved = nil; return false
        }
        if current != pids || firstObserved == nil || time < (firstObserved ?? time) {
            pids = current; firstObserved = time; return false
        }
        return time - (firstObserved ?? time) >= 1
    }
}
