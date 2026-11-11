<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/readme/logo-dark.svg">
    <img src="docs/assets/readme/logo.svg" width="220" alt="Vorssaint logo">
  </picture>
</p>

<h1 align="center">Vorssaint <sub>(personal fork)</sub></h1>

<p align="center">
  <strong>This is a fork, not the original repository.</strong><br>
  Based on <a href="https://github.com/vorssaint/vorssaint-utils">vorssaint/vorssaint-utils</a>.
  Not affiliated with, endorsed by or supported by the Vorssaint maintainer.
</p>

<p align="center">
  <a href="https://github.com/vorssaint/vorssaint-utils">Upstream repository</a> ·
  <a href="https://vorssaint.com">Upstream website</a> ·
  <a href="https://github.com/vorssaint/vorssaint-utils/releases">Official releases</a> ·
  <a href="#what-this-fork-changes">Fork changes</a> ·
  <a href="#dexcom-glucose">Dexcom glucose</a> ·
  <a href="#install">Install</a>
</p>

<p align="center">
  <a href="https://github.com/RileyvKing/vorssaint-utils"><img src="https://img.shields.io/badge/fork-RileyvKing%2Fvorssaint--utils-4c8dff" alt="Fork of vorssaint/vorssaint-utils"></a>
  <a href="#what-you-need"><img src="https://img.shields.io/badge/macOS-14%2B%20Apple%20Silicon-black" alt="macOS 14 and newer, Apple Silicon"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0--or--later-blue" alt="License GPL 3.0 or later"></a>
</p>

> **Fork notice**
>
> This is a personal fork maintained by [@RileyvKing](https://github.com/RileyvKing). It exists to add a Dexcom Share glucose readout to the Dynamic Island. Everything else is the upstream project, and all credit for Vorssaint belongs to its maintainers.
>
> Official downloads, documentation, support and community live upstream at [vorssaint/vorssaint-utils](https://github.com/vorssaint/vorssaint-utils) and [vorssaint.com](https://vorssaint.com). This repository is not an official Vorssaint release, and upstream cannot support the changes here.

<p align="center">
  One menu bar icon doing the job of a dozen paid Mac apps.<br>
  Install only what you use.
</p>

## What this fork changes

| | Upstream | This fork |
| --- | --- | --- |
| Repository | [vorssaint/vorssaint-utils](https://github.com/vorssaint/vorssaint-utils) | [RileyvKing/vorssaint-utils](https://github.com/RileyvKing/vorssaint-utils) |
| Features | The original Vorssaint toolkit | Upstream, plus a **Dexcom Share glucose** section in the Dynamic Island |
| Releases | Signed and notarized | **None**; build from source |
| Support | The Vorssaint maintainer | This fork's maintainer, for the glucose changes only |

The fork currently adds one feature on top of upstream `main`:

- **Dexcom Share glucose in the Dynamic Island.** A glucose value, trend arrow and the last day's trace from a Dexcom Share account, with configurable low/high colors and an optional priority mode that lets a fresh reading lead the closed island.

Everything else — features, design, build scripts and documentation — comes from upstream, with the docs amended only where the glucose section needs it. The fork-specific work lives in:

- [`Sources/Vorssaint/Services/Glucose/`](Sources/Vorssaint/Services/Glucose) — the Share API client, reading model, polling service and Keychain storage
- [`NotchGlucoseView.swift`](Sources/Vorssaint/UI/Notch/NotchGlucoseView.swift) and [`NotchGlucoseStrip.swift`](Sources/Vorssaint/UI/Notch/NotchGlucoseStrip.swift) — the expanded page and closed-island strip
- [`NotchGlucoseSettings.swift`](Sources/Vorssaint/UI/Settings/NotchGlucoseSettings.swift) — sign-in, test and threshold controls
- [`Tests/GlucoseTests.swift`](Tests/GlucoseTests.swift) — parsing, trend, freshness and request-shape tests
- [`docs/PRIVACY.md`](docs/PRIVACY.md) — one added paragraph for the Dexcom Share connection

To see exactly what differs, compare the branches: [upstream `main`...this fork's `main`](https://github.com/vorssaint/vorssaint-utils/compare/main...RileyvKing:main).

If you want the original app without the glucose section, install the official build from upstream. This fork does not publish binaries.

## Dexcom glucose

It shows a Dexcom Share glucose reading in the Dynamic Island. It is a convenience display, not a medical device: do not use it for treatment decisions.

### What you get

- **Closed island strip.** The drop icon, the current value and the trend arrow, colored by your target range. When *Glucose takes the island while fresh* is on, a reading less than ten minutes old leads the closed island ahead of music, agents and other activities. With the option off, glucose keeps its place after them.
- **Glucose page.** The value and trend arrow, how long ago it was confirmed, and a sparkline of the last 24 hours. Readings below the low threshold are red, above the high threshold yellow, and in range green. Values outside the sensor's measuring range appear as `LOW` or `HIGH` instead of a number.
- **Settings.** Install the feature from the Features hub, then sign in under Dynamic Island → Glucose. You can choose the low and high thresholds (default `80` and `200 mg/dL`) and turn the closed-island priority off.

### Setting it up

1. In Dexcom's mobile app, make sure Share is enabled for the account. This integration reads through Dexcom Share, not directly from the sensor.
2. In Vorssaint, turn on the Dynamic Island, then make sure the Glucose feature is installed under Settings → Features → Dynamic Island.
3. Open the Glucose settings and enter the username and password of the account that runs the Dexcom mobile app, **not a follower's account**.
4. Choose the region where the account was created: **United States**, **Outside the United States**, or **Japan**. A mismatched region is the most common reason a sign-in fails.
5. Press **Save & Test**. A success message shows the latest reading from the last day. The credentials are then saved in the login Keychain.

To remove the saved account, press **Clear Credentials**. The cached last reading stays on this Mac but stops being shown once it is stale; the 24-hour history is kept in memory for the session.

### How it works

- It talks to Dexcom's legacy Share service over HTTPS. The endpoint depends on the selected region (`share2.dexcom.com`, `shareous1.dexcom.com` or `share.dexcom.jp`).
- While the section is enabled, it asks for the newest reading once a minute — the sensor itself only adds one every five minutes. A new reading is used for up to ten minutes, which is the window Dexcom uses for a current value; after that the strip disappears and the page marks the reading as old.
- It normally fetches the newest two readings. While the Glucose page is open it asks for up to 288 readings (24 hours, the Share API's maximum) so the sparkline can fill.
- If Dexcom omits a trend, the app computes one from the two newest readings using Dexcom's rate bands.
- Errors back off instead of retrying hard: network failures retry after 30 seconds and other failures after 60 seconds, doubling up to five minutes. An invalid password or a rate-limit response stops polling until you change the credentials or press Refresh.
- The session lives in memory in an ephemeral `URLSession` with no cookies or cache. The last reading is cached in the app's preferences so the island can show it on the next launch, but only while it is still fresh and the section is on. That cache is excluded from settings exports.

### Privacy and credentials

Enabling glucose adds one outbound connection: the requests to Dexcom Share described above. Dexcom sees them as it would see any Share client, including your public IP address. The app sends only the sign-in and the reading request; it does not send anything to Vorssaint, this fork's maintainer or any analytics service.

Your Dexcom username and password are stored as generic passwords in the **login Keychain** under `com.vorssaint.utils.glucose`. They are not written to preferences, backups or logs. The password remains in memory only for the lifetime of the API client, so an expired session can be renewed once. Readings are cached locally in the app's preferences.

### Limitations

- **Dexcom Share only.** It does not read a sensor directly over Bluetooth, and it does not support Nightscout, Libre, Apple Health or other CGM sources.
- **Not a medical device.** It has no low or high alarms, no urgent-low handling and no guarantee of timely delivery. Keep using Dexcom's own app and alarms for treatment decisions.
- **mg/dL only.** Values and thresholds are shown in mg/dL; there is no mmol/L display option yet.
- **English only.** The glucose screens ship in English even when the rest of the app is in another language.
- **Basic implementation.** The legacy Share API is undocumented and can change. Fork-specific bugs belong in [this repository's issues](https://github.com/RileyvKing/vorssaint-utils/issues), not upstream.

<p align="center">
  <img src="docs/assets/readme/panel-mixer.png" width="196" alt="Volume mixer with per app sliders, one app boosted past 100 percent">
  <img src="docs/assets/readme/panel-system.png" width="196" alt="System tab with temperatures, usage graphs and memory pressure">
  <img src="docs/assets/readme/panel-controls.png" width="196" alt="Window controls with the app switcher and Dock features">
  <img src="docs/assets/readme/panel-utilities.png" width="196" alt="Utilities with cleaner, Homebrew, media tools and clipboard">
</p>

Per app volume, a real system monitor, a better app switcher, window snapping, Dock previews, clipboard history, text snippets, a file shelf, an uninstaller. The utilities Mac users usually buy one by one, together behind a single menu bar icon, with no account, no telemetry and no subscription. This fork adds a Dexcom Share glucose section to that list.

## Install only what you use

Choose individual features or start with a preset. Uninstalled features stop loading and disappear from the interface; reinstalling restores their settings. Setup asks only for the permissions your choices need.

<p align="center">
  <img src="docs/assets/readme/features-hub.png" width="720" alt="The Features hub in Settings, installing and uninstalling whole features">
</p>

Reorder or hide panel sections, choose a compact layout, and export settings to another Mac or [keep them in your dotfiles](docs/TROUBLESHOOTING.md#keeping-settings-in-your-dotfiles). The app supports more than a dozen languages.

## Everything it does

### Sound

- **Volume mixer.** Set volume per app, boost quiet audio past 100%, and pin or reorder favorites. No audio driver required.
- **Per app output.** Play music through speakers while a call uses your headset.
- **Output switcher.** Switch audio outputs with a shortcut and lower the volume when headphones disconnect.
- **Microphone tools.** Choose a preferred input, adjust its level on supported devices, and apply available microphone mute or input-volume controls with one shortcut. Siri and some apps may still hear you; Mic Mute is not a privacy lock. Its indicator shows that the feature is on, not that every app receives silence.
- **Music app blocker.** Prevent unwanted Music launches after detected playback-button presses. Requires Accessibility.

### Know what your Mac is doing

- **System monitor.** CPU, GPU, memory, temperatures, battery health and power use, with history graphs and a view of energy-hungry apps.
- **Fan Control (beta).** Set manual fan speeds or temperature curves and monitor live RPM.
- **Menu bar readouts.** Put your chosen readings, usage bars, battery time or fan speed directly in the menu bar.
- **Network.** See live traffic, session totals and your local IP address, or run a speed test.
- **Alerts.** Get notified about sustained CPU load, high temperatures, memory pressure, low disk space or low battery.

### Windows and the Dock

- **App switcher.** Switch between apps and windows with live previews, search and display filters. A simpler mode works without screen capture.
- **Window layout.** Snap windows into layouts, move them between displays and restore earlier positions using shortcuts, screen edges or modifier-drag gestures.
- **Dock Preview.** Hover over Dock icons to preview windows across desktops. Switch, close, move or snap them from the preview.
- **Dock clicks.** Click an active app's Dock icon to minimize, hide or cycle through its windows.
- **Maximize windows.** Use the green button to fill the screen without creating another Space.
- **Fixed Space order.** Keep Spaces in the order you set instead of rearranging them by recent use. Turning it off restores your previous setting.
- **Quit on close.** Quit selected apps when their last window closes.
- **Quit and close protection.** Prevent accidental ⌘Q or ⌘W with a hold, double press or extra modifier, per app.

<p align="center">
  <img src="docs/assets/readme/quit-protection-hold.png" width="300" alt="The hold-to-confirm prompt showing progress below the Command-Q quit shortcut hint">
</p>

<p align="center">
  <img src="docs/assets/readme/window-switcher.gif" width="540" alt="The window switcher showing live thumbnails of open windows">
</p>

### Keyboard and mouse

- **Text snippets.** Expand short triggers into text with clipboard, date and time variables, or insert snippets from a searchable menu.
- **Smooth scrolling.** Give your mouse wheel a fluid glide with adjustable speed and response.
- **Pointer acceleration.** Disable mouse acceleration and restore your previous setting when turned off.
- **Linear scrolling.** Make every mouse wheel notch scroll the same number of lines, however fast the wheel spins.
- **Focus follows mouse.** Bring the window under the pointer forward after an adjustable pause.
- **Scroll direction.** Invert vertical and horizontal mouse scrolling independently of the trackpad.
- **Scroll sideways while holding a key.** Turn vertical wheel movement into horizontal scrolling while holding a chosen key.
- **Side buttons.** Use mouse Back and Forward buttons in Finder, browsers and compatible apps.
- **Mouse button shortcuts.** Assign keys to extra buttons and side wheels, or use button-drag gestures for Spaces and Mission Control.
- **Middle click.** Turn a three-finger trackpad press into a middle click.
- **Apps to leave alone.** Exclude chosen apps from mouse enhancements.
- **Extra click filter.** Ignore accidental rapid clicks from worn mouse buttons without delaying normal clicks.
- **Key debounce.** Filter repeated letters caused by a worn keyboard.
- **Super key.** Use Caps Lock or a right-side modifier as a shortcut combination, with a separate tap action and app exclusions.
- **Keyboard shortcuts.** Manage feature shortcuts in one place, including optional takeover of supported macOS shortcuts while a feature is active.

### Clipboard, files and links

- **Clipboard history.** Search local text, image and file history, pin favorites, preview entries and paste with shortcuts.
- **Auto clear clipboard.** Clear the system clipboard after a delay, sleep or lock, while keeping saved history.
- **Paste as plain text.** Paste without formatting while preserving the original clipboard content.
- **Shelf.** Park files, text and links near your cursor while dragging, then drop or share them later.
- **Finder shortcuts.** Move files with ⌘X and ⌘V, rename with F2, or paste copied images as PNG files.
- **Clean URL.** Remove tracking parameters from links, manually or automatically.
- **Disk image installer.** Install an app from a mounted disk image and eject it, with optional download cleanup.

### Everyday tools

- **Dynamic Island.** Keep music, notifications, calendars, timers, downloads and everyday controls around the camera cutout, or a simulated one on other Macs. Customize sections and shortcuts, with optional lyrics, a live equalizer, camera preview and file tools.
- **Glucose (this fork only).** Show your Dexcom Share reading, its trend arrow and the last day's trace in the Dynamic Island. See [Dexcom glucose](#dexcom-glucose) for setup and limitations.
- **AI agents.** Follow Claude, Codex, OpenCode and GitHub Copilot in the Dynamic Island: plan limits and when they reset where available, tokens, API value, models, projects and live work, with a notice when a long task finishes. Codex's banked resets can be used from there too, and each extra Codex account (`CODEX_HOME`) can have a limits card of its own. Copilot uses local CLI/app session logs; its token totals update when shutdown metrics arrive, and aggregate API-value estimates use base rates.
- **Command Bar.** Search apps, windows, files, clipboard history, snippets and app menu commands from one field. Calculate, convert units, find emoji or run saved scripts.
- **Quick panel.** Open a floating palette of favorite tools with ⌃⌘V.
- **Quick toggles.** Switch appearance, hide desktop icons, eject disks, empty the Trash, lock the screen and more.
- **Quit apps.** See every open app in one list and quit them one by one, all at once or all but the one in front.
- **Radial menu.** Open a customizable wheel of apps, files, shortcuts and tools around the pointer, with profiles and submenus.
- **Scratchpad.** Keep autosaved notes in tabs, with Markdown preview and export, in a floating window or Dynamic Island.
- **Cleaning Mode.** Lock keyboard input while cleaning, with a black screen or a small visible indicator.

### Capture and create

- **Screen capture.** Switch between screenshots, recording, text recognition and color picking in one selector with a pixel magnifier.
- **Screenshot.** Capture an area, window, screen or scrolling page. Annotate, crop, redact, add backgrounds and watermarks, pin captures, send them through the Share menu or share an expiring link.
- **Screen recording.** Record with separate system-audio and microphone tracks. Trim, cut, add automatic zooms, blur private details and export video or GIFs, or share an expiring link.
- **Camera preview.** Check your camera in a floating mirror or Dynamic Island before a call.
- **Copy text from screen.** Recognize text offline from any screen area, or read a QR code.
- **Color picker.** Copy a screen color as HEX, RGB, HSL or SwiftUI code.
- **Media tools.** Compress and edit videos, batch-convert images, add watermarks, make GIFs and extract text, all locally.

### App management

- **App updates.** Check store apps, package-managed apps and supported developer feeds in one list. Install managed updates together or open an app's own updater.
- **Cleaner.** Remove caches, logs and app leftovers, manually or on a schedule.
- **Messaging downloads.** Review, organize or move messaging downloads to the Trash using retention rules.
- **Uninstaller.** Remove apps and review their related caches, preferences and helpers before moving them to the Trash.
- **Homebrew manager.** Search, install and remove formulae and casks without opening a terminal.
- **Port manager.** Find processes listening on network ports and stop them with Kill Process when installed.

### Energy and display

- **Keep awake.** Keep your Mac working on a timer, with the lid closed, or while selected apps, power or external displays are present.
- **Displays.** Control individual displays and brightness, with hardware control where supported, half or quarter steps for the brightness keys, optional extra dimming below a monitor's minimum, software dimming as a fallback, and the volume and mute of a monitor's built-in speakers.
- **Extra brightness.** Use a MacBook Pro XDR display's HDR headroom to go beyond its normal maximum brightness.
- **Bluetooth on sleep.** Disconnect Bluetooth during sleep and restore it on wake only if Vorssaint turned it off.

## Install

This fork publishes no signed or notarized binaries. Build it from source instead.

```sh
git clone https://github.com/RileyvKing/vorssaint-utils.git
cd vorssaint-utils
./build.sh --dev            # build the separate "Vorssaint (Developer)" variant
./build.sh --dev --install  # install it in /Applications and launch it
```

The Developer variant has its own bundle identifier, so it can sit beside an official Vorssaint install. The build script creates a stable local signing identity when one is not already installed, falling back to ad hoc signing if that fails; only upstream releases are signed with an Apple Developer ID and notarized.

If you want the official app without the glucose section, install upstream Vorssaint with [Homebrew](https://brew.sh) or from its [releases page](https://github.com/vorssaint/vorssaint-utils/releases):

```sh
brew install --cask vorssaint
```

## Uninstall

If you installed the Developer variant from this fork, quit it first, then remove the app and its local state:

```sh
rm -rf "/Applications/Vorssaint (Developer).app"
defaults delete com.vorssaint.utils.dev
rm -rf "$HOME/Library/Application Support/com.vorssaint.utils.dev"
```

Use **Clear Credentials** in the Glucose settings first if you also want the Dexcom account removed from the login Keychain. The upstream [uninstall script](Tools/uninstall.sh) targets the official app and its bundle identifier, not the Developer variant.

## Private by default

Vorssaint is local-first, with no account, analytics or tracking. The network is touched only by things you can see: update checks, the speed test, Homebrew actions, optional online lyric lookup, Dexcom Share requests when the glucose section is enabled, temporary screenshot or recording links and feedback you explicitly send. The full story is in the [privacy notes](docs/PRIVACY.md).

Permissions get the same treatment. Every one is optional, the app explains each in plain words, shows which features actually use it, and even tells you when a permission you granted is no longer needed by anything, with a shortcut to revoke it.

<p align="center">
  <img src="docs/assets/readme/permissions.png" width="720" alt="The Permissions page showing what each permission does, which features use it, and an unused permission warning">
</p>

See the [permissions guide](docs/PERMISSIONS.md) for which features need access and what remains available without it.

## What you need

- A Mac with Apple Silicon
- macOS 14 Sonoma or newer
- Xcode Command Line Tools, to build this fork from source

See [Install](#install) for the build commands. The [contributing guide](CONTRIBUTING.md) covers the layout and conventions.

Official builds come only from the upstream maintainer: the GPL covers the source, while the Vorssaint name, icon and look are covered by [TRADEMARKS.md](TRADEMARKS.md). This fork is not an official Vorssaint release.

## When something misbehaves

See [troubleshooting](docs/TROUBLESHOOTING.md) for launch problems, permissions and missing previews, or [support](SUPPORT.md) for help.

## Documentation

- [Privacy](docs/PRIVACY.md), what does and does not leave your Mac
- [Permissions](docs/PERMISSIONS.md), every macOS permission in plain words
- [Troubleshooting](docs/TROUBLESHOOTING.md), the common fixes
- [Contributing](CONTRIBUTING.md), build, layout and conventions
- [Support](SUPPORT.md), where to get help
- [Security](SECURITY.md), how to report a vulnerability

These are the upstream documents carried over by the fork. For official guidance and support, use the [upstream documentation](https://github.com/vorssaint/vorssaint-utils/tree/main/docs) and [upstream support](https://github.com/vorssaint/vorssaint-utils/blob/main/SUPPORT.md). For the glucose integration, use [this repository's issues](https://github.com/RileyvKing/vorssaint-utils/issues).

## Upstream project

Vorssaint is created and maintained by [@vorssaint](https://github.com/vorssaint). It went from first commit to the front of GitHub trending in three days and top of the Swift charts, and issues and pull requests have shaped every release since. Bug reports, feature ideas and translations for Vorssaint itself belong upstream, starting from the [upstream contributing guide](https://github.com/vorssaint/vorssaint-utils/blob/main/CONTRIBUTING.md).

Vorssaint is free and will stay that way. If it earned its place in your menu bar, star the [upstream repository](https://github.com/vorssaint/vorssaint-utils) and consider [buying the upstream maintainer a coffee](https://buymeacoffee.com/vorssaint). Upstream also has a [Discord](https://discord.gg/M6BwWH4BJp).

## This fork

Maintained by [@RileyvKing](https://github.com/RileyvKing). For fork-specific bugs, setup questions or improvements to the Dexcom integration, [open an issue in this repository](https://github.com/RileyvKing/vorssaint-utils/issues). Please do not send fork-specific reports upstream. General Vorssaint fixes and features should go to the [upstream repository](https://github.com/vorssaint/vorssaint-utils).

## Acknowledgements

- App icon designed by [@divisionseven](https://github.com/divisionseven)
- Vorssaint created and maintained upstream by [@vorssaint](https://github.com/vorssaint)

## License

[GPL 3.0 or later](LICENSE), copyright 2026 Vorssaint. Fork modifications copyright 2026 Riley King and released under the same license. The license covers the source code; the Vorssaint name, logo and look are covered separately in [TRADEMARKS.md](TRADEMARKS.md), and this fork does not claim to be an official Vorssaint release.

<p align="center">
  <sub>Vorssaint by <a href="https://x.com/vorssaint">@vorssaint</a> · this fork maintained by <a href="https://github.com/RileyvKing">@RileyvKing</a></sub>
</p>
