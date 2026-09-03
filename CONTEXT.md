# WorldClock (working name)

A native macOS menu-bar utility for seeing, exploring and manipulating time across the places and people that matter to you. The core idea: there is only one global moment, and every surface renders it.

## Language

### Time model

**Global Instant**:
The single moment in time the entire interface represents.
_Avoid_: selected time, current time (ambiguous with a Location's local time)

**Now**:
The Time State in which the Global Instant tracks the real clock.

**Time Travel**:
The Time State in which the user has scrubbed the Global Instant away from Now.
_Avoid_: preview mode, simulation mode

**Scrubbing**:
Dragging along any Day Line to move the Global Instant; all Locations move together. Snaps subtly to the dragged Location's full hours, half hours, sunrise and sunset (Option disables snapping; Shift slows the pointer-to-time ratio for precision, which also disables snapping).
_Avoid_: sliding, seeking

**Local Time**:
A Location's rendering of the Global Instant through its timezone rules. Never stored; always derived.
_Avoid_: offset time

### Places

**City**:
An entry in the bundled offline city database (GeoNames subset): name, country, coordinate, IANA timezone identifier, alternate names.

**Location**:
A saved entry in the user's list — one City plus optional custom label, list position, and (later) Working Hours.
_Avoid_: clock, entry, row

**Home**:
The first Location; defaults to the Mac's system timezone and is the reference point for Relative Mode.

**Label**:
An optional personal name on a Location ("Sarah", "Techzy SF"). The City stays the timezone source.

### Display

**Panel**:
The primary floating surface, anchored under the menu-bar icon, opened by click or global shortcut.

**Globe**:
The expanded 3D exploratory surface. Opens inside the Panel — the Panel widens in place and the lanes give way to the Earth. Renders the same Global Instant as the Panel, including its sunlight terminator.

**Day Line**:
A Location's horizontal 24-hour timeline: night is dark, daylight bright, with the time indicator (sun or moon-phase). Since the Meridian layout, every Day Line is a lane on one shared axis — HOME's civil day — and a single meridian cursor crosses all lanes at the Global Instant, where each lane's indicator sits.
_Avoid_: timeline, time bar

**Relative Mode**:
Offsets displayed relative to Home ("+5h"). The default.

**UTC Mode**:
Offsets displayed as UTC offsets ("UTC+9").

**Greeting**:
A locale-specific salutation matching a Location's simulated Local Time, stored as per-locale rules, not translations.

**Inspection**:
Secondary info revealed on the selected Location (Return toggles it): sunrise/sunset, timezone identifier, coordinate. Esc closes it before touching anything else.

**Jump**:
Rotating the Globe directly to a searched City.

### Later (V1.5+)

**Working Hours**:
An optional per-Location availability window drawn on its Day Line.

**Overlap**:
Time ranges where multiple Locations are simultaneously within Working Hours.

## Relationships

- A **Location** references exactly one **City**; the City is the sole timezone source.
- Every **Local Time** derives from the one **Global Instant** plus the Location's IANA timezone rules (never from stored offsets — DST comes free).
- The **Panel** and the **Globe** always render the same **Global Instant**.
- **Home** is the reference for **Relative Mode** offsets.
- **Scrubbing** any Day Line mutates the shared **Global Instant**, never a per-Location time.

## Example dialogue

> **Dev:** "When the user drags Tokyo's **Day Line** to 15:00, do we store Tokyo's new time?"
> **Domain expert:** "No — scrubbing converts 15:00 Tokyo into a **Global Instant** and sets it. Tokyo's 15:00 and New York's 01:00 are both just **Local Times** derived from it."
> **Dev:** "And pressing Esc?"
> **Domain expert:** "Returns the **Time State** to **Now**; the Global Instant tracks the real clock again."

## Flagged ambiguities

- "time" was overloaded — resolved: **Global Instant** (the shared moment) vs **Local Time** (a Location's rendering of it).
- "city" vs "clock" vs "location" — resolved: **City** is database data; **Location** is the user's saved list entry. "Clock" is avoided entirely.
- Panel placement — resolved: always under the menu-bar icon, for both click and shortcut invocation.
