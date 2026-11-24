r"""Rebuild the data built into hoh_hoard.lua (next to this file) from the CSVs RecordSpots writes.

    python build_data.py [folder]

folder: where hoh_hoard_spots.csv and hoh_roomchanges.csv are. Default:
SND's config folder (%APPDATA%\XIVLauncher\pluginConfigs\SomethingNeedDoing).

- SHIPPED_SPOTS <- hoh_hoard_spots.csv (every known hoard spot and how often it was found)
- HOH11 halls   <- hoh_roomchanges.csv (median spot where the game switches rooms, per tileset
  and direction; rooms in the CSV are 0-based, the table's are 1-based)

Prints any hallway
point that moved more than 2y, and directions with fewer than 4 crossings, to check by eye.
"""
import csv, math, os, re, statistics as st, sys
from collections import defaultdict

HERE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.environ.get("APPDATA", ""), "XIVLauncher", "pluginConfigs", "SomethingNeedDoing")
LUA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hoh_hoard.lua")
for name in ("hoh_hoard_spots.csv", "hoh_roomchanges.csv"):
    if not os.path.exists(os.path.join(HERE, name)):
        sys.exit("No %s in %s (pass the folder with the CSVs)" % (name, HERE))
src = open(LUA, encoding="utf-8").read()

# Spots
spots = list(csv.DictReader(open(os.path.join(HERE, "hoh_hoard_spots.csv"))))
spots.sort(key=lambda r: (int(r["territory"]), float(r["x"]), float(r["z"])))
finds = sum(int(r["finds"]) for r in spots)
items = ["{ %s, %.2f, %.2f, %.2f, %d }" % (r["territory"], float(r["x"]), float(r["y"]), float(r["z"]), int(r["finds"]))
         for r in spots]
body = ",\n".join("    " + ", ".join(items[i:i + 3]) for i in range(0, len(items), 3))
i = src.index("local SHIPPED_SPOTS = {")
e = src.index("\n}", i)
src = src[:i] + "local SHIPPED_SPOTS = {\n" + body + src[e:]
src = re.sub(r"-- \{territory, x, y, z, finds\}; \d+ spots, \d+ finds(?: \([\d-]+\))?",
             "-- {territory, x, y, z, finds}; %d spots, %d finds" % (len(spots), finds), src)
print("spots: %d spots, %d finds" % (len(spots), finds))

# Hallways
cross = defaultdict(list)
for r in csv.DictReader(open(os.path.join(HERE, "hoh_roomchanges.csv"))):
    if r["kind"] != "change" or r["dungeon"] != "2" or r["tileset"] not in ("A", "B"):
        continue
    a, b = int(r["from"]) + 1, int(r["to"]) + 1
    if abs(a - b) in (1, 5):
        cross[(r["tileset"], a, b)].append((float(r["x"]), float(r["z"])))
start = src.index("local HOH11 = {")
for ts in ("A", "B"):
    i = src.index("    %s = {" % ts, start)
    j = src.index("        halls = {", i)
    e = src.index("\n        }", j)
    old = {(int(a), int(b)): (float(x), float(z))
           for a, b, x, z in re.findall(r'\["(\d+)>(\d+)"\] = \{ (-?[\d.]+), (-?[\d.]+) \}', src[j:e])}
    keys = sorted(k[1:] for k in cross if k[0] == ts)
    out = []
    for a, b in keys:
        pts = cross[(ts, a, b)]
        mx, mz = st.median(p[0] for p in pts), st.median(p[1] for p in pts)
        out.append('["%d>%d"] = { %.1f, %.1f }' % (a, b, mx, mz))
        if len(pts) < 4:
            print("  %s %d>%d: only %d crossings" % (ts, a, b, len(pts)))
        if (a, b) in old and math.hypot(mx - old[(a, b)][0], mz - old[(a, b)][1]) > 2:
            print("  %s %d>%d moved %.1fy" % (ts, a, b, math.hypot(mx - old[(a, b)][0], mz - old[(a, b)][1])))
    missing = [k for k in old if k not in [(a, b) for a, b in keys]]
    if missing:
        print("  %s: no crossings for %s (kept out of the table!)" % (ts, missing))
    lines = ["            " + ", ".join(out[n:n + 4]) + "," for n in range(0, len(out), 4)]
    lines[-1] = lines[-1].rstrip(",")
    src = src[:j] + "        halls = {\n" + "\n".join(lines) + src[e:]
    print("hallways %s: %d directions" % (ts, len(out)))

open(LUA, "w", encoding="utf-8", newline="").write(src)
print("wrote", os.path.normpath(LUA))
