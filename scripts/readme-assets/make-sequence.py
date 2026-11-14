#!/usr/bin/env python3
"""Assemble unmodified native capture frames into a layout comparison, using FFmpeg."""
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
ffmpeg = shutil.which("ffmpeg")
if not ffmpeg:
    raise SystemExit("FFmpeg is required only for GIF assembly.")
for theme in ("dark", "light"):
    entries = []
    for name, seconds in (("full", 2.4), ("compact", 2.0), ("compact-details", 3.2), ("compact", 1.2), ("full", 1.0)):
        path = root / f"sequence-{name}-{theme}.png"
        if not path.is_file():
            raise SystemExit(f"Missing native capture: {path.name}")
        # FFmpeg's concat-file syntax uses single quotes and shell-like escaping.
        quoted = str(path).replace("'", "'\\''")
        entries.extend((f"file '{quoted}'", f"duration {seconds}"))
    quoted = str(root / f"sequence-full-{theme}.png").replace("'", "'\\''")
    entries.append(f"file '{quoted}'")
    manifest = root / f"{theme}-sequence.txt"
    manifest.write_text("\n".join(entries) + "\n")
    subprocess.run([ffmpeg, "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", str(manifest),
        "-filter_complex", "[0:v]fps=5,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3",
        "-loop", "0", str(root / f"layouts-{theme}.gif")], check=True)
