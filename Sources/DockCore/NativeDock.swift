import Foundation

/// Adapted from bartekczyz/ai-profiles 1.2.0 (MIT); see THIRD_PARTY_NOTICES.md.
public enum NativeDock {
    public static let prefix = "io.github.haiderali136a.profileshelf.native."
    public static let profileKey = "ProfileShelfNativeProfileID"
    public static let homeKey = "ProfileShelfNativeHome"
    public static let dataKey = "ProfileShelfNativeUserData"
    public static let versionKey = "ProfileShelfNativeVendorVersion"
    public static let artworkVersionKey = "ProfileShelfNativeArtworkVersion"
    public static let artworkVersion = 2
    public static let sourceKey = "ProfileShelfNativeSourceApp"
    public static let managerKey = "ProfileShelfNativeManager"

    public static func sourceChanged(_ info: [String: Any]) -> Bool {
        guard let path = info[sourceKey] as? String,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist")),
              let source = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let version = source["CFBundleVersion"] as? String else { return false }
        return version != info[versionKey] as? String
    }

    public static func identifier(_ profile: Profile) -> String { prefix + profile.id }

    public static func patchedInfo(_ vendor: [String: Any], profile: Profile, home: URL, data: URL) throws -> [String: Any] {
        guard Profile.validID(profile.id),
              let executable = vendor["CFBundleExecutable"] as? String,
              !executable.isEmpty, executable == URL(fileURLWithPath: executable).lastPathComponent,
              let version = vendor["CFBundleVersion"] as? String else { throw CocoaError(.fileReadCorruptFile) }
        var info = vendor.filter { key, _ in
            !["CFBundleIconName", "CFBundleURLTypes", "CFBundleDocumentTypes"].contains(key)
                && !(key.hasPrefix("UT") && key.hasSuffix("TypeDeclarations"))
                && !key.hasPrefix("SU")
        }
        // Electron locates its helper apps using CFBundleName. Preserve it.
        info["CFBundleIdentifier"] = identifier(profile)
        info["CFBundleDisplayName"] = profile.dockDisplayName
        info["CFBundleIconFile"] = "ProfileShelfProfile.icns"
        info["LSUIElement"] = false
        info["SUEnableAutomaticChecks"] = false
        info["SUAllowsAutomaticUpdates"] = false
        info[profileKey] = profile.id
        info[homeKey] = profile.home(in: home).path
        info[dataKey] = data.path
        info[versionKey] = version
        info[artworkVersionKey] = artworkVersion
        info["ProfileShelfNativeColor"] = profile.color
        info["ProfileShelfNativeImage"] = profile.iconFilename ?? ""
        info["ProfileShelfNativeOrganizationBadge"] = profile.organizationBadgeFilename ?? ""
        info["ProfileShelfNativeOriginalIcon"] = profile.usesOriginalAppIcon == true
        info["ProfileShelfNativeIconStyle"] = profile.profileIconStyle.rawValue
        info["ProfileShelfNativeIconText"] = profile.dockLetters
        return info
    }

    public static func entitlements(_ source: [String: Any], team: String) -> [String: Any] {
        let removed: Set<String> = ["com.apple.application-identifier", "application-identifier", "com.apple.developer.team-identifier", "keychain-access-groups", "com.apple.security.application-groups", "com.apple.developer.aps-environment", "com.apple.developer.associated-domains"]
        func clean(_ value: Any) -> Any? {
            if let text = value as? String { return text.hasPrefix(team + ".") ? nil : text }
            if let array = value as? [Any] { let kept = array.compactMap(clean); return !array.isEmpty && kept.isEmpty ? nil : kept }
            if let dictionary = value as? [String: Any] { let kept = dictionary.compactMapValues(clean); return !dictionary.isEmpty && kept.isEmpty ? nil : kept }
            return value
        }
        var result = source.filter { !removed.contains($0.key) }.compactMapValues(clean)
        result["com.apple.security.cs.disable-library-validation"] = true
        return result
    }

    public static func launchParameters(info: [String: Any], arguments: [String]) throws -> (home: String, data: String, arguments: [String]) {
        guard let id = info[profileKey] as? String, Profile.validID(id),
              info["CFBundleIdentifier"] as? String == prefix + id,
              let home = info[homeKey] as? String, home.hasPrefix("/"), !home.contains("\0"),
              let data = info[dataKey] as? String, data.hasPrefix("/"), !data.contains("\0") else { throw CocoaError(.fileReadCorruptFile) }
        var kept: [String] = [], skip = false
        for argument in arguments {
            if skip { skip = false; continue }
            if argument == "--user-data-dir" { skip = true; continue }
            if argument.hasPrefix("--user-data-dir=") || argument.hasPrefix("-psn_") { continue }
            kept.append(argument)
        }
        return (home, data, ["--user-data-dir=\(data)"] + kept)
    }
}
