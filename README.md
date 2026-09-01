# WorldClock

Native macOS menu-bar utility for seeing, exploring and manipulating time across the places and people that matter to you. Product description: [`productdoc.md`](productdoc.md). Domain language: [`CONTEXT.md`](CONTEXT.md).

## Requirements

- macOS 15+
- Xcode 16+ (Swift 6)
- [Tuist](https://tuist.dev) — the Xcode project is generated, never committed

## Build

```sh
git clone https://github.com/InsaneArts/worldclock-macos.git
cd worldclock-macos
mise install          # installs the pinned tuist version (or: brew install tuist)
tuist generate        # generates WorldClock.xcworkspace and opens Xcode
```

Then build and run the `WorldClock` scheme in Xcode, or from the terminal:

```sh
xcodebuild build -workspace WorldClock.xcworkspace -scheme WorldClock -destination "platform=macOS"
```

The app is menu-bar only (no Dock icon). Look for the tilted-Earth icon in the menu bar; click it to toggle the Panel.

## Test

```sh
xcodebuild test -workspace WorldClock.xcworkspace -scheme WorldClock -destination "platform=macOS"
```

Tests use Swift Testing. CI runs build + tests on every push to `main` and on pull requests.

## City database

The offline city index is generated from the GeoNames cities15000 dataset and
committed at `WorldClock/Resources/cities.json`. To refresh it:

```sh
python3 Scripts/generate_city_database.py
```

The script downloads the current GeoNames snapshot when run (the dump is not
versioned upstream, so the committed index is the reproducibility anchor).
The app itself never touches the network.

## Greetings

Hovering a Location shows a local-language greeting for its (possibly
simulated) Local Time. Greetings are per-locale rules — locales divide the day
differently — bundled at `WorldClock/Resources/greetings.json`:

```json
{
  "countries": { "JP": "ja" },
  "rules": {
    "ja": [
      { "from": "04:00", "greeting": "おはようございます", "gloss": "Good morning" }
    ]
  }
}
```

To contribute a locale: map its ISO country codes to a language key under
`countries`, then add that language's day periods under `rules`. Each rule
starts at `from` (24h local time) and runs until the next rule; the last rule
wraps across midnight. `gloss` is the English gloss shown next to the
greeting. Pick boundaries that match how the locale actually divides the day,
not a translation of another locale's schedule.

## Attribution

City data: [GeoNames](https://www.geonames.org), licensed under
[CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/). This attribution
belongs in the app's About screen once it exists.

## License

MIT — see [`LICENSE`](LICENSE).
