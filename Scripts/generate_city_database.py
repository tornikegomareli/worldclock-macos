#!/usr/bin/env python3
"""Generate the bundled offline City index from GeoNames cities15000.

Usage (from the repo root):

    python3 Scripts/generate_city_database.py

Downloads cities15000.zip from GeoNames (build time only — the app never
touches the network), converts it to WorldClock/Resources/cities.json, and
prints a summary. The output is committed, so contributors only rerun this
to refresh the dataset.

Data: GeoNames (https://www.geonames.org), licensed CC-BY 4.0.
"""

import io
import json
import re
import urllib.request
import zipfile
from pathlib import Path

DUMP_URL = "https://download.geonames.org/export/dump/cities15000.zip"
OUTPUT = Path(__file__).resolve().parent.parent / "WorldClock" / "Resources" / "cities.json"

# Keep alternates that are searchable from a Latin keyboard: letters, digits,
# spaces, and common punctuation. Drops other scripts, which would bloat the
# index without being reachable from the search field for now.
LATIN_ALTERNATE = re.compile(r"^[A-Za-z0-9 .'\-]{2,40}$")

# GeoNames cities15000.txt tab-separated columns (see geonames.org/export).
COL_NAME = 1
COL_ASCII_NAME = 2
COL_ALTERNATES = 3
COL_LATITUDE = 4
COL_LONGITUDE = 5
COL_COUNTRY = 8
COL_POPULATION = 14
COL_TIMEZONE = 17


def main() -> None:
    print(f"Downloading {DUMP_URL} …")
    with urllib.request.urlopen(DUMP_URL) as response:
        archive = zipfile.ZipFile(io.BytesIO(response.read()))

    cities = []
    with archive.open("cities15000.txt") as file:
        for raw in io.TextIOWrapper(file, encoding="utf-8"):
            fields = raw.rstrip("\n").split("\t")
            name = fields[COL_NAME]
            ascii_name = fields[COL_ASCII_NAME]
            seen = {name.lower(), ascii_name.lower()}
            alternates = []
            for alt in fields[COL_ALTERNATES].split(","):
                alt = alt.strip()
                if alt.lower() in seen or not LATIN_ALTERNATE.match(alt):
                    continue
                seen.add(alt.lower())
                alternates.append(alt)
            cities.append(
                {
                    "name": name,
                    "asciiName": ascii_name,
                    "country": fields[COL_COUNTRY],
                    "latitude": float(fields[COL_LATITUDE]),
                    "longitude": float(fields[COL_LONGITUDE]),
                    "timeZone": fields[COL_TIMEZONE],
                    "alternates": alternates,
                    "population": int(fields[COL_POPULATION] or 0),
                }
            )

    # Most-populous first, so rank ties resolve to well-known cities and the
    # app can rely on the order instead of re-sorting at load.
    cities.sort(key=lambda c: -c["population"])

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", encoding="utf-8") as out:
        json.dump(cities, out, ensure_ascii=False, separators=(",", ":"))

    size_mb = OUTPUT.stat().st_size / 1024 / 1024
    print(f"Wrote {len(cities)} cities to {OUTPUT} ({size_mb:.1f} MB)")


if __name__ == "__main__":
    main()
