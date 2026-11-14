#!/usr/bin/env python3
"""Retain one verified rollback app after a verified successful build/install.
Only matching app bundles are considered. Unknown, linked and unsigned files
are preserved. The optional metadata mode handles generated preferences-only
backup folders; active preferences, account data and build caches are excluded.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys

BUNDLE_ID = 'io.github.haiderali136a.profileshelf'

def owned_app(path):
    path = Path(path)
    if path.is_symlink() or not path.is_dir() or path.resolve() != path.absolute():
        return False
    contents = path/'Contents'
    info = contents/'Info.plist'
    if contents.is_symlink() or info.is_symlink() or not info.is_file():
        return False
    try:
        return plistlib.loads(info.read_bytes()).get('CFBundleIdentifier') == BUNDLE_ID
    except (OSError, ValueError, plistlib.InvalidFileException):
        return False

def verified(path):
    return owned_app(path) and subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0

def retain(current, prefix, verify=verified, remove=shutil.rmtree):
    current = Path(current).absolute()
    # Validate the active copy before considering any deletion.
    if not verify(current):
        raise ValueError('Current app was not verified; no backups were removed.')
    if prefix != current.stem + '.backup-' and prefix != current.stem + '.previous-':
        raise ValueError('Unexpected backup prefix; no backups were removed.')
    pattern = re.compile(re.escape(prefix) + r'[0-9]{14}(?:-[0-9]+)?\.app\Z')
    candidates = [p for p in current.parent.iterdir() if pattern.fullmatch(p.name) and owned_app(p)]
    # Timestamp lives in the name because moving an app preserves its old mtime.
    candidates.sort(key=lambda p: p.name, reverse=True)
    valid = [p for p in candidates if verify(p)]
    removed = []
    for path in valid[1:]:
        # Reverify after selecting retention; fail closed on concurrent changes.
        if not verify(current) or not verify(valid[0]):
            raise ValueError('The current or retained app changed; cleanup stopped.')
        if not owned_app(path) or not verify(path):
            continue
        remove(path)
        removed.append(path.name)
    return removed

def retain_metadata(directory):
    directory=Path(directory).absolute()
    if directory.is_symlink() or directory.resolve()!=directory or not directory.is_dir() or directory.stat().st_uid!=os.getuid():
        raise ValueError('Metadata backup location was not verified; nothing was removed.')
    def valid(folder):
        if folder.is_symlink() or not folder.is_dir() or folder.stat().st_uid!=os.getuid(): return False
        if not re.fullmatch(r'[0-9]{14}-[0-9]+',folder.name): return False
        files=list(folder.iterdir())
        if len(files)!=1 or files[0].name!='preferences.json': return False
        file=files[0]
        if file.is_symlink() or not file.is_file() or file.stat().st_uid!=os.getuid() or file.stat().st_size>8_388_608: return False
        try:
            data=json.loads(file.read_text())
            return isinstance(data,dict) and isinstance(data.get('profiles'),list)
        except (OSError,ValueError): return False
    candidates=sorted((p for p in directory.iterdir() if valid(p)),key=lambda p:p.name,reverse=True)
    removed=[]
    for old in candidates[1:]:
        if not valid(candidates[0]): raise ValueError('Retained metadata changed; cleanup stopped.')
        if valid(old): shutil.rmtree(old); removed.append(old.name)
    return removed

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('current', type=Path, nargs='?')
    parser.add_argument('--prefix')
    parser.add_argument('--metadata-dir',type=Path)
    args = parser.parse_args()
    if args.metadata_dir is not None:
        if args.current is not None or args.prefix is not None: parser.error('Choose app retention or metadata retention.')
        removed=retain_metadata(args.metadata_dir)
        print(f'Metadata backup retention: removed {len(removed)} older verified preference snapshots.')
        return
    if args.current is None or args.prefix is None: parser.error('App retention requires current and --prefix.')
    if sys.platform != 'darwin':
        parser.error('App signature verification requires macOS.')
    # Do not delete a bundle from which the manager might currently be running.
    if subprocess.run(['/usr/bin/pgrep', '-x', 'ProfileShelf'], stdout=subprocess.DEVNULL).returncode == 0:
        print('Backup retention deferred while Profile Shelf is running.')
        return
    removed = retain(args.current, args.prefix)
    print(f'App backup retention: removed {len(removed)} older verified copies; kept the newest verified rollback.')

if __name__ == '__main__':
    main()
