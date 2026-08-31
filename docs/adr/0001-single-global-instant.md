# Single Global Instant time model

The app never stores per-location times or UTC offsets. State holds one value — `TimeState` (`now` or a simulated `Date`) — and every location derives its local time from that instant through its IANA timezone identifier. This makes synchronized scrubbing trivial (one mutation moves every clock and the globe's sunlight), makes DST correct for free when scrubbing into future dates, and forbids an entire class of offset-drift bugs. The cost: no surface may ever cache a formatted local time across instant changes.
