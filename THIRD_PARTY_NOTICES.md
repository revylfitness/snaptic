# Third-party notices

Snaptic is MIT-licensed (see [LICENSE](LICENSE)). This file lists the third-party code, data, standards and names that Snaptic uses or refers to.

## Vendored code

**None.** Snaptic contains no copied or vendored third-party source code, libraries or binaries, and has no package dependencies (see `Package.swift`). Everything in `Sources/` was written for Snaptic. GPL-licensed code was not read while writing it.

## Projects studied

These open-source projects document how undocumented macOS behavior works. Snaptic's own implementation follows the approaches they describe; no code was copied. They are credited here and in Settings → General → About & Licenses.

| Project | License | What Snaptic follows | Where |
|---|---|---|---|
| [yabai](https://github.com/koekeishiya/yabai) | MIT | Focusing one specific window from a background app (`_SLPSSetFrontProcessWithOptions` plus a synthetic event record) | `Sources/Snaptic/Switcher/PrivateAPIs.swift` |
| [MonitorControl](https://github.com/MonitorControl/MonitorControl) | MIT | DDC/CI approach on macOS, including the field-proven checksum seed for read requests | `Sources/SnapticKit/DDCPacket.swift` |
| [m1ddc](https://github.com/waydabber/m1ddc) | MIT | DDC on Apple silicon: matching a display to its `DCPAVServiceProxy` in the IORegistry and talking through `IOAVService` | `Sources/SnapticShims/SNDDC.m`, `Sources/SnapticKit/DDCPacket.swift` |
| [displayplacer](https://github.com/jakehilborn/displayplacer) | MIT | Display arrangement, and the record layout of the private CGS display-mode list | `Sources/SnapticKit/DisplayModeDescriptor.swift` |
| BetterDummy (by the BetterDisplay author, released under MIT) | MIT | Cross-check of the same CGS mode-record layout | `Sources/SnapticKit/DisplayModeDescriptor.swift` |
| force-hidpi | MIT | HiDPI virtual displays with `CGVirtualDisplay`, and the argument type of its HDR mode initializer | `Sources/SnapticShims/SNVirtualDisplay.m` |
| [Chromium](https://www.chromium.org/) | BSD-3-Clause | Process-responsibility handling for helper processes (`responsibility_spawnattrs_setdisclaim`), the declared type of the virtual-display HDR initializer, and CoreGraphics' `'virt'` model number for virtual displays | `Sources/SnapticShims/SNSpawn.m`, `Sources/SnapticShims/SNVirtualDisplay.m`, `Sources/Snaptic/Displays/Platform/LayoutReader.swift` |

Their MIT and BSD licenses ask for their notices in copies of their code. Snaptic includes none of that code, so the credits above are given as thanks rather than as a license condition.

## Standards and formats

Snaptic implements these from their public descriptions. No specification text is included.

- **VESA DDC/CI** and **MCCS** (Monitor Control Command Set): VCP codes, request framing and the capabilities string. `Sources/SnapticKit/DDCPacket.swift`, `DDCReply.swift`, `DDCCapabilities.swift`, `VCPPolicy.swift`. The standard input names ("HDMI 1", "DisplayPort 1", …) follow the MCCS input-source values. LG's alternate input command is used for LG monitors that need it.
- **VESA E-EDID**: decoding a display's name, size and color data. `Sources/SnapticKit/EDIDInfo.swift`.
- **Adobe / DaVinci Resolve `.cube` 3D LUT format**: importing color lookup tables for Picture in Picture filters. `Sources/SnapticKit/CubeLUT.swift`.
- **ICC color profiles**, read and assigned through Apple's ColorSync.

VESA, DDC/CI, MCCS and E-EDID are trademarks or standards of the Video Electronics Standards Association.

## Apple frameworks

Snaptic links or loads only frameworks that ship with macOS; none are redistributed.

- **Public:** Foundation, AppKit, SwiftUI, Combine, CoreGraphics, QuartzCore, CoreImage, CoreVideo, CoreMedia, IOSurface, Metal, ScreenCaptureKit, ColorSync, IOKit, ApplicationServices (Accessibility), Carbon (HIToolbox, for hotkeys and keyboard type), CoreAudio, Security, CryptoKit, ServiceManagement, UniformTypeIdentifiers.
- **Undocumented, loaded at runtime and never linked:** SkyLight, CoreDisplay, DisplayServices, CoreBrightness, MonitorPanel, OSD, plus private symbols in CoreGraphics, IOKit and libsystem. See "Undocumented APIs" in the [README](README.md).

SF Symbols are used through the system APIs and are not bundled. Apple, Mac, macOS, Sidecar, AirPlay, XDR, Night Shift, True Tone and SF Symbols are trademarks of Apple Inc. Snaptic is not affiliated with or endorsed by Apple.

## Names of other products

Snaptic refers to other products by name only to detect them or to describe compatibility. No names, icons, identifiers or other assets of these products are used as Snaptic's own.

- **BetterDisplay**, **MonitorControl** and **Lunar** are detected by bundle-identifier prefix (`Sources/SnapticKit/OtherDisplayApps.swift`) so Snaptic can pause overlapping features while they run.
- **AltTab** is named in the README only to say Snaptic is not derived from it.
- **1Password, Bitwarden, Apple Passwords, Tor Browser** and other password managers and private browsers appear in the default "never capture" list by bundle identifier. **Firefox, Edge, Chrome** private-window titles are recognized so those windows are left out of captures.
- **Parallels** and other virtual-machine and remote-desktop apps are matched by bundle identifier in the switcher's exceptions.
- **DisplayLink** and **LG** are named in user-facing text to describe hardware behavior.
- **Stream Deck** and **Raycast** are named in the README as places to run `snaptic` commands.

All trademarks belong to their owners.

## Website

The website (`site/`) uses the **DM Sans** typeface, loaded from Google Fonts and not bundled in this repository. DM Sans is © The DM Sans Project Authors and is licensed under the [SIL Open Font License, Version 1.1](https://openfontlicense.org/). The website contains no other third-party code, images or fonts; its illustrations, icons and demo content are original and fictional.
