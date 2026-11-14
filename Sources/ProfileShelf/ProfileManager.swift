import AppKit
import DockCore

enum AppOperationError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(message) = self { return message }; return nil }
}

enum AppFiles {
    static func createLauncher(profile: Profile, executable: URL, icon: URL?, destination: URL) throws {
        guard Profile.validID(profile.id), !FileManager.default.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
        let contents = destination.appendingPathComponent("Contents")
        do {
            try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
            let manager = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let forwarder = manager.appendingPathComponent("Contents/Resources/ProfileShelfLauncher")
            let lightweight = FileManager.default.isExecutableFile(atPath: forwarder.path)
            let plus = Bundle(url: manager)?.object(forInfoDictionaryKey: "ProfileShelfBuild") as? Bool == true
            if plus && !lightweight { throw AppOperationError.message("The lightweight launcher is missing. Rebuild Profile Shelf before updating shortcuts.") }
            try FileManager.default.copyItem(at: lightweight ? forwarder : executable, to: contents.appendingPathComponent("MacOS/ProfileLauncher"))
            // Legacy and test bundles retain their original loader behavior.
            // A Plus shortcut uses the independent AppKit helper, never Sparkle.
            if !lightweight {
                let frameworks = manager.appendingPathComponent("Contents/Frameworks")
                if FileManager.default.fileExists(atPath: frameworks.path) {
                    _ = try run("/usr/bin/ditto", ["--norsrc", "--noextattr", frameworks.path, contents.appendingPathComponent("Frameworks").path])
                }
            }
            // A fresh resource name avoids reusing stale icon cache keys.
            let iconName = "AppIcon-" + UUID().uuidString
            if let icon, FileManager.default.fileExists(atPath: icon.path) { try FileManager.default.copyItem(at: icon, to: contents.appendingPathComponent("Resources/\(iconName).icns")) }
            // Keep a stable physical bundle while Finder/Dock display the chosen
            // label. Adaptation credits and MIT notices are in THIRD_PARTY_NOTICES.md.
            let stem = (destination.deletingPathExtension().lastPathComponent)
            let names = try PropertyListSerialization.data(fromPropertyList: ["CFBundleName": profile.dockDisplayName, "CFBundleDisplayName": profile.dockDisplayName], format: .binary, options: 0)
            for language in ["en", "Base"] {
                let localization = contents.appendingPathComponent("Resources/\(language).lproj")
                try FileManager.default.createDirectory(at: localization, withIntermediateDirectories: true)
                try names.write(to: localization.appendingPathComponent("InfoPlist.strings"))
            }
            let plist: [String: Any] = ["CFBundleIdentifier": "io.github.haiderali136a.profileshelf.launcher.\(profile.id)", "CFBundleName": stem, "CFBundleDisplayName": stem, "CFBundleDevelopmentRegion": "en", "CFBundleLocalizations": ["en", "Base"], "LSHasLocalizedDisplayName": true, "CFBundleExecutable": "ProfileLauncher", "CFBundlePackageType": "APPL", "CFBundleVersion": "3", "CFBundleIconFile": iconName, "LSUIElement": true, "LSMinimumSystemVersion": "14.0", "ProfileShelfProfileID": profile.id, "ProfileShelfShortcutAppearanceVersion": 3, "ProfileShelfManagerPath": manager.path, "NSAppleEventsUsageDescription": "This shortcut opens and selects its Terminal tab."]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
            _ = try run("/usr/bin/codesign", ["--force", "--sign", "-", destination.path])
            _ = try run("/usr/bin/codesign", ["--verify", "--strict", destination.path])
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
    }
    /// Commands use separate arguments, never shell interpolation. No inherited account credentials.
    static func run(_ executable: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path, "TMPDIR": NSTemporaryDirectory()]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AppOperationError.message(String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "The operation could not finish.")
        }
        return data
    }

    static func verifyVendorApp(_ url: URL) throws {
        guard Bundle(url: url)?.bundleIdentifier == "com.openai.codex" else {
            throw AppOperationError.message("Choose the current ChatGPT or Codex desktop app. ChatGPT Classic is not supported.")
        }
        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R", "=anchor apple generic and certificate leaf[subject.OU] = \"2DC432GLL2\"", url.path])
    }

    static func copyVendorApp(from source: URL, to destination: URL) throws {
        try verifyVendorApp(source)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            _ = try run("/usr/bin/ditto", [source.path, destination.path])
            try verifyVendorApp(destination)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}

@MainActor
extension DockModel {
    var installedApplications: [URL] {
        let candidates = ["/Applications/ChatGPT.app", "/Applications/Codex.app", home.appendingPathComponent("Applications/ChatGPT.app").path, home.appendingPathComponent("Applications/Codex.app").path]
            .map { URL(fileURLWithPath: $0) } + NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").compactMap(\.bundleURL)
        var seen = Set<String>()
        return candidates.filter { Bundle(url: $0)?.bundleIdentifier == "com.openai.codex" && seen.insert($0.standardizedFileURL.path).inserted }
    }
    var defaultApplication: URL? { installedApplications.first }

    var managedAppsDirectory: URL { home.appendingPathComponent("Applications/Profile Shelf Apps", isDirectory: true) }

    func applicationURL(for profile: Profile) -> URL? {
        if profile.kind == .agent, let tool = profile.agentTool {
            if tool.launchesInTerminal { return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") }
            // The scan already chose one copy among renamed, duplicate and trashed ones.
            if let installedAgents {
                return installedAgents.first { $0.id == tool.id }?.applicationPath.map { URL(fileURLWithPath: $0) }
            }
            if let url = tool.bundleIdentifiers.lazy.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first(where: { !AgentApplications.excluded($0.path) }) { return url }
            // Renamed builds (Windsurf / Devin) can be found by their app name.
            return [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")].lazy
                .flatMap { root in tool.applicationNames.map { root.appendingPathComponent($0) } }
                .first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Contents/Info.plist").path) }
        }
        if profile.kind == .agent { return nil }
        // A session in another terminal app shows that app's icon; tmux and screen show Terminal's.
        if let host = profile.terminalHost, host.contains(".") { return cachedApplicationPath([host]).map { URL(fileURLWithPath: $0) } }
        if profile.kind != .codex { return NSWorkspace.shared.urlForApplication(withBundleIdentifier: profile.kind.bundleIdentifier) }
        if let path = profile.applicationPath {
            let url = URL(fileURLWithPath: path)
            return Bundle(url: url)?.bundleIdentifier == "com.openai.codex" ? url : nil
        }
        return defaultApplication
    }

    func createProfile(name: String, separateApp: Bool, source: URL? = nil) async throws {
        guard var profile = ProfileLaunch.newProfile(name: name) else { throw AppOperationError.message("Use a name between 1 and 32 characters.") }
        guard let application = source ?? defaultApplication else { throw AppOperationError.message("Install ChatGPT first, or choose its application below.") }
        let directory = profile.home(in: home)
        guard !FileManager.default.fileExists(atPath: directory.path) else { throw CocoaError(.fileWriteFileExists) }
        let destination = managedAppsDirectory.appendingPathComponent(profile.id).appendingPathComponent("ChatGPT \(profile.name.replacingOccurrences(of: "/", with: "-")).app")
        let launcher = home.appendingPathComponent("Applications/Profile Shelf Launchers").appendingPathComponent("ChatGPT \(profile.name.replacingOccurrences(of: "/", with: "-")) \(profile.id.suffix(6)).app")
        guard let executable = Bundle.main.executableURL else { throw CocoaError(.fileNoSuchFile) }
        let icon = Bundle.main.resourceURL?.appendingPathComponent("AppIcon.icns")
        let newProfile = profile
        // The destination basename is cosmetic; the vendor's signed bundle stays unchanged.
        try await Task.detached {
            try AppFiles.verifyVendorApp(application)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            do {
                if separateApp { try AppFiles.copyVendorApp(from: application, to: destination) }
                try AppFiles.createLauncher(profile: newProfile, executable: executable, icon: icon, destination: launcher)
            } catch {
                try? FileManager.default.removeItem(at: directory)
                if separateApp { try? FileManager.default.removeItem(at: destination) }
                throw error
            }
        }.value
        if separateApp { profile.applicationPath = destination.path }
        else if application != defaultApplication { profile.applicationPath = application.path }
        profile.launcherPath = launcher.path
        preferences.profiles.append(profile)
        save()
    }

    func makeSeparateCopy(for profile: Profile) async throws {
        refresh()
        guard running[profile.id]?.isEmpty != false else { throw AppOperationError.message("Close this profile before changing its app.") }
        guard let source = applicationURL(for: profile) else { throw AppOperationError.message("The original application is missing.") }
        let destination = managedAppsDirectory.appendingPathComponent(profile.id).appendingPathComponent("ChatGPT.app")
        try await Task.detached { try AppFiles.copyVendorApp(from: source, to: destination) }.value
        var updated = profile
        updated.applicationPath = destination.path
        update(updated)
    }

    func createFinderLauncher(for profile: Profile) async throws {
        guard let executable = Bundle.main.executableURL else { throw CocoaError(.fileNoSuchFile) }
        let destination = home.appendingPathComponent("Applications/Profile Shelf Launchers").appendingPathComponent("\(profile.shortcutTitle) \(profile.name.replacingOccurrences(of: "/", with: "-")) \(profile.id.suffix(6)).app")
        let icon = Bundle.main.resourceURL?.appendingPathComponent("AppIcon.icns")
        try await Task.detached { try AppFiles.createLauncher(profile: profile, executable: executable, icon: icon, destination: destination) }.value
        var updated = profile; updated.launcherPath = destination.path; update(updated)
    }

    func useSharedAppAndTrashCopy(_ profile: Profile) throws {
        refresh()
        guard running[profile.id]?.isEmpty != false, defaultApplication != nil, let path = profile.applicationPath else {
            throw AppOperationError.message("Close this profile and make sure the shared ChatGPT app is installed first.")
        }
        let app = URL(fileURLWithPath: path)
        let parent = managedAppsDirectory.appendingPathComponent(profile.id)
        guard app.deletingLastPathComponent().standardizedFileURL == parent.standardizedFileURL,
              parent.resolvingSymlinksInPath() == parent.standardizedFileURL else {
            throw AppOperationError.message("Only copies created by Profile Shelf can be moved to the Trash here.")
        }
        try FileManager.default.trashItem(at: parent, resultingItemURL: nil)
        var changed = profile; changed.applicationPath = nil; update(changed)
    }

    func removeProfile(_ profile: Profile, trashData: Bool) throws {
        refresh()
        // A shared desktop agent entry owns no data, so an app that is always open (an editor) can lose its tile while it runs.
        let ownsNothing = profile.kind == .agent && !profile.usesIsolatedAgentHome && profile.agentTool?.launchesInTerminal == false
        guard ownsNothing || running[profile.id]?.isEmpty != false, !opening.contains(profile.id), !nativeDockOperations.contains(profile.id) else { throw AppOperationError.message("Close this profile before removing it.") }
        if trashData && (!profile.id.hasPrefix("profile-") || !Profile.validID(profile.id) || profile.adoptedHome != nil) {
            throw AppOperationError.message("Imported profiles can be removed from Profile Shelf, but their original data is kept.")
        }
        if profile.dockApplicationPath != nil {
            guard let app = nativeDockURL(for: profile) else { throw AppOperationError.message("The native Dock copy could not be verified. Disable or repair it before removing the profile.") }
            try FileManager.default.trashItem(at: app, resultingItemURL: nil)
        }
        if trashData {
            guard profile.id.hasPrefix("profile-"), Profile.validID(profile.id) else {
                throw AppOperationError.message("Imported profiles can be removed from Profile Shelf, but their original data is kept.")
            }
            let fm = FileManager.default
            let directory = profile.home(in: home)
            // Trash only exact directories owned by this manager. Never follow a substituted symlink.
            guard directory.resolvingSymlinksInPath().path == directory.standardizedFileURL.path else { throw CocoaError(.fileWriteNoPermission) }
            if fm.fileExists(atPath: directory.path) { try fm.trashItem(at: directory, resultingItemURL: nil) }
            if let path = profile.applicationPath {
                let app = URL(fileURLWithPath: path)
                let parent = managedAppsDirectory.appendingPathComponent(profile.id)
                if app.deletingLastPathComponent().standardizedFileURL == parent.standardizedFileURL,
                   parent.resolvingSymlinksInPath() == parent.standardizedFileURL, fm.fileExists(atPath: parent.path) {
                    try fm.trashItem(at: parent, resultingItemURL: nil)
                }
            }
        }
        if let path = profile.launcherPath {
            let launcher = URL(fileURLWithPath: path)
            let root = home.appendingPathComponent("Applications/Profile Shelf Launchers").resolvingSymlinksInPath()
            if launcher.resolvingSymlinksInPath().deletingLastPathComponent() == root,
               Bundle(url: launcher)?.object(forInfoDictionaryKey: "ProfileShelfProfileID") as? String == profile.id {
                try FileManager.default.trashItem(at: launcher, resultingItemURL: nil)
            }
        }
        preferences.profiles.removeAll { $0.id == profile.id }
        rememberDismissal(of: profile)
        var retained = profile; retained.launcherPath = nil; retained.dockApplicationPath = nil
        preferences.removedProfiles = (preferences.removedProfiles ?? []).filter { $0.id != profile.id } + [retained]
        preferences.hiddenProfileIDs = Array(Set((preferences.hiddenProfileIDs ?? []) + [profile.id]))
        save()
    }

    func restoreImportedProfiles() {
        preferences.hiddenProfileIDs = []
        for profile in preferences.removedProfiles ?? [] where FileManager.default.fileExists(atPath: profile.home(in: home).path) && !preferences.profiles.contains(where: { $0.id == profile.id }) {
            preferences.profiles.append(profile)
        }
        preferences.removedProfiles = (preferences.removedProfiles ?? []).filter { item in !preferences.profiles.contains(where: { $0.id == item.id }) }
        if let discovered = try? ProfileCatalog.discover(home: home) {
            for profile in discovered where !preferences.profiles.contains(where: { $0.id == profile.id }) { preferences.profiles.append(profile) }
        }
        save()
    }
}
