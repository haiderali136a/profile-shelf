import AppKit
import SwiftUI
import DockCore

enum AppBrand {
    static let name = "Profile Shelf"
    static let tagline = "Profiles for your AI apps, one click away."
    // Set by build.sh from ProfileShelfRepositoryURL. When empty, links fall back
    // to the bundled documents.
    static var repository: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "ProfileShelfRepositoryURL") as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
    // Prefer the formatted page on GitHub. A bundled Markdown file depends on whichever
    // app handles .md on this Mac, and some ignore files inside another app's bundle.
    static func document(_ path: String) -> URL {
        if let repository { return repository.appendingPathComponent("blob/main/" + path) }
        return Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Documentation/" + path)
    }
    static let guide = document("docs/GUIDE.md")
    static let privacy = document("PRIVACY.md")
    static let contributing = document("CONTRIBUTING.md")
    static let credits = document("ACKNOWLEDGMENTS.md")
}

struct SettingsView: View {
    @ObservedObject var model: DockModel
    @ObservedObject var loginItem: LoginItemModel
    @ObservedObject var activity: ActivityMonitor
    @ObservedObject var updates: AppUpdates
    @ObservedObject var selfUpdates: ProfileShelfUpdates
    @ObservedObject var insights: InsightsStore
    let cues: ActivityCues
    let chooseImage: (Profile) -> Void
    let compact: (() -> Void)?
    @State private var section: SettingsDestination?
    @State private var navigationQuery = ""
    @State private var adding = false
    /// Add Profile opened on one tool from Coding Agents.
    @State private var addingTool: AddStart?
    private struct AddStart: Identifiable { let id: String }
    @State private var editing: Profile?
    @State private var removing: Profile?
    @State private var trashData = false
    @State private var copying = false
    @State private var showingConnections = false
    @State private var showingDiscovery = false
    @State private var showingAdvanced = false
    @State private var confirmingUpdate = false

    init(model: DockModel, loginItem: LoginItemModel, activity: ActivityMonitor, updates: AppUpdates,
         selfUpdates: ProfileShelfUpdates, insights: InsightsStore, cues: ActivityCues,
         chooseImage: @escaping (Profile) -> Void,
         compact: (() -> Void)? = nil,
         destination: SettingsDestination = .initial(arguments: CommandLine.arguments)) {
        self.model = model
        self.loginItem = loginItem
        self.activity = activity
        self.updates = updates
        self.selfUpdates = selfUpdates
        self.insights = insights
        self.cues = cues
        self.chooseImage = chooseImage
        self.compact = compact
        _section = State(initialValue: destination)
    }

    private var groups: [AppUpdateGroup] { AppUpdateGroup.make(profiles: model.preferences.profiles, defaultApplication: model.defaultApplication) }
    private var selectedGroups: [AppUpdateGroup] { groups.filter { updates.selected.contains($0.id) && updates.needsUpdate($0) } }

    var body: some View {
        HSplitView {
            sidebar
            detail

        }
        .groupBoxStyle(SettingsGroupBoxStyle())
        .onReceive(NotificationCenter.default.publisher(for: .profileShelfShowGeneralSettings)) { _ in navigate(.general) }
        .onReceive(NotificationCenter.default.publisher(for: .profileShelfShowUpdates)) { _ in navigate(.updates) }
        .onReceive(NotificationCenter.default.publisher(for: .profileShelfShowProfiles)) { _ in navigate(.profiles) }
        .onReceive(NotificationCenter.default.publisher(for: .profileShelfShowInsights)) { _ in navigate(.insights) }
        .onReceive(NotificationCenter.default.publisher(for: .profileShelfShowSearch)) { _ in navigate(.search) }
        .onReceive(NotificationCenter.default.publisher(for: .profileShelfShowSupport)) { _ in navigate(.support) }
        .onReceive(NotificationCenter.default.publisher(for: .profileShelfShowAbout)) { _ in navigate(.about) }
        .onReceive(NotificationCenter.default.publisher(for: .profileShelfAddProfile)) { _ in navigate(.profiles); adding = true }
        .sheet(isPresented: $adding) { AddProfileSheet(model: model) }
        .sheet(item: $addingTool) { start in AddProfileSheet(model: model, start: start.id) }
        .sheet(item: $editing) { profile in
            ProfileSettingsSheet(model: model, profileID: profile.id) { editing = nil; manageContext(for: profile.id) }
        }
        .sheet(item: $removing) { profile in RemoveProfileSheet(model: model, profile: profile, trashData: $trashData) { removing = nil } }
        .alert("Update the selected ChatGPT apps?", isPresented: $confirmingUpdate) {
            Button("Cancel", role: .cancel) {}
            Button("Download & update") { updates.install(groups: selectedGroups, model: model, activity: activity) }
        } message: {
            Text("\(selectedGroups.flatMap(\.profiles).map(\.name).joined(separator: ", ")) will close after the download and reopen when the update finishes. Profiles sharing an app update together. Active tasks must finish first.")
        }

    }

    private let pageWidth: CGFloat = 760
    private var isEmptyPage: Bool {
        model.preferences.profiles.isEmpty && [.profiles, .search, .insights, .icons, .access].contains(destination)
    }
    private func columnWidth(_ available: CGFloat) -> CGFloat { max(0, min(pageWidth, available - 48)) }

    private var detail: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                pageHeader.frame(width: columnWidth(geometry.size.width))
                    .padding(.vertical, 20).frame(width: geometry.size.width)
                Divider()
                GeometryReader { pane in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if isEmptyPage { emptyState }
                            else { pageContent }
                        }
                        .frame(width: columnWidth(pane.size.width), alignment: .leading)
                        .padding(.vertical, 24)
                        .frame(width: pane.size.width)
                        .frame(minHeight: pane.size.height, alignment: isEmptyPage ? .center : .top)
                    }.id(destination)
                }
                if model.message != nil {
                    ProfileMessageNotice(model: model)
                        .frame(width: columnWidth(geometry.size.width)).padding(.vertical, 12)
                }
            }
        }.frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
    }

    private var pageHeader: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(destination.rawValue).font(.system(size: 20, weight: .semibold))
                Text(destination.subtitle).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if destination == .profiles, !isEmptyPage {
                Button { adding = true } label: { Label("Add Profile", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).disabled(copying || updates.busy)
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    @ViewBuilder private var pageContent: some View {
        switch destination {
        case .profiles: profiles
        case .agents: AgentsSettingsView(model: model) { addingTool = AddStart(id: $0 ?? "codex") }
        case .search: ContextSettingsView(model: model, mode: .search) { manageContext() }
        case .insights: insightsSettings
        case .updates: updateSettings
        case .general: generalSettings
        case .appearance: appearance
        case .icons: profileIconSettings
        case .access: ContextSettingsView(model: model, mode: .access)
        case .support: support
        case .about: about
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: destination == .profiles ? "person.crop.circle.badge.plus" : destination.symbol)
                .font(.system(size: 44, weight: .light)).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Add your first profile").font(.title3.weight(.semibold))
                Text("Keep your accounts in one place, with a separate sign-in for each.")
                    .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Add Profile") { adding = true }.buttonStyle(.borderedProminent)
                .keyboardShortcut("n", modifiers: .command)
            if destination == .profiles { FoundAgentsCard(model: model, compact: true) { navigate(.agents) }.frame(width: 360) }
            Button("Import or Restore Profiles…") { model.restoreImportedProfiles() }.buttonStyle(.borderless)
        }
        .frame(maxWidth: 360).padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var destination: SettingsDestination { section ?? .profiles }

    private func navigate(_ destination: SettingsDestination) {
        navigationQuery = ""
        section = destination
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                BrandMark(size: 21)
                Text("Profile Shelf").font(.system(size: 15, weight: .semibold))
            }.padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 12)
            if let compact {
                Button(action: compact) {
                    Label("Compact view", systemImage: "rectangle.compress.vertical")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .help("Return to the account switcher")
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find a setting", text: $navigationQuery).textFieldStyle(.plain)
                    .accessibilityLabel("Find a setting")
                    .onSubmit { if let match = SettingsDestination.allCases.first(where: { $0.matches(navigationQuery) }) { navigate(match) } }
                if !navigationQuery.isEmpty {
                    Button { navigationQuery = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear settings search")
                }
            }.font(.system(size: 12)).padding(7)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                .padding(.horizontal, 12).padding(.bottom, 10)
            List(selection: $section) {
                sidebarGroup("Workspace", items: SettingsDestination.workspace)
                sidebarGroup("Settings", items: SettingsDestination.settings)
                sidebarGroup("", items: [.support, .about])
                if !SettingsDestination.allCases.contains(where: { $0.matches(navigationQuery) }) {
                    Text("No matching settings").font(.caption).foregroundStyle(.secondary)
                }
            }.listStyle(.sidebar).environment(\.defaultMinListRowHeight, 26)
            Divider().padding(.horizontal, 16)
            Text("Version " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"))
                .font(.caption).foregroundStyle(.secondary).padding(16)
        }
        .frame(minWidth: 190, idealWidth: 210, maxWidth: 240, maxHeight: .infinity)
        .background(.regularMaterial)
    }

    @ViewBuilder private func sidebarGroup(_ title: String, items: [SettingsDestination]) -> some View {
        let matches = items.filter { $0.matches(navigationQuery) }
        if !matches.isEmpty {
            Section(title) {
                ForEach(matches) { item in
                    Label {
                        Text(item.rawValue).font(.system(size: 13)).lineLimit(1)
                    } icon: {
                        Image(systemName: item.symbol).font(.system(size: 14)).frame(width: 22)
                            .foregroundStyle(item == .support ? Color.pink : Color.accentColor)
                    }.padding(.vertical, 1).tag(item)
                }
            }
        }
    }

    private var profiles: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.preferences.profiles.isEmpty {
                ContentUnavailableView("Add your first profile", systemImage: "person.crop.circle.badge.plus", description: Text("Keep work and personal accounts together, with a separate sign-in for each."))
            } else {
                HStack {
                    Text("\(model.preferences.profiles.count) profiles").font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(model.preferences.profiles.filter { model.running[$0.id]?.isEmpty == false }.count) open")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 2)
                SettingsCard {
                    VStack(spacing: 0) {
                        ForEach(Array(model.preferences.profiles.enumerated()), id: \.element.id) { index, profile in
                            profileRow(profile, index: index)
                                .modifier(ReorderableProfile(model: model, profile: profile, handle: false))
                            if index < model.preferences.profiles.count - 1 { Divider().padding(.leading, 72) }
                        }
                    }
                }
            }
            SettingsCard {
                DisclosureGroup("Connections & activity", isExpanded: $showingConnections) {
                    ActivityConnectionsView(model: model, activity: activity).padding(.top, 12)
                }.padding(16)
            }
            SettingsCard {
                DisclosureGroup("Discover more apps", isExpanded: $showingDiscovery) {
                    FoundAgentsCard(model: model) { navigate(.agents) }.padding(.top, 12)
                    Button("Browse coding tools") { navigate(.agents) }.buttonStyle(.borderless).padding(.top, 8)
                }.padding(16)
            }
            if copying || !model.nativeDockOperations.isEmpty { ProgressView("Preparing your profile…").controlSize(.small) }
            HStack {
                Button { model.restoreImportedProfiles() } label: { Label("Import or Restore Profiles…", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.borderless)
                Spacer()
            }
            Text("Drag the handles to change the order here or in the strip. Click a name to edit its icon and settings.")
                .font(.caption).foregroundStyle(.secondary)
        }.disabled(updates.busy || copying || !model.nativeDockOperations.isEmpty)
    }

    private func profileRow(_ profile: Profile, index: Int) -> some View {
        let isOpen = model.running[profile.id]?.isEmpty == false
        return HStack(spacing: 12) {
            ProfileDragHandle(model: model, profile: profile).frame(width: 18, height: 22)
            Button { editing = profile } label: {
                HStack(spacing: 12) {
                    ProfileBadge(model: model, profile: profile, size: 40, showStatus: false).opacity(profile.isShownInStrip ? 1 : 0.45)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(profile.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                        HStack(spacing: 5) {
                            ProfileStateMark(model: model, profile: profile)
                            // The state is the one fact that must stay readable in a narrow window.
                            Text(model.state(profile)).fixedSize().layoutPriority(2)
                            Text("·")
                            Text(profile.kind != .codex ? profile.listDetail : profile.dockApplicationPath != nil ? "Custom Dock icon" : profile.applicationPath == nil ? "Shared app" : "Separate app")
                                .layoutPriority(1)
                            if !profile.isShownInStrip { Text("·"); Text("Hidden from strip") }
                            if profile.addedAutomatically == true { Text("·"); Text("Added automatically") }
                        }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help("Edit \(profile.name)").accessibilityLabel("Edit \(profile.name)")
            if let shortcut = model.displayedProfiles.firstIndex(where: { $0.id == profile.id }), shortcut < 9 {
                Text("⌥⌘\(shortcut + 1)").font(.system(size: 11)).foregroundStyle(.tertiary).frame(width: 38)
                    .accessibilityLabel("Option Command \(shortcut + 1)")
            }
            Toggle(isOn: Binding(get: { profile.isShownInStrip }, set: { model.setShownInStrip(profile.id, $0) })) {
                Image(systemName: profile.isShownInStrip ? "eye" : "eye.slash")
            }.toggleStyle(.button).buttonStyle(.borderless).frame(width: 26)
                .help(profile.isShownInStrip ? "Hide \(profile.name) from the strip, shortcuts and menu. Its app and data are kept." : "Show \(profile.name) in the strip again.")
                .accessibilityLabel("Show \(profile.name) in strip")
            Button(isOpen ? "Show" : (profile.kind == .codex || profile.kind == .claude) ? "Switch" : "Open") { model.select(profile) }
                .buttonStyle(.bordered).frame(width: 62)
                .disabled(model.opening.contains(profile.id) || model.closing.contains(profile.id) || model.switchingTargets[profile.kind] != nil)
                .accessibilityLabel("\(isOpen ? "Show" : (profile.kind == .codex || profile.kind == .claude) ? "Switch to" : "Open") \(profile.name)")
            Menu { profileCommands(profile, index: index) } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 16)).frame(width: 22, height: 24)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("More actions for \(profile.name)").accessibilityLabel("Options for \(profile.name)")
        }.padding(.horizontal, 16).padding(.vertical, 15)
            .contextMenu { profileCommands(profile, index: index) }
    }

    @ViewBuilder private func profileCommands(_ profile: Profile, index: Int) -> some View {

        Section {
            Button("Profile settings…", systemImage: "slider.horizontal.3") { editing = profile }
            if profile.kind != .terminal && profile.kind != .agent { Button("Context tagging…", systemImage: "at") { manageContext(for: profile.id) } }
        }
        Section("Window") {
            Button("Open profile", systemImage: "arrow.up.forward.app") { model.select(profile) }
                .disabled(model.switchingTargets[profile.kind] != nil)
            if profile.kind == .codex || profile.kind == .claude {
                Button("Open alongside", systemImage: "plus.rectangle.on.rectangle") { model.select(profile, mode: .alongside) }
                    .disabled(!model.canOpenAlongside(profile))
            }
            Button("Close profile", systemImage: "xmark.circle") { model.requestQuit(profile) }.disabled(model.running[profile.id]?.isEmpty != false)
            if let url = model.nativeDockURL(for: profile) ?? model.applicationURL(for: profile) {
                Button("Show app in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            if let path = profile.launcherPath {
                Button("Show profile shortcut", systemImage: "arrow.turn.up.right") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
            } else {
                Button("Create profile shortcut", systemImage: "plus.app") {
                    copying = true
                    Task { defer { copying = false }; do { try await model.createFinderLauncher(for: profile) } catch { model.message = error.localizedDescription } }
                }
            }
        }
        Section("Organize") {
            Button("Move up", systemImage: "arrow.up") { model.move(profile.id, by: -1) }.disabled(index == 0)
            Button("Move down", systemImage: "arrow.down") { model.move(profile.id, by: 1) }.disabled(index + 1 == model.preferences.profiles.count)
            if profile.isShownInStrip { Button("Hide from strip", systemImage: "eye.slash") { model.setShownInStrip(profile.id, false) } }
            else { Button("Show in strip", systemImage: "eye") { model.setShownInStrip(profile.id, true) } }
        }
        Section {
            Button("Remove profile…", systemImage: "trash", role: .destructive) { trashData = false; removing = profile }
        }

    }


    private var insightsSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            InsightsPanel(model: model, store: insights)
            Picker("In the profile strip", selection: Binding(get: { model.preferences.insightsExpansion ?? .button }, set: { model.preferences.insightsExpansion = $0; model.save() })) {
                ForEach(InsightsExpansion.allCases, id: \.self) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented)
            Text("Choose how the Usage insights drawer opens inside your expanded profile strip. Hover mode stays open until you leave the strip.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var updateSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            profileShelfUpdateCard
            Divider()
            Label("ChatGPT / Codex", systemImage: "sparkles").font(.title3.weight(.semibold))
            Text("Update the OpenAI app used by your profiles. Choose the groups you can restart.").foregroundStyle(.secondary)
            Text("Checks when you open this panel. Updates install only after you confirm.").font(.caption).foregroundStyle(.secondary)
            if model.preferences.profiles.contains(where: { $0.dockApplicationPath != nil }) {
                Text("Enabled native Dock copies are rebuilt automatically with each update, keeping their profile names, colors and data. Updates made outside Profile Shelf are applied to the Dock copy on its next launch.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button(updates.checking ? "Checking ChatGPT…" : "Check ChatGPT updates") { Task { await updates.check() } }.disabled(updates.checking || updates.busy)
                Spacer()
                Button("Select all") { updates.selected = Set(groups.filter { updates.needsUpdate($0) }.map(\.id)) }.disabled(updates.busy)
            }
            ForEach(groups) { group in
                GroupBox {
                    Toggle(isOn: Binding(get: { updates.selected.contains(group.id) }, set: { if $0 { updates.selected.insert(group.id) } else { updates.selected.remove(group.id) } })) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(group.profiles.map(\.name).joined(separator: ", ")).font(.headline)
                            Text(group.application.lastPathComponent + " · " + AppUpdates.installedVersion(at: group.application) + (updates.needsUpdate(group) ? " · Update available" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                            if group.profiles.count > 1 { Text("These profiles share one app and restart together.").font(.caption).foregroundStyle(.secondary) }
                        }
                    }.toggleStyle(.checkbox).padding(8)
                }.disabled(!updates.needsUpdate(group) || updates.busy)
            }
            if updates.busy {
                VStack(alignment: .leading, spacing: 8) {
                    if let progress = updates.progress, !updates.verifying, !updates.cancelling {
                        ProgressView(value: progress.fraction ?? 0).accessibilityLabel("ChatGPT download progress")
                        HStack {
                            Text(progress.label).monospacedDigit()
                            Spacer()
                            if let fraction = progress.fraction { Text("\(Int(fraction * 100))%").monospacedDigit() }
                        }.font(.caption).foregroundStyle(.secondary)
                    } else { ProgressView().controlSize(.small) }
                    if updates.canCancel {
                        Button("Cancel download") { updates.cancel() }
                    } else if !updates.cancelling {
                        Text("Installation is in progress. Keep Profile Shelf open until it finishes.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let status = updates.status { Text(status).font(.callout).foregroundStyle(.secondary) }
            if let error = updates.error {
                SettingsNotice(text: error, symbol: "exclamationmark.triangle.fill", isWarning: true,
                               actionTitle: "Check Again", action: { Task { await updates.check() } })
            }
            Button("Update selected ChatGPT apps") { confirmingUpdate = true }.buttonStyle(.borderedProminent).disabled(selectedGroups.isEmpty || updates.busy || selfUpdates.sessionInProgress)
            Text("Only selected app groups restart. Your profiles, sign-ins and chats stay in place. Enabled custom Dock icons are reapplied automatically.").font(.caption).foregroundStyle(.secondary)
        }.task { await updates.check() }
    }

    private var profileShelfUpdateCard: some View {
        GroupBox("Profile Shelf") {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    BrandMark(size: 30).frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Profile Shelf").font(.headline)
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development") · Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "local")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selfUpdates.enabled {
                        Button("Check for Updates…") { selfUpdates.check() }.disabled(!selfUpdates.canCheck || updates.busy)
                    }
                }.padding(16)
                if selfUpdates.enabled {
                    Divider().padding(.leading, 16)
                    SettingsRow(title: "Check automatically", detail: "Checks daily. You choose when to download and install.") {
                        Toggle("Automatically check for Profile Shelf updates", isOn: Binding(get: { selfUpdates.automatic }, set: { selfUpdates.setAutomatic($0) }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                } else {
                    Text("Local build. To update Profile Shelf, install a newer build.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding([.horizontal, .bottom], 16)
                }
                if let last = selfUpdates.lastChecked {
                    Text("Last checked \(last.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding([.horizontal, .bottom], 16)
                }
            }
        }
    }

    private func manageContext(for profileID: String? = nil) {
        if let profileID { model.contextSettings.selectCaller(profileID) }
        navigate(.access)
    }

    private var profileIconSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.preferences.profiles.isEmpty {
                ContentUnavailableView("Add your first profile", systemImage: "person.crop.circle.badge.plus", description: Text("Then choose an icon for it here."))
                Button("Add Profile") { adding = true }.buttonStyle(.borderedProminent)
            } else {
                SettingsCard {
                    VStack(spacing: 0) {
                        ForEach(Array(model.preferences.profiles.enumerated()), id: \.element.id) { index, profile in
                            HStack(spacing: 14) {
                                Image(nsImage: model.artwork(for: profile))
                                    .resizable().frame(width: 44, height: 44).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(profile.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Text(profile.dockApplicationPath == nil ? "Profile artwork · official running Dock icon" : model.nativeDockAwaitsRelaunch(profile) ? "Ready for next launch" : "Native Dock icon on")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Button("Customize…") { editing = profile }.accessibilityLabel("Customize icon for \(profile.name)")
                            }.padding(16)
                            if index < model.preferences.profiles.count - 1 { Divider().padding(.leading, 74) }
                        }
                    }
                }
            }
            SettingsNotice(text: "Profile artwork appears in Profile Shelf and generated shortcuts. The official running app controls its own Dock icon and name. Experimental running-icon options are under Advanced for ChatGPT profiles.")
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 22) {
            GroupBox("Startup") {
                VStack(spacing: 0) {
                    SettingsRow(title: "Open at login", detail: "Have your profiles ready when you sign in to your Mac.") {
                        Toggle("Open at login", isOn: Binding(get: { loginItem.enabled }, set: { loginItem.setEnabled($0) })).labelsHidden()
                    }
                    if loginItem.requiresApproval {
                        Divider().padding(.leading, 16)
                        SettingsRow(title: "Allow Profile Shelf in Login Items") {
                            Button("Open System Settings…") { loginItem.openSystemSettings() }
                        }
                    }
                    if let error = loginItem.error {
                        SettingsNotice(text: error, symbol: "exclamationmark.triangle.fill", isWarning: true,
                                       actionTitle: "Open System Settings…", action: { loginItem.openSystemSettings() }).padding(12)
                    }
                }
            }
            GroupBox("Dock & Menu Bar") {
                VStack(spacing: 0) {
                    SettingsRow(title: "Quick access", detail: "Choose where the profile switcher appears.") {
                        Picker("Quick access", selection: Binding(get: {
                            model.preferences.showNotch == false ? "menu" : model.preferences.showMenuBarIcon == false ? "notch" : "both"
                        }, set: { value in
                            model.preferences.showNotch = value != "menu"
                            model.preferences.showMenuBarIcon = value != "notch"
                            model.save()
                        })) {
                            Text("Notch only").tag("notch")
                            Text("Menu bar only").tag("menu")
                            Text("Both").tag("both")
                        }.labelsHidden().fixedSize()
                    }
                    Divider().padding(.leading, 16)
                    SettingsRow(title: "Menu bar style", detail: "Shows one remembered ChatGPT/Codex account and one Claude account. Hover the menu bar to identify them. Uses the normal usage refresh schedule.") {
                        Picker("Menu bar style", selection: Binding(get: { model.preferences.menuBarIconOnly == true }, set: { model.preferences.menuBarIconOnly = $0; model.save() })) {
                            Text("Icon & usage").tag(false)
                            Text("Icon only").tag(true)
                        }.labelsHidden().fixedSize()
                    }
                    Divider().padding(.leading, 16)
                    SettingsRow(title: "Keep in Dock", detail: "Keep the Profile Shelf icon visible when its window is closed.") {
                        Toggle("Keep Profile Shelf in the Dock", isOn: Binding(get: { model.preferences.showDockIcon == true }, set: { model.preferences.showDockIcon = $0; model.save() })).labelsHidden()
                    }
                }
            }
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    DisclosureGroup("Advanced", isExpanded: $showingAdvanced) {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Record switch logs", isOn: Binding(get: { model.preferences.switchDiagnosticsEnabled != false }, set: { model.preferences.switchDiagnosticsEnabled = $0; model.save() }))
                            Text("Bounded local switch records. No account names, email addresses, app paths, command arguments or credentials; nothing is uploaded.")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("Show switch logs in Finder…") { model.revealSwitchDiagnostics() }
                                    .disabled(!FileManager.default.fileExists(atPath: model.switchDiagnosticLog.directory.path))
                                Button(model.upgradingShortcuts ? "Updating shortcuts…" : "Upgrade existing shortcuts") {
                                    Task { await model.upgradeManagedShortcuts() }
                                }.disabled(model.upgradingShortcuts || !model.shortcutOperations.isEmpty || !model.switchingTargets.isEmpty)
                            }
                            Text("Rebuilds your Dock shortcuts with the faster launcher. Pinned shortcuts keep working; account data isn’t touched.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.top, 12)
                    }
                    if model.diagnosticWriteFailed {
                        Text("Switch logs could not be written. Account switching remains available.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }.padding(16)
            }
            Text("You can always open Profile Shelf from Applications or Spotlight. Individual profile icons are managed in Profile Icons.")
                .font(.caption).foregroundStyle(.secondary)
        }.toggleStyle(.switch).controlSize(.small)
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 22) {
            GroupBox("Profile Strip") {
                VStack(spacing: 0) {
                    SettingsRow(title: "Layout", detail: "Full keeps the larger cards. Compact uses usage rings with expandable details. Switch back at any time.") {
                        Picker("Notch layout", selection: Binding(get: { model.preferences.effectiveNotchLayout }, set: { model.setNotchLayout($0) })) {
                            ForEach(NotchLayout.allCases, id: \.self) { Text($0.label).tag($0) }
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 210)
                    }
                    Divider().padding(.leading, 16)
                    SettingsRow(title: "Position") {
                        Picker("Position", selection: Binding(get: { model.placement }, set: { model.preferences.placement = $0; model.save() })) {
                            ForEach(DockPlacement.allCases, id: \.self) { Text($0.label).tag($0) }
                        }.labelsHidden().fixedSize().frame(width: 210, alignment: .trailing)
                    }
                    Divider().padding(.leading, 16)
                    SettingsRow(title: "Profile size") {
                        Picker("Profile size", selection: Binding(get: { model.preferences.scale }, set: { model.preferences.scale = $0; model.save() })) {
                            Text("Small").tag(0.85); Text("Default").tag(1.0); Text("Large").tag(1.3)
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 210)
                    }
                    Divider().padding(.leading, 16)
                    ProfileGridSettings(model: model).padding(16)
                    Divider().padding(.leading, 16)
                    SettingsRow(title: "Terminals section", detail: "Show coding terminals in the notch menu.") {
                        Toggle("Show terminals section", isOn: Binding(get: { model.preferences.showTerminalsSection != false }, set: { model.preferences.showTerminalsSection = $0; model.save() })).labelsHidden().toggleStyle(.switch)
                    }
                    Divider().padding(.leading, 16)
                    SettingsRow(title: "Usage Insights section", detail: "Show usage analytics in the notch menu.") {
                        Toggle("Show Usage Insights section", isOn: Binding(get: { model.preferences.showInsightsSection != false }, set: { model.preferences.showInsightsSection = $0; model.save() })).labelsHidden().toggleStyle(.switch)
                    }
                    Divider().padding(.leading, 16)
                    VStack(alignment: .leading, spacing: 18) {
                        Text("These widths control the notch strip. Expanded strip width applies to Full; Compact sizes itself to its accounts. The compact account window is separate.")
                            .font(.caption).foregroundStyle(.secondary)
                        widthControl("Collapsed strip width", value: Binding(get: { model.preferences.compactWidth }, set: { model.preferences.compactWidth = $0; model.save() }), range: 160...480, automatic: WidgetSizing.compact(count: model.preferences.profiles.count, preferred: nil))
                        if model.preferences.profileGrid == nil { widthControl("Expanded strip width", value: Binding(get: { model.preferences.expandedWidth }, set: { model.preferences.expandedWidth = $0; model.save() }), range: 320...1400, automatic: WidgetSizing.expanded(count: model.preferences.profiles.count, scale: model.preferences.scale, preferred: nil, insights: false)) }
                    }.padding(16)
                    if model.placement == .free {
                        Divider().padding(.leading, 16)
                        SettingsRow(title: "Positions on each display") {
                            Button("Reset Positions") { model.preferences.floatingPositions = nil; model.preferences.placement = .free; model.save() }
                        }
                    }
                }
            }
            Text(model.placement.instruction).font(.caption).foregroundStyle(.secondary)
            GroupBox("Profile Shelf App Icon") { AppIconAppearancePicker(model: model).padding(12) }
            GroupBox("Activity & Sound") {
                VStack(spacing: 0) {
                    SettingsRow(title: "Activity cues", detail: "Show when a task finishes or needs your input.") {
                        Toggle("Show activity cues", isOn: Binding(get: { model.preferences.activityCues != false }, set: { model.preferences.activityCues = $0; model.save(); if !$0 { cues.dismiss() } })).labelsHidden()
                    }
                    Divider().padding(.leading, 16)
                    SettingsRow(title: "Activity sounds", detail: "Play a quiet sound with each cue.") {
                        Toggle("Play activity sounds", isOn: Binding(get: { model.preferences.activitySounds == true }, set: { model.preferences.activitySounds = $0; model.save() })).labelsHidden()
                    }
                    if model.preferences.activitySounds == true {
                        HStack(spacing: 12) {
                            Image(systemName: "speaker.wave.1")
                            Slider(value: Binding(get: { model.preferences.activitySoundVolume ?? 0.18 }, set: { model.preferences.activitySoundVolume = $0; model.save() }), in: 0...0.5).accessibilityLabel("Activity sound volume")
                            Image(systemName: "speaker.wave.2")
                        }.foregroundStyle(.secondary).padding(16)
                    }
                    Divider().padding(.leading, 16)
                    SettingsRow(title: "Sign-in reminders", detail: (model.preferences.mutedSignInReminders ?? []).isEmpty ? "Drop the strip down when an account needs to sign in again." : "Drop the strip down when an account needs to sign in again. Muted for \((model.preferences.mutedSignInReminders ?? []).count) account\((model.preferences.mutedSignInReminders ?? []).count == 1 ? "" : "s").") {
                        HStack {
                            if !(model.preferences.mutedSignInReminders ?? []).isEmpty {
                                Button("Unmute all") { model.preferences.mutedSignInReminders = nil; model.save() }.controlSize(.small)
                            }
                            Toggle("Show sign-in reminders", isOn: Binding(get: { model.preferences.signInReminders != false }, set: { model.preferences.signInReminders = $0; model.save() })).labelsHidden()
                        }
                    }
                    Divider().padding(.leading, 16)
                    SettingsRow(title: "Wait for subagents", detail: "Stay quiet when a Claude Code session pauses while its subagents are still working. You get one cue when everything is done.") {
                        Toggle("Wait for subagents before signalling done", isOn: Binding(get: { model.preferences.activityWaitsForSubagents != false }, set: { model.preferences.activityWaitsForSubagents = $0; model.save() })).labelsHidden()
                    }
                    Divider().padding(.leading, 16)
                    HStack {
                        Text("Try a cue").foregroundStyle(.secondary)
                        Spacer()
                        Button("Task Complete") { cues.present(.finished, model: model, preview: true) }
                        Button("Input Needed") { cues.present(.needsInput, model: model, preview: true) }
                    }.padding(16)
                }
            }.toggleStyle(.switch).controlSize(.small)
            Text("Activity covers local Work and Codex tasks. Ordinary chats and tasks on other computers are outside this view.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func widthControl(_ title: String, value: Binding<Double?>, range: ClosedRange<Double>, automatic: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Toggle("Automatic", isOn: Binding(get: { value.wrappedValue == nil }, set: { value.wrappedValue = $0 ? nil : automatic }))
                    .toggleStyle(.checkbox).controlSize(.small)
            }
            if let current = value.wrappedValue {
                HStack {
                    Slider(value: Binding(get: { value.wrappedValue ?? automatic }, set: { value.wrappedValue = $0 }), in: range, step: 10)
                        .accessibilityLabel(title)
                    Text("\(Int(current)) pt").font(.caption).monospacedDigit().frame(width: 52, alignment: .trailing)
                }
            }
        }
    }

    private var support: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 16) {
                    BrandMark(size: 40)
                    Text("Make Profile Shelf better").font(.title2.weight(.semibold))
                    Text("Share a reproducible bug, improve the documentation, or add support for another app. Small contributions are welcome.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Link("Contribution guide", destination: AppBrand.contributing).buttonStyle(.bordered)
                    if let repository = AppBrand.repository {
                        Link("Open an issue", destination: repository.appendingPathComponent("issues"))
                        Link("View source", destination: repository)
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Use fictional profiles in screenshots and reports. Keep account details, tokens, and conversation content private.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard {
                HStack(spacing: 18) {
                    BrandMark(size: 48).frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Profile Shelf").font(.title2.weight(.semibold))
                        Text(AppBrand.tagline).foregroundStyle(.secondary)
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(24)
            }
            GroupBox("Help & Feedback") {
                VStack(alignment: .leading, spacing: 14) {
                    Link("Read the guide", destination: AppBrand.guide)
                    Link("Privacy & security", destination: AppBrand.privacy)
                    Link("Credits & licenses", destination: AppBrand.credits)
                    if let repository = AppBrand.repository {
                        Link("Report an issue", destination: repository.appendingPathComponent("issues"))
                        Link("View on GitHub", destination: repository)
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Free and open source. An independent companion for AI apps and coding tools; not affiliated with their vendors.").font(.caption).foregroundStyle(.secondary)
        }
    }

}

