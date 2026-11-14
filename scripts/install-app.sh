#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
destination="${1:-/Applications/Profile Shelf.app}"
source_app="${2:-$project_dir/dist/Profile Shelf.app}"
stage_dir="$(mktemp -d /private/tmp/profile-shelf-local-install.XXXXXX)"
trap 'rm -rf "$stage_dir"' EXIT
ditto --norsrc --noextattr "$source_app" "$stage_dir/Profile Shelf.app"
source_app="$stage_dir/Profile Shelf.app"
xattr -cr "$source_app"
if pgrep -x ProfileShelf >/dev/null || pgrep -x AccountDock >/dev/null; then
    echo "Quit Profile Shelf before installing." >&2
    exit 1
fi
codesign --verify --strict "$source_app"
backup=""
if [[ -e "$destination" ]]; then
    existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")"
    if [[ "$existing_id" == "nl.breukr.account-dock" ]]; then
        echo "An older build (ProfileDock identity) is installed at $destination. Quit it and move it out of that folder, then run this again. Its data is not affected." >&2
        exit 1
    fi
    [[ "$existing_id" == "io.github.haiderali136a.profileshelf" ]] || { echo "An unrelated app already uses this name." >&2; exit 1; }
    backup="${destination%.app}.backup-$(date +%Y%m%d%H%M%S)-$$.app"
    mv "$destination" "$backup"
fi
if ! ditto --norsrc --noextattr "$source_app" "$destination" || ! codesign --verify --strict "$destination"; then
    [[ -n "$backup" ]] && { rm -rf "$destination"; mv "$backup" "$destination"; }
    exit 1
fi
echo "Installed: $destination"

python3 "$project_dir/scripts/retain-app-backups.py" "$destination" --prefix "$(basename "${destination%.app}").backup-" || echo 'Installation succeeded; backup cleanup was deferred and existing copies were kept.' >&2
