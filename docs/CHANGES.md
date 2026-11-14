# Profile Shelf 0.1.0: what's new

Profile Shelf started from ProfileDock commit `5ba7ba2` and goes its own way: a different switching model, new layouts and its own app identity. Version 0.1.0 is the first release; the internal build number is 183.

## What Profile Shelf adds

| Area | What it does |
| --- | --- |
| Quick account access | New bounded account window and menu-bar account popup, provider groups, usage details, explicit routes to/from the dashboard. |
| Notch density | Optional Compact cards, labelled usage rings and expandable usage/reset details. Full remains the default. Existing grid, paging and reordering remain available. |
| Optional menu stats | One remembered ChatGPT/Codex account and one Claude account; account-specific tooltip. Icon only hides stats. Notch only removes the menu item. Readings use the shared scheduler, without an extra polling timer. |
| Switching | A closed desktop account’s Switch action can normally quit other accounts for that provider. Open alongside preserves parallel profiles. An already-open target is brought forward. Added coordination, preflight, uncertain-process guards, quit settlement and launch confirmation. |
| Launchers | Lightweight AppKit forwarding helper, shortcut labels/logo overlays, original-icon reset and upgrade maintenance. The separate launcher adaptation is credited in the third-party notices. |
| Usage recovery | Persistent hashed account/endpoint cooldowns, Retry-After handling and clearer recovery across quick/Full/Compact surfaces. Explicit numeric zero Claude usage can omit a reset time; missing data remains unknown. |
| Terminal labels | Optional project names from live session metadata, with short dynamic terminal IDs as fallback. Display metadata remains separate from the folder used to launch a terminal. |
| Diagnostics | Bounded local redacted switch-stage records, recording toggle, Finder reveal action and visible write-failure notice under General. No new telemetry upload service. |
| Display changes | The notch strip is rebuilt only when the display setup really changes (screens, frames, notch or scale). Dock resizes when apps open or quit no longer collapse it mid-switch. |
| Claude accounts | Separate Claude accounts that are already open are found and added automatically, keeping their existing folder and sign-in. A sign-in hint explains when another Claude window may catch the browser sign-in. Profile Shelf drops an inherited `CLAUDE_CONFIG_DIR` at startup so launched accounts never share another account's settings. New automatic profiles are simply named ChatGPT and Claude. |
| Packaging and branding | Profile Shelf artwork/copy, its own bundle identifier (`io.github.haiderali136a.profileshelf`), data folder, helper names, independent versioning, local build checks, package verification and retained rollback copies. See [identifiers and old folders](REBRANDING.md). |

## Limits

- Manager self-updates are unavailable until Profile Shelf has its own distribution feed. Provider ChatGPT updates remain separate.
- There is no Tinted app icon option. Auto, Dark, Light and Clear are available.
- Compact moves reset dates and secondary quota information behind expansion. Full is available immediately.
- Quick account cards focus on launch state and usage; they do not duplicate every task-attention indicator from the notch.
- Parallel work requires Open alongside when opening a closed account; Switch has different semantics from simply adding another instance.
- Menu stats show two tracked accounts, not all connected profiles or an aggregate quota. Codex limits do not cover every ChatGPT chat limit.
- Separate sign-ins depend on each tool’s supported isolation mechanism. Discovery alone does not promise multi-account support.
- Profile Shelf uses its own bundle identifier and folders, so it does not read ProfileDock or older-build data. Import or Restore Profiles brings ChatGPT profiles across. Profiles within one macOS user are not a security boundary.

See [validation](TEST-RESULTS.md), [privacy](../PRIVACY.md) and [credits](../ACKNOWLEDGMENTS.md). Release downloads and local builds are ad hoc signed, not notarized; there is no self-update feed yet.
