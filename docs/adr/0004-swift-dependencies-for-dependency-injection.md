# swift-dependencies for dependency injection

Modules that touch the wall clock or timers use Point-Free's [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) instead of hand-rolled closure injection: `@Dependency(\.date.now)` for reading the current instant and `@Dependency(\.continuousClock)` for tick timing. Tests override both with `withDependencies`, a mutable `DateGenerator`, and `TestClock` from swift-clocks, so timing behavior (TimeEngine's minute-boundary ticking) is tested deterministically — no sleeps, no flakiness.

Consequence for the Tuist setup: the shared products (`Dependencies`, `Clocks`, `ConcurrencyExtras`, and their dependencies) are built as dynamic frameworks in `Tuist/Package.swift` so the app and the app-hosted test bundle share one copy; static linking would duplicate the library's classes across host and test bundle.
