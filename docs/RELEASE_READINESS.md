# Release preparation

## September 9, 2026: current launch status

- Transferred the repository to `tornikegomareli/worldclock-macos`. GitHub confirms it remains private. No tags or releases were created.
- Updated the Git remote, app feed, release scripts, cask template, contribution instructions, and separate landing page links to the new owner.
- Prepared version 0.1.0, build 4 locally in `release-output/0.1.0-4/assets/`. It includes the current stylized globe and WeatherKit configuration. Builds 1–3 are historical and must not be published.
- All 131 Swift tests passed. All 11 release-script tests passed. Git history and current non-ignored publication files passed redacted Gitleaks scans.
- The universal app and DMG passed signing, notarization, and stapling. Gatekeeper accepted the app. All four artifact checksums passed.
- Sparkle's public key matches the existing Keychain key. The release embeds the new HTTPS feed URL. Both the feed signature and update ZIP signature passed verification.
- Sparkle is implemented, but a real older-to-newer installation and relaunch remain unverified. The production feed returns HTTP 404 while the repository is private and has no releases. Do not describe automatic updates as live.
- The active landing page is the separate `../worldclock-landing` Next.js project. It remains local and noindex, with the supplied demo and two equal-height screenshots.
- Upgraded the landing page from Next.js 16.3.0 to 16.3.4 after the dependency audit reported GHSA-2xp9-vwfh-vxw4 and GHSA-p293-qw3h-jr36. The patched dependency installation reports zero vulnerabilities.

### Before launch

1. Review, commit, and push the intended source changes. Existing local work remains uncommitted; build 4 is a local candidate, not a published release tied to a clean commit.
2. Test Sparkle's older-to-newer installation and relaunch with a private test setup, then verify the production feed after publication is authorized.
3. Choose the landing page hostname and deployment destination. Keep indexing disabled until launch.
4. Keep the signing certificate and Sparkle key backed up. GitHub Actions has no signing secrets or release environment configured; local signing works without them.
5. Obtain explicit approval before changing visibility, publishing a release, or deploying the landing page publicly. Rebuild from the approved clean source before publication.

## September 6, 2026: historical checks

## Current publication status

- The repository remains private, with no GitHub releases or release environment configured. There are no repository Actions secrets.
- The public update feed returns HTTP 404. Both current local Debug and Release builds have an empty `SUPublicEDKey`, so their update controls are intentionally disabled.
- Sparkle integration, update notifications, signing, and packaging code exist. A real older-to-newer update is still unverified; do not describe automatic updates as live.
- `bash Scripts/publish-release.sh VERSION` now wraps local signed packaging with version/build checks, draft creation, asset uploads, downloaded-checksum verification, and final publication. Its tests use fake GitHub/build commands; no real release has been created by the script yet.
- Git history and current non-ignored publication files passed a redacted Gitleaks scan on September 6. Ignored credentials and generated output must remain excluded.
- Settings now contains General, Time, Appearance, and About. Locations, Advanced, import/export, reset, and the inactive first-day-of-week preference were removed. Credits are in README; required notices remain bundled with the app.

Builds 2 and 3 must not be published. Build 2 cannot start Sparkle. Build 3 fixes that configuration, but predates the decision to keep only the stylized Earth. Create a new signed build from the current source after the remaining live checks.

## Verified locally

- 131 Swift tests passed after Settings and dead-code cleanup on September 6, including weather recovery, globe resource reuse, and city-flight tests. Two tests for the removed import/reset feature were deleted; preference persistence and timeline fixtures still run against active code.
- WorldClock's Techzy App ID and Developer ID profile now enable WeatherKit. A signed diagnostic app compiled with the production provider and cache fetched live London weather successfully. The weather-enabled Release app passed strict signature verification with its embedded profile. The profile remains local and ignored by Git.
- Five release-validation tests passed.
- Website build, lint, TypeScript checks, and three rendered-page tests passed.
- Website dependency audit reported zero vulnerabilities.
- Version 0.1.0, build 3 compiled for Apple Silicon and Intel. Its Developer ID signature passed strict verification.
- Apple accepted both the app and disk image for notarization. Both tickets were stapled and validated; Gatekeeper accepted the app.
- A Homebrew cask was generated from the notarized disk image's actual SHA-256. Ruby syntax and Homebrew style checks passed for the template used by build 3. The artifacts remain under ignored `release-output/0.1.0-3/`.
- The release script completed. Sparkle verified the update feed and the ZIP's enclosure signature. All four artifact checksums passed verification.
- Build 2 launched outside Xcode. Its city search and London flight worked. Its Settings UI exposed the update-configuration failure and hidden tabs; both fixes are included in build 3 and need a live retest.
- Git history and the files eligible for publication passed the secret scan. Generated, ignored website output contains private runtime secrets and must not be committed.
- Three real app screenshots are included in `docs/images` and the homepage. The globe capture needs refreshing after removal of the appearance switch. The homepage also has a separate generated social image.

## Remaining local checks

- Inspect weather in the signed app's city rows, including the unavailable indicator and Apple attribution. Computer Use launched the app but could not inspect its hidden menu-bar panel. The live data request and code tests passed; this visual check remains pending.

- The desktop was unlocked. The old debug process was stopped, and the signed build was launched. An additional pointer-free evening clock screenshot is saved as `docs/images/clocks-evening.jpeg`.
- Capture the stylized-only globe without the retired appearance switch. Realistic screenshots and the unused day-photo texture were moved into ignored `.scratch/retired-realistic/` and are recoverable. Record a usage video if desired; no video has been recorded.
- Verify Sparkle's windows, notification permission, and a real older-to-newer signed update. These interaction checks have not run.

## Needs the maintainer's publication choices

- Configure the protected GitHub release environment and its signing secrets. No secrets have been uploaded to GitHub.
- Choose the homepage hostname and deployment destination. The site remains local and unpublished.
- Make the repository public and publish the first verified release only when approved.
- Publish the generated cask. Homebrew installation has not been tested against a published artifact.
- Replace the README and homepage's prerelease copy with download links after publication.

No release, tag, commit, push, public deployment, or repository visibility change was made during preparation. The WorldClock Sparkle private key was created in the local login Keychain under account `WorldClock`; it was not exported.

## Optional next features

Consider highlighting shared working hours across selected cities, or letting a city carry a person's name. Neither feature was implemented.
