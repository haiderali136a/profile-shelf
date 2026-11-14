# README image sources

The README uses two kinds of media.

## Screen recordings of the real app

- `switch.gif` (still: `switch.png`): the installed app on a MacBook. The notch panel opens, ChatGPT Work is clicked, ChatGPT Personal quits and ChatGPT Work becomes active. The wait for the other app to quit is sped up 3×, and the final state is held for about 2.5 seconds so it can be read.
- `working-wide.gif` (still: `working-wide.png`): the installed app on a MacBook. The panel drops from the notch while two accounts are running tasks.

These were recorded with macOS screen recording, not generated. Profile names are generic, but the usage readings are real values from the recorded accounts. Both are cropped to the notch area and trimmed where another app's window came forward. An organization badge on the two Work profile icons was painted over with the badge's own white. Nothing else in the app UI was altered.

## Native captures with sample data

The images below are offscreen captures of Profile Shelf’s production SwiftUI/AppKit components, not HTML mockups or AI-generated app screenshots. They use an isolated temporary home, fictional profile IDs/names and an in-memory usage client. No real authentication, account history, provider requests or sign-in files are used.

- `full.png`, `compact.png`, `compact-details.png`: the actual `IslandView`/Compact components, with four sample desktop profiles. Names, icons, remaining quotas, reset times, launch states and controls are drawn by the app.
- `desktop-terminal.png`: the same Compact `IslandView` with the four sample desktop profiles plus one sample Claude Code terminal session in the Terminals section. The terminal window, TTY and project folder are fixture values; no real terminal or project is read. Dark only, because the notch is always black.
- `quick-dark.png`, `quick-light.png`: the actual `QuickSwitchPanel`, using a two-profile example in a valid resized window. The installed app defaults to a larger height; longer lists scroll.
- `menu-dark.png`, `menu-light.png`: an isolated capture of the real `MenuBarSummaryArtwork` component, not a screenshot of the entire macOS menu bar. It shows two sample provider rows.
- `layouts-dark.gif`, `layouts-light.gif`: a timed sequence of native Full/Compact/detail captures on a fixed-size canvas, preserving their relative footprint. It is not a recording of clicks, switching speed or live quota refreshes. No cursor or fake transition animation is added. A static capture is provided for reduced motion.

The notch itself remains black in both macOS appearances. Theme variants are supplied for the account window, menu component and animation canvas. Vendor marks are visible as part of the app UI; no affiliation is implied.

## Regenerate

Use a disposable source copy, not a checkout with work in progress. With the same Xcode/Swift prerequisites as the app build:

```sh
cp scripts/readme-assets/NativeCapture.swift Tests/ProfileShelfTests/ReadmeAssetsRenderingTests.swift
SHELF_README_MEDIA_DIR=/private/tmp/profile-shelf-readme-media \
  swift test --filter ReadmeAssetsRenderingTests
python3 scripts/readme-assets/make-sequence.py /private/tmp/profile-shelf-readme-media
```

FFmpeg is needed only for GIF assembly. Do not commit the temporary XCTest file. Inspect every exported image before replacing the published assets. The screen recordings above are not produced by this script. Copy `full-dark.png` to `full.png`, `compact-dark.png` to `compact.png`, and `compact-details-dark.png` to `compact-details.png`; the other published filenames stay as exported.

The capture source lives under `scripts` and is not compiled into the app or normal test suite. Readings in these native captures are deliberately labelled sample data in the README. The shorter remaining-quota percentages correspond to the menu/account window’s used percentages; they are not separate live account statistics.
