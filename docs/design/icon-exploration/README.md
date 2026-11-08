# Snaptic app icon

The selected icon is **Onyx Latch**: the original Latch geometry with the website’s
off-white mark (`#ffffff`–`#f4f4f5`) on charcoal (`#222227`–`#0d0d0f`).

- `Resources/AppIcon.svg` is the editable vector master.
- `Resources/AppIcon.png` is the transparent 1024 × 1024 export.
- `Resources/AppIcon.icns` contains the standard macOS 16, 32, 128, 256 and 512 pt
  representations at 1× and 2×.

Regenerate with `bash scripts/build-icon.sh` on macOS with Python’s `cairosvg`
package and Cairo (`brew install cairo`) installed. The script uses macOS `sips`
and `iconutil` for resizing and packaging. Generated assets are committed;
normal builds do not need image tooling.
`scripts/build-app.sh` copies the icon into both local and release bundles,
and `Resources/Info.plist` selects it through `CFBundleIconFile`.

The HTML studies preserve the earlier exploration and the neutral color options.
This icon is a conventional `.icns` asset; the studies are not an Icon Composer
asset or automatic macOS appearance variants.
