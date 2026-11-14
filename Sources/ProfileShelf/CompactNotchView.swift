import AppKit
import SwiftUI
import DockCore

struct NotchLayoutMenu: View {
    @ObservedObject var model: DockModel
    var body: some View {
        Menu {
            ForEach(NotchLayout.allCases, id: \.self) { layout in
                Button { model.setNotchLayout(layout) } label: {
                    if model.preferences.effectiveNotchLayout == layout {
                        Label(layout.label, systemImage: "checkmark")
                    } else {
                        Text(layout.label)
                    }
                }
            }
        } label: {
            // Keep the symbol inline so AppKit cannot move it before the title.
            (Text(model.preferences.effectiveNotchLayout.label + " ")
             + Text(Image(systemName: "chevron.down")).font(.system(size: 8, weight: .medium)).baselineOffset(1))
                .font(.system(size: 10)).frame(minHeight: 22)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Notch layout: \(model.preferences.effectiveNotchLayout.label)")
        .help("Full keeps the larger cards. Compact shows usage rings. Switch back at any time.")
    }
}

/// Reuses Full's identity validation and account-specific status-line fallback.
struct CompactNotchReading {
    let snapshot: UsageSnapshot?
    let isStatusLine: Bool
    init(entry: UsageEntry?, statusLine: UsageSnapshot?) {
        let verified = entry?.validatingIdentity == false ? entry?.snapshot : nil
        isStatusLine = verified == nil && entry?.error != nil && statusLine != nil
        snapshot = verified ?? (isStatusLine ? statusLine : nil)
    }
    var windows: [UsageWindow] { Array((snapshot?.windows ?? []).sorted { $0.duration < $1.duration }.prefix(2)) }
    func isStale(profile: Profile, entry: UsageEntry?, now: Date) -> Bool {
        guard let snapshot else { return false }
        let ageLimit: TimeInterval = profile.kind == .agent ? 3600 : profile.usesClaudeAccountUsage && !isStatusLine ? 360 : 90
        return (entry?.error != nil && !isStatusLine) || now.timeIntervalSince(snapshot.fetchedAt) > ageLimit
    }
}

struct CompactNotchCard: View {
    @ObservedObject var model: DockModel
    @ObservedObject var usage: UsageStore
    @ObservedObject var activity: ActivityMonitor
    @ObservedObject var presentation: IslandPresentation
    let profile: Profile
    let index: Int
    @State private var hovered = false
    @FocusState private var usageFocused: Bool
    private var open: Bool { model.running[profile.id]?.isEmpty == false }
    private var entry: UsageEntry? { usage.entries[profile.id] }
    private var reading: CompactNotchReading { CompactNotchReading(entry: entry, statusLine: usage.statusLineReadings[profile.id]) }
    private var selected: Bool { presentation.compactUsageProfileID == profile.id }
    private var summary: ActivitySummary? { activity.entries[profile.id] }
    private var stateText: String {
        if let warning = model.tileWarning(profile) { return warning.text }
        if model.opening.contains(profile.id) { return "Opening…" }
        if model.closing.contains(profile.id) { return "Closing…" }
        if let text = summary?.profileStatusText { return text }
        return model.activeProfile == profile.id ? "Active" : open ? "Open" : "Closed"
    }
    private var stateColor: Color {
        if model.tileWarning(profile) != nil || (summary?.waiting ?? 0) > 0 { return .orange }
        if (summary?.working ?? 0) > 0 { return .blue }
        return .white.opacity(0.65)
    }
    private var usageContentHeight: CGFloat { CGFloat(max(48, max(30, 32 * model.preferences.scale) + 15)) }
    private var supportsUsage: Bool { profile.kind == .codex || profile.usesClaudeAccountUsage || reading.snapshot != nil }

    var body: some View {
        VStack(spacing: 4) {
            identityButton
            usageControl
            statusRow
            shortcutRow
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .frame(height: IslandLayout.compactCardHeight(scale: model.preferences.scale), alignment: .top)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
        .onChange(of: presentation.compactUsageProfileID) { previous, current in
            if previous == profile.id && current == nil { usageFocused = true }
        }
    }

    private var identityButton: some View {
            Button { model.select(profile) } label: {
                HStack(spacing: 6) {
                    ProfileBadge(model: model, profile: profile, size: 24 * model.preferences.scale, showStatus: false, activity: summary)
                    Text(profile.name).font(.system(size: 11, weight: .medium))
                        .lineLimit(2).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                }
                .padding(2).contentShape(RoundedRectangle(cornerRadius: 7))
                .background(hovered ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain).onHover { hovered = $0 }
                .disabled(model.switchingTargets[profile.kind] != nil)
                .accessibilityLabel("\(open ? "Show" : "Switch to") \(profile.name), \(model.state(profile))")
                .help("\(open ? "Show" : "Switch to") \(profile.name)" + (index < 9 ? " · ⌥⌘\(index + 1)" : ""))

    }

    @ViewBuilder
    private var usageControl: some View {
            if supportsUsage {
                Button { presentation.toggleCompactUsage(profile.id) } label: {
                    Group {
                        if !reading.windows.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(reading.windows) { window in CompactUsageRing(window: window, scale: model.preferences.scale) }
                            }
                        } else {
                            usagePlaceholder
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: usageContentHeight, maxHeight: usageContentHeight)
                    .padding(.vertical, 2)
                    .background(selected ? Color.blue.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Color.blue.opacity(0.5) : .clear, lineWidth: 1))
                    .overlay(alignment: .topTrailing) {
                        if reading.isStale(profile: profile, entry: entry, now: usage.now) {
                            Image(systemName: "clock.badge.exclamationmark").font(.system(size: 9)).foregroundStyle(.orange)
                                .help(entry?.error?.message ?? "Showing the last reading. Open usage details for its update time.")
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).focused($usageFocused)
                    .onExitCommand { if selected { presentation.closeCompactUsage() } }
                    .accessibilityLabel("Usage for \(profile.name). " + usageDescription)
                    .accessibilityValue(selected ? "Expanded" : "Collapsed")
                    .accessibilityHint("Show or hide usage details without switching accounts.")
                    .help(usageDescription + "\nClick for reset times and saved resets.")
            } else {
                Text(profile.tileCaption).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2).frame(maxWidth: .infinity, minHeight: usageContentHeight + 4, maxHeight: usageContentHeight + 4)
            }

    }

    private var statusRow: some View {
            HStack(spacing: 4) {
                StatusDot(isOpen: open, size: 5)
                Text(stateText).font(.system(size: 10)).foregroundStyle(stateColor).lineLimit(2).minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(stateText)
                Spacer(minLength: 0)
            }.frame(height: 24)
    }

    private var shortcutRow: some View {
            HStack(spacing: 2) {
                ProfileDragHandle(model: model, profile: profile).frame(width: 24, height: 18)
                Spacer(minLength: 0)
                Text(index < 9 ? "⌥⌘\(index + 1)" : " ").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                if open && profile.terminalHost == nil {
                    Button { model.requestQuit(profile) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                            .frame(width: 24, height: 18).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(model.closing.contains(profile.id))
                        .accessibilityLabel("Close \(profile.name)").help("Close \(profile.name)")
                } else {
                    Color.clear.frame(width: 24, height: 1).accessibilityHidden(true)
                }
            }.frame(height: 18)
    }

    private var usagePlaceholder: some View {
        Text(usageLabel)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(usagePlaceholderColor)
            .lineLimit(2)
            .multilineTextAlignment(.center)
    }
    private var usagePlaceholderColor: Color { entry?.error?.needsSignIn == true ? Color.orange : Color.white.opacity(0.7) }

    private var usageLabel: String {
        if entry?.error == .claudeConnectionNeeded || entry?.error == .claudeOtherAccount { return "Connect usage…" }
        return entry?.error?.statusLabel ?? (entry?.isRefreshing == true || entry?.validatingIdentity != false ? "Loading usage…" : "Usage details")
    }
    private var usageDescription: String {
        let values = reading.windows.map { "\($0.title): \(Int($0.remainingPercent.rounded())) percent remaining" }.joined(separator: ", ")
        return (values.isEmpty ? usageLabel : values) + (reading.isStale(profile: profile, entry: entry, now: usage.now) ? ". Last reading; refresh pending." : "")
    }
}

private struct CompactUsageRing: View {
    let window: UsageWindow
    let scale: Double
    private var title: String { window.duration == 18000 ? "5h" : window.title }
    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().stroke(.white.opacity(0.14), lineWidth: 3)
                Circle().trim(from: 0, to: window.remainingPercent / 100)
                    .stroke(UsageTint.remaining(window.remainingPercent).color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(window.remainingPercent.rounded()))%").font(.system(size: 10, weight: .medium)).monospacedDigit()
            }.frame(width: max(30, 32 * scale), height: max(30, 32 * scale))
            Text(title).font(.system(size: 9)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
        }.accessibilityHidden(true)
    }
}

struct CompactNotchUsageDetails: View {
    @ObservedObject var model: DockModel
    @ObservedObject var usage: UsageStore
    @ObservedObject var presentation: IslandPresentation
    let profile: Profile
    private var entry: UsageEntry? { usage.entries[profile.id] }
    private var reading: CompactNotchReading { CompactNotchReading(entry: entry, statusLine: usage.statusLineReadings[profile.id]) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(.white.opacity(0.1))
            HStack {
                Text(profile.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Text("Remaining").font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 5)
                Button { presentation.closeCompactUsage() } label: {
                    Image(systemName: "xmark").font(.system(size: 9)).frame(width: 24, height: 24)
                }.buttonStyle(.plain).accessibilityLabel("Close usage details")
            }
            if let snapshot = reading.snapshot, !snapshot.windows.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                    ForEach(snapshot.windows.sorted { $0.duration < $1.duration }) { window in
                        UsageWindowView(window: window, now: usage.now)
                    }
                }
            }
            if let error = entry?.error {
                HStack(alignment: .top, spacing: 10) {
                    Text(error.statusLabel).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2).help(error.message)
                    Spacer(minLength: 0)
                    if UsageRecoveryAction.actions(for: error).contains(.refresh) {
                        Button("Refresh") { usage.refresh(profile, force: true) }.help(error.message)
                    }
                    if UsageRecoveryAction.actions(for: error).contains(.reconnect) {
                        Button(usage.isReconnecting(profile) ? "Finish in browser…" : (error == .claudeConnectionNeeded ? "Connect usage…" : "Reconnect…")) { usage.reconnect(profile, home: model.home) }
                            .disabled(usage.isReconnecting(profile)).help(usage.reconnectionMessages[usage.connectionKey(profile)] ?? error.message)
                    }
                }.font(.system(size: 10)).buttonStyle(.plain)
            } else if reading.snapshot == nil {
                Text(entry?.validatingIdentity != false || entry?.isRefreshing == true ? "Loading usage…" : "Usage is not reported for this account.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
            }
            HStack(alignment: .top, spacing: 18) {
                if profile.usesClaudeAccountUsage && reading.snapshot?.bankedResets == nil {
                    if entry?.error != .claudeConnectionNeeded && entry?.error != .claudeOtherAccount {
                        Button("Connect saved resets…") { ClaudeResetConnection.connection(configDirectory: usage.claudeConfigPath(profile)).connect() }
                            .font(.system(size: 10)).buttonStyle(.plain)
                            .help("Connect Claude saved resets. No reset is consumed.")
                    }
                } else if profile.kind == .codex || profile.usesClaudeAccountUsage {
                    ResetInventoryView(snapshot: reading.snapshot, now: usage.now, expanded: presentation.compactResetExpanded) { presentation.toggleCompactResets() }
                }
                Spacer(minLength: 0)
                if let snapshot = reading.snapshot {
                    Text("Updated \(IslandView.age(snapshot.fetchedAt, now: usage.now)) ago")
                        .font(.system(size: 9)).foregroundStyle(reading.isStale(profile: profile, entry: entry, now: usage.now) ? .orange : .white.opacity(0.55))
                        .help("Updated at \(IslandView.absoluteDate(snapshot.fetchedAt)).")
                }
            }
            if reading.isStatusLine {
                Text("Reported by this account’s Claude Code status line.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onExitCommand { presentation.closeCompactUsage() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Usage details for \(profile.name)")
    }
}
