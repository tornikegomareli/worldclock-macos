import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

function validate(version, build, releases = []) {
  const directory = mkdtempSync(join(tmpdir(), "worldclock-release-test-"));
  const input = join(directory, "releases.json");
  try {
    writeFileSync(input, JSON.stringify(releases));
    return spawnSync(process.execPath, [new URL("./validate-release.mjs", import.meta.url).pathname, version, build, input], { encoding: "utf8" });
  } finally {
    rmSync(directory, { recursive: true });
  }
}

test("accepts the first release", () => {
  assert.equal(validate("0.1.0", "1").status, 0);
});

test("rejects malformed versions and build numbers", () => {
  for (const [version, build] of [["v0.1.0", "1"], ["0.1", "1"], ["0.1.0", "0"], ["0.1.0", "-1"], ["0.1.0", "1; echo unsafe"]]) {
    assert.notEqual(validate(version, build).status, 0);
  }
});

test("never replaces an existing release or draft", () => {
  for (const draft of [true, false]) {
    const result = validate("0.1.0", "2", [{ tag_name: "v0.1.0", draft, prerelease: false }]);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /already exists/);
  }
});

test("rejects a version older than a published release", () => {
  const result = validate("0.1.0", "3", [{ tag_name: "v0.2.0", draft: false, prerelease: false }]);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /must be newer/);
});

test("fails closed when an existing release has no verifiable appcast", () => {
  const result = validate("0.2.0", "3", [{ tag_name: "v0.1.0", draft: false, prerelease: false, assets: [] }]);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /no appcast/);
});
