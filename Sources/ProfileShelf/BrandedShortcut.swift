import AppKit
import DockCore
import CoreServices

extension DockModel {
    // Contents-only installation and localized display names adapted from
    // Launcher adaptation credits and MIT notices are in THIRD_PARTY_NOTICES.md.
    // See THIRD_PARTY_NOTICES.md for the retained license.
    /// Generated launchers only. Official apps and account data are never changed.
    /// A profile-specific parent permits duplicate labels without visible ID suffixes.
    func updateBrandedShortcut(for profile: Profile, reveal: Bool = false) async throws {
        guard Profile.validID(profile.id), profile.kind == .codex || profile.kind == .claude,
              switchingTargets[profile.kind] == nil, !shortcutOperations.contains(profile.id), let executable = Bundle.main.executableURL else {
            throw AppOperationError.message("Wait for the current action before updating the shortcut.")
        }
        shortcutOperations.insert(profile.id)
        defer { shortcutOperations.remove(profile.id) }
        let root = home.appendingPathComponent("Applications/Profile Shelf Launchers").standardizedFileURL
        let folder = root.appendingPathComponent(profile.id).standardizedFileURL
        let fm = FileManager.default
        for directory in [root, folder] {
            guard directory.resolvingSymlinksInPath().path == directory.path else {
                throw AppOperationError.message("The shortcuts folder is linked elsewhere and was left unchanged.")
            }
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        // Permit our previous flat layout, and recreate a shortcut the user deleted.
        let previous = profile.launcherPath.map { URL(fileURLWithPath: $0).standardizedFileURL }
        if let previous {
            guard [root.path, folder.path].contains(previous.deletingLastPathComponent().path),
                  previous.resolvingSymlinksInPath().path == previous.path else {
                throw AppOperationError.message("The existing shortcut is outside its managed folder and was left unchanged.")
            }
        }
        // Keep existing bundle paths and directory identities so pinned Dock
        // references survive. Localized names hide old implementation suffixes.
        let destination = previous ?? folder.appendingPathComponent(profile.dockShortcutFilename)
        let vendor = applicationURL(for: profile).map { NSWorkspace.shared.icon(forFile: $0.path) }
        if profile.usesOriginalAppIcon == true && vendor == nil {
            throw AppOperationError.message("Locate the original app before restoring its icon.")
        }
        let icon = try NativeDockApp.icon(profile: profile, image: image(for: profile), vendor: vendor, organization: organizationBadge(for: profile))
        try await Task.detached {
            let fm = FileManager.default
            func verify(_ url: URL) throws {
                guard url.resolvingSymlinksInPath().path == url.path,
                      url.appendingPathComponent("Contents").resolvingSymlinksInPath().path == url.appendingPathComponent("Contents").path,
                      let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
                      let info = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                      info["ProfileShelfProfileID"] as? String == profile.id,
                      info["CFBundleIdentifier"] as? String == "io.github.haiderali136a.profileshelf.launcher.\(profile.id)" else {
                    throw AppOperationError.message("The existing shortcut could not be verified and was left unchanged.")
                }
            }
            let temporary = fm.temporaryDirectory.appendingPathComponent("profile-shelf-shortcut-" + UUID().uuidString)
            try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: temporary) }
            let iconURL = temporary.appendingPathComponent("AppIcon.icns")
            try icon.write(to: iconURL)
            let stagingRoot = folder.appendingPathComponent(".prepared-" + UUID().uuidString)
            try fm.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: stagingRoot) }
            let staged = stagingRoot.appendingPathComponent(destination.lastPathComponent)
            defer { if fm.fileExists(atPath: staged.path) { try? fm.removeItem(at: staged) } }
            try AppFiles.createLauncher(profile: profile, executable: executable, icon: iconURL, destination: staged)
            // Recheck both directories and ownership after preparation, before replacing anything.
            guard root.resolvingSymlinksInPath().path == root.path, folder.resolvingSymlinksInPath().path == folder.path else {
                throw AppOperationError.message("The shortcuts folder changed during preparation.")
            }
            if fm.fileExists(atPath: destination.path) {
                try verify(destination)
                let installed = destination.appendingPathComponent("Contents")
                let backup = folder.appendingPathComponent(".previous-Contents-" + UUID().uuidString)
                try fm.moveItem(at: installed, to: backup)
                do {
                    try fm.moveItem(at: staged.appendingPathComponent("Contents"), to: installed)
                } catch {
                    do { try fm.moveItem(at: backup, to: installed) }
                    catch {
                        throw AppOperationError.message("Shortcut update failed. The previous shortcut contents are preserved at \(backup.path).")
                    }
                    throw error
                }
                try? fm.removeItem(at: backup)
            } else {
                try fm.moveItem(at: staged, to: destination)
            }
        }.value
        if var current = preferences.profiles.first(where: { $0.id == profile.id }) {
            current.launcherPath = destination.path
            update(current)
        }
        _ = LSRegisterURL(destination as CFURL, true)
        if reveal { NSWorkspace.shared.activateFileViewerSelecting([destination]) }
    }
}

extension DockModel {
    /// Explicit maintenance action. Missing/deleted or externally stored
    /// shortcuts are skipped; no user profile or account directory is removed.
    func upgradeManagedShortcuts() async {
        guard switchingTargets.isEmpty, shortcutOperations.isEmpty, !upgradingShortcuts else { return }
        upgradingShortcuts = true
        defer { upgradingShortcuts = false }
        var updated = 0
        for saved in preferences.profiles where saved.kind == .codex || saved.kind == .claude {
            guard let profile = preferences.profiles.first(where: { $0.id == saved.id }),
                  let path = profile.launcherPath, FileManager.default.fileExists(atPath: path),
                  switchingTargets[profile.kind] == nil else { continue }
            do { try await updateBrandedShortcut(for: profile); updated += 1 }
            catch { showProfileMessage("Some shortcuts could not be updated. Open that profile’s settings and retry.", for: profile); return }
        }
        message = "Updated \(updated) profile shortcuts. Account data was unchanged."
    }
}
