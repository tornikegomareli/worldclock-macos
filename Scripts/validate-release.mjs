import { existsSync, readFileSync, readdirSync } from "node:fs";

const [version, requestedBuild, releasesPath, minimumBuild = "1"] = process.argv.slice(2);
const automatic = requestedBuild === "auto";
let build = automatic ? minimumBuild : requestedBuild;
if (!/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(version) || !/^[1-9]\d*$/.test(build)) {
  throw new Error("Use a numeric X.Y.Z version and a positive build number.");
}
if (automatic && existsSync("release-output")) {
  for (const entry of readdirSync("release-output", { withFileTypes: true })) {
    const previous = entry.name.match(/^\d+\.\d+\.\d+-([1-9]\d*)$/);
    if (entry.isDirectory() && previous && BigInt(previous[1]) >= BigInt(build)) {
      build = String(BigInt(previous[1]) + 1n);
    }
  }
}
const releases = JSON.parse(readFileSync(releasesPath, "utf8"));
if (releases.some((release) => release.tag_name === `v${version}`)) {
  throw new Error(`Release v${version} already exists, including drafts. Never overwrite release assets.`);
}
for (const release of releases.filter((item) => !item.draft && !item.prerelease)) {
  const previous = release.tag_name.replace(/^v/, "").split(".").map(Number);
  if (previous.length !== 3 || previous.some(Number.isNaN)) continue;
  const current = version.split(".").map(Number);
  const firstDifference = current.findIndex((part, index) => part !== previous[index]);
  if (firstDifference === -1 || current[firstDifference] < previous[firstDifference]) {
    throw new Error(`Version must be newer than ${release.tag_name}.`);
  }
}
// The appcast's actual CFBundleVersion, not the marketing version, controls updates.
const published = releases.find((item) => !item.draft && !item.prerelease);
if (published) {
  const feed = published.assets.find((asset) => asset.name === "appcast.xml");
  if (!feed) throw new Error("Latest release has no appcast; verify its build number manually before releasing.");
  const response = await fetch(feed.url, {
    headers: {
      Accept: "application/octet-stream",
      ...(process.env.GH_TOKEN ? { Authorization: `Bearer ${process.env.GH_TOKEN}` } : {}),
    },
    redirect: "follow",
  });
  if (!response.ok) throw new Error(`Cannot verify previous appcast: HTTP ${response.status}`);
  const xml = await response.text();
  const previousBuilds = [...xml.matchAll(/<sparkle:version>(\d+)<\/sparkle:version>/g)].map((match) => BigInt(match[1]));
  if (!previousBuilds.length) throw new Error("Latest appcast has no verifiable build number.");
  if (automatic) {
    for (const previous of previousBuilds) {
      if (previous >= BigInt(build)) build = String(previous + 1n);
    }
  }
  if (previousBuilds.some((previous) => BigInt(build) <= previous)) {
    throw new Error("Build number must exceed every build in the latest appcast.");
  }
}
console.log(automatic ? build : `Release ${version}, build ${build}: version checks passed.`);
