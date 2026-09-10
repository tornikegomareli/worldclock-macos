# Releasing WorldClock

`Scripts/publish-release.sh` builds and publishes a release. `Scripts/release.sh` builds local artifacts only. Neither script commits source changes, pushes branches, or changes repository visibility.

## Build and publish with one command

```sh
bash Scripts/publish-release.sh 0.1.0
```

This follows Talkify's local release flow and uses the existing certificate and Keychain credentials described below. GitHub Actions signing secrets are not needed for this local command.

Before running it:

1. Write `releases/VERSION.md` and commit the intended source changes.
2. Push `main`. The local checkout must be clean and match GitHub's `main` commit.
3. Authenticate `gh`, unlock the signing Keychain, and provide the WeatherKit profile.
4. Make the repository public when ready. Publication refuses a private repository because users could not fetch the Sparkle feed.

The script chooses a build number at least as high as the Git commit count and higher than previous local attempts and the published appcast. It verifies the Sparkle public key against the previous release, then tests, builds Release for Apple Silicon and Intel, signs, notarizes, and packages the app.

After packaging, it rechecks the source and release version. It creates a GitHub draft pinned to the exact source commit, uploads all five artifacts, downloads them to verify checksums, and only then publishes the release as latest. GitHub creates the version tag at that source commit.

To run the same build without creating a tag or release:

```sh
bash Scripts/publish-release.sh 0.1.0 --dry-run
```

The dry run still reads GitHub metadata and requires clean, pushed source. It allows a private repository. Its artifacts stay local; the next run chooses a fresh build number.

Existing tags, drafts, or releases are never overwritten. If an upload or checksum check fails, the draft remains unpublished. Inspect and complete that draft manually; rerunning the same version is deliberately refused. Do not announce a release until all assets are verified.

The command uploads the generated Homebrew cask as an artifact. It does not commit the cask or deploy the website. A real older-to-newer Sparkle installation still needs a separate live test.

## First public release

1. Review the working tree and the secret-scan reports. Commit the intended changes.
2. Enable GitHub private vulnerability reporting and review Actions permissions.
3. Keep the Developer ID certificate and the WorldClock Sparkle private key backed up securely.
4. Build and verify the release below. Test the signed app on an unlocked Mac, including update windows and notification permission.
5. When ready, make the repository public. Publish the release, then enable its Homebrew cask and homepage download link.

Do not advertise a download before its assets are published. The README and website currently say the first release is being prepared.

## Local signed build

The existing Techzy Developer ID certificate and `camus-notary` Keychain profile are the defaults, matching Camus/Talkify. Override `SIGN_IDENTITY`, `TEAM_ID`, and `NOTARY_PROFILE` when needed. Keep the login Keychain unlocked.

Save the Developer ID WeatherKit profile as `.private/WorldClock-WeatherKit.provisionprofile`, or set `WEATHERKIT_PROFILE` to its path. The release script embeds it and signs the WeatherKit entitlement. Profiles stay out of Git.

```sh
bash Scripts/release.sh 0.1.0 1
```

Use a new positive build number for every build intended for distribution. It must exceed all published `CFBundleVersion` values. Write `releases/VERSION.md` first. The script refuses to replace an existing output directory.

Artifacts appear in `release-output/VERSION-BUILD/assets/`:

- `WorldClock.dmg`: signed, notarized, and stapled installer image.
- `WorldClock-VERSION.zip`: stapled app for Sparkle.
- `appcast.xml`: signed feed with a signed update enclosure.
- `worldclock.rb`: Homebrew cask with the DMG's actual SHA-256.
- `SHA256SUMS`: checksums for the above files.

The script tests, archives both Apple Silicon and Intel, signs nested frameworks, verifies the signature and team, checks notarization acceptance, and verifies the feed signature. It never exports private keys.

The app expects its feed at `https://github.com/tornikegomareli/worldclock-macos/releases/latest/download/appcast.xml`. Keep old GitHub release assets available. The feed advertises the newest full archive; delta updates are intentionally disabled.

## Sparkle key

The public key is in `Config/Sparkle-public-key.txt`. Its private counterpart is stored in the login Keychain under Sparkle account `WorldClock`. Do not replace this key after shipping.

Sparkle's `generate_keys` is downloaded with the dependency at `SourcePackages/artifacts/sparkle/Sparkle/bin/` inside Xcode's DerivedData. Use `generate_keys --account WorldClock -p` to inspect only the public key. For backup or CI export, use its `-x` option to write to an ignored, access-restricted file. Never paste the private key into an issue or commit it.

## GitHub Actions

Create a protected `release` environment with these secrets:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded Developer ID `.p12`, including its private key |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `RELEASE_KEYCHAIN_PASSWORD` | Random password for the runner's temporary Keychain |
| `SPARKLE_PRIVATE_KEY` | WorldClock key exported by Sparkle's `generate_keys` |
| `APPLE_ID` | Apple ID for notarization |
| `APPLE_APP_PASSWORD` | Its app-specific password |
| `WEATHERKIT_PROFILE_BASE64` | Base64-encoded WorldClock Developer ID WeatherKit provisioning profile |

The workflow only runs from `main`. It rejects an existing version and verifies increasing versions and build numbers against published releases. With **Publish** off, it only uploads workflow artifacts. With **Publish** on, it stages all assets in a draft release and then publishes it. It never overwrites existing release assets.

After publication, the workflow commits the generated cask with a normal fast-forward push. If branch protection rejects that push, the release remains published; apply the `worldclock.rb` artifact to `Casks/worldclock.rb` through a reviewed PR. Never force-push to recover this step.

## Homebrew

After the first signed release and `Casks/worldclock.rb` are published:

```sh
brew tap tornikegomareli/worldclock https://github.com/tornikegomareli/worldclock-macos
brew install --cask tornikegomareli/worldclock/worldclock
```

The template `Casks/worldclock.rb.in` is not installable. It becomes a real cask only after packaging computes a verified artifact's checksum. Do not replace the hash with `:no_check`.

## Before calling a release verified

- Open the stapled app outside Xcode. Confirm Gatekeeper accepts it.
- Confirm the menu bar icon, globe, city flight, timeline, keyboard shortcut, and settings.
- Check the no-update and failed-network states in Sparkle.
- Test an older signed build against a higher build with the same key. Confirm the update installs and relaunches.
- Enable and deny notification permission separately. The menu reminder must work in both cases.
- Install the published DMG through the cask. Confirm its checksum and bundle path.

WeatherKit is enabled for the Techzy WorldClock App ID. Signed releases require its matching Developer ID profile. Unsigned contributor builds cannot fetch Apple Weather and show an unavailable indicator.

To build a weather-enabled app locally without packaging a release, install the profile in Xcode's provisioning profiles directory, then run:

```sh
tuist generate --no-open
xcodebuild build -workspace WorldClock.xcworkspace -scheme WorldClock \
  -configuration Release -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Developer ID Application: Techzy LLC (539293JFA3)' \
  DEVELOPMENT_TEAM=539293JFA3 CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  WORLD_CLOCK_WEATHERKIT_ENTITLEMENTS=Config/WeatherKit.entitlements \
  WORLD_CLOCK_WEATHERKIT_PROFILE='WorldClock Developer ID WeatherKit'
```

The active Next.js landing page is the separate `../worldclock-landing` project. The old `website/` directory is not the launch site. Build the landing page before deployment. Choose its public hostname and update download copy only after the first release exists.
