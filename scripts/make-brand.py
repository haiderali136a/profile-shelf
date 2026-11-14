#!/usr/bin/env python3
"""Generate Profile Shelf's editable SVG marks and README headers. No dependencies."""
import json
from pathlib import Path
root = Path(__file__).resolve().parent.parent
brand = root / 'Resources/Brand'
mark = {'size': 64, 'cards': [10, 26, 42], 'cardY': 20, 'cardWidth': 12, 'cardHeight': 32, 'radius': 4, 'shelf': [6, 10, 52, 4]}
(brand/'mark.json').write_text(json.dumps(mark, indent=2)+'\n')
def shapes(color):
    parts=[]
    for x in mark['cards']:
        parts += [f'<rect x="{x}" y="12" width="12" height="32" rx="4" fill="{color}"/>', f'<circle cx="{x+6}" cy="23" r="3" fill="currentColor"/>', f'<rect x="{x+3}" y="31" width="6" height="2" rx="1" fill="currentColor"/>']
    parts += [f'<rect x="6" y="50" width="52" height="4" rx="2" fill="{color}"/>']
    return ''.join(parts)
for theme in ['dark','light','black','white']:
    dark=theme in ['dark','white']; fg='#FFFFFF' if dark else '#181818'; bg='#181818' if dark else '#FFFFFF'
    background=f'<rect width="64" height="64" rx="12" fill="{bg}"/>' if theme in ['light','dark'] else ''
    # Transparent template marks have genuine cutouts, not background-colored holes.
    artwork=shapes(fg).replace('fill="currentColor"','fill="black"')
    masked=shapes('white').replace('fill="currentColor"','fill="black"')
    svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 64 64" role="img" aria-label="Profile Shelf"><defs><mask id="mark"><rect width="64" height="64" fill="black"/>{masked}</mask></defs>{background}<rect width="64" height="64" fill="{fg}" mask="url(#mark)"/></svg>\n'
    (brand/f'mark-{theme}.svg').write_text(svg)
for dark in [False,True]:
    bg='#181818' if dark else '#FFFFFF'; fg='#FFFFFF' if dark else '#000000'; secondary='#9B9B9B' if dark else '#666666'; line='#313131' if dark else '#9B9B9B'
    cards=''
    for x,label in [(80,'Personal'),(432,'Work'),(784,'Side project')]:
        cards+=f'<rect x="{x}" y="320" width="336" height="96" rx="12" fill="none" stroke="{line}"/><circle cx="{x+40}" cy="368" r="12" fill="{fg}"/><text x="{x+72}" y="376" fill="{fg}" font-size="24">{label}</text>'
    svg=f'''<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="480" viewBox="0 0 1200 480" role="img" aria-label="Profile Shelf. Profiles for your AI apps, one click away."><defs><linearGradient id="title"><stop stop-color="{fg}"/><stop offset="1" stop-color="{secondary}"/></linearGradient></defs><rect width="1200" height="480" rx="24" fill="{bg}"/><g font-family="Manrope, sans-serif"><text x="80" y="144" fill="url(#title)" font-size="60" font-weight="600" letter-spacing="-2">Profile Shelf</text><text x="80" y="200" fill="{secondary}" font-size="24">Profiles for your AI apps, one click away.</text><text x="80" y="256" fill="{secondary}" font-size="16">macOS · Open source · Desktop apps &amp; coding tools</text>{cards}<path d="M80 440h1040" stroke="{fg}" stroke-width="4" stroke-linecap="round"/></g></svg>\n'''
    (root/'docs'/('hero-dark.svg' if dark else 'hero.svg')).write_text(svg)
print('Generated Profile Shelf vector marks and headers.')
