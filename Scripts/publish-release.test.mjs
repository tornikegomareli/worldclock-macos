import assert from "node:assert/strict";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

// Exercise the real publisher with isolated GitHub/Git/build stand-ins.
// No test can invoke the real gh CLI, signing tools, or notarization service.
function release(args = ["0.2.0"], options = {}) {
  const root = mkdtempSync(join(tmpdir(), "worldclock-publish-test-"));
  const bin = join(root, "bin");
  try {
    for (const dir of [bin, join(root, "Scripts"), join(root, "Config"), join(root, "releases")]) mkdirSync(dir);
    symlinkSync(process.execPath, join(bin, "node"));
    for (const file of ["publish-release.sh", "validate-release.mjs"]) {
      copyFileSync(new URL(file, import.meta.url), join(root, "Scripts", file));
    }
    writeFileSync(join(root, "Config/Sparkle-public-key.txt"), "public-key\n");
    if (!options.missingNotes) writeFileSync(join(root, "releases/0.2.0.md"), "Release notes");
    if (options.previousLocalBuild) mkdirSync(join(root, `release-output/0.2.0-${options.previousLocalBuild}`), { recursive: true });
    const executable = (path, code) => writeFileSync(path, `#!${process.execPath}\n${code}`, { mode: 0o755 });
    executable(join(bin, "git"), `
      const fs=require('node:fs'); const a=process.argv.slice(2);
      if(a[0]==='branch') console.log(process.env.BRANCH || 'main');
      else if(a[0]==='status') console.log(process.env.DIRTY || (fs.existsSync('.changed') ? ' M changed.swift' : ''));
      else if(a[0]==='rev-parse') console.log('source-commit');
      else if(a[0]==='rev-list') console.log('40');
      else if(a[0]==='show-ref') process.exit(process.env.LOCAL_TAG ? 0 : 1);
      else process.exit(99);
    `);
    executable(join(bin, "gh"), `
      const fs=require('node:fs'),path=require('node:path'); const a=process.argv.slice(2);
      fs.appendFileSync('calls.jsonl',JSON.stringify(a)+'\\n');
      if(a[0]==='auth') { if(a[1]==='token') console.log('test-token'); }
      else if(a[0]==='api') {
        if(a.includes('--slurp') && a.includes('--jq')) process.exit(96);
        const endpoint=a.find(x=>x.startsWith('repos/'));
        if(endpoint.endsWith('/git/ref/heads/main')) console.log(process.env.REMOTE_COMMIT || 'source-commit');
        else if(endpoint.includes('/git/matching-refs/')) console.log(process.env.REMOTE_TAG || '0');
        else if(endpoint.endsWith('/Config/Sparkle-public-key.txt')) console.log(process.env.PREVIOUS_KEY || 'public-key');
        else if(endpoint.endsWith('/releases')) console.log(JSON.stringify([JSON.parse(process.env.RELEASES || '[]')]));
        else if(endpoint==='repos/tornikegomareli/worldclock-macos') console.log(process.env.PRIVATE || 'false');
        else process.exit(98);
      } else if(a[0]==='release') {
        if(a[1]==='upload' && process.env.UPLOAD_FAILURE) process.exit(1);
        if(a[1]==='download') {
          const dest=a[a.indexOf('--dir')+1]; fs.mkdirSync(dest,{recursive:true});
          const assets=fs.readFileSync('built-assets','utf8');
          for(const file of fs.readdirSync(assets)) fs.copyFileSync(path.join(assets,file),path.join(dest,file));
          if(process.env.CORRUPT_UPLOAD) fs.appendFileSync(path.join(dest,'WorldClock-0.2.0.zip'),'corrupt');
        }
        if(a[1]==='view') console.log('https://github.com/tornikegomareli/worldclock-macos/releases/tag/v0.2.0');
      } else process.exit(97);
    `);
    writeFileSync(join(root, "Scripts/release.sh"), `#!/bin/bash
set -euo pipefail
echo "$1 $2" > built-version
[[ -z "\${BUILD_FAILURE:-}" ]] || exit 1
assets="$PWD/release-output/$1-$2/assets"
mkdir -p "$assets"
for file in WorldClock.dmg "WorldClock-$1.zip" appcast.xml worldclock.rb; do
  echo "fixture $file" > "$assets/$file"
done
(cd "$assets" && shasum -a 256 WorldClock.dmg "WorldClock-$1.zip" appcast.xml worldclock.rb > SHA256SUMS)
echo -n "$assets" > built-assets
[[ -z "\${SOURCE_CHANGED:-}" ]] || touch .changed
`);
    const result = spawnSync("/bin/bash", ["Scripts/publish-release.sh", ...args], {
      cwd: root, encoding: "utf8",
      env: { PATH: `${bin}:/usr/bin:/bin:/usr/sbin:/sbin`, GH_TOKEN: "test-token", ...options.env },
    });
    const read = (file) => { try { return readFileSync(join(root, file), "utf8"); } catch { return ""; } };
    return { ...result, calls: read("calls.jsonl").trim().split("\n").filter(Boolean).map(JSON.parse), built: read("built-version") };
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

const writes = (result) => result.calls.filter(a => a[0] === "release" && ["create", "upload", "edit"].includes(a[1]));
const previousRelease = (build = 80) => JSON.stringify([{
  tag_name: "v0.1.0", draft: false, prerelease: false,
  assets: [{ name: "appcast.xml", url: `data:text/xml,${encodeURIComponent(`<sparkle:version>${build}</sparkle:version>`)}` }],
}]);

test("version-only command builds, creates a pinned draft, uploads and verifies before publication", () => {
  const result = release();
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.built.trim(), "0.2.0 40");
  const calls = result.calls.filter(a => a[0] === "release");
  assert.deepEqual(calls.map(a => a[1]), ["create", "upload", "download", "edit", "view"]);
  assert.ok(calls[0].includes("--draft"));
  assert.equal(calls[0][calls[0].indexOf("--target") + 1], "source-commit");
  assert.equal(calls[1].filter(a => a.includes("/assets/")).length, 5);
  assert.ok(!calls[1].includes("--clobber"));
  assert.ok(calls[3].includes("--draft=false"));
});

test("dry run builds signed artifacts but never changes GitHub", () => {
  const result = release(["0.2.0", "--dry-run"], { env: { PRIVATE: "true" } });
  assert.equal(result.status, 0, result.stderr);
  assert.ok(result.built);
  assert.deepEqual(writes(result), []);
});

test("automatically advances past local attempts and published Sparkle builds", () => {
  const result = release(["0.2.0"], { previousLocalBuild: 90, env: { RELEASES: previousRelease(80) } });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.built.trim(), "0.2.0 91");
  const remote = release(["0.2.0"], { env: { RELEASES: previousRelease(100) } });
  assert.equal(remote.status, 0, remote.stderr);
  assert.equal(remote.built.trim(), "0.2.0 101");
});

test("rejects invalid versions, unknown options, missing notes and unsafe source states before building", () => {
  for (const [args, options] of [
    [[], {}], [["v0.2.0"], {}], [["00.2.0"], {}], [["0.2.0", "--force"], {}],
    [["0.2.0"], { missingNotes: true }],
    ...[{ DIRTY: " M file.swift" }, { BRANCH: "feature" }, { REMOTE_COMMIT: "other" }, { PRIVATE: "true" },
      { LOCAL_TAG: "1" }, { REMOTE_TAG: "1" }, { RELEASES: JSON.stringify([{ tag_name: "v0.2.0", draft: true }]) },
      { RELEASES: previousRelease(), PREVIOUS_KEY: "rotated-key" }].map(env => [["0.2.0"], { env }]),
  ]) {
    const result = release(args, options);
    assert.notEqual(result.status, 0, `${JSON.stringify(options)}: ${result.stdout}`);
    assert.equal(result.built, "");
    assert.deepEqual(writes(result), []);
  }
});

test("build failure or source changes cannot create a release", () => {
  for (const env of [{ BUILD_FAILURE: "1" }, { SOURCE_CHANGED: "1" }]) {
    const result = release(["0.2.0"], { env });
    assert.notEqual(result.status, 0);
    assert.deepEqual(writes(result), []);
  }
});

test("failed or corrupted uploads leave the release unpublished", () => {
  for (const env of [{ UPLOAD_FAILURE: "1" }, { CORRUPT_UPLOAD: "1" }]) {
    const result = release(["0.2.0"], { env });
    assert.notEqual(result.status, 0);
    assert.ok(writes(result).some(a => a[1] === "create"));
    assert.ok(!writes(result).some(a => a[1] === "edit"));
  }
});
