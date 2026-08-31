# WeatherKit behind a WeatherProvider protocol

Weather uses Apple's WeatherKit, which requires a paid Apple Developer account and a per-bundle-ID entitlement — a surprising choice for an MIT open-source app, where keyless Open-Meteo would let every clone fetch weather. We chose WeatherKit for data quality, privacy, and zero third-party service dependency, and accepted the consequence: contributor builds without the entitlement show no weather. This is tolerable because weather is optional enrichment by design — the app must work fully offline and weather failures must be silent.

WeatherKit is isolated behind a small `WeatherProvider` protocol so an Open-Meteo (or other) backend can be added later without touching the UI.
