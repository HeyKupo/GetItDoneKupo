# HoH Hoard Farm

Farms Accursed Hoards in Heaven-on-High for the 10k / 20k / 30k hoard achievements.

Each run, the script:
1. Talks to Kyusei, picks your save, and enters.
2. Uses a Pomander of Intuition.
3. If there's no hoard, leaves right away. An empty floor takes about 12 seconds.
4. If there is a hoard, uses your Protection item and Safety (if on), then runs to it. On the way it uses your job's dash, then Concealment if that's your Protection, then Sprint. Concealment goes before Sprint so its animation doesn't use up Sprint's time. It stands on the spot until the hoard is discovered, then leaves.

Leaving the duty doesn't save your progress. You go back in with the same save and the same pomanders every time, but each hoard you discover still counts toward the achievements. In testing, just under half of floors had a hoard (48% over 1,140 runs).

The script doesn't open the hoard's coffer. The achievements count a hoard as soon as it's discovered, and hoard loot is only awarded when you clear the floor set's boss, so opening it would only cost time.

## Requirements

- [SomethingNeedDoing](https://github.com/Jaksuhn/SomethingNeedDoing) (v15 or later)
- [vnavmesh](https://github.com/awgil/ffxiv_navmesh)
- Any game client language. The script looks everything up by ID and reads text from the game's own data, so it should work in any language, but it has only been tested on an English client.
- A Heaven-on-High save at floor 11 that has a Pomander of Intuition and your Protection item. See [Making a save](#making-a-save).
- To be on the **same job** that made the save. Deep dungeon saves are tied to the job.

## Making a save

1. **Pick a job.** Any job works, but one with a forward dash gets to the hoard a little faster: PCT (Smudge), WHM (Aetherial Shift), RPR (Hell's Ingress) or DNC (En Avant). On DNC, try to reach level 68 for En Avant's second charge. That means killing almost everything on floors 1–10. Remember that the save stays tied to this job.
2. **Clear floors 1–10 only.** After the floor 10 boss, the game saves you at floor 11, and that's the floor the script farms.
3. **Open every chest on the way** to collect what you need. You only need one of each item, because leaving puts them back:
   - a Pomander of Intuition
   - your Protection: Inferno, Crag or Vortex magicite, or a Pomander of Concealment or Petrification
   - a Pomander of Safety (recommended: it clears the floor's traps, so you don't lose time being turned into an otter or toad on the way)

   If you're short, use your Pomanders of Affluence and Fortune to get more chests.

## Install

1. In SND, click **New Macro**.
2. Give it a name (for example `HoH_hoard`) and set **Type** to **Lua**.
3. Under **Import from Github**, paste this URL, then click **Create**:
   ```
   https://github.com/HeyKupo/GetItDoneKupo/blob/main/HoH/HoH_hoard_macro.lua
   ```
4. Open the macro's settings and set them up (see [Settings](#settings)).

That's all. You don't need to download anything else: the macro lists `hoh_hoard.lua` as a dependency, and SND fetches it from this repo on its own.

**Updates:** SND checks for a new version of the macro each time the plugin starts. Auto Update is on by default, under the macro's Git settings. Updating keeps your settings, and each macro version fetches the `hoh_hoard.lua` that goes with it.

## Use

Stand next to Kyusei and start the macro. Leave the deep dungeon status window turned on. The script uses it to use pomanders and waits for it on each floor.

To stop, stop the macro in SND.

## Settings

| Setting | Default | Notes |
|---|---|---|
| ScriptPath | *(empty)* | Leave this empty. It's only for testing a local copy of `hoh_hoard.lua`: put the copy's full path here. |
| SaveSlot | 1 | Which save file to enter with: 1 or 2. |
| Runs | 30000 | How many times to enter. |
| Protection | Inferno magicite | What to use once a hoard is found. The options are Inferno, Crag, or Vortex magicite, Concealment, Petrification, or None. Petrification is **not recommended**: see below. |
| Safety | on | **Recommended.** Uses a Pomander of Safety on the way to the hoard. It removes the floor's traps, so you don't lose time being transformed. |
| RecordSpots | off | Keeps a list of where hoards were found, for a planned mode that searches without Intuition. See [Files](#files). |
| Dash | Auto (by job) | A forward dash to use on the way. Supported dashes: Smudge (PCT), Aetherial Shift (WHM), Hell's Ingress (RPR), and En Avant (DNC, both charges). Auto picks the one for your current job. |

### Why Petrification isn't recommended

Petrified enemies still count as being in a fight with you. That stops the game's normal way of leaving the duty from working, so after every hoard the script has to fall back to SND's leave. The server treats that leave like being kicked for inactivity, which isn't how a player normally leaves. Use magicite or Concealment instead.

### Notes on Concealment

Concealment wears off when you use an ability or another pomander, but Sprint doesn't break it. With Concealment selected, the script:
- uses Safety (if on) before setting off
- dashes, then uses Concealment while running, then Sprints
- skips dashes that would start or land within 20y of an enemy
- skips Concealment if the hoard is less than 10y away

## How it finds the hoard

Intuition shows a marker where the hoard is. However, the game only loads objects for nearby rooms, so sometimes the chat says a hoard is on the floor but no marker has loaded yet. When that happens, the script explores until the marker shows up, for up to 90 seconds. It first walks to the farthest loaded objects, such as coffers and beacons. If it runs out of those, it heads for the nearest part of the floor it hasn't been near yet. Before the second step and the longer time limit were added, exploring found the hoard 49 times out of 52.

## Files

The script keeps a few small files in SND's config folder (`%APPDATA%\XIVLauncher\pluginConfigs\SomethingNeedDoing`). They're separate from the Dalamud log, so they survive log rotation.

| File | When | What |
| --- | --- | --- |
| `hoh_hoard_runs.csv` | Always | Running totals per floor set: runs, floors with a hoard, discovered, missed, not found, deaths. The hoard rate shown at the start of each session comes from here. |
| `hoh_hoard_spots.csv` | RecordSpots on | One line per hoard spot found, with how many times. |
| `hoh_hoard_finds.csv` | RecordSpots on | One line per hoard found, with time and position. |

Don't keep these open in Excel while the script runs: Excel locks the file and that run's update is skipped (the log shows a warning).

## Logs

Open `/xllog` and filter on `[HoH]`.
- At **Information** level you get the run tally (and the spot list summary, if RecordSpots is on) at the start and end, one line per run, and any warnings, such as a hoard that wasn't discovered or one that was sensed but never found.
- At **Debug** level you get step-by-step details.

## Known limits

- Only Inferno magicite has been tested. Crag and Vortex are assumed to be the second and third magicite slots.
- The check that stops a dash from landing in a wall hasn't been triggered in testing yet.
- Leaving uses the game's normal leave, the same as Duty Finder → Leave. SND's own `LeaveCurrentContent()` makes the server treat it as an inactivity kick ("You were expelled from the duty due to extended inactivity"), so the script only uses it as a fallback: when the normal leave doesn't work, as with Petrification.
