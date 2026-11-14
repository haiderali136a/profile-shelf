import AppKit
import DockCore

extension DockModel {
    func canOpenAlongside(_ profile: Profile) -> Bool {
        running[profile.id]?.isEmpty != false && !opening.contains(profile.id)
            && !desktopLaunchInFlight.contains(profile.id)
            && !closing.contains(profile.id) && switchingTargets[profile.kind] == nil
    }

    /// Focus never closes intentional parallel work. Opening a closed desktop
    /// account is a serialized transaction; existing provider launchers are reused.
    func select(_ profile: Profile, mode: ProfileOpenMode = .switchProfile) {
        guard let appKey = DesktopProfileApp(rawValue: profile.kind.rawValue) else { selectAlongside(profile); return }
        refresh()
        recordSwitch(profile, stage: .requested)
        if mode == .alongside {
            guard canOpenAlongside(profile) else { recordSwitch(profile, stage: .blocked, code: .busy); return }
            selectAlongside(profile)
            return
        }
        guard switchingTargets[profile.kind] == nil else {
            recordSwitch(profile, stage: .blocked, code: .busy)
            message = "An account switch is in progress. Wait for it to finish."
            return
        }
        let snapshot = desktopSwitchSnapshot(profile.kind)
        let pending = providerHasPendingAction(profile.kind)
        switch ProfileSwitchPolicy.plan(targetID: profile.id, provider: appKey, mode: .switchProfile,
            processes: snapshot.facts, unresolved: snapshot.unresolved, pending: pending) {
        case .focus: recordSwitch(profile, stage: .confirmed); selectAlongside(profile)
        case .blocked:
            recordSwitch(profile, stage: .blocked, code: .identityUnknown)
            showProfileMessage("A running account could not be safely identified, or another account is opening or closing. Finish that action and retry. Nothing was closed.", for: profile)
        case .open, .quit:
            switchingTargets[profile.kind] = profile.id
            profileSwitchTasks[profile.kind] = Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.switchingTargets[profile.kind] = nil; self.switchStages[profile.kind] = nil; self.profileSwitchTasks[profile.kind] = nil }
                do { try await self.switchDesktopAccount(profile, provider: appKey) }
                catch {
                    self.recordSwitch(profile, stage: .failed, code: .operationFailed)
                    self.showProfileMessage(error.localizedDescription, for: profile)
                }
            }
        }
    }

    private func providerHasPendingAction(_ provider: ProfileProvider) -> Bool {
        preferences.profiles.contains { $0.kind == provider && (opening.contains($0.id) || closing.contains($0.id) || desktopLaunchInFlight.contains($0.id)) }
    }

    private func switchDesktopAccount(_ requested: Profile, provider: DesktopProfileApp) async throws {
        var target = try preflightSwitch(requested)
        if target.kind == .codex, target.dockApplicationPath != nil, nativeDockNeedsRebuild(target) {
            try await setNativeDockIcon(for: target, enabled: true)
            target = try preflightSwitch(requested)
        }
        recordSwitch(target, stage: .prepared)
        refresh()
        let current = desktopSwitchSnapshot(target.kind)
        let decision = ProfileSwitchPolicy.plan(targetID: target.id, provider: provider, mode: .switchProfile,
            processes: current.facts, unresolved: current.unresolved, pending: providerHasPendingAction(target.kind))
        switch decision {
        case .focus: recordSwitch(target, stage: .confirmed); selectAlongside(target); return
        case .blocked: throw AppOperationError.message("The running accounts changed during preparation. Nothing was closed; retry the switch.")
        case .open: break
        case .quit(let pids):
            let ids = Set(pids)
            let instances = current.applications.filter { ids.contains($0.processIdentifier) }
            guard instances.count == ids.count else {
                throw AppOperationError.message("Could not verify every running account. Nothing was closed.")
            }
            let closingIDs = Set(current.facts.filter { ids.contains($0.pid) }.compactMap(\.profileID))
            recordSwitch(target, stage: .quitting)
            closing.formUnion(closingIDs)
            defer { closing.subtract(closingIDs) }
            message = "Waiting for the other accounts to quit. Finish any confirmation in their windows."
            for instance in instances {
                guard instance.terminate() else {
                    throw AppOperationError.message("An account declined to quit. The switch stopped; check its window. No new account was opened.")
                }
            }
            let deadline = ProcessInfo.processInfo.systemUptime + 30
            var settledSince: TimeInterval?
            var ready = false
            while ProcessInfo.processInfo.systemUptime < deadline {
                try Task.checkCancellation()
                refresh()
                let snapshot = desktopSwitchSnapshot(target.kind)
                let stillRunning = Set(instances.filter { !$0.isTerminated }.map(\.processIdentifier))
                switch ProfileSwitchPolicy.afterQuit(targetID: target.id, provider: provider,
                    originalPIDs: ids, stillRunning: stillRunning, processes: snapshot.facts, unresolved: snapshot.unresolved) {
                case .changed:
                    throw AppOperationError.message("Another account opened during the switch. The switch stopped; no additional account was closed.")
                case .waiting: settledSince = nil
                case .ready:
                    let now = ProcessInfo.processInfo.systemUptime
                    if settledSince == nil { settledSince = now }
                    ready = now - (settledSince ?? now) >= 1
                }
                if ready { break }
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            guard ready else {
                throw AppOperationError.message("The app has not finished quitting or its identity is temporarily unreadable. Check its window, then retry. Nothing was force-quit.")
            }
            closing.subtract(closingIDs)
            recordSwitch(target, stage: .settled)
        }
        target = try preflightSwitch(requested)
        try await launchAndConfirm(target)
    }

    /// Launch Services completing is not account readiness. Wait for a stable,
    /// verified target PID, even if an earlier callback already cleared opening.
    /// Retry once only when the launcher finished and no same-provider process
    /// remains. Unknown/running processes never trigger a duplicate launch.
    private func launchAndConfirm(_ requested: Profile) async throws {
        var lastFailure = "The selected account did not appear."
        for attempt in 0..<2 {
            let target = try preflightSwitch(requested)
            try Task.checkCancellation()
            refresh()
            let before = desktopSwitchSnapshot(target.kind)
            guard !before.unresolved, before.facts.allSatisfy({ $0.profileID == target.id }) else {
                throw AppOperationError.message("The app is still starting or another account appeared. Wait for it to settle, then retry; no extra instance was launched.")
            }
            desktopLaunchErrors[target.id] = nil
            if before.facts.isEmpty {
                recordSwitch(target, stage: .launching, attempt: attempt + 1)
                selectAlongside(target)
            }
            var confirmation = ProfileLaunchConfirmation()
            let deadline = ProcessInfo.processInfo.systemUptime + 32
            while ProcessInfo.processInfo.systemUptime < deadline {
                try Task.checkCancellation()
                refresh()
                let snapshot = desktopSwitchSnapshot(target.kind)
                let pids = Set(snapshot.facts.filter { $0.profileID == target.id }.map(\.pid))
                if snapshot.facts.contains(where: { $0.profileID != nil && $0.profileID != target.id }) {
                    throw AppOperationError.message("Another account opened while the target was starting. Check the app windows before retrying.")
                }
                if confirmation.observe(pids: pids, readable: !snapshot.unresolved && snapshot.facts.allSatisfy({ $0.profileID == target.id }), at: ProcessInfo.processInfo.systemUptime) {
                    recordSwitch(target, stage: .confirmed, attempt: attempt + 1)
                    message = nil
                    return
                }
                if let error = desktopLaunchErrors[target.id], !desktopLaunchInFlight.contains(target.id), snapshot.facts.isEmpty, !snapshot.unresolved {
                    lastFailure = error
                    break
                }
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            refresh()
            let after = desktopSwitchSnapshot(target.kind)
            guard attempt == 0, !after.unresolved, after.facts.isEmpty,
                  !desktopLaunchInFlight.contains(target.id), !opening.contains(target.id) else {
                throw AppOperationError.message("Could not confirm \(target.name) opened. \(desktopLaunchErrors[target.id] ?? lastFailure) Check its app window before retrying.")
            }
            recordSwitch(target, stage: .retrying, attempt: attempt + 1)
            message = "The app did not finish opening. Retrying \(target.name) once…"
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    func beginDesktopLaunch(_ profile: Profile) -> UUID {
        let token = UUID()
        desktopLaunchTokens[profile.id] = token
        desktopLaunchInFlight.insert(profile.id)
        desktopLaunchErrors[profile.id] = nil
        return token
    }
    func completeDesktopLaunch(_ profile: Profile, token: UUID, error: String? = nil, exitStatus: Int32? = nil) {
        guard desktopLaunchTokens[profile.id] == token else { return }
        desktopLaunchInFlight.remove(profile.id)
        recordSwitch(profile, stage: .launcherFinished, code: error == nil ? nil : .launchRejected, exitStatus: exitStatus)
        if let error {
            desktopLaunchErrors[profile.id] = error
            opening.remove(profile.id)
            showProfileMessage(error, for: profile)
        }
    }
    func scheduleDesktopLaunchTimeout(_ profile: Profile, token: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.desktopLaunchTimedOut(profile, token: token)
        }
    }
    /// Also callable by fixture tests without waiting 30 seconds or launching apps.
    func desktopLaunchTimedOut(_ profile: Profile, token: UUID) {
        guard desktopLaunchTokens[profile.id] == token, opening.contains(profile.id) else { return }
        refresh()
        if opening.remove(profile.id) != nil {
            let detail = "\(profile.name) has not appeared yet. Check its app window before retrying."
            desktopLaunchErrors[profile.id] = detail
            recordSwitch(profile, stage: .failed, code: .observationTimeout)
            showProfileMessage(detail, for: profile)
        }
    }

    private func preflightSwitch(_ requested: Profile) throws -> Profile {
        guard let target = preferences.profiles.first(where: { $0.id == requested.id && $0.kind == requested.kind }),
              Profile.validID(target.id), FileManager.default.fileExists(atPath: target.home(in: home).path),
              let app = applicationURL(for: target), FileManager.default.fileExists(atPath: app.path) else {
            throw AppOperationError.message("The target account or its app is missing. The selected account was not opened.")
        }
        let sameProvider = preferences.profiles.filter { $0.kind == target.kind }
        guard let executable = Bundle(url: app)?.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw AppOperationError.message("The selected app has no usable executable. Reinstall or locate the app before switching.")
        }
        guard sameProvider.allSatisfy({ !nativeDockOperations.contains($0.id) }),
              sameProvider.allSatisfy({ profile in
                  guard let url = applicationURL(for: profile) else { return true }
                  return !updatingApplications.contains(url.resolvingSymlinksInPath().standardizedFileURL.path)
              }) else { throw AppOperationError.message("Wait for the app update or Dock-copy preparation to finish before switching.") }
        if target.kind == .codex, target.dockApplicationPath != nil, !nativeDockNeedsRebuild(target) {
            guard let wrapper = nativeDockURL(for: target), let executable = Bundle(url: wrapper)?.executableURL,
                  FileManager.default.isExecutableFile(atPath: executable.path) else {
                throw AppOperationError.message("The target account’s Dock copy needs repair. Rebuild it from profile settings before switching.")
            }
        }
        // Prepare only empty directories before asking another account to quit.
        // No token, cookie, database, lock-file or Keychain entry is changed.
        var directories: [URL] = []
        if target.kind == .codex {
            directories = [target.home(in: home)]
            if target.id != "default" { directories.append(target.home(in: home).appendingPathComponent("electron-user-data")) }
        } else if target.usesSeparateClaudeAccount {
            directories = [target.claudeConfigDirectory(in: home), target.claudeUserDataDirectory(in: home)].compactMap { $0 }
        }
        for directory in directories {
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  FileManager.default.isWritableFile(atPath: directory.path) else {
                throw AppOperationError.message("The selected account’s data folder is not writable. Fix its permissions before switching.")
            }
        }
        return target
    }

    /// Reuse the verified running-app objects and profile assignments.
    /// Unassigned main processes block switching rather than being guessed/quit.
    private func desktopSwitchSnapshot(_ provider: ProfileProvider) -> (applications: [RunningProfileApplication], facts: [ProfileSwitchProcess], unresolved: Bool) {
        var unresolved = provider == .codex && unreadableProcesses
        let applications: [RunningProfileApplication]
        if provider == .codex { applications = observedApplications.filter { !$0.isTerminated } }
        else {
            let candidates = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == ProfileProvider.claude.bundleIdentifier && !$0.isTerminated }
            applications = candidates.compactMap { RunningProfileApplication($0) }
            if applications.count != candidates.count { unresolved = true }
        }
        var owners: [pid_t: String] = [:]
        for profile in preferences.profiles where profile.kind == provider {
            for app in running[profile.id] ?? [] {
                if let previous = owners[app.processIdentifier], previous != profile.id { unresolved = true }
                owners[app.processIdentifier] = profile.id
            }
        }
        let facts = applications.map { ProfileSwitchProcess(pid: $0.processIdentifier, provider: provider == .codex ? .codex : .claude, profileID: owners[$0.processIdentifier]) }
        return (applications, facts, unresolved)
    }
}
