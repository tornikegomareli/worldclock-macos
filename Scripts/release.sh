#!/bin/bash
# Builds local, signed release artifacts. Never commits, tags, pushes, or publishes.
set -euo pipefail

fail() { echo "Error: $*" >&2; exit 1; }
[[ $# == 2 ]] || fail "Usage: bash Scripts/release.sh VERSION BUILD_NUMBER"
version="$1"
build_number="$2"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Version must be numeric X.Y.Z"
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] || fail "Build number must be a positive integer"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
[[ -s "releases/$version.md" ]] || fail "Write releases/$version.md before packaging"
output="$repo_root/release-output/$version-$build_number"
[[ ! -e "$output" ]] || fail "Output already exists: $output. Use a new build number."
sign_identity="${SIGN_IDENTITY:-Developer ID Application: Techzy LLC (539293JFA3)}"
team_id="${TEAM_ID:-539293JFA3}"
notary_profile="${NOTARY_PROFILE:-camus-notary}"
sparkle_account="${SPARKLE_ACCOUNT:-WorldClock}"
weather_profile="${WEATHERKIT_PROFILE:-$repo_root/.private/WorldClock-WeatherKit.provisionprofile}"
[[ -f "$weather_profile" ]] || fail "Set WEATHERKIT_PROFILE to WorldClock's Developer ID WeatherKit profile"
public_key="$(tr -d '\r\n' < Config/Sparkle-public-key.txt)"
[[ -n "$public_key" ]] || fail "Missing Sparkle public key"
identities="$(security find-identity -v -p codesigning)"
[[ "$identities" == *"$sign_identity"* ]] || fail "Developer ID certificate is not installed"
xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null
mkdir -p "$output/assets" "$output/updates" "$output/dmg"

tuist install
tuist generate --no-open
xcodebuild test -workspace WorldClock.xcworkspace -scheme WorldClock \
  -destination 'platform=macOS' -derivedDataPath "$output/DerivedData" \
  -resultBundlePath "$output/Tests.xcresult" -quiet
xcodebuild archive -workspace WorldClock.xcworkspace -scheme WorldClock \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$output/DerivedData" -archivePath "$output/WorldClock.xcarchive" \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" \
  SPARKLE_PUBLIC_KEY="$public_key" CODE_SIGNING_ALLOWED=NO \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO -quiet

app="$output/WorldClock.xcarchive/Products/Applications/WorldClock.app"
sparkle_bin="$output/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"
[[ -d "$app" && -x "$sparkle_bin/generate_appcast" ]] || fail "Missing app or Sparkle tools"
[[ "$("$sparkle_bin/generate_keys" --account "$sparkle_account" -p)" == "$public_key" ]] || fail "Sparkle signing key does not match the committed public key"
plist="$app/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" == "$build_number" ]] || fail "Incorrect build number"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" == "$version" ]] || fail "Incorrect version"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist")" == "$public_key" ]] || fail "Incorrect embedded update key"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$plist")" == 'https://github.com/tornikegomareli/worldclock-macos/releases/latest/download/appcast.xml' ]] || fail "Incorrect update feed owner"
lipo "$app/Contents/MacOS/WorldClock" -verify_arch arm64 x86_64

framework="$app/Contents/Frameworks/Sparkle.framework"
for component in \
  "$framework/Versions/B/XPCServices/Downloader.xpc" \
  "$framework/Versions/B/XPCServices/Installer.xpc" \
  "$framework/Versions/B/Updater.app" \
  "$framework/Versions/B/Autoupdate"; do
  codesign --force --options runtime --timestamp --sign "$sign_identity" "$component"
done
# Tuist also embeds the Point-Free dynamic frameworks.
while IFS= read -r -d '' component; do
  codesign --force --options runtime --timestamp --sign "$sign_identity" "$component"
done < <(find "$app/Contents/Frameworks" -maxdepth 1 -name '*.framework' -print0)
SIGN_IDENTITY="$sign_identity" TEAM_ID="$team_id" bash Scripts/sign-weather-app.sh "$app" "$weather_profile"
codesign --verify --deep --strict --verbose=2 "$app"
signature="$(codesign -dv "$app" 2>&1)"
[[ "$signature" == *"TeamIdentifier=$team_id"* ]] || fail "Incorrect signing team"

# Notarize the app first so both distributed containers hold the stapled app.
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/notarization.zip"
xcrun notarytool submit "$output/notarization.zip" --keychain-profile "$notary_profile" \
  --wait --output-format json > "$output/notarization.json"
[[ "$(plutil -extract status raw "$output/notarization.json")" == Accepted ]] || fail "App notarization failed; inspect notarization.json"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"

ditto "$app" "$output/dmg/WorldClock.app"
ln -s /Applications "$output/dmg/Applications"
hdiutil create -volname WorldClock -srcfolder "$output/dmg" -format UDZO \
  "$output/assets/WorldClock.dmg"
codesign --force --timestamp --sign "$sign_identity" "$output/assets/WorldClock.dmg"
xcrun notarytool submit "$output/assets/WorldClock.dmg" --keychain-profile "$notary_profile" \
  --wait --output-format json > "$output/dmg-notarization.json"
[[ "$(plutil -extract status raw "$output/dmg-notarization.json")" == Accepted ]] || fail "DMG notarization failed"
xcrun stapler staple "$output/assets/WorldClock.dmg"
xcrun stapler validate "$output/assets/WorldClock.dmg"

archive="WorldClock-$version.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/updates/$archive"
cp "releases/$version.md" "$output/updates/WorldClock-$version.md"
"$sparkle_bin/generate_appcast" --account "$sparkle_account" --maximum-deltas 0 \
  --download-url-prefix "https://github.com/tornikegomareli/worldclock-macos/releases/download/v$version/" \
  --link 'https://github.com/tornikegomareli/worldclock-macos' --embed-release-notes \
  -o "$output/assets/appcast.xml" "$output/updates"
cp "$output/updates/$archive" "$output/assets/$archive"
"$sparkle_bin/sign_update" --account "$sparkle_account" "$output/assets/appcast.xml"
"$sparkle_bin/sign_update" --account "$sparkle_account" --verify "$output/assets/appcast.xml"
archive_signature="$(xmllint --xpath 'string(/rss/channel/item/enclosure/@*[local-name()="edSignature"])' "$output/assets/appcast.xml")"
"$sparkle_bin/sign_update" --account "$sparkle_account" --verify "$output/assets/$archive" "$archive_signature"
bash Scripts/generate-cask.sh "$version" "$output/assets/WorldClock.dmg" "$output/assets/worldclock.rb"
(cd "$output/assets" && shasum -a 256 WorldClock.dmg "$archive" appcast.xml worldclock.rb > SHA256SUMS)
echo "Release artifacts verified at $output/assets. Nothing has been published."
