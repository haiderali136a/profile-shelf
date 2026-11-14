# Testing

## Run the checks

With full Xcode supporting Swift 6 and Python 3 installed, run from the source folder:

```sh
bash build.sh
```

It runs the native XCTest suite, the standalone switch-policy and backup-retention checks, the release build, signature checks and a packaged-launcher smoke test. `bash build.sh --skip-tests` builds a local preview without XCTest; the standalone checks still run.

Every push and pull request runs the same `bash build.sh` on GitHub Actions.

## Latest results (0.1.0, build 183)

- Native suite: 411 tests, 392 passed, 19 skipped, 0 failed. Skips are opt-in or environment-dependent cases, such as settings rendering and packaged-app checks.
- Packaged Finder-launcher test: passed.
- Backup retention: 11 passed. Switch policy: 25 checks passed.
- Release bundle: deep/strict signature verification passed.

## Tested by hand

On a MacBook Pro with a notch (Apple Silicon), using the installed app:

- Hovering the notch opens the panel; the strip stays put when other apps open or quit.
- Switching between two ChatGPT accounts: the open account quits normally and the other one opens.
- Open alongside keeps two accounts open together.
- ChatGPT/Codex and Claude Desktop accounts, including an existing separate Claude account picked up automatically.
- Usage readings for both ChatGPT and both Claude accounts.
- Antigravity, opened while Profile Shelf was running, was added automatically within seconds.
- The release DMG, installed into `/Applications` with the browser download flag: macOS blocks it until allowed, then it opens with the notch strip, menu-bar item and usage for every account.

## Not yet covered

These have not been verified and are welcome reports:

- First run on a fresh macOS user or Mac: permissions, provider sign-in and onboarding.
- A full day of normal use, sleep/wake, Spaces and full-screen transitions, and multiple displays.
- Clicking outside the menu-bar popup to close it.
- Coding tools other than ChatGPT/Codex, Claude and Antigravity, provider updates, shortcut upgrades and data removal.

Passing checks are not a guarantee that the app is free of bugs.
