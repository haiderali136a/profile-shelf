# Profile Shelf branding

**Name:** Profile Shelf  
**Tagline:** Profiles for your AI apps, one click away.  
**Repository slug:** `profile-shelf`

The mark shows three profile cards resting on a shelf. It is monochrome so the menu bar can choose the appropriate contrast. The app ships light, dark, and translucent icon appearances using the same geometry.

- [Dark mark](../Resources/Brand/mark-dark.svg)
- [Light mark](../Resources/Brand/mark-light.svg)
- [Black template](../Resources/Brand/mark-black.svg)
- [White template](../Resources/Brand/mark-white.svg)
- [README header](hero.svg)

Run `python3 scripts/make-brand.py` to regenerate the SVGs and README headers. Run `swift scripts/render-brand.swift` on macOS to regenerate the four PNG previews. `build.sh` packages those previews into the app icon. `BrandArtwork.swift` draws the same mark as a native template image.

In-app guides and credits are bundled for local use. Set `ProfileShelfRepositoryURL` in the app metadata (as `build.sh` does) to link the app to its source and issues.

Historical bundle IDs, defaults keys, helpers, and storage paths are compatibility details, not public branding. See [REBRANDING.md](REBRANDING.md).
