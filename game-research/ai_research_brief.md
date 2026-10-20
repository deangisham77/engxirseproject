# AI Research Brief — Roblox Three-Game Research System

*Last updated: 2026-10-18 (session 3 — live observation of steal_egg). Read this file first when resuming.*

## What this project is

Evidence-first, long-term research on three Roblox games to support **later** design of
update ideas. Update generation stays gated until enough equivalent data exists.

| game_id | Game | Place | Universe | Creator | Status |
|---|---|---|---|---|---|
| `break_steal_egg` | Break and Steal an Egg | 114326934417838 | **10765288803** | ILGames x Eggs (creatorId 187288153) | **PARTIALLY_COMPLETE** |
| `steal_egg` | Steal An Egg | 107778070777162 | 10563114921 | and Collect Rare Pets (group) | **PARTIALLY_COMPLETE** |
| `ride_a_pet` | Ride A Pet | 124216119978534 | 10035204815 | this game is gud | WAITING_FOR_OBSERVATION |

Lineage: Break and Steal an Egg's official description says *"Game inspired by steal an egg"*.

## Data-collection capabilities (verified 2026-10-18)

| Capability | Status |
|---|---|
| Local file read/write | ✅ |
| Public web sources | ⚠️ partial (search snippets) |
| Screenshot/image analysis | ✅ if user supplies files |
| **Live game observation (executor MCP)** | ✅ **WORKS** — used twice (BSE session 2, SAE session 3) |
| Auto-detect the open game | ✅ indirectly — `agent-context` reports the active client's `placeId` |
| Player analytics | ❌ never available; retention = hypotheses only |

**Repeatable read-only capture recipe** (proven twice):
1. `agent-context` → confirm active `placeId`.
2. `script`: tree `ReplicatedStorage` + `workspace` (structure, remotes, folders).
3. `script`: require config modules and serialize with a depth/byte budget →
   zone tables, prices, odds, product IDs. *(BSE: `ReplicatedStorage.Shared.*Config`.
   SAE: `ReplicatedStorage.Data.*` + `ReplicatedStorage.Shared.Flags.GameplayBalance` —
   paths differ per game.)*
4. Persist raw output to `evidence_live_<game>_<date>.json` **before** analyzing.
5. NEVER fire a remote, move the character, or prompt a purchase during research.

## Where everything lives

- Progress/state: `research_progress.json` ← **read this first**
- Live raw data: `evidence_live_bse_2026-10-18.json`, `evidence_live_sae_2026-10-18.json`
- Profiles: `break_and_steal_an_egg.json`, `steal_an_egg.json` (rewritten), `ride_a_pet.json`
- Databases: `mechanics_database.json` (31 rows), `economy_database.json` (BSE + SAE),
  `content_database.json` (BSE + SAE)
- Sources: `source_registry.json` (SRC-017 = BSE capture, **SRC-018 = SAE capture**)
- Gaps: `unknowns_and_gaps.json` (GAP-001…020)
- Observations to perform: `manual_observation_checklist.md`
- Comparisons: `cross_game_comparison.json` · Retention: `retention_analysis.json`
- Ideas (gated, still empty): `update_opportunities.json` · History: `research_changelog.md`

## Verified findings

### From live observation — Break and Steal an Egg (SRC-017, OBSERVED, HIGH)
1. **Universe 10765288803, creatorId 187288153**.
2. **10 zones** gated by `RequiredPower`: 5, 1k, 50k, 750k, 12M, 150M, 1B, 5B, 25B, 100B —
   each with a named guardian, GuardSpeed 30→70, fling 12→115.
3. **458 egg nests**; **86 base animals** with weights and cash values (1 → 1.944B),
   **13 rarities**, **5 mutations** (×2 … ×25).
4. **Four cash sinks**: 20 pickaxes (0 → 7.5e16), 9 plot levels (1e4 → 1.5e14),
   6 satchels, treadmill (two CONFLICTING tables, 6 tiers vs 9 levels).
5. **Zone-gated bats = player-vs-player combat**; deep retention layer (offline rewards,
   pity, 7-day merge timers, events); monetization with a DevProductId on every pickaxe tier.

### From live observation — Steal An Egg (SRC-018, OBSERVED, HIGH) — NEW THIS SESSION
6. **13 areas** (rarity ranks 1–12) with full 8-entry weighted drop tables; Light Dark
   splits into 3 weighted sub-biomes (Light 45 / Dark 45 / Mixed 10).
7. **16 guard configs** — one per area + Light/Dark variants. Guards **retrieve and deposit**
   eggs, WalkSpeed 16→251.075, HitDistance 2.5→7, attack ragdoll 2.5s + knockback.
8. **13 index-gated bats** ("Fling players and steal their eggs!", force 35→99.86) plus an
   **explicit anti-theft kit**: Trap/BigTrap (freeze 7s, 3 max), GravityDisruptor (50% slow),
   BeeLauncher (invert controls 5s). Starter kit: 1 bat + 3 traps.
9. **263 pet entries** (11 sampled): EarningRate 180/s → 1.8B/s, real-time GrowthTime
   10s → 64,800s. **11 weighted egg size bands** (0.1x→35x, cap 150x) with income taper;
   **carry penalty up to 33%** (per-biome, down to 15.4% late).
10. **12 base levels** (1,000 → 5e15, capacity 7→19), **12 treadmill tiers**
    (0 → 7.5e15, ×2 → ×8,500), speed XP curve (1.15 growth, +2/level).
11. **3 gamepasses + 127 products**: server-wide paid luck ×4/×8, Instant Hatch ladder
    (15min–10h), all 12 treadmills, rewarded-video ads, legacy "DNA stealing no longer
    available". A **Halloween Dimension event was LIVE** at capture.
12. **Cross-game impact**: guards, bat combat, mutations, and collection-indexes exist in
    BOTH BSE and SAE — none of them can be called unique to either.

### From public sources (SOURCE_DERIVED)
13. All three share the backbone: acquire egg → hatch pet → speed progression → rarer content.
14. Acquisition verb differs: **BREAK** (BSE) · **STEAL** (SAE) · **FIND** (RAP).
15. Speed source differs: trained player stat (BSE, SAE) vs. pet speed (RAP).

### Explicitly NOT proven
- Any uniqueness claim that survives only one game (see `uniqueness_claims_checked`).
- BSE guard-catch failure outcome; live witnessing of SAE theft/guard/trap flows.
- SAE area-access rule (no numeric gate in config; index-completion is INFERRED).
- SAE per-mutation stat effects; SAE offline-reward values (module errored on require).
- RAP: everything live (egg timer, rebirth, PvP absence, event contents).
- Any retention effect (no analytics, ever).
- Robux prices for any game (no purchase prompted).
- BSE "30 eggs" claim vs 458 nests — unresolved (CONFLICTING).

## Open questions for the user
1. **Readiness gate decision**: BSE and SAE now both have equivalent-depth live data. The
   literal §14 condition (≥2 games) is arguably met for a 2-way comparison. Unlock
   `generate update ideas` on a BSE+SAE basis, or wait for ride_a_pet?
2. Switch the client to **Ride A Pet** (124216119978534) for the same read-only capture?
3. Is **Punch and Steal an Egg** (PlaceId 86978157069603 in this repo's AGENTS.md) a fourth
   game for this research, or out of scope?
4. May I call `MarketplaceService:GetProductInfo` (read-only metadata) for Robux prices, or
   would you prefer store screenshots? No purchase will ever be prompted.
5. Is `KengPrime` (maxed gear, 5.4e17 cash, but SatchelTier 1) an admin/test account? Its
   numbers must not be treated as typical-player economy.

## Suggested next actions (in order)
1. Switch client → capture **Ride A Pet** with the same recipe (closes the 3-way gap).
2. Second SAE pass: full 263-pet table (chunked), area-access logic, mutation effects,
   offline-reward values.
3. Second BSE pass: `EggConfig`, `EggRewards`, egg HP per zone, `TutorialConfig`,
   `IndexConfig.Reward()`, tier-20 pickaxe row, full Legacy animal pool.
4. Manual observations (OBS-BSE-03 guard-catch outcome; OBS-SAE theft/guard/trap flows).
5. When the user confirms the gate basis: mark comparison dimensions sufficient, then
   unlock `generate update ideas`.

## Session handoff protocol
Read `research_progress.json` first. Save raw capture before analysis. Never overwrite
unchanged files. Never claim a save succeeded if the write failed. Keep conflicting
findings side by side as `CONFLICTING`.
