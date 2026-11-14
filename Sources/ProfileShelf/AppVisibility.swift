import AppKit

enum AppVisibility {
    static func menuBarVisible(preferences: Preferences) -> Bool {
        preferences.showMenuBarIcon != false || preferences.showNotch == false
    }

    static func activationPolicy(preferences: Preferences, settingsOpen: Bool) -> NSApplication.ActivationPolicy {
        // Accessory apps cannot own a menu bar. Temporarily become a regular
        // app while Settings is open, then restore the background preference.
        preferences.showDockIcon == true || settingsOpen ? .regular : .accessory
    }
}

extension Notification.Name {
    static let profileShelfShowGeneralSettings = Notification.Name("io.github.haiderali136a.profileshelf.show-settings")
    static let profileShelfShowProfiles = Notification.Name("io.github.haiderali136a.profileshelf.show-profiles")
    static let profileShelfShowSearch = Notification.Name("io.github.haiderali136a.profileshelf.show-search")
    static let profileShelfAddProfile = Notification.Name("io.github.haiderali136a.profileshelf.add-profile")
    static let profileShelfShowSupport = Notification.Name("io.github.haiderali136a.profileshelf.show-support")
    static let profileShelfShowAbout = Notification.Name("io.github.haiderali136a.profileshelf.show-about")
    static let profileShelfShowUpdates = Notification.Name("io.github.haiderali136a.profileshelf.show-updates")
}

/// Content limits exclude the title bar and leave room for the menu bar and Dock.
enum CompactWindowLayout {
    static func limits(available: NSSize) -> (minimum: NSSize, maximum: NSSize) {
        let width = min(520, max(1, available.width - 32))
        let height = min(640, max(1, available.height * 0.8))
        return (NSSize(width: min(400, width), height: min(420, height)), NSSize(width: width, height: height))
    }
}
