# World Clock for macOS

## Product Concept

### Working description

A native macOS world-time utility that makes it effortless to understand **what time it is for the people and places you care about**, explore time visually, and find good moments to communicate across time zones.

Instead of presenting world clocks as a static list of digital clocks, the app treats time as something spatial.

Every location has a visual day timeline. Daylight, nighttime, current time, relative offset, date changes, weather, and eventually working hours can all be understood without mentally calculating offsets.

The core interaction is a **shared time scrubber**.

Move through time in one city and the entire world moves with you.

---

# 1. Product Vision

Traditional world clocks answer:

> What time is it in Tokyo?

This product should answer something more useful:

> What does the world look like at this moment?

And eventually:

> When is the best time for all of us?

The application should feel closer to a beautifully designed macOS instrument than a timezone calculator.

It should combine:

* the immediacy of a menu-bar utility,
* the interaction quality of a native macOS application,
* the spatial understanding of a timeline,
* the delight of an interactive globe,
* and the usefulness of a lightweight meeting planner.

The application should be understandable within seconds but contain progressively deeper interactions.

---

# 2. Core Product Principles

## Visual before numerical

Users should not have to constantly calculate:

> Tbilisi is UTC+4, New York is UTC-4, therefore...

The interface should make those relationships immediately visible.

Numbers remain available, but the visual structure should do most of the cognitive work.

---

## Time is synchronized

The most important conceptual decision in the product is:

**There is only one global moment.**

Every city's timeline represents the same instant from a different location.

Therefore, when the user scrubs Tokyo forward three hours, London, Tbilisi, New York, San Francisco, and every other location should move simultaneously.

This turns the application from a collection of clocks into a **time exploration tool**.

---

## Delight should communicate information

The rotating Earth, moon phase, greetings and animations are excellent ideas, but they should never exist purely as decoration.

Every delightful visual should also reinforce a concept.

Examples:

* globe rotation → geographical relationship,
* sunlight → daytime,
* moon → nighttime and lunar state,
* local greeting → cultural/time-of-day context,
* city displacement animation → physical sense of the globe entering the interface,
* timeline position → immediate understanding of where the city is in its day.

---

## Keyboard first, mouse friendly

This is a macOS utility. Frequent users should eventually be able to operate almost everything without touching the mouse.

The mouse should make exploration enjoyable.

The keyboard should make repeated usage extremely fast.

---

## Progressive complexity

Opening the application should not expose twenty timezone controls.

The default interface should answer:

* What time is it?
* Is it day or night?
* How far ahead/behind are they?
* What will the world look like later?

Advanced information should appear through interaction.

---

# 3. Application Architecture

The product should have three major surfaces.

## Menu Bar

The application lives primarily in the macOS menu bar.

Clicking the icon opens the World Clock panel.

A configurable global shortcut can also open it anywhere.

For example:

`⌥ Space`

The menu-bar icon itself can subtly represent the Earth's axial tilt rather than using a generic clock symbol.

The original 23-degree idea is excellent because it gives the icon meaning without making it complicated.

---

## World Clock Panel

This is the application's primary surface.

It should appear as a floating macOS panel attached to the menu bar or near the current pointer when invoked using a shortcut.

This is where the user spends approximately 90% of their time.

---

## Globe

The Globe is an expanded exploratory mode.

It should not feel like opening an entirely different application.

The world-clock interface should physically transition into the globe.

The globe can occupy a larger floating window or expand the panel.

The key principle is continuity:

**the time currently being explored in the clock remains the time represented by the globe.**

If the user has scrubbed to tomorrow at 14:00, the sunlight on the globe should also represent tomorrow at 14:00.

That makes the globe part of the time model rather than an isolated gimmick.

---

# 4. Main Interface

The panel could conceptually look like this:

```text
┌──────────────────────────────────────┐
│  ◉ Tbilisi                      NOW  │
│  Monday · Aug 31                     │
│                                      │
│  New York                    -8h     │
│  4:23 AM                    ☾ 19°    │
│  ━━━━━━━━━●━━━━━━━━━━━━━━━━━━━━━━   │
│                                      │
│  London                      -3h     │
│  9:23 AM                    ☀︎ 17°    │
│  ━━━━━━━━━━━━━●━━━━━━━━━━━━━━━━━━   │
│                                      │
│  Copenhagen                  -2h     │
│  10:23 AM                   ☀︎ 18°    │
│  ━━━━━━━━━━━━━━●━━━━━━━━━━━━━━━━━   │
│                                      │
│  Tokyo                       +5h     │
│  5:23 PM                    ☀︎ 28°    │
│  ━━━━━━━━━━━━━━━━━━━━━●━━━━━━━━━━   │
│                                      │
│          ＋ Add Location              │
│                                      │
│  ◉ Globe                 UTC / Local │
└──────────────────────────────────────┘
```

The actual product should be significantly more visual than this representation.

---

# 5. Location Row

Every location should have several information layers.

## Primary information

The user immediately sees:

**City**

Tokyo

**Time**

17:23

**Relative difference**

+5h

**Day / night**

Represented visually rather than primarily with text.

---

## Secondary information

Optional secondary information includes:

* weather,
* date when different from the user's local date,
* timezone abbreviation,
* UTC offset,
* local-language greeting,
* sunrise/sunset,
* working hours.

Secondary information should never overpower the time itself.

---

# 6. The Day Line

The day line is one of the strongest concepts from the original project and should become the visual signature of this application.

Every city gets a horizontal 24-hour timeline.

Conceptually:

```text
00        06        12        18        24
│---------│---------│---------│---------│
██████░░░░░░░░░░░░░░░░░░██████████████
                   ●
```

Instead of showing explicit hour labels constantly, the interface can primarily communicate periods through lighting.

Dark portions represent nighttime.

Bright portions represent daylight.

Transitions represent sunrise and sunset.

The current moment appears as an indicator moving along the timeline.

---

# 7. Sun and Moon Indicator

During daytime, the time indicator becomes a small sun.

During nighttime, it becomes a moon.

The moon should represent the approximate real lunar phase.

Examples include:

🌑

🌒

🌓

🌔

🌕

🌖

🌗

🌘

The representation should use custom graphics rather than emoji in the final UI.

This feature has low functional importance but very high personality value.

It is exactly the sort of detail that makes someone remember the application.

---

# 8. Time Scrubbing

This should be the hero interaction of the entire product.

The user can click anywhere on a city's timeline and drag.

The moment the drag begins, the app enters:

**Time Travel Mode**

The clock stops representing "now" and instead represents the selected global moment.

Every city updates simultaneously.

For example:

```text
Tbilisi       23:00
London        20:00
New York      15:00
San Francisco 12:00
Tokyo         04:00 +1
```

The UI should strongly indicate that the user is no longer looking at the current time.

A floating time indicator could appear:

```text
Tomorrow
14:30 Tbilisi

────────────●────────────
            ↑
```

A visible **Now** control returns immediately to realtime.

Keyboard:

`Esc`

returns to Now.

Potential shortcut:

`N`

returns to Now.

---

# 9. Cross-City Scrubbing

The important detail is that the user should be able to begin scrubbing from **any location**.

Suppose the user thinks:

> I want to call someone in New York around 3 PM their time.

They don't have to calculate Tbilisi time.

They drag New York to:

`15:00`

Every other location instantly updates.

This is dramatically more natural than typing timezone conversions.

---

# 10. Time Snapping

While scrubbing, subtle snapping should happen around useful boundaries:

* full hours,
* half hours,
* sunrise,
* sunset,
* start of working hours,
* end of working hours.

Holding `Option` can disable snapping for precise control.

Holding `Shift` could increase scrubbing precision.

---

# 11. Greetings

The local greeting feature from the original application is delightful and worth keeping, but it should remain secondary.

Hovering a city could temporarily replace secondary information with:

**Tokyo**

おはようございます

*Good morning*

Or:

**Paris**

Bonsoir

*Good evening*

The greeting changes according to the simulated local time.

This means greetings continue working while the user scrubs through time.

Greetings should be culturally appropriate rather than mechanically translating:

"Good afternoon"

into every language.

Some languages do not divide greetings into the same time periods.

Therefore greetings should be stored as locale-specific rules.

---

# 12. Relative Time Mode

By default, the application should show differences relative to the user's current timezone.

Example:

```text
London      -3h
New York    -8h
Tokyo       +5h
```

This is much easier to understand during everyday use than UTC.

---

# 13. UTC Mode

Users can switch the interpretation to UTC.

Example:

```text
London      UTC+1
New York    UTC-4
Tokyo       UTC+9
```

The mode should persist between launches.

Clicking an individual offset could temporarily reveal both values:

```text
Tokyo

+5h from you
UTC+9
```

The application should remember the global preference.

---

# 14. Adding Locations

Press:

`A`

or choose:

`+ Add Location`

A search field takes focus immediately.

The user can search:

```text
Tokyo
Japan
JST
UTC+9
San Francisco
SFO
```

Results should appear instantly.

A result may show:

```text
Tokyo
Japan · JST · UTC+9

17:24
```

Press Return to add.

Press Escape to cancel.

The location should animate into the list.

---

# 15. Search Everywhere

I would extend the original design slightly.

`⌘K`

opens a universal command/search interface.

Commands could include:

```text
Add Tokyo

Show Tokyo

Remove Tokyo

Open Globe

Switch to UTC

Return to Now

Find overlap

Copy Tokyo time

Settings
```

The application should remain simple enough that Command Search is optional rather than necessary.

---

# 16. Location Reordering

Locations can be dragged vertically.

The ordering persists.

Keyboard users should eventually be able to reorder using something like:

`⌘ ↑`

`⌘ ↓`

after selecting a location.

---

# 17. Home Location

The first location has special meaning:

**Home**

By default this comes from the Mac's current system timezone.

Location permission should not be required simply to use the app.

If the user grants location access, the application can automatically update Home while traveling.

For example:

```text
Home
Malibu, California
```

When the user returns to Georgia:

```text
Home
Tbilisi, Georgia
```

There should also be an option to disable automatic Home location.

---

# 18. Globe

The Globe should be one of the signature experiences, but not the main navigation system.

The globe should represent:

* Earth,
* city positions,
* daylight,
* nighttime,
* the current simulated time,
* saved locations.

Opening it should feel physical.

The existing city list moves away.

The globe expands into the available space.

Saved locations appear as subtle points.

---

# 19. Globe Lighting

This is where the macOS version can go significantly beyond the original.

The globe should have a proper day/night terminator.

At a glance, users can see:

```text
Americas       night
Europe         morning
Asia           afternoon
Australia      evening
```

When scrubbing time, the sunlight rotates around the globe.

That makes time exploration extraordinarily intuitive.

---

# 20. Globe Interaction

Users can:

* drag to rotate,
* scroll/pinch to zoom,
* click city markers,
* hover locations,
* double-click an area,
* jump to locations through search.

Clicking Tokyo might show:

```text
Tokyo
17:31
UTC+9
+5h from Tbilisi

Sunset 18:08
```

A button can then:

`Add to Clocks`

if Tokyo is not already saved.

---

# 21. Jump

Keyboard:

`J`

opens:

```text
Jump to...
```

Typing:

`Reykjavik`

rotates the Earth directly toward Reykjavik.

This is worth retaining from the original product because it makes globe exploration significantly faster.

---

# 22. Globe → Clock Continuity

Selecting a city should never destroy the user's existing context.

If the user closes the globe, they return to exactly:

* the same location ordering,
* the same scroll position,
* the same simulated time,
* the same selection.

This seemingly small rule makes the application feel carefully designed.

---

# 23. Working Hours

This is where I would begin differentiating the macOS application from the original project.

Each city can optionally define typical availability.

Example:

```text
San Francisco

09 ━━━━━━━━━ 17
```

The day line then has three concepts:

* night,
* daylight,
* working hours.

Working hours should be subtle.

They should not transform the interface into a calendar application.

---

# 24. Shared Availability

Once working hours exist, the application can solve something genuinely valuable.

Suppose the user has:

```text
Tbilisi
London
New York
San Francisco
```

The application can highlight times when multiple locations have reasonable working hours.

Example:

```text
Best overlap

Tbilisi        18:00
London         15:00
New York       10:00
San Francisco  07:00
```

Or:

```text
3 of 4 locations available
```

This converts the product from:

**beautiful world clock**

into:

**international collaboration tool**.

---

# 25. Overlap Mode

Potential shortcut:

`O`

The regular timelines become an overlap visualization.

For example:

```text
       08       12       16       20
TBS    ███████████████
LDN        ███████████████
NYC                ███████████████
SF                     ███████████████

                   ███
                   ↑
               overlap
```

The user can immediately identify viable meeting periods.

---

# 26. People, Not Just Cities

A future version should allow an optional label.

Instead of:

```text
San Francisco
```

the user could configure:

```text
Sarah
San Francisco
```

or:

```text
Techzy SF
San Francisco
```

This changes the mental model.

People usually don't care about "what time is it in California?"

They care about:

> Can I message Sarah right now?

The city remains the timezone source.

The label gives it personal meaning.

---

# 27. Quick Copy

Right-clicking a location could provide:

```text
Copy Local Time
Copy Time Difference
Copy Time Conversion
```

For example:

`Copy Time Conversion`

might produce:

```text
3:00 PM New York / 11:00 PM Tbilisi
```

This is extremely useful in Slack, Discord, email and messaging.

---

# 28. Dragging Time

A more ambitious macOS interaction could allow dragging a simulated time out of the application.

Imagine scrubbing until:

```text
New York
15:00
```

and dragging the time somewhere else.

The drag payload could contain:

```text
3:00 PM New York
11:00 PM Tbilisi
```

Dropping it into Messages, Slack or Mail inserts formatted text.

This would be distinctly macOS-like.

---

# 29. Calendar Integration

Not part of V1.

Eventually, users could select a simulated time and choose:

`Create Event at This Time`

The system Calendar event editor opens with the correct date and time.

The application should not become a calendar client.

Its role is to **find the time**.

Calendar handles the event.

---

# 30. Menu Bar Information

The menu-bar icon should remain minimal.

Optional configurations could show:

```text
◉
```

or:

```text
NYC 04:23
```

or a selected favorite:

```text
Tokyo 17:23
```

But the default should probably remain icon-only to avoid clutter.

---

# 31. Global Shortcut

One of the most important macOS features.

Example:

`⌥ Space`

The world-clock panel appears.

The user:

1. presses shortcut,
2. sees global times,
3. scrubs if needed,
4. presses Escape,
5. continues working.

This should take seconds.

---

# 32. Keyboard Model

Recommended baseline:

```text
⌥ Space     Open / close app

A           Add location

J           Jump to city

Space       Toggle globe

O           Overlap mode

N           Return to Now

U           Toggle UTC / Relative

⌘K          Commands

↑ ↓         Navigate cities

Return      Inspect selected city

Delete      Remove selected city

Esc         Exit current mode / close
```

Shortcuts should be discoverable through menus and command search.

---

# 33. Interaction Philosophy

The product should have three layers.

### Glance

Open → understand.

No interaction required.

### Explore

Hover → scrub → inspect.

### Act

Copy → add → plan → share.

This hierarchy should drive feature decisions.

---

# 34. Animation

Animation matters significantly for this application.

But animation should represent changes in spatial state.

Good animations include:

* globe expanding into the list,
* cities moving aside,
* Earth rotating toward selected locations,
* location rows smoothly reordering,
* daylight changing during scrubbing,
* the current-time indicator smoothly returning to Now,
* newly added locations appearing naturally.

Avoid generic scale/fade animations everywhere.

The app should feel physical rather than merely animated.

---

# 35. Globe Entrance

The "weight of the world pushes the cities away" interaction from the original plugin is worth preserving conceptually.

For macOS, I would make it slightly more restrained.

When Globe opens:

1. the globe expands,
2. nearby city rows translate outward,
3. their opacity decreases slightly,
4. the globe settles,
5. saved city markers become visible.

When Globe closes, the exact animation reverses.

The important principle is:

**objects remember where they came from.**

---

# 36. Reduced Motion

Respect:

`Reduce Motion`

from macOS accessibility settings.

Instead of large physical transformations:

* crossfade,
* short scale transition,
* minimal positional movement.

Functionality remains identical.

---

# 37. Weather

Weather should stay lightweight.

Example:

```text
Tokyo
17:32    ☀︎ 28°
```

No forecast dashboard.

No precipitation maps.

No weather application inside the world clock.

Weather exists to provide context:

> It is 17:00, sunny and warm in Tokyo.

That makes a distant location feel real.

---

# 38. Date Changes

Crossing date boundaries must be extremely clear.

For example:

```text
Auckland
07:13
Tomorrow
```

Avoid forcing users to infer the date from time offsets.

During scrubbing, dates should transition visibly.

Possible labels:

```text
Yesterday
Today
Tomorrow
Tue, Sep 1
```

---

# 39. Daylight Saving Time

The user should never have to understand DST calculations.

The application should use timezone rules rather than fixed UTC offsets.

If New York changes from UTC-4 to UTC-5 in the future, scrubbing into that future date should automatically represent the correct offset.

This is especially important because the application encourages exploring future dates.

---

# 40. Time Travel Range

V1 should probably support:

approximately ±7 days

through direct scrubbing.

A calendar picker can allow jumping farther.

The main interaction is about planning the next hours or days, not exploring historical timezone changes.

---

# 41. Time Travel Header

Once the user leaves Now, the top of the interface should change.

Normal:

```text
Tbilisi
12:34
```

Time Travel:

```text
Tomorrow · 16:30
───────────────
      NOW
```

The user must always understand whether the interface represents realtime or a simulated moment.

---

# 42. Settings

Settings should remain small.

### General

Launch at Login

Global Shortcut

Home Location

Automatically Update Home Location

### Time

24-hour / 12-hour

Relative / UTC

First Day of Week

### Appearance

Weather

Greetings

Moon Phase

Working Hours

Animations

### Locations

Default working hours

Location labels

### Advanced

Reset Data

Export Configuration

Import Configuration

No giant preferences interface should be required.

---

# 43. Onboarding

Onboarding should take less than one minute.

### Screen 1

**See the world in time.**

Visual showing synchronized city timelines.

### Screen 2

Add a few important places.

Suggested:

```text
London
New York
Tokyo
San Francisco
```

Search is immediately available.

### Screen 3

Set global shortcut.

Example:

`⌥ Space`

Done.

No account creation.

---

# 44. Local-First

For the initial product, I strongly recommend:

* no account,
* no mandatory cloud,
* no login,
* no analytics requirement for functionality.

Locations and preferences can live locally.

Optional iCloud synchronization could come later.

This makes the utility feel native and lightweight.

---

# 45. Suggested Data Model

Conceptually:

```swift
struct Location {
    let id: UUID
    var city: City
    var customName: String?
    var position: Int
    var workingHours: WorkingHours?
}

struct City {
    let identifier: String
    let name: String
    let country: String
    let coordinate: Coordinate
    let timeZoneIdentifier: String
}

struct WorkingHours {
    var start: LocalTime
    var end: LocalTime
    var weekdays: Set<Weekday>
}
```

The central application state should contain one selected global instant:

```swift
enum TimeState {
    case now
    case simulated(Date)
}
```

Every city derives its displayed local time from that one value.

That architectural decision mirrors the interaction model and greatly simplifies reasoning about the application.

---

# 46. Technical Direction

The application should be built as a native Swift macOS application.

A reasonable architecture would be:

```text
App
│
├── Menu Bar
│
├── Clock Panel
│
│   ├── Location List
│
│   ├── Day Timeline
│
│   └── Time Scrubber
│
├── Globe
│
├── Location Search
│
├── Overlap Engine
│
└── Settings
```

SwiftUI can handle most of the interface.

AppKit interoperability will likely be useful for:

* precise floating-panel behavior,
* global keyboard interactions,
* menu-bar behavior,
* advanced pointer handling,
* drag-and-drop.

The globe should be considered an independent rendering component.

---

# 47. Time Engine

Avoid storing manually calculated offsets.

Store:

`TimeZone.Identifier`

and always derive local times from a common `Date`.

Conceptually:

```text
Global Instant
       │
       ├── Tbilisi TimeZone
       │        ↓
       │     18:00
       │
       ├── London TimeZone
       │        ↓
       │     15:00
       │
       └── New York TimeZone
                ↓
             10:00
```

This should be the heart of the product.

---

# 48. City Database

The application needs an offline searchable city database containing approximately:

* city name,
* country,
* timezone identifier,
* latitude,
* longitude,
* alternative names.

Timezone correctness should come from platform timezone data.

Coordinates power the globe and approximate sunrise/sunset calculations.

---

# 49. Weather Architecture

Weather should be treated as optional enrichment.

The Clock experience must work perfectly without network connectivity.

Without weather:

```text
Tokyo
17:32
```

With weather:

```text
Tokyo
17:32   28°
```

Weather failure should never produce visible error noise in the primary interface.

---

# 50. Offline Behavior

Without internet:

Working:

* clocks,
* city search,
* timezone conversion,
* globe,
* day/night,
* moon phase,
* scrubbing,
* working hours,
* greetings,
* overlap calculation.

Potentially unavailable:

* current weather.

This is ideal for a utility application.

---

# 51. V1 Scope

I would deliberately keep the first version focused.

V1 should include:

* macOS menu-bar application,
* global shortcut,
* location list,
* add/remove locations,
* drag-to-reorder,
* automatic Home timezone,
* local-relative offsets,
* UTC mode,
* 12/24-hour format,
* 24-hour day timeline,
* day/night visualization,
* synchronized time scrubbing,
* date transitions,
* Now mode,
* interactive globe,
* city search,
* jump-to-city,
* basic weather,
* local greetings,
* moon phase,
* persisted settings,
* polished animation,
* keyboard navigation.

That is already a substantial and distinctive 1.0.

---

# 52. V1.5

After validating the fundamental product:

* customizable working hours,
* overlap visualization,
* copy/share converted time,
* city/person labels,
* favorites,
* sunrise/sunset details,
* calendar action,
* Shortcuts actions,
* improved globe visualization.

---

# 53. V2

Possible future direction:

### Teams

Collections such as:

```text
Engineering

Tornike · Tbilisi
Sarah · London
John · New York
Ken · Tokyo
```

### Meeting Finder

Select people and immediately find reasonable shared times.

### Calendar Awareness

Overlay existing busy periods.

### iCloud Sync

Synchronize locations between Macs.

### Shortcuts

Actions such as:

```text
Get current time in Tokyo

Convert 15:00 Tbilisi to New York

Find next overlap between Tbilisi and San Francisco
```

---

# 54. What I Would Not Build

Do not turn the application into:

* another calendar,
* another weather application,
* a timezone database browser,
* a giant map,
* a meeting scheduling SaaS,
* a team collaboration platform,
* an Electron dashboard.

The strength of the idea comes from remaining small.

Open it.

Understand time.

Manipulate time.

Close it.

---

# 55. Product Personality

The original plugin has personality.

That must survive the macOS adaptation.

Its personality comes from small things:

* tilted Earth,
* physical globe transition,
* changing moon,
* local greetings,
* daylight movement,
* playful keyboard shortcuts.

A purely utilitarian implementation would technically work but lose what makes the concept interesting.

The macOS product should therefore feel:

**calm, geographical, physical, precise, slightly playful.**

Not futuristic.

Not cyberpunk.

Not corporate.

Not overloaded with glass effects.

Think:

**an instrument sitting on the Mac rather than a dashboard living inside it.**

---

# 56. Visual Design Direction

The interface should use a dark neutral foundation with light derived from the world itself.

Instead of assigning random accent colors:

* sunlight can produce warm illumination,
* moonlight can produce cool neutral light,
* timeline daylight provides brightness,
* weather can introduce extremely subtle atmospheric context.

The Earth should naturally become the most colorful object in the interface.

Everything else should remain restrained.

This gives the Globe visual authority without requiring artificial gradients everywhere.

---

# 57. Signature Interaction

If the entire product had to be demonstrated in ten seconds, the demo should be:

1. Open application.
2. See five cities.
3. Grab New York's timeline.
4. Drag New York from 04:00 to 15:00.
5. Every other city moves simultaneously.
6. Globe sunlight moves.
7. Release.
8. Press Escape.
9. Everything smoothly returns to Now.

If that interaction feels exceptional, the product has a reason to exist.

---

# 58. Product Positioning

I would **not** primarily market this as:

> A beautiful world clock for macOS.

That immediately places it beside hundreds of generic clock applications.

A stronger positioning is:

> **See when the world is awake.**

Or conceptually:

> A visual world clock for people who work across time zones.

Or:

> Move through time. See everyone at once.

The differentiation is not having more clocks.

The differentiation is **understanding relationships between times**.

---

# 59. Core Jobs To Be Done

The application succeeds when users can solve these situations faster:

### Before messaging someone

> Is it too late to message my coworker in San Francisco?

### Before scheduling

> If it's 4 PM in London, what time will that be for everyone else?

### While traveling

> How far am I from my normal timezone?

### International teams

> When are Tbilisi, London and New York simultaneously awake?

### Casual curiosity

> Where on Earth is it morning right now?

Each of these use cases naturally emerges from the same underlying time model.

---

# 60. Product Thesis

The fundamental thesis is:

**Timezone software has traditionally represented time numerically when the human problem is spatial and relational.**

A list like:

```text
Tokyo       17:42
London      09:42
New York    04:42
```

contains the information.

But this:

```text
night ───── morning ───── day ───── evening

London               ●
Tokyo                           ●
New York      ●
```

creates understanding.

That difference is what the product should be built around.

---

# 61. One-Sentence Definition

**A native macOS world-time utility that lets you see, explore and manipulate time across the places and people that matter to you.**

---

# 62. The Product Loop

The ideal repeated behavior is extremely short:

**Open → glance → scrub → understand → close.**

Everything in the product should make that loop faster or more enjoyable.

If a feature does not improve that loop, it deserves serious scrutiny before being added.

---

# 63. Recommended V1 Navigation

There should effectively be almost no traditional navigation.

The application consists of:

```text
World Clock
    ↕
Globe
```

with temporary overlays for:

```text
Add Location
Search
Commands
Settings
```

No sidebar.

No tab bar.

No complicated navigation stack.

That simplicity is particularly important for a menu-bar utility.

---

# 64. Final Product Direction

The original Omarchy plugin gives us an excellent visual starting point:

**clock rows + globe + timeline + scrubbing + personality.**

For the macOS product, the opportunity is to push the idea one conceptual step further.

Do not build:

> the Omarchy world clock, but for Mac.

Build:

> **the fastest way on a Mac to understand time across the world.**

The Globe provides discovery.

The city rows provide awareness.

The shared scrubber provides understanding.

Working-hour overlap eventually provides action.

And the small details — greetings, moon phases, daylight, physical animations — give the product its character.

That combination is strong enough to become a real standalone macOS utility rather than a novelty world clock.

