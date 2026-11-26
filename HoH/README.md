# HoH Hoard Farm

Farms Accursed Hoards in Heaven-on-High for the 10k / 20k / 30k and Of the Sixth Sense achievements.

## Get Going

1. **Make a save at floor 11.** Clear floors 1–10, killing everything and opening every chest. The more you end up with, the better, but you need at least:
   - *Minimum Save*: Intuition, Safety, Concealment or magicite
   - *Bonus*: multiple Concealments and a magicite.

   *Tips*: Use Affluences on floors 6-8, Fortunes on 7-9, unless they cap earlier. A job with a forward dash is a little faster: PCT, DNC, WHM or RPR.  Spend other poms freely to make it easy on yourself!
   
2. **Install** [SomethingNeedDoing](https://github.com/Jaksuhn/SomethingNeedDoing) (15.16 or later) and [vnavmesh](https://github.com/awgil/ffxiv_navmesh).

3. **Add the macro.** In SND, click **New Macro**, set **Type** to **Lua**, paste this URL under **Import from Github**, and click **Create**:
   ```
   https://github.com/HeyKupo/GetItDoneKupo/blob/main/HoH/HoH_hoard_macro.lua
   ```
4. **Stand next to Kyusei and start the macro.** Any job is fine: it switches to your save's job (you need a gearset for it).

For **Of the Sixth Sense**, turn on **SixthSense** first.

## TL;DR

- **Normal:** enter, use Intuition, run to the hoard if there is one, leave, repeat. About 75 hoards an hour.
- **Sixth Sense:** enter, check the likeliest spots, leave, repeat. About 15 hoards an hour.
- Your save never runs down: you go back in with the same pomanders every time.
- Pomanders and magicites are used automatically: Concealment until something attacks, then magicite.
- Chat shows your find rate and progress to the next achievement after every hoard, and a summary when you stop.
- Stops by itself when you earn the achievements: For the Hoard VII (30,000 hoards) in normal mode, The Trouble with Buried II in Sixth Sense. Turn off **StopOnAchievement** to keep going.
- Made for floor 11 saves. Other floors may work. YMMV.

## Settings

| Setting | Default | |
|---|---|---|
| SaveSlot | 1 | Which save file to use (1 or 2). |
| Runs | 100 | Stop after this many runs. 0 = until you stop it. |
| SixthSense | off | Search without Intuition, for Of the Sixth Sense. |
| ForTheHoard | 0 | Your hoard count. Kept up by the script and checked against your achievements now and then. |
| TroubleWithBuried | 0 | Same, for hoards found without Intuition. |
| StopOnAchievement | on | Stop when the mode's last achievement is earned. |
| RecordSpots | off | Development. Leave it off. |
| ScriptPath | *(empty)* | Development. Leave it empty. |

## Good to know

- **Updates** install themselves when SND starts, and keep your settings.
- **Client language:** any should work, but only English has been tested.
