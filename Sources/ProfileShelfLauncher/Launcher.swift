import AppKit
import Foundation
import Darwin

/// Tiny forwarding process: no DockModel, account storage, polling or Sparkle.
/// The one manager remains responsible for profile validation and switch locks.
@main
@MainActor
struct ProfileShelfLauncher {
    static func main() {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "ProfileShelfProfileID") as? String,
              !id.isEmpty, id.range(of: "^[a-zA-Z0-9][a-zA-Z0-9_-]*$", options: .regularExpression) != nil else {
            fail("This shortcut has no valid profile reference.")
        }
        if CommandLine.arguments.contains("--validate-launcher") { print(id); return }
        let managers = NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.haiderali136a.profileshelf")
        if managers.contains(where: { $0.bundleURL.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "ProfileShelfBuild") as? Bool } == true }) {
            DistributedNotificationCenter.default().postNotificationName(Notification.Name("ProfileShelf.OpenProfile"), object: nil,
                userInfo: ["profileID": id], deliverImmediately: true)
            return
        }
        guard managers.isEmpty else { fail("Quit the other profile manager and open Profile Shelf before using this shortcut.") }
        guard let path = Bundle.main.object(forInfoDictionaryKey: "ProfileShelfManagerPath") as? String else {
            fail("Open Profile Shelf and recreate this shortcut from profile settings.")
        }
        let manager = URL(fileURLWithPath: path)
        guard let bundle = Bundle(url: manager), bundle.bundleIdentifier == "io.github.haiderali136a.profileshelf",
              bundle.object(forInfoDictionaryKey: "ProfileShelfBuild") as? Bool == true else {
            fail("The manager moved or is unavailable. Open Profile Shelf and update this shortcut.")
        }
        var finished = false
        var failure: String?
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--select-profile", id]
        NSWorkspace.shared.openApplication(at: manager, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                failure = error == nil ? nil : "Could not open Profile Shelf. Open it from Applications and retry."
                finished = true
            }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 15
        while !finished, ProcessInfo.processInfo.systemUptime < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        if let failure { fail(failure) }
        if !finished { fail("The manager is taking longer to open. Check it in Applications before retrying.") }
    }
    static func fail(_ message: String) -> Never {
        if !CommandLine.arguments.contains("--validate-launcher") {
            let application = NSApplication.shared
            application.setActivationPolicy(.accessory)
            application.activate(ignoringOtherApps: true)
            let alert = NSAlert(); alert.messageText = "Could not open profile"; alert.informativeText = message
            alert.runModal()
        }
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}

