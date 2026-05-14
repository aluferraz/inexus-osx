# iNexus OSX

Native macOS driver and menu-bar app for the **Corsair iCUE Nexus** touchscreen
(640×48, VID `0x1B1C` / PID `0x1B8E`). No iCUE, no hidapi, no Rosetta — just
IOKit/IOHIDManager and AppKit.

The wire protocol is reverse-engineered from
[willneedit/NexusTool](https://github.com/willneedit/NexusTool) (Linux) and is
identical on macOS, since the Nexus is a plain USB HID device with no vendor
kernel driver.

## Targets

- **`NexusCore`** — Swift library: device discovery, brightness, blank,
  firmware-embedded animations, full-frame image upload, touch input + gesture
  recognition. RGBA8 640×48 frames in, byte-level USB-HID reports out.
- **`nexusctl`** — CLI for one-shot commands and protocol debugging.
- **`NexusBar`** — menu-bar app that draws a clock + CPU meter to the screen,
  with brightness slider and touch shortcuts.

## Build & run

```bash
swift build -c release
.build/release/nexusctl info
.build/release/NexusBar
```

### Build the installable .app

```bash
scripts/build-app.sh                  # produces build/NexusBar.app
scripts/build-app.sh /Applications    # also installs into /Applications
```

The bundle is ad-hoc signed. On first launch macOS may need a right-click →
Open to bypass Gatekeeper (since the signature isn't from a registered Apple
developer). After that, **Preferences → Launch at login** works via
`SMAppService` — it only takes effect when running from the .app bundle.

## CLI quick reference

```text
nexusctl info                     read firmware version
nexusctl brightness 0..100        set backlight (0 turns it off)
nexusctl blank                    clear the panel
nexusctl anim 1|2|3 [--loop]      play firmware-embedded animation
nexusctl stop-anim                stop a looping animation
nexusctl image path/to/img.png    resize-and-push an image
nexusctl touch [seconds]          stream touch events until timeout
nexusctl demo                     push a rainbow test pattern
```

## NexusBar features

Menu-bar app: click the icon in the menu bar for **Preferences…**, blank /
restore, push a custom image, reconnect, quit.

**Preferences let you change:**

- **Display layout** — Clock + CPU, Clock + CPU + Memory, Date + Clock,
  Clock only, CPU + Memory
- **Theme** — Dark, Midnight Blue, Sunset, Monochrome, Ocean
- **Time format** — 24h or 12h, with or without seconds
- **Brightness** — 0–100
- **Refresh rate** — 0.5s to 10s
- **Launch at login** (requires running from the installed .app bundle)

All settings persist in `UserDefaults` and apply live without restarting.

### Background image (menu → Background Image…, or ⌘I)

Drop any image into the window or click **Choose Image…**. The live clock /
CPU / memory overlay your image — the image is the *background*, not a
replacement. Options:

- **Scale** — Stretch, Fit (letterbox), Fill (crop to fill), Center (1:1)
- **Dim** — 0–100% black overlay so text stays readable on bright images
- **Live preview** — 2× preview shows exactly what the device renders, with
  the current time and stats on top

The image path persists across launches. Use **Remove Background** to clear.

### Touch shortcuts (on the Nexus itself)

- Tap left half → blank / restore
- Tap right half → open status-bar menu
- Swipe left → brightness −20
- Swipe right → brightness +20

## Permissions

Reading/writing HID reports to a non-keyboard, non-pointer device requires no
entitlements on macOS. If macOS prompts for Input Monitoring it's because the
device matched as input-like — granting once is sufficient.
