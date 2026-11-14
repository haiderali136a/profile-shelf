import Foundation
import DockCore

extension ActivitySummary {
    /// Full and Compact retain the same task and connection states.
    var profileStatusText: String? {
        if working > 0 { return "\(working) working" + (waiting > 0 ? " · \(waiting) waiting" : "") }
        if waiting > 0 { return "\(waiting) needs you" }
        if let unread, unread > 0 { return "\(unread) unread" }
        if appOpen && !liveAvailable { return connectionIssue?.label ?? "Activity unavailable" }
        if unread == nil { return "Results unknown" }
        return nil
    }
}

enum UsageRecoveryAction: Equatable {
    case refresh, reconnect
    static func actions(for error: UsageLoadError) -> [Self] {
        if error.needsSignIn || error == .claudeConnectionNeeded || error == .claudeOtherAccount { return [.reconnect] }
        return error.offersReconnect ? [.refresh, .reconnect] : [.refresh]
    }
}

/// Preserve strip visibility and ordering, while supporting every displayed provider.
struct QuickProfileSection: Identifiable {
    let id: ProfileProvider
    let profiles: [Profile]
    var title: String { id == .codex ? "ChatGPT / Codex" : id == .claude ? "Claude" : id == .agent ? "Coding agents" : id.label }
    static func sections(profiles: [Profile], query: String) -> [Self] {
        let matching = profiles.filter { query.isEmpty || $0.name.localizedStandardContains(query) }
        return [ProfileProvider.codex, .claude, .agent, .claudeCode, .terminal].compactMap { provider in
            let entries = matching.filter { $0.kind == provider }
            guard !entries.isEmpty || (query.isEmpty && (provider == .codex || provider == .claude)) else { return nil }
            return Self(id: provider, profiles: entries)
        }
    }
}

/// Menu-bar space is bounded: one remembered visible account per desktop provider.
enum MenuBarProfileSelection {
    static func profiles(from displayed: [Profile], remembered: [String: String], running: Set<String>) -> [Profile] {
        [ProfileProvider.codex, .claude].compactMap { provider in
            let candidates = displayed.filter { $0.kind == provider }
            if let id = remembered[provider.rawValue], let profile = candidates.first(where: { $0.id == id }) { return profile }
            return candidates.first(where: { running.contains($0.id) }) ?? candidates.first
        }
    }
}
