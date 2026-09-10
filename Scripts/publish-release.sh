#!/bin/bash
# Build, sign, notarize, upload to a draft, verify, then publish.
set -euo pipefail

fail() { echo "Error: $*" >&2; exit 1; }
[[ $# -ge 1 && $# -le 2 ]] || fail "Usage: bash Scripts/publish-release.sh VERSION [--dry-run]"
version="$1"
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || fail "Version must be numeric X.Y.Z"
dry_run=false
if [[ $# == 2 ]]; then
  [[ "$2" == --dry-run ]] || fail "Unknown option: $2"
  dry_run=true
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
repo="tornikegomareli/worldclock-macos"
tag="v$version"
for tool in git gh node shasum; do
  command -v "$tool" >/dev/null || fail "Missing tool: $tool"
done

check_source() {
  [[ "$(git branch --show-current)" == main ]] || fail "Release from main"
  [[ -z "$(git status --porcelain)" ]] || fail "Working tree is dirty; commit and push the intended changes first"
  [[ "$(git rev-parse HEAD)" == "$commit" ]] || fail "HEAD changed during packaging"
  [[ "$(gh api "repos/$repo/git/ref/heads/main" --jq .object.sha)" == "$commit" ]] \
    || fail "Local HEAD must match GitHub main; push or synchronize it first"
}

commit="$(git rev-parse HEAD)"
gh auth status >/dev/null 2>&1 || fail "Authenticate with gh auth login first"
check_source
[[ -s "releases/$version.md" ]] || fail "Write and commit releases/$version.md first"
if ! $dry_run; then
  [[ "$(gh api "repos/$repo" --jq .private)" == false ]] \
    || fail "The repository must be public before publishing a working Sparkle feed"
fi
if git show-ref --verify --quiet "refs/tags/$tag"; then
  fail "Local tag $tag already exists"
fi
[[ "$(gh api "repos/$repo/git/matching-refs/tags/$tag" \
  --jq "[.[] | select(.ref == \"refs/tags/$tag\")] | length")" == 0 ]] \
  || fail "Remote tag $tag already exists"

release_tmp="$(mktemp -d "${TMPDIR:-/tmp}/worldclock-publish.XXXXXX")"
trap 'rm -r "$release_tmp"' EXIT
gh api --paginate --slurp "repos/$repo/releases" \
  | node -e 'let input=""; process.stdin.on("data", c => input += c); process.stdin.on("end", () => console.log(JSON.stringify(JSON.parse(input).flat())));' \
  > "$release_tmp/releases.json"
build_number="$(GH_TOKEN="${GH_TOKEN:-$(gh auth token)}" node Scripts/validate-release.mjs \
  "$version" auto "$release_tmp/releases.json" "$(git rev-list --count HEAD)")"
previous_tag="$(node -e 'const r=require(process.argv[1]); console.log(r.find(x=>!x.draft&&!x.prerelease)?.tag_name ?? "")' "$release_tmp/releases.json")"
if [[ -n "$previous_tag" ]]; then
  previous_key="$(gh api --method GET "repos/$repo/contents/Config/Sparkle-public-key.txt" \
    -f "ref=$previous_tag" -H 'Accept: application/vnd.github.raw+json' | tr -d '\r\n')"
  [[ "$previous_key" == "$(tr -d '\r\n' < Config/Sparkle-public-key.txt)" ]] \
    || fail "Sparkle public key changed since $previous_tag; existing installations would reject updates"
fi
echo "Building WorldClock $version ($build_number) from $commit"
bash Scripts/release.sh "$version" "$build_number"

assets="$repo_root/release-output/$version-$build_number/assets"
files=(WorldClock.dmg "WorldClock-$version.zip" appcast.xml worldclock.rb SHA256SUMS)
uploads=()
for file in "${files[@]}"; do
  [[ -s "$assets/$file" ]] || fail "Missing artifact: $file"
  uploads+=("$assets/$file")
done
(cd "$assets" && shasum -a 256 -c SHA256SUMS)
check_source
if $dry_run; then
  echo "Dry run complete: $assets. No tag or release was created."
  exit 0
fi

# A failed upload leaves a draft for inspection; never overwrite existing assets.
gh api --paginate --slurp "repos/$repo/releases" \
  | node -e 'let input=""; process.stdin.on("data", c => input += c); process.stdin.on("end", () => console.log(JSON.stringify(JSON.parse(input).flat())));' \
  > "$release_tmp/releases.json"
GH_TOKEN="${GH_TOKEN:-$(gh auth token)}" node Scripts/validate-release.mjs "$version" "$build_number" "$release_tmp/releases.json"
gh release create "$tag" --repo "$repo" --target "$commit" --draft \
  --title "WorldClock $version" --notes-file "releases/$version.md"
gh release upload "$tag" --repo "$repo" "${uploads[@]}"
gh release download "$tag" --repo "$repo" --dir "$release_tmp/uploaded"
cmp "$assets/SHA256SUMS" "$release_tmp/uploaded/SHA256SUMS"
(cd "$release_tmp/uploaded" && shasum -a 256 -c SHA256SUMS)
gh release edit "$tag" --repo "$repo" --draft=false --latest
gh release view "$tag" --repo "$repo" --json url --jq .url
echo "Update feed: https://github.com/$repo/releases/latest/download/appcast.xml"
