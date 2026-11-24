# HoH data

The data built into `../hoh_hoard.lua`, recorded on HeyKupo's normal runs (floor 11 saves, RecordSpots on).

| File | What |
|---|---|
| `hoh_hoard_spots.csv` | Every known hoard spot and how often the hoard was found there. Becomes `SHIPPED_SPOTS`. |
| `hoh_hoard_finds.csv` | Every recorded find, with the floor layout. |
| `hoh_roomchanges.csv` | Every room change: floor starts and hallway crossings. Becomes the hallway points in `HOH11`. |

To refresh: copy the three CSVs here from SND's config folder, then run `python build.py`. It rewrites both tables in `../hoh_hoard.lua` and prints anything worth a look.
