# Icon appearances

Profile Shelf uses the three-card shelf mark.

- **Auto** restores the default macOS app icon. It does not implement custom light/dark, tint, or clear switching.
- **Dark** and **Light** override the running Dock icon with the selected static artwork.
- **Clear** uses translucent artwork with a light/dark variant matching the app appearance.

Manual choices affect the running Dock icon. Finder keeps the bundled icon. Tinted is no longer offered because its artwork was identical to Light/Dark. Existing saved Tinted preferences remain readable and use Auto without changing profile data.

`swift scripts/render-brand.swift` generates four static PNG previews. `bash build.sh` packages the dark artwork as an ICNS icon; this build does not compile a layered Icon Composer asset.
