# Identifiers and old folders

Profile Shelf uses its own identity on macOS. It does not share settings, folders or integrations with ProfileDock or with older local builds.

| What | Profile Shelf uses |
| --- | --- |
| Bundle ID | `io.github.haiderali136a.profileshelf` |
| Settings, profiles and sign-in folders | `~/Library/Application Support/Profile Shelf` |
| Finder launchers | `~/Applications/Profile Shelf Launchers` |
| Managed ChatGPT copies | `~/Applications/Profile Shelf Apps` |
| Experimental native Dock copies | `~/Applications/Profile Shelf Dock Apps` |
| Insights cache | `~/Library/Caches/io.github.haiderali136a.profileshelf` |
| Bundled helpers | `ProfileShelfLauncher`, `ProfileShelfClaude`, `ProfileShelfContext`, `ProfileShelfShim` |
| Codex context connection | `profile-shelf-context` |

## Coming from ProfileDock or an older build

The first launch starts with no profiles. To keep existing ChatGPT/Codex profile history, add them back with **Import or Restore Profiles**, which uses the existing profile folders in place. A separate Claude account that is still open from an older build is added automatically as **Claude**, using its existing folder in place. It keeps its sign-in and history, and Profile Shelf never moves that folder to the Trash. If you remove it, it is not added again; you can also add it by hand under **Add profile → Claude Desktop → Separate Claude account**. Other separate coding-tool accounts are added again and signed in once. macOS asks again for permissions such as Automation, and Open at login needs to be turned on again.

Quit the older app before opening Profile Shelf. Two profile managers running together would compete for the notch and the ⌥⌘ shortcuts.

## Old folders

Nothing is deleted. After you have checked your profiles in Profile Shelf, you can remove the older app and, if you no longer need them, its folders:

- `~/Library/Application Support/Account Dock`, which also holds older separate Claude and tool sign-ins
- `~/Applications/ProfileDock Launchers`, `~/Applications/ProfileDock Apps` and `~/Applications/ProfileDock Dock Apps`
- `~/Library/Caches/nl.breukr.profiledock`

Close any app that was opened from an old profile before removing its folder. Older Claude Code hooks and Codex `profiledock-context` connections can be disconnected from the older app before removing it.

Original license notices and attribution remain in the credits.
