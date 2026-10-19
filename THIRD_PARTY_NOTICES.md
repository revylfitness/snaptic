# Third-party notices

Snaptic is MIT-licensed (see [LICENSE](LICENSE)). This file lists the third-party code, data, standards, and names that Snaptic uses or refers to.

## Vendored code

**None in the source.** Snaptic contains no copied or vendored third-party source code. Everything in `Sources/` was written for Snaptic. GPL-licensed code was not read while writing it.

## Bundled library: Sparkle

Release builds (from 0.3.1 on) embed **[Sparkle](https://sparkle-project.org) 2.10.0** as `Snaptic.app/Contents/Frameworks/Sparkle.framework`, to install updates. It is unmodified, apart from removing its unused XPC services and re-signing it with Snaptic’s Developer ID. It is Snaptic’s only package dependency (`Package.swift`, macOS only, pinned with `exact:`), fetched by Swift Package Manager as Sparkle’s official prebuilt binary. Builds from source without a Developer ID, and `main` and pull-request builds, don’t contain it. Only `Sources/Snaptic/Core/UpdaterController.swift` uses it.

Sparkle is licensed under the MIT License. Its license, including the notices for the code it incorporates (bsdiff, sais-lite, ed25519, and `SUSignatureVerifier.m`), reproduced exactly from [Sparkle 2.10.0’s `LICENSE`](https://github.com/sparkle-project/Sparkle/blob/2.10.0/LICENSE):

```text
Copyright (c) 2006-2013 Andy Matuschak.
Copyright (c) 2009-2013 Elgato Systems GmbH.
Copyright (c) 2011-2014 Kornel Lesiński.
Copyright (c) 2015-2017 Mayur Pawashe.
Copyright (c) 2014 C.W. Betts.
Copyright (c) 2014 Petroules Corporation.
Copyright (c) 2014 Big Nerd Ranch.
All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=================
EXTERNAL LICENSES
=================

bspatch.c and bsdiff.c, from bsdiff 4.3 <http://www.daemonology.net/bsdiff/>:

Copyright 2003-2005 Colin Percival
All rights reserved

Redistribution and use in source and binary forms, with or without
modification, are permitted providing that the following conditions 
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

--

sais.c and sais.h, from sais-lite (2010/08/07) <https://sites.google.com/site/yuta256/sais>:

The sais-lite copyright is as follows:

Copyright (c) 2008-2010 Yuta Mori All Rights Reserved.

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

--

Portable C implementation of Ed25519, from https://github.com/orlp/ed25519

Copyright (c) 2015 Orson Peters <orsonpeters@gmail.com>

This software is provided 'as-is', without any express or implied warranty. In no event will the
authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial
applications, and to alter it and redistribute it freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the
   original software. If you use this software in a product, an acknowledgment in the product
   documentation would be appreciated but is not required.

2. Altered source versions must be plainly marked as such, and must not be misrepresented as
   being the original software.

3. This notice may not be removed or altered from any source distribution.

--

SUSignatureVerifier.m:

Copyright (c) 2011 Mark Hamlin.

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted providing that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
```

## Projects studied

These open-source projects document how undocumented macOS behavior works. Snaptic’s own implementation follows the approaches they describe; no code was copied. They are credited here and in Settings › About › Acknowledgements.

| Project | License | What Snaptic follows | Where |
|---|---|---|---|
| [yabai](https://github.com/koekeishiya/yabai) | MIT | Focusing one specific window from a background app (`_SLPSSetFrontProcessWithOptions` plus a synthetic event record) | `Sources/Snaptic/Switcher/PrivateAPIs.swift` |
| [MonitorControl](https://github.com/MonitorControl/MonitorControl) | MIT | DDC/CI approach on macOS, including the field-proven checksum seed for read requests | `Sources/SnapticKit/DDCPacket.swift` |
| [m1ddc](https://github.com/waydabber/m1ddc) | MIT | DDC on Apple silicon: matching a display to its `DCPAVServiceProxy` in the IORegistry and talking through `IOAVService` | `Sources/SnapticShims/SNDDC.m`, `Sources/SnapticKit/DDCPacket.swift` |
| [displayplacer](https://github.com/jakehilborn/displayplacer) | MIT | Display arrangement, and the record layout of the private CGS display-mode list | `Sources/SnapticKit/DisplayModeDescriptor.swift` |
| BetterDummy (by the BetterDisplay author, released under MIT) | MIT | Cross-check of the same CGS mode-record layout | `Sources/SnapticKit/DisplayModeDescriptor.swift` |
| force-hidpi | MIT | HiDPI virtual displays with `CGVirtualDisplay`, and the argument type of its HDR mode initializer | `Sources/SnapticShims/SNVirtualDisplay.m` |
| [Chromium](https://www.chromium.org/) | BSD-3-Clause | Process-responsibility handling for helper processes (`responsibility_spawnattrs_setdisclaim`), the declared type of the virtual-display HDR initializer, and CoreGraphics’ `'virt'` model number for virtual displays | `Sources/SnapticShims/SNSpawn.m`, `Sources/SnapticShims/SNVirtualDisplay.m`, `Sources/Snaptic/Displays/Platform/LayoutReader.swift` |

Their MIT and BSD licenses ask for their notices in copies of their code. Snaptic includes none of that code, so the credits above are given as thanks rather than as a license condition.

## Keep-awake behavior references (Awake)

Awake’s behavior was designed after studying what these apps do, from their documentation, specifications, and observed behavior. Where Snaptic follows one of their rules closely, it is listed here. No code from them was copied, and Snaptic works differently underneath: its sessions use public IOKit power assertions, where KeepingYouAwake runs `caffeinate`. Its opt-in lid-closed mode does use `pmset disablesleep`, as Insomnia does, but through macOS’s administrator password prompt each time it turns on, never a sudoers rule.

| Project | License | What Snaptic follows | Where |
|---|---|---|---|
| [Insomnia](https://github.com/krishhgg/Insomnia) | MIT | The 30-day session cap including extensions; ending sessions at critical heat; the two-reads rule for a battery that can’t be read; the 5-minute “extend” reminder; warning when another tool left system sleep turned off (`SleepDisabled`); for lid-closed mode (ideas, not code): reading `SleepDisabled` again 5 s after setting it, a recovery journal written before sleep is turned off, and display sleep with the lid closed, honoring display assertions | `Sources/SnapticKit/AwakeClock.swift`, `AwakeGuards.swift`, `AwakeSessionPolicy.swift`, `OtherAssertions.swift`, `AwakeLidPolicy.swift`, `Sources/Snaptic/Awake/Core/LidClosedController.swift` |
| [KeepingYouAwake](https://github.com/newmarcel/KeepingYouAwake) | MIT | Ending a session when Low Power Mode turns on (an option, off by default), and watching power-source changes to apply battery rules | `Sources/SnapticKit/AwakeGuards.swift`, `Sources/Snaptic/Awake/Sources/PowerMonitor.swift`, `SystemEventsMonitor.swift` |

Their MIT licenses ask for their notices in copies of their code. Snaptic includes none of it, so these credits, too, are thanks rather than a license condition.

**Amphetamine** (closed source) was studied only through its App Store description, changelog, and public documentation of Amphetamine Power Protect and Amphetamine Enhancer, to decide which features Awake should offer; nothing of it is used.

**Apple open source.** Apple publishes parts of macOS power management (for example `caffeinate.c` and `pmconfigd` in the PowerManagement project, `IOPMLibPrivate.h`, and xnu’s `IOPMrootDomain.cpp`) under the Apple Public Source License. These were read only to understand how power assertions and the `SleepDisabled` setting behave (for example that macOS releases a process’s assertions when it exits, and that the kernel doesn’t re-check a closed lid when `SleepDisabled` clears). **No code from APSL sources is included or adapted**; Snaptic calls only the public API declared in the macOS SDK’s `IOKit/pwr_mgt/IOPMLib.h`. This is behavior only.

## Standards and formats

Snaptic implements these from their public descriptions. No specification text is included.

- **VESA DDC/CI** and **MCCS** (Monitor Control Command Set): VCP codes, request framing, and the capabilities string. `Sources/SnapticKit/DDCPacket.swift`, `DDCReply.swift`, `DDCCapabilities.swift`, `VCPPolicy.swift`. The standard input names (“HDMI 1”, “DisplayPort 1”, …) follow the MCCS input-source values. LG’s alternate input command is used for LG monitors that need it.
- **VESA E-EDID**: decoding a display’s name, size, and color data. `Sources/SnapticKit/EDIDInfo.swift`.
- **Adobe / DaVinci Resolve `.cube` 3D LUT format**: importing color lookup tables for Picture in Picture filters. `Sources/SnapticKit/CubeLUT.swift`.
- **ICC color profiles**, read and assigned through Apple’s ColorSync.

VESA, DDC/CI, MCCS, and E-EDID are trademarks or standards of the Video Electronics Standards Association.

## Apple frameworks

Apart from Sparkle (above), Snaptic links or loads only frameworks that ship with macOS; none are redistributed.

- **Public:** Foundation, AppKit, SwiftUI, Combine, CoreGraphics, QuartzCore, CoreImage, CoreVideo, CoreMedia, IOSurface, Metal, ScreenCaptureKit, ColorSync, IOKit (including its power-management API), ApplicationServices (Accessibility), Carbon (HIToolbox, for hotkeys and keyboard type), CoreAudio, SystemConfiguration, DiskArbitration, Security, CryptoKit, ServiceManagement, UniformTypeIdentifiers, and libSystem’s `notify` API.
- **Undocumented, loaded at runtime and never linked:** SkyLight, CoreDisplay, DisplayServices, CoreBrightness, MonitorPanel, OSD, plus private symbols in CoreGraphics, IOKit, and libsystem. Awake uses none of these; it only reads undocumented keys through public calls: `CGSSessionScreenIsLocked` from `CGSessionCopyCurrentDictionary`, the `SleepDisabled` power setting from the `com.apple.PowerManagement` preferences with `CFPreferencesCopyValue`, and the `SleepDisabled` and `AppleClamshellState` properties of `IOPMrootDomain` through IOKit. Its opt-in lid-closed mode runs Apple’s own command-line tools (`osascript`, `pmset`, `ioreg`, `notifyutil`, and standard shell tools), which ship with macOS. See “Undocumented APIs” in the [README](README.md).

SF Symbols are used through the system APIs and are not bundled. Apple, Mac, macOS, Sidecar, AirPlay, XDR, Night Shift, True Tone, and SF Symbols are trademarks of Apple Inc. Snaptic is not affiliated with or endorsed by Apple.

## Names of other products

Snaptic refers to other products by name only to detect them or to describe compatibility. No names, icons, identifiers, or other assets of these products are used as Snaptic’s own.

- **BetterDisplay**, **MonitorControl**, and **Lunar** are detected by bundle-identifier prefix (`Sources/SnapticKit/OtherDisplayApps.swift`) so Snaptic can pause overlapping features while they run.
- **AltTab** is named in the README only to say Snaptic is not derived from it.
- **1Password, Bitwarden, Apple Passwords, Tor Browser**, and other password managers and private browsers appear in the default “never capture” list by bundle identifier. **Firefox, Edge, and Chrome** private-window titles are recognized so those windows are left out of captures.
- **Parallels** and other virtual-machine and remote-desktop apps are matched by bundle identifier in the switcher’s exceptions.
- **DisplayLink** and **LG** are named in user-facing text to describe hardware behavior.
- **Stream Deck** and **Raycast** are named in the README as places to run `snaptic` commands.
- **GitHub** is named in Settings, onboarding, and the README as where updates come from, and **Homebrew** in the README for a possible future cask.
- **Amphetamine**, **Amphetamine Power Protect**, **Amphetamine Enhancer**, **Insomnia**, and **KeepingYouAwake** are named in the README and these notices to explain Awake’s choices and how to switch, and “amphetamine”, “insomnia”, and “caffeinate” are search words in Settings so people find Awake by the names they know. Snaptic doesn’t detect, read, or change these apps or their files.

All trademarks belong to their owners.

## Website

The website (`site/`) uses the **DM Sans** typeface, loaded from Google Fonts and not bundled in this repository. DM Sans is © The DM Sans Project Authors and is licensed under the [SIL Open Font License, Version 1.1](https://openfontlicense.org/). The website contains no other third-party code, images, or fonts; its illustrations, icons, and demo content are original and fictional.
