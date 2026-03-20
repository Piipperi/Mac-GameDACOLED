# GameDAC OLED Controller

Vibe coded Apple Silicon native macOS menu bar app for SteelSeries OLED devices such as the Nova Pro's GameDAC. It uses SteelSeries' local GameSense API, so it might work on other SS peripherals with OLED displays as well.

## What it does

- Runs as a hidden menu bar utility with an optional control window
- Sends OLED frames through the official local SteelSeries GameSense endpoint
- Remembers its settings across relaunches
- Exposes Shortcuts actions for switching display modes

## Modes

- `Off`
  Clears the OLED once and stops sending frames.

- `Clock`
  Shows a large `HH:mm` clock with optional date. Updates on the minute boundary instead of every second.

- `System`
  Shows a large clock plus CPU, GPU, and RAM usage.
  Supports:
  - optional date
  - adjustable update rate
  - Unix-style CPU percentages
  - optional `%` hiding

- `Visualizer`
  Shows a 12-band audio visualizer.
  Supports:
  - system audio capture
  - microphone input with remembered device selection
  - adjustable gain
  - optional 2-second AirPlay delay
  - optional CPU/GPU/RAM overlay
  - separate `%` hiding for the overlay
  - Unix-style CPU percentages for the overlay

- `Media`
  Shows either a still image or an animated GIF.
  Supports:
  - remembered file selection
  - contrast adjustment
  - zoom/scaling adjustment
  - invert
  - optional dithering, enabled by default
  - transparent pixels staying uninverted when invert is enabled

## Shortcuts

The app exports fixed App Shortcuts actions for:

- `Turn OLED Off`
- `Show Clock`
- `Show System`
- `Show Visualizer`
- `Show Media`

These actions switch modes without opening the main app window.

## Build

```bash
swift build
```

To build the standalone app bundle:

```bash
scripts/build-app.sh
```

Output:

```bash
dist/GameDAC OLED Controller.app
```

The bundle build also embeds the generated `Metadata.appintents` resources needed for Shortcuts discovery.

## Run

From source:

```bash
swift run
```

Or launch the built app bundle:

```bash
open "dist/GameDAC OLED Controller.app"
```

## Requirements

- macOS 13+
- SteelSeries GG or SteelSeries Engine running locally
- A SteelSeries device that supports the `screened-128x52` OLED handler

The app looks for the local GameSense `coreProps.json` in locations such as:

- `/Library/Application Support/SteelSeries GG/coreProps.json`
- `/Library/Application Support/SteelSeries Engine 3/coreProps.json`
- `~/Library/Application Support/SteelSeries GG/coreProps.json`
- `~/Library/Application Support/SteelSeries Engine 3/coreProps.json`

## Notes

- The OLED payload uses the documented `image-data-128x52` frame key.
- The app explicitly registers the GameSense event and sends changing event values to avoid overly aggressive caching.
- Static content is kept alive with GameSense heartbeats.
- GPU usage is read from macOS `IOAccelerator` / `AGXAccelerator` statistics when available.
- RAM usage follows a macOS-style used-memory calculation closer to tools like Stats/iStat Menus.
- The bundled app uses `LSUIElement`, so it stays out of the Dock by default.
