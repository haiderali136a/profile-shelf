#!/bin/bash
# Local Profile Shelf build. No global SDK changes, vendor app changes,
# credential migration, or administrator access.
set -euo pipefail
install=0
skip_tests=0
for argument in "$@"; do
  case "$argument" in
    --install) install=1 ;;
    --skip-tests) skip_tests=1 ;;
    -h|--help)
      printf '%s\n' 'Usage: bash build.sh [--install] [--skip-tests]' \
        'Default: run the XCTest suite, build and optionally install.' \
        '--skip-tests explicitly builds without running XCTest (local preview only).'
      exit 0 ;;
    *) printf 'Unknown option: %s\n' "$argument" >&2; exit 2 ;;
  esac
done
[[ "$(uname -s)" == Darwin ]] || { echo 'Build on your Mac using Apple Command Line Tools or Xcode.' >&2; exit 1; }
[[ "$(uname -m)" == arm64 ]] || { echo 'This build packages Apple Silicon only.' >&2; exit 1; }
if [[ "$install" -eq 1 ]] && { pgrep -x ProfileShelf >/dev/null || pgrep -x AccountDock >/dev/null; }; then
  echo 'Quit Profile Shelf (and any older build) from its menu-bar menu, then retry. ChatGPT and Claude can stay open.' >&2
  exit 1
fi
project_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$project_dir"
unset SDKROOT TOOLCHAINS SWIFT_EXEC SWIFT_DRIVER_SWIFT_FRONTEND_EXEC SWIFT_RESOURCE_DIR
# XCTest belongs to full Xcode. Prefer an installed Xcode when the active
# Command Line Tools cannot provide its runner. This changes this process only.
if [[ -z "${DEVELOPER_DIR:-}" ]] && ! /usr/bin/xcrun --sdk macosx --find xctest >/dev/null 2>&1; then
  for candidate in /Applications/Xcode*.app/Contents/Developer "$HOME"/Applications/Xcode*.app/Contents/Developer; do
    [[ -d "$candidate" ]] || continue
    if DEVELOPER_DIR="$candidate" /usr/bin/xcrun --sdk macosx --find xctest >/dev/null 2>&1; then
      export DEVELOPER_DIR="$candidate"
      printf 'Using installed Xcode for this build: %s\n' "$candidate"
      break
    fi
  done
fi
if [[ "$skip_tests" -eq 0 ]] && ! /usr/bin/xcrun --sdk macosx --find xctest >/dev/null 2>&1; then
  printf '%s\n' 'XCTest is unavailable in the selected developer tools.' \
    'For a tested build, install/select full Xcode and retry.' \
    'To explicitly build a local preview without the XCTest suite, run:' \
    '  bash build.sh --install --skip-tests' >&2
  exit 1
fi
sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
swift_bin="$(/usr/bin/xcrun --sdk macosx --find swift)"
export SDKROOT="$sdk"
printf 'Apple Swift: %s\nmacOS SDK: %s\n' "$swift_bin" "$sdk"
cache_root="$HOME/Library/Caches/ProfileShelf"
[[ ! -L "$cache_root" ]] || { echo 'The Profile Shelf build cache is a symlink; choose a normal cache folder.' >&2; exit 1; }
build_cache="$cache_root/SwiftPM/arm64"
mkdir -p "$build_cache"
chmod 700 "$cache_root"
printf 'Shared build cache: %s\n' "$build_cache"
python3 scripts/tests/test_backup_retention.py
stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/profile-shelf.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
# Dependency-free checks still run when XCTest is explicitly skipped.
swiftc_bin="$(/usr/bin/xcrun --sdk macosx --find swiftc)"
"$swiftc_bin" -sdk "$sdk" -target arm64-apple-macos14.0 -parse-as-library \
  Sources/DockCore/ProfileSwitchPolicy.swift scripts/tests/ProfileSwitchSmoke.swift \
  -o "$stage_dir/switch-checks"
"$stage_dir/switch-checks"
# Runs the full test suite before packaging.
if [[ "$skip_tests" -eq 1 ]]; then
  printf '%s\n' 'XCTest suite skipped at your request. Standalone policy, backup and packaged-helper checks still run.' >&2
else
  "$swift_bin" build --scratch-path "$build_cache" --product ProfileShelfShim -Xswiftc -sdk -Xswiftc "$sdk"
  debug_bin="$("$swift_bin" build --scratch-path "$build_cache" --show-bin-path)"
  PROFILE_SHELF_SHIM_PATH="$debug_bin/ProfileShelfShim" "$swift_bin" test --scratch-path "$build_cache" -Xswiftc -sdk -Xswiftc "$sdk"
fi
"$swift_bin" build --scratch-path "$build_cache" -c release --arch arm64 -Xswiftc -sdk -Xswiftc "$sdk"
binary_dir="$("$swift_bin" build --scratch-path "$build_cache" -c release --arch arm64 --show-bin-path)"
bundle="$stage_dir/Profile Shelf.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$bundle/Contents/Frameworks"
for executable in ProfileShelf ProfileShelfClaude ProfileShelfContext; do
  cp "$binary_dir/$executable" "$bundle/Contents/MacOS/$executable"
done
cp "$binary_dir/ProfileShelfLauncher" "$bundle/Contents/Resources/ProfileShelfLauncher"
cp "$binary_dir/ProfileShelfShim" "$bundle/Contents/Resources/ProfileShelfShim"
ditto Resources/profile-shelf-context "$bundle/Contents/Resources/ContextPlugin"
ditto Resources/Sounds "$bundle/Contents/Resources/Sounds"
ditto Resources/Brand "$bundle/Contents/Resources/Brand"
ditto Resources/IconPreviews "$bundle/Contents/Resources/IconPreviews"
sparkle="$build_cache/artifacts/sparkle/Sparkle"
ditto --norsrc --noextattr "$sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$bundle/Contents/Frameworks/Sparkle.framework"
cp "$sparkle/LICENSE" "$bundle/Contents/Resources/Sparkle-LICENSE.txt"
cp THIRD_PARTY_NOTICES.md "$bundle/Contents/Resources/ThirdPartyNotices.txt"
cp LICENSE "$bundle/Contents/Resources/LICENSE.txt"
mkdir -p "$bundle/Contents/Resources/Documentation"
cp README.md PRIVACY.md CONTRIBUTING.md ACKNOWLEDGMENTS.md "$bundle/Contents/Resources/Documentation/"
ditto docs "$bundle/Contents/Resources/Documentation/docs"
# Package the Profile Shelf artwork without requiring actool.
iconset="$stage_dir/ProfileShelf.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/IconPreviews/dark.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -z "$doubled" "$doubled" Resources/IconPreviews/dark.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$bundle/Contents/Resources/ProfileShelf.icns"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.haiderali136a.profileshelf</string>
<key>CFBundleName</key><string>Profile Shelf</string>
<key>CFBundleDisplayName</key><string>Profile Shelf</string>
<key>CFBundleExecutable</key><string>ProfileShelf</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>183</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>ProfileShelfRepositoryURL</key><string>https://github.com/haiderali136a/profile-shelf</string>
<key>CFBundleIconFile</key><string>ProfileShelf</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>ProfileShelfBuild</key><true/>
<key>LSUIElement</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Profile Shelf opens and selects the Terminal window you choose.</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
# No self-update feed for Profile Shelf yet. Provider app updates are unchanged.
plutil -lint "$bundle/Contents/Info.plist"
python3 scripts/sign-bundle.py "$bundle"
mkdir -p dist
output="$project_dir/dist/Profile Shelf.app"
if [[ -e "$output" ]]; then
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$output/Contents/Info.plist")" == io.github.haiderali136a.profileshelf ]] || {
    echo "dist/Profile Shelf.app has a different identity (for example an older build). Move it out of dist, then run this again." >&2; exit 1; }
  mv "$output" "$project_dir/dist/Profile Shelf.previous-$(date +%Y%m%d%H%M%S)-$$.app"
fi
ditto "$bundle" "$output"
printf 'Built: %s\n' "$output"
python3 scripts/launcher-smoke.py "$output"
if [[ "$skip_tests" -eq 0 ]]; then
  PROFILE_SHELF_APP_PATH="$output" "$swift_bin" test --scratch-path "$build_cache" --skip-build --filter AppManagementTests.testPackagedFinderLauncherIsLightweightAndStarts
fi
python3 scripts/retain-app-backups.py "$output" --prefix 'Profile Shelf.previous-' || echo 'Build backup cleanup was deferred; existing copies were kept.' >&2
if [[ "$install" -eq 1 ]]; then
  # AccountDock is the process name of older local builds; two managers must not run together.
  if pgrep -x ProfileShelf >/dev/null || pgrep -x AccountDock >/dev/null; then
    echo 'Quit Profile Shelf (and any older build) from its menu-bar menu, then rerun. No installed app or account data was changed.' >&2
    exit 1
  fi
  # Back up only metadata, never copy tokens, cookies or account databases.
  metadata="$HOME/Library/Application Support/Profile Shelf/preferences.json"
  if [[ -f "$metadata" ]]; then
    backup_dir="$HOME/Library/Application Support/Profile Shelf/Backups/$(date +%Y%m%d%H%M%S)-$$"
    mkdir -p "$backup_dir"; chmod 700 "$backup_dir"
    cp -p "$metadata" "$backup_dir/preferences.json"; chmod 600 "$backup_dir/preferences.json"
  fi
  mkdir -p "$HOME/Applications"
  bash scripts/install-app.sh "$HOME/Applications/Profile Shelf.app" "$output"
  if [[ -f "$metadata" ]]; then
    python3 scripts/retain-app-backups.py --metadata-dir "$HOME/Library/Application Support/Profile Shelf/Backups" || echo 'Metadata backup cleanup was deferred; existing snapshots were kept.' >&2
  fi
  open "$HOME/Applications/Profile Shelf.app"
fi
