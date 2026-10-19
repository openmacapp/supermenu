# SuperMenu icons and system localization

`AppIconSource.png` and `MenuBarSource.png` are the original transparent PNGs
generated with the built-in image tool. `scripts/build-icons.sh` derives the
macOS `.icns` sizes and 18 pt / 36 px menu-bar images with `sips` and `iconutil`.
Generated sizes live in `dist/`, not in source control. No image service or
third-party image library is needed to build the app.

`Host/MenuIcons.swift` shares the template image and SF Symbols between the
SwiftUI menu bar and the Finder extension. Finder symbols use an adaptive label
color before serialization, as well as template rendering, for light and dark
appearances. Installed apps use their own full-color icons
from `NSWorkspace`; unavailable apps use a template fallback. Finder exposes
one context-menu entry with five categories and no additional toolbar button.

The four `.lproj` folders contain system-facing app names, permission descriptions,
and Services menu titles. Keep the Services keys equal to `NSMenuItem.default` in
`App/Info.plist`. These strings follow macOS language preferences. App-selected
languages use `Sources/SuperMenuCore/Resources/*/Localizable.strings`; they do not
override the system's language or permissions.

## Image-tool prompts

### AppIconSource.png

Use case: logo-brand. Asset type: one production macOS application icon for SuperMenu, a right-click productivity utility. A completely new identity based on the physical RIGHT mouse button. Design ONE finished square app icon, not a sheet. On a beautifully proportioned soft porcelain-white macOS rounded-square tile, place a compact elegant wireless mouse seen exactly from above, rotated about 12 degrees counterclockwise. The mouse has a clean continuous pill-shaped outline, a pearl-white lower body and left button, a crisp softly rounded coral-orange RIGHT button, and a tiny graphite scroll wheel. The right-button color is a small purposeful accent, not the whole background. A subtle warm gray seam separates the buttons and body. Two very small graphite click rays just beyond the upper-right button communicate right-click. Quiet exquisite industrial-design quality, precise curves, good optical weight, abundant negative space, soft tactile satin finish, only very slight contact depth, a clean clear silhouette at 32px. Mouse should occupy about 58 percent of the tile width and 68 percent of height. Restrained palette: porcelain #FAFAF7, soft aluminum gray #D8DADD, graphite #41464D, coral #F4856D. No green, no purple, no blue gradient, no cursor arrow, no menu card, no hamburger lines, no lettering, no watermark, no busy embellishment, no thick black outline, no heavy shadows or glass effects. Tile occupies 82 percent of the square canvas. Surrounding canvas fully transparent with clean antialiased rounded tile edges. Straight-on orthographic icon artwork, no mockup, no scene. Freshness must come from spacing, proportion, simplicity and precise geometry.

### MenuBarSource.png

Use case: logo-brand. Asset type: one production macOS menu-bar TEMPLATE glyph for a right-click utility. Draw a minimal bold BLACK silhouette of a computer mouse seen from above, rotated 12 degrees counterclockwise. Smooth rounded pill-shaped outer silhouette, clear transparent interior with an outline thick enough to read at 18px. The upper RIGHT mouse button is solid black, separated from the empty upper left button and lower body by crisp transparent seams. Tiny black scroll-wheel dash near the central vertical division. Only ONE short black click ray outside the upper-right button, with a large clear gap so it does not merge at small size. Pure black marks, fully transparent holes and background. Very simple precise geometry, balanced optical weight, centered, occupies 80 percent of square canvas. All strokes substantial, no delicate hairlines. No tile, no app background, no white paint, no gray, no colored areas, no shadow, no gradient, no text, no arrow, no menu panel. A recognizable right-button mouse icon intended for 18x18 and 36x36 pixels. Transparent alpha background.
