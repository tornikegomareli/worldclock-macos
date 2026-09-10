cask "worldclock" do
  version "0.1.0"
  sha256 "7bda6864ee298ed7137cd2a02995e176a5e5e061dbed69f55a31cad46a5bd427"

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
