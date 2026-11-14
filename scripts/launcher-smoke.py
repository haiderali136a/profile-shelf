#!/usr/bin/env python3
"""Validate the packaged forwarding executable with fictional metadata only.
Never opens a manager, provider app, profile directory or OAuth session.
"""
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

app=Path(sys.argv[1])
helper=app/'Contents/Resources/ProfileShelfLauncher'
assert helper.is_file(), 'Missing lightweight launcher'
linked=subprocess.check_output(['/usr/bin/otool','-L',str(helper)],text=True)
assert 'Sparkle' not in linked, 'Forwarder unexpectedly links Sparkle'
assert helper.stat().st_size < 1_048_576, 'Forwarder exceeds 1 MiB budget'
with tempfile.TemporaryDirectory(prefix='profile-shelf-launcher-fixtures-') as directory:
    bundle=Path(directory)/'Fixture.app'
    binary=bundle/'Contents/MacOS/ProfileLauncher'
    binary.parent.mkdir(parents=True)
    shutil.copy2(helper,binary)
    info={'CFBundleIdentifier':'io.github.haiderali136a.profileshelf.launcher.fixture','CFBundleExecutable':'ProfileLauncher','CFBundlePackageType':'APPL','LSUIElement':True}
    for profile, expected in [('profile-fictional',0),('../unsafe',1),(None,1)]:
        metadata=dict(info)
        if profile is not None: metadata['ProfileShelfProfileID']=profile
        (bundle/'Contents/Info.plist').write_bytes(plistlib.dumps(metadata))
        result=subprocess.run([str(binary),'--validate-launcher'],capture_output=True,text=True,timeout=10)
        assert result.returncode==expected, (profile,result.returncode)
        if expected==0: assert result.stdout.strip()==profile
print(f'Packaged launcher: no Sparkle, {helper.stat().st_size:,} bytes; 3 metadata fixtures passed.')
