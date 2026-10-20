# Manual Observation Checklist

Live in-game observation is **currently unavailable** to the agent (executor MCP returned
`fetch failed` on 2026-10-18). Everything below must be done **by you, in-game**, or by
restoring the MCP connection. Record answers as notes, screenshots or short video clips —
each one closes a specific gap listed in `unknowns_and_gaps.json`.

When recording, use: `record observation: [game] — [what you saw] — [screenshot file if any]`

---

## Break and Steal an Egg (`break_steal_egg`) — place 114326934417838

- **OBS-BSE-01** What does the first-time player see? Is there a tutorial, popup or arrow?
  *Record: every prompt shown in the first 60 seconds (screenshot each).*
- **OBS-BSE-02** Swing at a common egg: what is its HP, how many swings, what happens
  when it breaks? *Record: HP number, hatch result, any alert UI.*
- **OBS-BSE-03** When a guard catches you: are you stunned, teleported, or does the animal
  just drop? Do you keep the animal if you re-pick it up? *Record: exact outcome + any UI message.*
- **OBS-BSE-04** Deposit an animal at base: what cash amount appears, and does it vary by
  animal rarity? *Record: animal name + cash number (2-3 different animals).*
- **OBS-BSE-05** Open the upgrade shop: record every upgrade name, current level, next cost.
  *Record: full screenshot(s) of the shop panel.*
- **OBS-BSE-06** How many zones/biomes exist, names, and their speed requirements?
  *Record: map/sign screenshots, or the list shown at the edge of each zone.*
- **OBS-BSE-07** Open the Index: how many entries, grouped how?
- **OBS-BSE-08** Is there a treadmill? What does it cost per speed point?
- **OBS-BSE-09** Open the in-game shop/Store: every gamepass and product with price.
- **OBS-BSE-10** Can another player steal an animal you have already deposited, or only
  mid-carry? *Record: attempt result.*
- **OBS-BSE-11** Is there a daily reward, code box, or group reward button in the UI?

## Steal An Egg (`steal_egg`) — place 107778070777162

- **OBS-SAE-01** First-time player experience: tutorial prompts in the first 60 seconds.
  *(Config-level tutorial modules exist; the actual flow still needs observing.)*
- **OBS-SAE-02** Steal an egg from a world pet: what happens? Any resistance, timer, or NPC?
  *(Config says guard chases + ragdoll 2.5s and carry slows you up to 33% — WITNESS LIVE to confirm.)*
- **OBS-SAE-03** Steal from another player: what happens to the victim? Any cooldown or
  restriction (e.g. can't steal the same player twice)? *Record: both perspectives if possible.*
- **OBS-SAE-04** ~~Is there ANY NPC/guard/defense structure?~~ **RESOLVED BY LIVE CONFIG
  (SRC-018): 16 guards (one per area) + traps/GravityDisruptor/BeeLauncher.** Remaining:
  witness a guard actually catching a thief (does the egg get deposited back?).
- **OBS-SAE-05** What happens when your egg/pet is stolen — do you lose progress or just the item?
- **OBS-SAE-06** ~~Treadmill cost/cap, base costs/levels~~ **RESOLVED BY LIVE CONFIG (SRC-018):
  12 treadmill tiers (0 → 7.5e15), 12 base levels (1,000 → 5e15).** Still open: what
  UNLOCKS a new area (no numeric gate found in config).
- **OBS-SAE-07** Pet detail UI: what do size and mutation change (stats shown)?
  *(Size → income taper seen in config; a worked UI example would confirm.)*
- **OBS-SAE-08** Full Index/collection screenshot.
- **OBS-SAE-09** Store tab: every gamepass/product **with Robux price** (IDs already known).
- **OBS-SAE-10** Any zones/areas with unlock requirements? Map screenshot.

## Ride A Pet (`ride_a_pet`) — place 124216119978534

- **OBS-RAP-01** First-time player experience: tutorial prompts in the first 60 seconds.
- **OBS-RAP-02** Does an egg have a visible timer? What happens when it runs out —
  egg disappears, or fails? *Record: countdown UI screenshot.*
- **OBS-RAP-03** Pet list with exact hatch chances (open the index/pet panel and screenshot
  every page) — closes GAP-008.
- **OBS-RAP-04** Rebirth UI: requirement, reward, current multiplier. Screenshot.
- **OBS-RAP-05** Gears shop: every item, price, and what mutation/reroll costs and does.
- **OBS-RAP-06** What exactly sells at the sell point, and for how much?
- **OBS-RAP-07** What does feeding a pet do? (Only effect, not the animation.)
- **OBS-RAP-08** Zone/location list with unlock requirements (map or gate signs).
- **OBS-RAP-09** The active [🎃EVENT]: what does it add, what does it reward?
- **OBS-RAP-10** Store tab: every gamepass/product with price.
- **OBS-RAP-11** Is there ANY player-vs-player interaction (steal, shove, race)?
  *Search explicitly; record "searched, found nothing" if absent.*

---

## Cross-game observations (do these in each of the three games)

- **OBS-ALL-01** First 3 minutes of a brand-new account: what does the game ask you to do,
  and what do you receive? *(Compare onboarding across the three.)*
- **OBS-ALL-02** What is the FIRST thing the UI points at (shop, egg, treadmill, index)?
- **OBS-ALL-03** Leave the game idle for 2 minutes: does anything prompt you to return/act?
- **OBS-ALL-04** Screenshot of the full HUD with each element labeled.
- **OBS-ALL-05** Server population: how many other players, and what are they doing?
