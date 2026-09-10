#!/bin/bash
# Embed an authorized WeatherKit profile and sign the app after its frameworks.
set -euo pipefail
[[ $# == 2 ]] || { echo 'Usage: bash Scripts/sign-weather-app.sh APP PROFILE' >&2; exit 1; }
weather_app="$1"
weather_profile="$2"
weather_identity="${SIGN_IDENTITY:-Developer ID Application: Techzy LLC (539293JFA3)}"
weather_team="${TEAM_ID:-539293JFA3}"
weather_config="$(cd "$(dirname "$0")/../Config" && pwd)/WeatherKit.entitlements"
[[ -d "$weather_app/Contents" && -f "$weather_profile" ]] || { echo 'App or weather profile is missing' >&2; exit 1; }
weather_work="$(mktemp -d -t worldclock-weather-signing)"
security cms -D -i "$weather_profile" -o "$weather_work/profile.plist"
weather_bundle="$(plutil -extract CFBundleIdentifier raw "$weather_app/Contents/Info.plist")"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$weather_work/profile.plist")" == "$weather_team.$weather_bundle" ]] || { echo 'Weather profile does not match the app and team' >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.weatherkit' "$weather_work/profile.plist")" == true ]] || { echo 'Profile does not enable WeatherKit' >&2; exit 1; }
cp "$weather_config" "$weather_work/entitlements.plist"
/usr/libexec/PlistBuddy -c "Set :com.apple.application-identifier $weather_team.$weather_bundle" "$weather_work/entitlements.plist"
/usr/libexec/PlistBuddy -c "Set :com.apple.developer.team-identifier $weather_team" "$weather_work/entitlements.plist"
cp "$weather_profile" "$weather_app/Contents/embedded.provisionprofile"
codesign --force --options runtime --timestamp --sign "$weather_identity" \
  --entitlements "$weather_work/entitlements.plist" "$weather_app"
codesign --verify --deep --strict "$weather_app"
