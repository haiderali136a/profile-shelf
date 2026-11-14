import AppKit
import SwiftUI
import DockCore

extension Notification.Name {
    static let profileShelfShowInsights = Notification.Name("ProfileShelf.ShowInsights")
}

extension UsageStore {
    func menuSnapshot(_ profile: Profile) -> (snapshot: UsageSnapshot?, statusLine: Bool) {
        let entry = entries[profile.id]
        guard entry?.validatingIdentity != true else { return (nil, false) }
        if let snapshot = entry?.snapshot, entry?.identity == snapshot.identity { return (snapshot, false) }
        // Do not let a fallback mask a confirmed mismatch with the Desktop account.
        if entry?.error != nil, entry?.error != .claudeOtherAccount, let snapshot = statusLineReadings[profile.id] { return (snapshot, true) }
        return (nil, false)
    }
    func menuQuota(_ profile: Profile) -> MenuBarQuota {
        let reading = menuSnapshot(profile), entry = entries[profile.id]
        return MenuBarQuotaFormatter.format(reading.snapshot,
            expectedIdentity: reading.statusLine ? reading.snapshot?.identity : entry?.identity,
            validating: entry?.validatingIdentity == true, hasError: !reading.statusLine && entry?.error != nil,
            now: now, statusLine: reading.statusLine)
    }
}

/// A compact native surface over Profile Shelf's existing model, discovery,
/// launchers, activity and usage clients. The original dashboard is retained.
struct QuickSwitchPanel: View {
    @ObservedObject var model: DockModel
    @ObservedObject var usage: UsageStore
    @ObservedObject var activity: ActivityMonitor
    let choose: (Profile) -> Void
    let alongside: (Profile) -> Void
    let add: () -> Void
    let dashboard: () -> Void
    let insights: () -> Void
    let tracked: (Profile) -> Bool
    @State private var query = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sections: [QuickProfileSection] {
        QuickProfileSection.sections(profiles: model.displayedProfiles, query: query)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                BrandMark(size: 32).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Profile Shelf").font(.system(size: 18, weight: .semibold))
                    Text("Your accounts, within reach").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { usage.refreshAll(force: true); model.refresh(); model.companions.refresh() } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 26, height: 26)
                }.buttonStyle(.borderless).help("Refresh profiles and provider usage")
                Button(action: add) { Image(systemName: "plus").frame(width: 26, height: 26) }
                    .buttonStyle(.borderedProminent).clipShape(RoundedRectangle(cornerRadius: 8)).help("Add any account profile")
            }
            Text("Select an account to switch. More options in ⋯.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if model.displayedProfiles.count > 6 || !query.isEmpty {
                TextField("Find an account", text: $query).textFieldStyle(.roundedBorder)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(section.title)
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                                Spacer()
                                if section.id == .codex {
                                    Text("Codex quota").font(.system(size: 11)).foregroundStyle(.tertiary)
                                }
                            }.padding(.horizontal, 2)
                            ForEach(section.profiles) { profile in card(profile) }
                            if section.profiles.isEmpty {
                                Button("Add \(section.id == .codex ? "ChatGPT" : "Claude") account…", action: add)
                                    .buttonStyle(.bordered).frame(maxWidth: .infinity)
                            }
                        }
                    }
                    if sections.isEmpty {
                        Text("No matching profiles").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 2)
            }
            .frame(minHeight: 0, maxHeight: .infinity)
            .layoutPriority(1)
            .scrollIndicators(.visible)
            if let message = model.message {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(4).help(message)
                    if let recovery = model.messageRecovery {
                        Button(recovery.title) { model.retryMessage(selectProfile: choose) }
                            .font(.system(size: 11, weight: .medium)).disabled(!model.switchingTargets.isEmpty)
                    }
                }
            }
            Divider()
            HStack {
                Button("Usage insights", action: insights)
                Spacer()
                Button("Full dashboard", action: dashboard)
            }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.accentColor)
        }.padding(18).background(.ultraThinMaterial)
    }
    private func card(_ profile: Profile) -> some View {
        let reading = usage.menuSnapshot(profile)
        let quota = usage.menuQuota(profile)
        let entry = usage.entries[profile.id]
        let isOpen = model.running[profile.id]?.isEmpty == false
        let selected = tracked(profile)
        let tasks = activity.entries[profile.id]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
            Button { choose(profile) } label: {
                HStack(spacing: 10) {
                    Image(nsImage: model.artwork(for: profile)).resizable().scaledToFit().frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(model.switchingTargets[profile.kind] == profile.id ? (model.switchStages[profile.kind]?.label ?? "Switching…") : model.opening.contains(profile.id) ? "Opening…" : isOpen ? "Open" : "Ready to open")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selected { Image(systemName: "menubar.rectangle").font(.system(size: 12)).foregroundStyle(Color.accentColor).help("Shown in menu-bar usage") }
                    Circle().fill(isOpen ? Color.green : Color.secondary.opacity(0.35)).frame(width: 6, height: 6)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(model.opening.contains(profile.id) || model.closing.contains(profile.id) || model.switchingTargets[profile.kind] != nil)
            Menu {
                Button(isOpen ? "Show profile" : (profile.kind == .codex || profile.kind == .claude ? "Switch to account" : "Open profile")) { choose(profile) }
                Button("Open alongside", systemImage: "plus.rectangle.on.rectangle") { alongside(profile) }
                    .disabled(!model.canOpenAlongside(profile))
                Divider()
                Button("Close profile window") { model.requestQuit(profile) }.disabled(!isOpen || profile.terminalHost != nil)
            } label: { Image(systemName: "ellipsis").frame(width: 22, height: 28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Account actions, including Open alongside")
                .accessibilityLabel("Actions for \(profile.name)")
                .disabled(model.switchingTargets[profile.kind] != nil || model.opening.contains(profile.id) || model.closing.contains(profile.id))
            }
            if let snapshot = reading.snapshot {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 8) {
                    ForEach(snapshot.windows.sorted { $0.duration < $1.duration }) { window in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Text(window.duration == 604800 ? "7-day" : window.duration == 18000 ? "5-hour" : window.title)
                                    .lineLimit(1).minimumScaleFactor(0.9)
                                Spacer(minLength: 2)
                                Text(String(format: "%.0f%% used", window.usedPercent)).monospacedDigit().fixedSize()
                            }.font(.system(size: 11)).foregroundStyle(.secondary)
                            ProgressView(value: min(100, max(0, window.usedPercent)), total: 100)
                                .tint(window.usedPercent >= 90 ? .orange : Color.accentColor)
                                .accessibilityLabel(window.title + " usage")
                        }
                    }
                }
            } else if profile.kind != .codex && !profile.usesClaudeAccountUsage {
                Text(profile.listDetail).font(.system(size: 11)).foregroundStyle(.secondary)
            } else if entry?.error == nil {
                Text(entry?.validatingIdentity == true ? "Checking usage…" : "Usage unavailable")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let error = entry?.error {
                HStack(alignment: .top, spacing: 8) {
                    Text(error.statusLabel).font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(2).help(error.message)
                    Spacer(minLength: 0)
                    if UsageRecoveryAction.actions(for: error).contains(.refresh) {
                        Button("Refresh") { usage.refresh(profile, force: true) }
                            .disabled(entry?.isRefreshing == true)
                            .help(error.message).accessibilityLabel("Refresh usage for \(profile.name)").foregroundStyle(Color.accentColor)
                    }
                    if UsageRecoveryAction.actions(for: error).contains(.reconnect) {
                        Button(usage.isReconnecting(profile) ? "Finish sign-in…" : error == .claudeConnectionNeeded ? "Connect usage" : "Reconnect") {
                            usage.reconnect(profile, home: model.home)
                        }.disabled(usage.isReconnecting(profile)).foregroundStyle(Color.accentColor)
                            .help(usage.reconnectionMessages[usage.connectionKey(profile)] ?? error.message)
                            .accessibilityLabel("Reconnect usage for \(profile.name)")
                    }
                }.font(.system(size: 11)).buttonStyle(.plain)
            }
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    if let error = entry?.error {
                        Text(error.message).foregroundStyle(.secondary)
                    }
                    if let snapshot = reading.snapshot {
                        if let plan = snapshot.plan { Text("Plan: " + plan) }
                        ForEach(snapshot.windows.sorted { $0.duration < $1.duration }) { window in
                            if let date = window.resetsAt {
                                Text("\(window.title) resets \(date.formatted(date: .abbreviated, time: .shortened))")
                            }
                        }
                        Text("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))" + (quota.stale ? " · stale" : ""))
                        if let count = snapshot.bankedResets { Text("Saved resets: " + String(count)) }
                        if reading.statusLine { Text("Source: local Claude Code report; account usage is not yet verified.") }
                        else { Text(profile.kind == .codex ? "Source: Codex account limits, not all ChatGPT chat usage." : profile.usesClaudeAccountUsage ? "Source: this account’s Claude Code subscription usage." : "Source: this tool’s local usage report.") }
                        if let tasks, tasks.liveAvailable { Text("Local tasks: \(tasks.working) working · \(tasks.waiting) waiting") }
                        Text("Provider windows roll forward; the 7-day limit is not a calendar-week total.")
                        Divider()
                    }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Profile: " + profile.name)
                    Text(isOpen ? "Running. Check the signed-in account inside the app." : "No running process is assigned to this profile.")
                    if let app = model.applicationURL(for: profile) { Text("Launch source: " + app.path).textSelection(.enabled) }
                    ForEach(Array(Set((model.running[profile.id] ?? []).compactMap { $0.bundleURL?.path })).sorted(), id: \.self) { path in
                        Text("Running app: " + path).textSelection(.enabled)
                    }
                    Text("Profile artwork and shortcut labels do not change the official running app’s Dock icon or name.")
                }
                }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 8)
            } label: {
                HStack(spacing: 8) {
                    Text("Details")
                    Spacer(minLength: 4)
                    if let snapshot = reading.snapshot {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            Text((quota.stale ? "~ " : "") + UsageFreshness.label(fetchedAt: snapshot.fetchedAt, now: context.date))
                                .foregroundStyle(quota.stale ? Color.orange : Color.secondary)
                                .help(quota.stale ? "Last available reading; may be out of date." : "When usage was last fetched.")
                        }
                    }
                }
            }.font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(12)
            .background(selected ? Color.accentColor.opacity(0.07) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Color.primary.opacity(selected ? 0.15 : 0.07), lineWidth: 0.7))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isOpen)
    }
}
