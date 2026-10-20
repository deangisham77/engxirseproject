# Research Changelog

Format: `YYYY-MM-DD · action · files · detail`

---

## 2026-10-18 · Session 1 · initial system build

**Environment check**
- Project folder inspected: no pre-existing `game-research/` data → nothing to preserve or migrate.
- Capabilities verified:
  - local file read/write ✅
  - public web search ✅ (partial snippets only)
  - image analysis ✅ (awaiting user files)
  - executor-roblox MCP ❌ — `agent-context` returned `fetch failed` twice → **no live observation performed**; recorded as SRC-900 `NOT_AVAILABLE`.
  - player analytics ❌ → SRC-901 `NOT_AVAILABLE`; all retention content tagged `RETENTION_HYPOTHESIS`.

**Game identification (all three verified from official Roblox pages)**
- `break_steal_egg` = Break and Steal an Egg, place 114326934417838, by ILGames x Eggs. Universe ID unknown.
- `steal_egg` = Steal An Egg, place 107778070777162, universe 10563114921, by and Collect Rare Pets.
- `ride_a_pet` = Ride A Pet, place 124216119978534, universe 10035204815, by this game is gud.
- Lineage note captured: BSE's official description states it is "Game inspired by steal an egg".

**Files created**
- `README.md`, `games_registry.json`, `research_progress.json`
- `break_and_steal_an_egg.json`, `steal_an_egg.json`, `ride_a_pet.json`
- `mechanics_database.json` (16 rows incl. cross-game families), `economy_database.json` (structure only, no numbers)
- `content_database.json` (mostly empty lists — intentional), `retention_analysis.json` (hypotheses only)
- `cross_game_comparison.json` (7 dimensions, 5 marked insufficient for use)
- `update_opportunities.json` (**intentionally empty** — gate rule not satisfied)
- `source_registry.json` (16 sources + 2 unavailable), `unknowns_and_gaps.json` (17 gaps)
- `manual_observation_checklist.md`, `ai_research_brief.md`, this changelog

**No data deleted; no file overwritten.** All prior research state: none existed.

**Deliberate omissions this session**
- No numeric economy values (none verified).
- No update ideas (gate not satisfied).
- No uniqueness claims (comparative data too thin).
- No `OBSERVED` status anywhere (no live observation was possible).

---

## 2026-10-18 · Session 2 · live observation restored — break_steal_egg captured

**Capability change**
- `agent-context` succeeded (previously `fetch failed`) → `live_game_observation` moved from
  `NOT_AVAILABLE` to `AVAILABLE`. SRC-900 marked `RESOLVED_2026-10-18`.
- Active client `KengPrime` (Real 2.7.8) was already in **place 114326934417838 = break_steal_egg**,
  5/7 players, placeVersion 1360 → research started there.
- Method: **read-only** — instance trees + `require` of shipped config data tables.
  No remote fired, no character moved, no purchase prompted (stated in capture file).

**New verified data (all OBSERVED / HIGH, source SRC-017)**
- Universe ID `10765288803`; creatorId `187288153` (matches group in `GroupRewardConfig`) → closes GAP-017.
- 10 zones + SafeZone, `RequiredPower` gates 5 → 100B, per-zone guardians with AI parameters,
  458 nests, 86 base animals with weights/cash + 22 event extras + partial 58-entry Legacy pool.
- 13-rarity ladder; 5 mutations with odds and cash multipliers; pity system; Lucky Egg system.
- Economy: 20 pickaxe tiers, 9 plot costs, 6 satchel tiers, treadmill (2 CONFLICTING tables),
  10 zone gates, per-animal cash values → **first real economy data in this project**.
- New mechanic discovered: **zone-gated bat weapons = player-vs-player combat**.
- Retention systems: offline reward, group/like reward, pity, 7-day merge timers, events, polls.
- Monetization inventory (product IDs) — Robux prices still NOT captured.

**Files updated**
- NEW `evidence_live_bse_2026-10-18.json` (raw capture, traceable evidence)
- `source_registry.json` (+SRC-017, SRC-900 resolved)
- `economy_database.json` (BSE numbers + 3 calculations + 3 imbalance flags)
- `content_database.json` (BSE zones/guardians/animals/gear/events)
- `mechanics_database.json` (guards + treadmill upgraded to OBSERVED; +8 new rows → 25 total)
- `break_and_steal_an_egg.json` (all 7 sections refreshed with live evidence)
- `research_progress.json` (BSE → PARTIALLY_COMPLETE; SAE/RAP → WAITING_FOR_OBSERVATION;
  capabilities table updated; session log added)
- `cross_game_comparison.json` (multiplayer, progression, risk/reward, monetization dimensions
  updated; +4 uniqueness checks; readiness reason revised)
- `update_opportunities.json` (readiness checklist → PARTIAL; **ideas still empty**)
- `ai_research_brief.md` (rewritten for handoff)

**Not done this session**
- No ideas generated (gate still requires ≥2 games at equivalent depth).
- No SAE/RAP observation (client not in those places — requires a user-side switch).
- No `OBSERVED` claims for SAE or RAP.
- Robux prices not captured (no purchase prompted; read-only price lookup pending user approval).

**Conflicts recorded (not resolved, not deleted)**
- Treadmill `SpeedConfig.Tiers` (6) vs `TreadmillUpgradeConfig.Levels` (9) — shared costs, different names.
- Guide claim "30 eggs" vs 458 live nests — different grouping assumed, unverified.

---

## 2026-10-18 � Session 3: Live read-only observation of steal_egg

**Trigger**: `start research: steal_an_egg` (user switched the client into place 107778070777162 = Steal An Egg).

**Method**: Same proven recipe as Session 2 � executor MCP `script` tool, read-only. Instance trees read directly; config tables read by requiring `ReplicatedStorage.Data.*` and `Shared.Flags.*` ModuleScripts. NO state mutated: no movement, no remote fired, no purchase, no character action.

**New source**
- SRC-018: Live read-only observation of Steal An Egg � raw capture in `evidence_live_sae_2026-10-18.json`.

**Headline findings (OBSERVED)**
- 13 areas with rarity ranks 1-12, each with a full 8-entry drop table; Light Dark splits into 3 weighted sub-biomes.
- 16 guard configs � one guardian per area + Light/Dark variants. Guards RETRIEVE/DEPOSIT eggs, WalkSpeed 16 -> 251, ragdoll 2.5s.
- 13 index-gated bats ("Fling players and steal their eggs!") + explicit anti-theft kit: Trap/BigTrap (freeze 7s), GravityDisruptor (50% slow), BeeLauncher (invert controls 5s). Starter kit: 1 bat + 3 traps.
- 263 pet entries (11 sampled): EarningRate 180/s -> 1.8B/s, real-time GrowthTime 10s -> 18h.
- 11 weighted egg size bands (0.1x -> 35x, cap 150x) + income taper; carry penalty up to 33% (per-biome).
- 12 base levels (1,000 -> 5e15), 12 treadmill tiers (0 -> 7.5e15, x2 -> x8,500), speed XP curve (1.15 growth).
- 3 gamepasses + 127 products: SERVER-WIDE paid luck x4/x8, Instant Hatch ladder (15min-10h), all treadmills, rewarded-video ads, legacy "DNA stealing no longer available".
- Halloween Dimension event was LIVE at capture (InHalloweenDimension=true).
- Cross-game impact: guards, bat combat, mutations, collection-index are NOT unique to BSE � SAE has all of them.

**Files updated**
- `evidence_live_sae_2026-10-18.json` (new; the SRC-018 evidence base)
- `source_registry.json` (+SRC-018)
- `steal_an_egg.json` (rewritten; most sections upgraded SOURCE_DERIVED -> OBSERVED)
- `economy_database.json` (+SAE economy block, CALC-004..006, +3 imbalance flags)
- `content_database.json` (SAE zones/guards/bats/pets/events filled)
- `mechanics_database.json` (SAE rows upgraded; +6 new mechanic rows: bat-fling, area-guards, anti-theft, carry-penalty, fusion, index-completion)
- `cross_game_comparison.json` (core loop, risk/reward, progression, collection, monetization, live-ops dimensions updated; +2 uniqueness checks; readiness -> GATE_REVIEW_NEEDED)
- `unknowns_and_gaps.json` (GAP-005/006/007/012/015 upgraded; +GAP-018/019/020)
- `research_progress.json` (S3 session logged; steal_egg -> PARTIALLY_COMPLETE)
- `ai_research_brief.md` (rewritten for handoff)
- `research_changelog.md` (this entry)

**Readiness gate note**
- BSE and SAE now both have OBSERVED live data of equivalent depth. The literal �14 condition (=2 games at equivalent depth) is arguably met for a 2-way comparison, but RAP remains unobserved. `update_opportunities.json` stays EMPTY until the user explicitly confirms the basis.

**Not done this session**
- ride_a_pet observation (requires another user-side game switch).
- Robux prices (no purchase prompted; GetProductInfo pending user approval).
- Full 263-pet table (output budget; second pass planned).
- Live witnessing of theft/guard/trap flows (checklist OBS-SAE items).

**Conflicts recorded (not resolved, not deleted)**
- SAE previously described in third-party material as having no guards/combat � RESOLVED_BY_LIVE_DATA (guides were incomplete; stored in content_database conflict block).
- BSE treadmill double-table (6 vs 9) � still CONFLICTING.
- BSE "30 eggs" guide claim vs 458 nests � still CONFLICTING.

---

## 2026-10-18 � Session 4: Live read-only observation of ride_a_pet

**Trigger**: start research: ride_a_pet (client switched to place 124216119978534 = Ride A Pet; active client confirmed via agent-context).

**Method**: Same read-only recipe. Captured ReplicatedStorage configs with depth/byte budget; persisted raw capture before analysis. NO mutation, no remote fired, no purchase.

**New source**
- SRC-019: Live read-only observation of Ride A Pet � evidence_live_rap_2026-10-18.json.

**Key findings (OBSERVED/PARTIAL)**
- Pets: 75+ entries (Speed 50->260, Income 3->250M, Rarities Common->Secret). Includes EventOnly/GlobalHatch variants.
- Eggs: 20+ entries (GrowthTime 3s->43200s, Luck varies, PoolLuck with LogGaussian/Chase). Halloween/Volcanic eggs present.
- Shop: Foods (Grass 10, Meat 30000, Bone 1500, Magic Apple 700000, Dragonfruit 30000000) and Gears/Radars (Advanced 50, Jewel 700, Magic 300000, Angelic 7M, Eternal 30M, Name Tag 200M).
- Fusion: requiredPets=4, rarity fuse costs/times, mutationChancePerInput, activeWeeks/inactiveWeeks.
- Rebirths: initialCost 1M, costMultiplier 50, rigged cost curve up to 7 rebirths, petCapacityBase 5 +1 per rebirth, cap 7.

**Files updated**
- evidence_live_rap_2026-10-18.json (new)
- source_registry.json (+SRC-019)
- ide_a_pet.json (core loop/mechanics/economy/content partially upgraded with SRC-019)
- mechanics_database.json (RAP mutation/rebirth/find-eggs reference SRC-019)
- esearch_progress.json (S4, ride_a_pet PARTIALLY_COMPLETE, active_game_id=ride_a_pet)
- i_research_brief.md, cross_game_comparison.json, unknowns_and_gaps.json, update_opportunities.json status noted.

**Readiness**
- BSE (SRC-017), SAE (SRC-018), RAP (SRC-019) all have OBSERVED/PARTIAL live data. update_opportunities.json remains EMPTY pending explicit user confirmation.

## 2026-10-18 � Session 6: Live read-only capture of Punch and Steal an Egg (TARGET_GAME)
- Client active at place 86978157069603 (creator 617735136, v692, gameId 10769569690, max 7)
- Read configs: GameConfig, IndexConfig, ShopConfig, PvpConfig, MotherHitShapes, UiImagesConfig, SettingsConfig
- Observed: treadmill 1-10, PEN 1-11, 105 products + 4 passes, 10 biomes + animals, CARRY_SLOW_MAX=0.3, Mother threat + PVP
- punch_and_steal_an_egg.json -> PARTIALLY_OBSERVED; SRC-PASE-001 added to source_registry.json
- No mutations.
