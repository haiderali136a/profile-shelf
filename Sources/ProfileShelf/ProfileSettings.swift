import AppKit
import SwiftUI
import DockCore

enum NativeDockDisclosure {
    static let text = "Profile Shelf creates a local ChatGPT copy with this profile's icon. It replaces OpenAI's signature, removes vendor-only permissions and disables library validation, so some macOS protections and integrations differ. You may need to sign in again. The copy’s own updater is disabled; Profile Shelf rebuilds it from the updated original. Your original app and profile data are kept. To switch back, quit this profile’s Dock app and disable the option. Profile Shelf verifies the original app’s signature before removing the copy."
}

struct ProfileSettingsSheet: View {
    @ObservedObject var model: DockModel
    let profileID: String
    let tagging: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hex = ""
    @State private var busy = false
    @State private var initialProfile: Profile?
    @State private var consent = false
    @State private var advancedNative = false
    @State private var error: String?
    @State private var failedWork: (@MainActor () async throws -> Void)?
    private var profile: Profile? { model.preferences.profiles.first { $0.id == profileID } }
    private var nativeProgress: NativeDockStage? { model.nativeDockProgress[profileID] }
    private var isBusy: Bool { busy || model.nativeDockOperations.contains(profileID) || model.shortcutOperations.contains(profileID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edit Profile").font(.system(size: 20, weight: .semibold))
                    Text(profile?.name ?? "Profile settings").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            Divider()
            ScrollView {
                if let profile {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(spacing: 18) {
                            Image(nsImage: artwork(profile)).resizable().frame(width: 76, height: 76)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Profile name").font(.caption).foregroundStyle(.secondary)
                                TextField("Name", text: Binding(get: { profile.name }, set: { value in edit { $0.name = value } })).textFieldStyle(.roundedBorder)
                                Text(profile.accountCaption).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        GroupBox("Profile appearance") {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 8) {
                                    ForEach(DockIconStyle.allCases, id: \.self) { style in
                                        Button { edit { $0.dockIconStyle = style; $0.usesOriginalAppIcon = false } } label: {
                                            VStack(spacing: 5) {
                                                Image(nsImage: artwork(profile, style: style)).resizable().frame(width: 52, height: 52)
                                                Text(style == .chatgpt ? "Tinted logo" : style.label).font(.caption)
                                            }.frame(maxWidth: .infinity).padding(.vertical, 9)
                                                .background(profile.usesOriginalAppIcon != true && profile.profileIconStyle == style ? Color.accentColor.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(profile.usesOriginalAppIcon != true && profile.profileIconStyle == style ? Color.accentColor : Color.secondary.opacity(0.15)))
                                        }.buttonStyle(.plain).accessibilityLabel("\(style.label) profile icon").accessibilityAddTraits(profile.usesOriginalAppIcon != true && profile.profileIconStyle == style ? .isSelected : [])
                                    }
                                }
                                if profile.kind == .codex || profile.kind == .claude {
                                    Button("Use original app icon") { edit { $0.restoreOriginalAppIcon() } }
                                        .disabled(profile.usesOriginalAppIcon == true)
                                    Text(profile.usesOriginalAppIcon == true ? "Using the original app icon, without a badge or tint." : "Restore this profile’s original app icon without changing its name or account.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                HStack(spacing: 12) {
                                    ColorPicker("Profile color", selection: Binding(get: { Color(nsColor: NSColor(hex: profile.color)) }, set: { color in
                                        guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return }
                                        hex = String(format: "%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
                                        edit { $0.color = hex }
                                    }), supportsOpacity: false)
                                    Text("#").foregroundStyle(.secondary)
                                    TextField("377CF6", text: $hex).font(.body.monospaced()).textFieldStyle(.roundedBorder).frame(width: 95).accessibilityLabel("Profile color hex code")
                                        .onChange(of: hex) { _, value in
                                            let candidate = value.replacingOccurrences(of: "#", with: "").uppercased()
                                            if candidate.range(of: "^[0-9A-F]{6}$", options: .regularExpression) != nil { edit { $0.color = candidate } }
                                        }
                                }
                                if profile.profileIconStyle == .initials {
                                    TextField("Letters (leave empty for initials)", text: Binding(get: { profile.dockIconText ?? "" }, set: { value in edit { $0.dockIconText = String(value.prefix(3)) } }))
                                        .textFieldStyle(.roundedBorder).accessibilityLabel("Profile icon letters, up to three")
                                }
                                if profile.profileIconStyle == .image {
                                    HStack {
                                        Button(profile.iconFilename == nil ? "Choose image…" : "Replace image…") { model.chooseImage(for: profile, window: NSApp.keyWindow) }
                                        if profile.iconFilename != nil { Button("Remove image") { model.removeImage(for: profile) } }
                                    }
                                    Text("Images fill the rounded icon. Wide or tall images are cropped from the center.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                HStack {
                                    Button(profile.organizationBadgeFilename == nil ? "Choose organization logo…" : "Replace organization logo…") {
                                        model.chooseImage(for: profile, window: NSApp.keyWindow, organizationBadge: true)
                                    }
                                    if profile.organizationBadgeFilename != nil { Button("Remove badge") { edit { $0.organizationBadgeFilename = nil } } }
                                }
                                Text("Organization badges are chosen from local files and are not uploaded.").font(.caption).foregroundStyle(.secondary)
                                Text("Used in Profile Shelf’s notch, menu and profile list, and in generated shortcuts. This does not change the official running app’s Dock icon.").font(.caption).foregroundStyle(.secondary)
                            }.padding(10)
                        }
                        if profile.kind == .codex || profile.kind == .claude {
                        GroupBox("Dock shortcut") {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("Shortcut label, e.g. Claude Work", text: Binding(get: { profile.customDockLabel ?? "" }, set: { value in edit { $0.customDockLabel = value } }))
                                    .textFieldStyle(.roundedBorder).accessibilityLabel("Dock shortcut hover label")
                                Text("Leave the label empty for \(profile.kind == .claude ? "Claude" : "ChatGPT") \(profile.name). The label applies to the shortcut, not the running official app.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Button("Show Dock shortcut in Finder…") {
                                    perform { try await model.updateBrandedShortcut(for: profile, reveal: true) }
                                }.disabled(isBusy || model.switchingTargets[profile.kind] != nil)
                                Text("Done automatically creates or updates this profile’s shortcut with your label and icon. Use Show in Finder to pin it to the Dock. The official running app keeps its own icon and name. ChatGPT’s experimental running-icon setting below remains separate.")
                                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }.padding(10)
                        }
                        }
                        if profile.kind == .codex {
                        GroupBox("Advanced") {
                            DisclosureGroup("Running Dock icon — experimental", isExpanded: $advancedNative) {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle(isOn: Binding(get: { profile.dockApplicationPath != nil }, set: { enabled in if enabled { consent = true } else { native(false) } })) {
                                    HStack { Text("Native macOS Dock icon").font(.system(size: 13, weight: .semibold)); Text("Experimental").font(.caption.weight(.medium)).padding(.horizontal, 7).padding(.vertical, 3).background(.orange.opacity(0.15), in: Capsule()) }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }.toggleStyle(.switch).controlSize(.small).accessibilityLabel("Native macOS Dock icon, experimental").disabled(model.nativeDockChangeBlocker(for: profile) != nil)
                                Text("Give this profile its own running Dock icon and name. Profile Shelf keeps the copy up to date automatically.").font(.callout).foregroundStyle(.secondary)
                                if let nativeProgress {
                                    NativeDockProgressView(stage: nativeProgress)
                                } else if let reason = model.nativeDockChangeBlocker(for: profile) {
                                    Label(reason, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                                } else if model.nativeDockAwaitsRelaunch(profile) {
                                    Label("Ready for your next launch. Your current window keeps its original icon until you quit and reopen this profile.", systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary)
                                } else if model.running[profileID]?.isEmpty == false {
                                    Text("You can enable this while working. Profile Shelf prepares the copy now; the new icon appears after you quit and reopen this profile.").font(.callout).foregroundStyle(.secondary)
                                }
                                DisclosureGroup("Why experimental?") { Text(NativeDockDisclosure.text).font(.caption).foregroundStyle(.secondary).padding(.top, 6) }
                                if profile.dockApplicationPath != nil {
                                    HStack {
                                        if let app = model.nativeDockURL(for: profile) { Button("Show Dock app") { NSWorkspace.shared.activateFileViewerSelecting([app]) } }
                                        Button("Repair copy") { native(true) }.disabled(model.nativeDockChangeBlocker(for: profile) != nil)
                                    }
                                    Text("Drag the app from Finder to the Dock to pin it.").font(.caption).foregroundStyle(.secondary)
                                    Text("Turning this off returns to the original installed ChatGPT app. Your profile’s chats, settings and data stay in place.").font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.top, 10)
                            }.padding(10)
                        }
                        GroupBox("App Installation") {
                            DisclosureGroup("Shared or separate app") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(profile.applicationPath == nil ? "Shared installation" : "Separate installation").font(.subheadline.weight(.medium))
                                Text(profile.applicationPath == nil ? (profile.dockApplicationPath == nil ? "This profile uses the same installed ChatGPT app as your other shared profiles. Each profile still has its own sign-in, chats and settings. The app updates once for the group." : "This profile’s Dock app is rebuilt from the shared, signed ChatGPT installation. Profiles using that source update together. Sign-ins, chats and settings stay separate.") : "This profile has its own ChatGPT installation, so you can update or restart it separately. Its account data is still separate. A copy uses more disk space; it does not add another account or subscription.").font(.callout).foregroundStyle(.secondary)
                                Button(profile.applicationPath == nil ? "Create a separate installation…" : "Use shared installation & trash managed copy") {
                                    perform {
                                        if profile.applicationPath == nil { try await model.makeSeparateCopy(for: profile) }
                                        else { try model.useSharedAppAndTrashCopy(profile) }
                                    }
                                }.disabled(model.running[profileID]?.isEmpty == false || model.opening.contains(profileID))
                                if let app = model.applicationURL(for: profile) { Text(app.path).font(.caption).foregroundStyle(.tertiary).textSelection(.enabled) }
                            }.padding(.top, 12)
                            }.padding(10)
                        }
                        GroupBox {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Context access").font(.system(size: 13, weight: .semibold))
                                    Text("Choose which other profiles \(profile.name) can mention for earlier conversations.").font(.callout).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Manage access…") { tagging() }
                            }.padding(10)
                        }
                        } else { CompanionDetails(model: model, profile: profile) }
                    }.padding(24)
                }
            }
            Divider()
            if error != nil { errorNotice.padding(.horizontal, 24).padding(.top, 16) }
            HStack {
                if isBusy {
                    ProgressView().controlSize(.small)
                    Text(nativeProgress?.label ?? "Preparing your profile…").font(.caption).foregroundStyle(.secondary)
                } else { Text("Changes save automatically").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Done") { finish() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.padding(.horizontal, 24).padding(.vertical, 16)
        }.frame(width: 600, height: min(660, (NSScreen.main?.visibleFrame.height ?? 800) - 100))
            .background(Color(nsColor: .windowBackgroundColor)).groupBoxStyle(SettingsGroupBoxStyle())
            .disabled(isBusy).interactiveDismissDisabled(isBusy)
            .onExitCommand { if !isBusy { finish() } }
            .onAppear { hex = profile?.color ?? "377CF6"; initialProfile = profile; advancedNative = profile?.dockApplicationPath != nil }
            .alert("Enable experimental native Dock icon?", isPresented: $consent) {
                Button("Cancel", role: .cancel) {}
                Button("Enable") { native(true) }
            } message: { Text(NativeDockDisclosure.text + "\n\nAny open profile keeps running. Its new Dock icon takes effect after you quit and reopen it.") }
    }

    private func edit(_ change: (inout Profile) -> Void) {
        guard var profile else { return }; change(&profile); model.update(profile)
    }
    private func finish() {
        guard let profile else { dismiss(); return }
        guard profile.kind == .codex || profile.kind == .claude else { dismiss(); return }
        let shortcutExists = profile.launcherPath.map { FileManager.default.fileExists(atPath: $0) } ?? false
        let appearanceIsCurrent = profile.launcherPath.flatMap { Bundle(path: $0)?.object(forInfoDictionaryKey: "ProfileShelfShortcutAppearanceVersion") as? Int } == 3
        if profile == initialProfile && shortcutExists && appearanceIsCurrent { dismiss(); return }
        perform {
            try await model.updateBrandedShortcut(for: profile)
            dismiss()
        }
    }
    @ViewBuilder private var errorNotice: some View {
        if let error {
            SettingsNotice(text: error, symbol: "exclamationmark.triangle.fill", isWarning: true,
                           actionTitle: failedWork == nil ? nil : "Try Again",
                           action: { if let failedWork { perform(failedWork) } },
                           dismiss: { self.error = nil; failedWork = nil })
        }
    }
    private func artwork(_ profile: Profile, style: DockIconStyle? = nil) -> NSImage {
        model.artwork(for: profile, style: style)
    }
    private func native(_ enabled: Bool) {
        guard let profile else { return }
        perform { try await model.setNativeDockIcon(for: profile, enabled: enabled) }
    }
    private func perform(_ work: @escaping @MainActor () async throws -> Void) {
        busy = true; error = nil; failedWork = nil
        Task {
            defer { busy = false }
            do { try await work() }
            catch { self.error = error.localizedDescription; failedWork = work }
        }
    }
}

struct NativeDockProgressView: View {
    let stage: NativeDockStage
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ProgressView().controlSize(.small).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(stage.label).font(.callout.weight(.medium))
                Text("This can take a little while. Your profile data stays in place.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(12).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
    }
}
