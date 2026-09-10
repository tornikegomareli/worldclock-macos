<h1 align="center">WorldClock</h1>

<h3 align="center">Time zones at a glance.</h3>

<p align="center">
  <a href="[docs/media/worldclock-demo.mp4](https://getworldclock.app/#top)">
    

https://github.com/user-attachments/assets/513ebe21-b60d-44fa-ac0f-4135f612e2d5


  </a>
</p>

<br />

<p align="center">
  <img src="docs/images/clocks-panel.png" height="400" alt="City clocks, daylight strips, and weather in WorldClock" />
  &nbsp;&nbsp;
  <img src="docs/images/world-view.png" height="400" alt="WorldClock’s globe focused on Tbilisi" />
</p>

## Install

With Homebrew:

```sh
brew tap tornikegomareli/worldclock https://github.com/tornikegomareli/worldclock-macos
brew install --cask tornikegomareli/worldclock/worldclock
```

Or download [WorldClock.dmg](https://github.com/tornikegomareli/worldclock-macos/releases/latest/download/WorldClock.dmg).
The app is signed and notarized for macOS 15+, on Apple Silicon and Intel.

## Using it

- Press **⌥ Space** to open your clocks.
- Add cities and compare their local times.
- Drag the timeline to find a time that works.
- Open world view and pick a city to fly there.

## Build from source

You can build with Xcode, Swift 6, and [mise](https://mise.jdx.dev/).

```sh
git clone https://github.com/tornikegomareli/worldclock-macos.git
cd worldclock-macos
mise install
tuist install
tuist generate
```

Run the `WorldClock` scheme in Xcode.

To run tests:

```sh
xcodebuild test -workspace WorldClock.xcworkspace -scheme WorldClock -destination 'platform=macOS'
```

Source builds work without an Apple Developer account. Weather needs a WeatherKit signing profile. Update checks are disabled in source builds.

## License

[MIT License](LICENSE).

