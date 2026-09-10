cask "worldclock" do
  version "0.1.1"
  sha256 "ab5578184444ab6d7c5d67e2e69488890f394a8e7ee4e28c0b1ea91fb1f9af86"

  url "https://github.com/tornikegomareli/worldclock-macos/releases/download/v#{version}/WorldClock.dmg"
  name "WorldClock"
  desc "World clocks and a living globe in your menu bar"
  homepage "https://github.com/tornikegomareli/worldclock-macos"

  auto_updates true
  depends_on macos: :sequoia

  app "WorldClock.app"

  uninstall quit: "com.tornikegomareli.WorldClock"

  zap trash: [
    "~/Library/Application Support/WorldClock",
    "~/Library/Caches/com.tornikegomareli.WorldClock",
    "~/Library/Preferences/com.tornikegomareli.WorldClock.plist",
  ]
end
