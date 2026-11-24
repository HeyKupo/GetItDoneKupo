# HoH data

The data built into `../hoh_hoard.lua`, recorded on HeyKupo's normal runs (floor 11 saves, RecordSpots on).

| File | What | In git |
|---|---|---|
| `hoh_hoard_spots.csv` | Every known hoard spot and how often the hoard was found there. Becomes `SHIPPED_SPOTS`. | yes |
| `hoh_hoard_finds.csv` | Every recorded find, with the floor layout. | no (local) |
| `hoh_roomchanges.csv` | Every room change: floor starts and hallway crossings. Becomes the hallway points in `HOH11`. | no (local) |

The two raw files stay out of git (see `.gitignore`): run by run, they could be matched to the game's own records. Only the totals they produce are published.

When the script runs from this repo (ScriptPath set), it records straight into this folder. To refresh the built-in data: `python build.py`. It rewrites both tables in `../hoh_hoard.lua` and prints anything worth a look.
