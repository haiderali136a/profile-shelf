# Using Profile Shelf

1. **Add a profile.** Choose ChatGPT/Codex, Claude, or a supported coding tool. Existing sign-in uses the account already on this Mac. Separate sign-ins are available only for supported tools. ChatGPT profiles can use a shared app or a separate app copy.
2. **Open and sign in.** Use Profile Shelf or the new Finder launcher in `~/Applications/Profile Shelf Launchers`. Each launcher opens its assigned profile. Confirm the signed-in account inside the selected app or tool.
3. **Hover and switch.** Move to the top center of any display. Click a profile or use ⌥⌘1–9. Expand **Resets** to see expiry countdowns.
4. **Choose what updates.** Open **Updates → ChatGPT / Codex**, select app groups, and click **Update selected ChatGPT apps**. The panel checks whenever you open it. Selected groups close and previously running profiles reopen. Active tasks must finish first.

**Update Profile Shelf:** Profile Shelf has no automatic self-update feed yet. Install a newer Profile Shelf build to update the manager. The Updates page manages supported ChatGPT app installations separately. Account folders are retained when replacing the manager.

**Cancel a ChatGPT download:** use **Cancel download** beside its progress bar. During signature verification, cancellation may take a moment. Once app installation starts, cancellation is unavailable and Profile Shelf must remain open until it finishes.

**Activity cues:** blue dots mean working, orange needs input, green is idle, red is unread, and gray is closed or unknown. A single cue grows from the strip, showing **Done** or **Needs you** on the left and the environment name on the right, then settles back into the strip. The camera area stays clear on notched screens. **Appearance → Activity & sound** has previews, a visual-cue toggle, optional quiet chimes, and volume. Sounds are off by default. **Wait for subagents** (on by default) keeps a Claude Code session quiet, and showing as working, when its main turn pauses while background subagents still work; you get one cue once everything is done. Matching events are combined; different states queue separately so names stay accurate. Startup/reconnect snapshots stay quiet. Reduce Motion uses a simple fade.

**Find a setting:** the sidebar keeps workspace tools and settings in separate groups. Search by name or a familiar term such as “sound,” “menu bar,” or “permissions.” Press Return to open the first matching category. ⌘, opens General; ⌘N adds a profile; ⌘F opens Search Chats.

**Quick switching:** click the menu-bar icon to open the account popup; right-click it for the full menu. The popup and quick account window list visible supported profiles. Clicking an already-open desktop account brings it forward. Switching to a closed ChatGPT/Codex or Claude account can normally quit other accounts from that provider first. Use **⋯ → Open alongside** to keep parallel accounts open. The **Full dashboard** button opens all settings; **Compact view** in the dashboard returns to the account window. That account window is separate from the notch’s Full/Compact layout.

**Menu-bar stats:** **General → Dock & Menu Bar → Menu bar style → Icon & usage** enables the two-provider readout; **Icon only** hides the numbers. G is ChatGPT/Codex and C is Claude. Each row tracks one remembered account from that provider, not every connected account or a combined quota. Selecting or activating another account updates the remembered choice. Hover the menu bar to see the account names, reading times and source. A small menu-bar badge marks the tracked accounts in the popup when stats are shown. The popup can show all your visible accounts, including accounts without usage connections.

**Usage refresh:** menu-bar stats display the same readings as the rest of the app and create no additional polling timer. The existing scheduler normally refreshes about every five minutes in the background, or every minute while the notch is open. Startup, wake, explicit Refresh and connection changes can also refresh readings. Provider cooldowns can delay requests; manual Refresh does not bypass those cooldowns. The menu bar and quick account window show percentages used; the notch labels percentages remaining.

**Usage recovery:** an expired renewable Claude token offers **Refresh** first and **Reconnect** as a secondary action. A confirmed sign-in or account-connection problem offers Connect usage/Reconnect. Error actions remain available alongside a retained reading. Reconnecting usage is separate from opening the desktop app.

**Profile icons:** choose a colored dot, initials or custom letters, a custom image, or a colored ChatGPT logo in the profile editor. The notch, profile list and menu update immediately, even with experimental mode off. Square, wide and tall images fill a rounded tile without distortion. The optional **Native macOS Dock icon** also gives the running ChatGPT app this identity. Setup displays its current copy, signing and installation stage; [setup and tradeoffs](NATIVE-DOCK.md) explain how to return to the original signed app.

**Search earlier chats:** open **Search Chats** for local Work/Codex conversations. Choose all words, any word or an exact phrase, then narrow by source, date or archive status. Results retain their source and date and open around the matching passage. Your own profile needs no sharing permission; other sources require explicit, directional access in **Context Access**. [Context setup and limits](CONTEXT.md).

**Usage Insights:** use its sidebar page or the drawer beneath the profile strip. Hover mode adds a short delay before opening, followed by a spring and content fade. The drawer stays open while its chart controls are in use. Reduce Motion skips geometry changes. [Metrics and coverage](INSIGHTS.md).

**Warnings and retry:** recovery buttons retry the affected profile or operation. A failed window switch does not silently launch another account. Dock-copy errors stay visible in the profile editor with **Try Again**.

**Contribute and About:** **Contribute** opens the bundled contribution guide. **About** includes the installed version, guide, privacy information and credits. Repository and issue links appear only when a repository URL is configured.

**Shared app or separate copy?** Shared profiles use less disk space but update together. A separate, unmodified ChatGPT copy uses more space and can update independently. Click a profile’s name and expand **App Installation** to create a copy or return to the shared app.

**Remove a profile:** close it, then choose **Remove profile**. Data stays on your Mac by default. For profiles created here, you can also move their data and app copy to the Trash. Imported profiles' original data is protected from deletion here.

**Advanced controls:** expand **General → Advanced** for **Record switch logs**, **Show switch logs in Finder…**, and shortcut maintenance. Switching logs stay on this Mac. Turning recording off stops new records and keeps existing files; switching remains available. Log-write errors stay visible even when Advanced is collapsed.

**Start at login:** enable **Open at login** in **General**. Profile Shelf follows macOS Reduce Motion and responds to display changes automatically.

**Fit more accounts:** choose Full or Compact from the notch header or Appearance → Profile Strip → Layout. Compact keeps usage rings on the cards; click them for reset times and saved resets. Full keeps the larger cards and usage bars. Full’s saved grid and widths are retained when changing layouts. Appearance has separate collapsed-strip and expanded Full-panel width controls; Compact sizes itself automatically. Leave **Automatic** on to adapt to the account count, or choose a width with the slider. Tiles shrink to a readable minimum and wrap into rows. When the screen is full, use the page arrows to reach additional accounts. Compact dots use the available width, with a `+N` count for additional accounts. On a notched display, the compact trigger stays the size of the physical notch. Insights keep a minimum readable width.

**After a ChatGPT update or restart:** Profile Shelf reconnects to local activity automatically. **Reconnecting…** means the connection is recovering; **Activity unavailable** means metadata cannot be read; **Update needed** means the activity protocol has changed. Hover the account for an explanation. Unavailable activity is never presented as idle, and reconnecting does not replay completion sounds.

**Place it anywhere:** choose **Appearance → Position → Free position**. Drag the six-dot grip on the strip or panel header to move it anywhere inside that display's usable area. Each screen remembers its position, including after resizing or reconnecting it. Hover over the rest of the strip to open profiles; the panel opens toward available space and stays on screen. **Reset Positions** brings the strips back to their starting positions. Choose **Top center** to return to the notch/menu bar. Activity cues move with the strip, leaving room for other notch apps.

**General → Keep in Dock** adds a regular app icon. Clicking it restores an open dashboard, including a minimized one; otherwise it opens the quick account window. Custom hover expansion belongs to the floating strips, not the system Dock icon.

The app uses Profile Shelf’s shelf [artwork](BRANDING.md) and a monochrome menu-bar mark.

**Working indicators:** in Full layout, a blue rim, soft halo, and outer ring breathe around working profiles; compact working dots glow gently too. The image stays still. Hidden indicators stop animating, and Reduce Motion keeps a steady blue glow.

## A few useful boundaries

- Activity covers local **Work/Codex** tasks, not ordinary chats or tasks on another computer. Missing data is shown as unknown.
- Usage and activity rely on desktop interfaces that OpenAI may change. Profile Shelf never buys or redeems reset credits.
- Profiles separate local app state; they are **not a security boundary** between people or companies. The macOS user, files, and Keychain remain shared.
- Update selection is by physical app bundle. The signed source app keeps its updater; experimental native Dock copies update through Profile Shelf. New Profile Shelf releases require Apple Silicon and macOS 14 or later.
- Only the apps selected for an update restart. If an app refuses to quit, it is not force-closed. A hidden copy of its previous version is retained beside an updated app for recovery.

Read [Privacy & security](../PRIVACY.md). Profile Shelf is an independent project and is not affiliated with OpenAI.


## Uninstall and data retention

To remove only the manager:

1. Turn off **General → Open at login** if enabled.
2. Quit Profile Shelf and move `~/Applications/Profile Shelf.app` to the Trash. If you only opened the build output, its location is `dist/Profile Shelf.app` in your source folder.
3. Remove profile-launcher Dock pins and generated Finder shortcuts you no longer want. These shortcuts depend on the manager. Keep provider app installations and profile-data folders if you want to retain their sign-ins and history.

Removing the manager does not erase `~/Library/Application Support/Profile Shelf`, provider profile homes, Keychain entries, usage caches or `~/Library/Logs/Profile Shelf`. Reinstalling can reuse retained profiles. Do not delete these folders as a generic uninstall step: some belong to shared or imported provider accounts.

If you configured **Context Access**, use **Disconnect** for each connected receiving profile in Context Access before uninstalling; see [context setup](CONTEXT.md). For intentional profile-data removal, use the app’s per-profile removal choices after checking the selected profile and whether its data is shared/imported. Uninstalling the manager does not uninstall ChatGPT, Claude or your coding tools.
