# WorldClock — design brief

A native macOS menu-bar world clock, built in Swift/SwiftUI on macOS 15+. This brief describes everything the app does today and the design direction we want. The app is fully functional; what it needs is a visual language.

## The idea

There is only one moment in time — the **Global Instant** — and every surface renders it. Each saved city (**Location**) shows that one moment through its own timezone. Dragging anywhere doesn't change *a* clock, it moves *the* moment, and every city, date label, and the 3D Earth's sunlight move together. Returning to **Now** snaps the moment back to the real clock.

## Surfaces

### 1. The Panel (primary)

A floating panel anchored under the menu-bar icon (currently 320×360, borderless, material background). Opened by clicking the tilted-Earth menu-bar icon or ⌥Space from anywhere. Closes on Esc or focus loss. It contains:

- **Header** (currently a thin strip; wants redesign): shows "Now", or during Time Travel an accented "Time Travel · Tomorrow · 16:30" with a Now button, plus a globe button.
- **Location rows**, one per saved city. Each row shows:
  - City name (Home row shows a "Home" marker — the first row is Home, the reference for offsets)
  - Secondary caption: relative offset ("+5h") or UTC offset ("UTC+9") depending on mode; clicking it briefly reveals both; hovering the row swaps it for a local-language greeting with English gloss ("こんばんは · Good evening")
  - Time (12/24h per system or override), date label when the city's date differs from Home's ("Tomorrow", "Mon, Jul 13")
  - Optional weather: small condition glyph + temperature
  - **Day Line**: the row's signature — a horizontal 24-hour bar, night dark / twilight warm / day bright, computed from real astronomy (NOAA equations), with an indicator at the local time: a glowing sun by day, a phase-correct moon by night. **Dragging the Day Line scrubs time** for the whole app (±7 days), with subtle snapping to hours/half-hours/sunrise/sunset (Option disables snap, Shift = fine control).
- **"+ Add Location" footer** → search overlay.

### 2. Search overlay (in-panel)

Press A or click Add Location: the panel becomes a search field + results over a 34,000-city offline database. Matches names, alternate names, airport codes ("SFO"), country names, timezone abbreviations ("JST"), UTC offsets ("UTC+9"). Results show name, country, timezone, current local time. Return/click adds; Esc cancels.

### 3. ⌘K command overlay (in-panel)

Fuzzy command palette: Add/Show/Remove <city>, Switch to UTC/Relative Mode, Return to Now, Open Globe, Settings. Arrow keys move a highlighted row, Return executes, shortcut chips shown beside commands that have direct keys.

### 4. The Globe

A 3D Earth rendering the same Global Instant: NASA day/night textures with a physically correct sunlight terminator, atmosphere rim glow, ocean sun-glint, city lights at night. Saved Locations appear as markers; hover names them; clicking anything inspects the nearest city (name, local time, offsets, sunset, "Add to Clocks"); J = Jump (type a city, camera flies to it). Drag rotates, scroll/pinch zooms. Scrubbing time in the Panel visibly sweeps the sunlight.

Currently the Globe opens as a separate window that morphs out of the panel's frame. **Desired: the Globe opens *inside* the panel** — the panel expands in place (like Omarchy's widget growing), the rows give way to the Earth, with a compact footer showing the selected/home city and a "Jump to a city" affordance. Closing collapses back to the list, restoring everything exactly.

### 5. Settings & About

Small tabbed window: General (launch at login, global shortcut, menu-bar display: icon only or icon + a chosen city's time), Time (12/24h, Relative/UTC, first day of week), Appearance (weather, greetings, moon phase, animations toggles), Advanced (export/import configuration, reset), About (MIT, GeoNames CC-BY, NASA imagery attributions).

## Keyboard model (full app works without a mouse)

⌥Space open/close · ↑/↓ select row · Return inspect row (sunrise/sunset, coordinates, tz) · Delete remove · A add · U toggle offset mode · N return to Now · Space open/close Globe · J jump (in Globe) · ⌘K commands · Esc walks back one layer at a time (overlay → inspection → Time Travel → selection → close).

## States to design for

- **Now vs Time Travel** — Time Travel must be unmistakable (currently an orange header). The whole panel could shift temperature/accent.
- Reduced Motion (all spatial animation becomes crossfades), animations-off.
- Weather/greeting absent (offline, no entitlement) — rows simply show less; nothing may look broken.
- 1 city to ~10 cities; long city names; RTL greeting text (Arabic).
- Light and dark system appearance (the app currently leans dark; a real light treatment is open).

## Design direction

Reference: the Omarchy world clock widget (terminal-aesthetic Linux widget) — we love its **top-center identity header** ("It's 5:02 PM here in Malibu" over a "World 🌍 Clock" wordmark), its calm card-per-city rhythm with big right-aligned times, its restrained two-tone palette with a single warm accent for the time indicators, and its globe that expands inside the same surface as a stylized flat Earth (monochrome landmass, thin graticule, dot markers, ringed highlights).

But this must feel **macOS-native, Apple-grade** — not a terminal skin. Think: system materials/vibrancy, SF Pro (SF Mono only where tabular time digits want it), proper hierarchy instead of boxes, restrained color, the polish level of Apple's own menu-bar experiences (Control Center, Weather). Keep our real sun/moon Day Line concept — it is the product's signature — but it may be restyled. The Globe may keep its photorealistic NASA look or move toward Omarchy's stylized flat look (both are one shader for us — pick on design merit).

Must-keeps: top-center header with the home-time sentence; Day Line per row with sun/moon indicator; scrubbing as the hero interaction with a clear Time Travel state; in-panel expanding Globe; Add-a-city affordance at the bottom; everything above under "States".

## Technical constraints

- SwiftUI inside an AppKit NSPanel; panel width ~320–380pt collapsed, expands (animated, we control the frame) for the Globe — height/width targets are the designer's call.
- The Globe is RealityKit (a real 3D sphere, shader-controlled look); overlays on it are SwiftUI.
- System materials (.regularMaterial etc.) available; arbitrary gradients/colors fine.
- Weather glyphs are SF Symbols; the moon indicator is a custom-drawn phase-correct shape (not emoji) — keep it non-emoji.
- Menu bar icon is a template (monochrome) tilted-Earth glyph.

## Deliverables wanted from this brief

1. Panel: collapsed layout (header, rows, footer) in dark + light, Now + Time Travel states.
2. Row anatomy: name/caption/time/date/weather + Day Line styling, hover (greeting) and selected states, inspection expansion.
3. Search and ⌘K overlays.
4. The in-panel Globe expansion: expanded layout, footer (selected city + jump), and the transition concept between list and Globe.
5. Globe style verdict: photorealistic vs stylized flat (and if stylized: palette, graticule, marker/ring language).
6. Accent/color system incl. the Time Travel treatment.
