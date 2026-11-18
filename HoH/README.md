# HoH Hoard Farm

Farms Accursed Hoards in Heaven-on-High for the 10k / 20k / 30k hoard achievements.

Each run, the script:
1. Talks to Kyusei, picks your save, and enters.
2. Uses a Pomander of Intuition.
3. If there's no hoard, leaves right away. An empty floor takes about 12 seconds.
4. If there is a hoard, uses your Protection item and runs to it. On the way it uses your job's dash, Sprint, and Safety or Concealment if you've turned them on. Then it opens the hoard and leaves.

Leaving the duty doesn't save your progress. You go back in with the same save and the same pomanders every time, but each hoard you open still counts toward the achievements. In testing, about 47% of floors had a hoard.

## Requirements

- [SomethingNeedDoing](https://github.com/Jaksuhn/SomethingNeedDoing) (v15 or later)
- [vnavmesh](https://github.com/awgil/ffxiv_navmesh)
- An English game client. The script relies on English names for the NPC, the pomanders, the actions, and chat messages.
- A Heaven-on-High save at floor 11 that has a Pomander of Intuition and your Protection item. See [Making a save](#making-a-save).
- To be on the **same job** that made the save. Deep dungeon saves are tied to the job.

## Making a save

1. **Pick a job.** Any job works, but one with a forward dash gets to the hoard a little faster: PCT (Smudge), WHM (Aetherial Shift), RPR (Hell's Ingress) or DNC (En Avant). On DNC, try to reach level 68 for En Avant's second charge. That means killing almost everything on floors 1–10. Remember that the save stays tied to this job.
2. **Clear floors 1–10 only.** After the floor 10 boss, the game saves you at floor 11, and that's the floor the script farms.
3. **Open every chest on the way** to collect what you need. You only need one of each item, because leaving puts them back:
   - a Pomander of Intuition
   - your Protection: Inferno, Crag or Vortex magicite, or a Pomander of Concealment or Petrification
   - a Pomander of Safety (optional)

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
| Protection | Inferno magicite | What to use once a hoard is found. The options are Inferno, Crag, or Vortex magicite, Concealment, Petrification, or None. |
| Safety | off | Uses a Pomander of Safety on the way to the hoard, to remove traps. |
| Dash | Auto (by job) | A forward dash to use on the way. Supported dashes: Smudge (PCT), Aetherial Shift (WHM), Hell's Ingress (RPR), and En Avant (DNC, both charges). Auto picks the one for your current job. |

### Notes on Concealment

Concealment wears off when you use an ability or another pomander, but Sprint doesn't break it. With Concealment selected, the script:
- uses Safety (if on) before setting off
- dashes, then Sprints, then uses Concealment while running
- skips dashes that would start or land within 20y of an enemy
- skips Concealment if the hoard is less than 10y away

## How it finds the hoard

Intuition shows a marker where the hoard is. However, the game only loads objects for nearby rooms, so sometimes the chat says a hoard is on the floor but no marker has loaded yet. When that happens, the script walks toward the farthest objects that have loaded until the marker shows up, for up to 45 seconds. In testing, this found the hoard about 94% of the time.

## Logs

Open `/xllog` and filter on `[HoH]`.
- At **Information** level you get one line per run, a summary at the end, and any warnings, such as a hoard that wasn't opened or a hoard that was sensed but never found.
- At **Debug** level you get step-by-step details.

## Known limits

- Only Inferno magicite has been tested. Crag and Vortex are assumed to be the second and third magicite slots.
- The check that stops a dash from landing in a wall hasn't been triggered in testing yet.
- Leaving uses the game's normal leave, the same as Duty Finder → Leave. SND's own `LeaveCurrentContent()` makes the server treat it as an inactivity kick ("You were expelled from the duty due to extended inactivity"), so the script only uses it as a fallback.
