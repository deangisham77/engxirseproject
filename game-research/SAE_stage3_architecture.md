# SAE Stage 3 — Gameplay Architecture & Data Model (PROPOSED)

Status: IMPLEMENTED & VERIFIED (Stage 4 core loop done 2026-10-19; see §8 verification log)
Scope: design document. Evidence base: evidence_live_sae_2026-10-18.json (OBSERVED/HIGH),
steal_an_egg.json (SRC-006..008, SRC-016, SRC-018). Values marked [OWN] are OUR design
choices where the original's rule was UNKNOWN — not claims about the original game.

## 1. Data model (server-authoritative)

PlayerData (per player, saved via DataStore "SAE_P_v1"):
- Money: number (start 0)
- SpeedXP: number, SpeedLevel: number (curve: XP_needed = 100 * 1.15^level, +2 speed/level, ref base 10 -> max 400) [from TreadmillProgression, OBSERVED]
- BaseLevel: 1..12 (costs: 1e3, 1e6, 7.5e7, 5e8, 1e9, 5e10, 5e11, 1e12, 2.5e13, 1e14, 5e14, 5e15; capacity 7..19) [OBSERVED]
- TreadmillTier: 0..12 (tier 1 free x2, then 15e3 x5, 250e3 x12, 5e6 x30, 120e6 x80, 3e9 x100, 75e9 x200, 2e12 x500, 50e12 x1000, 1e15 x2000, 2.5e15 x3000, 7.5e15 x8500) [OBSERVED]
- UnlockedAreas: {areaId...} (area 1 always) ; AreaN+1 unlock = complete AreaN index (all 8 species) [OWN - original rule UNKNOWN]
- Index: { [areaId] = { [species] = count } }
- Pets: array {uid, species, areaId, rarity, growthEndsAt, sizeScale, earningRate}
- PlotAssigned: plot number
- Bats: highest tier unlocked (= number of completed area indexes + 1) [aligned with index-bat design, OBSERVED]

## 2. Systems (ServerScriptService/Sae)

- DataService: load/save (UpdateAsync, retries, BindToClose), leaderstats mirror (Money, Speed).
- PlotService: auto-assign one of 8 plots on join, set PlotOwner attribute + label; release on leave.
- EggService: nest state machine. Nest tagged CollectionService("SAE_Nest") + AreaId attr.
  PickUp request -> server validates: distance <= 10, nest ready (per-nest cooldown 20s [OWN]),
  player not carrying. Server rolls drop table (weights from evidence), sets Carrying attr,
  spawns carried egg visual welded above character, applies carry slowdown
  (max 0.33 early biomes -> ~0.16 late, per-biome table OBSERVED).
- DepositService (part of EggService): touch own plot -> egg enters growth (growthEndsAt =
  now + growthTime[area] [OWN per-area defaults 30s..600s inspired by 10s..18h original curve]),
  then auto-place if capacity, else stays in inventory.
- IncomeService: every 1s, Money += sum(earningRate of placed pets on owned plot).
- GuardService (Stage 5): pivot-steer Guard_<Area> models (no Humanoid; anchored statue rig)
  using OBSERVED WalkSpeed/HitDistance per area, chase only inside zone bounds, ragdoll+kncokback.
- TreadmillService (Stage 5): zone detect TM1..12 -> SpeedXP += rate * tierMultiplier.
- Notify (client): RemoteEvent for feedback.

## 3. Remotes (ReplicatedStorage/SaeRemotes)

Egg_Pickup (nest instance), Egg_Deposit, Base_BuyLevel, Treadmill_BuyTier, Area_TryUnlock,
Notify (S->C), DataReady (S->C).
All prices/rewards computed SERVER-side; client sends only intents + instance refs.

## 4. Folder layout

ReplicatedStorage/SaeConfig/{Areas, Bases, Treadmills, Balance, Pets}
ReplicatedStorage/SaeRemotes/*
ServerScriptService/Sae/{Main, DataService, PlotService, EggService, IncomeService}
StarterPlayer/StarterPlayerScripts/SaeClient (Stage 5 UI)
Workspace.SAEMap: attributes/tags added (no geometry moves).

## 5. Validation & exploit rules

- Server distance checks for pickup/deposit (10 studs pickup, plot ownership for deposit).
- Never trust client for price, reward, capacity, ownership.
- Rate-limit per-player remote calls (min 0.2s between egg actions).
- Guard/area positions read from workspace instances, not client.
- DataStore guarded: if Studio API access disabled -> in-memory fallback + warn (documented).

## 6. Staging

- Stage 4 (current): DataService + PlotService + EggService loop + IncomeService + spawn +
  config modules. Verify in solo playtest: leaderstats, plot assignment, steal -> deposit ->
  income tick.
- Stage 5: GuardService, TreadmillService, area gates, UI/notifications, buy flows.
- Stage 6: multiplayer playtest, persistence round-trip, remote abuse test, memory/perf.

## 7a. Stage 4 verification log (2026-10-19, solo playtest, OBSERVED)

- Main started: "[SAE] core loop server started" in runtime logs.
- DataStore disabled in Studio -> memory-mode fallback warned, game continued (by design).
- Plot auto-assign: Plot1.PlotOwner=11456836185 (KengPrime), billboard "KengPrime's Base".
- leaderstats: Money + Speed (10) present and syncing.
- 39 nests tagged SAE_Nest with AreaId + StealPrompt (0.6s hold, 9 studs).
- Pickup via real remote: CarriedEgg visual welded, WalkSpeed 10 -> 6.96 (carry penalty).
- Deposit at own plot (Folder! plots are Folders with Floor part -> PlotService.center helper):
  Carrying cleared, pet stored (DesertLark, 360/s), egg visual destroyed, speed restored 10.
- Growth -> auto-place: placed=true, money ticked 0 -> 1080 (3 ticks x 360/s), plot visual spawned.
- Anti-cheat (client-fired): far pickup REJECTED, fake-instance (HumanoidRootPart) pickup
  REJECTED, deposit while not carrying = no-op. No state corruption server-side.
- BUG FOUND & FIXED during test: plot instances are Folders (no GetPivot); replaced with
  PlotService.center() using Floor part position. Fixed in EggService + IncomeService.
- Backup: game-research/backup/SAE_stage4_backup_2026-10-19.rbxm (6 roots, 122 KB).

## 7. Known limitations at Stage 3

- 263-pet table not available -> Pets config uses per-rarity earning defaults [OWN]
  anchored to observed samples (180/s .. 1.8B/s span).
- Area unlock rule of original UNKNOWN -> index-completion chosen [OWN].
- Original theft flow not witnessed live -> our implementation follows config constraints
  (carry slowdown, dropped-egg timeout, guard params) but sequence is our design.
