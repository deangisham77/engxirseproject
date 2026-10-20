# game-research — Roblox Multi-Game Research System

Persistent, evidence-first research on three Roblox games:

| game_id | Game | Status |
|---|---|---|
| `break_steal_egg` | Break and Steal an Egg | IN_PROGRESS |
| `steal_egg` | Steal An Egg | IN_PROGRESS |
| `ride_a_pet` | Ride A Pet | IN_PROGRESS |

## Purpose

Collect, store, validate and compare verified information about these three games so
update ideas can be designed from evidence — not guesses.

## Principles (non-negotiable)

1. **Evidence first.** Every claim carries an `evidence_status` and `confidence`.
2. **No fabricated data.** Unknown values are `UNKNOWN` / `NOT AVAILABLE`, never estimated silently.
3. **No unverified claims.** A feature is only called "unique" after comparison across all three games.
4. **Old valid data is preserved.** Conflicting findings are stored as `CONFLICTING`, not deleted.
5. **Nothing is "complete" until every required category has been checked.**

## Epistemic status vocabulary

`OBSERVED` · `SOURCE_DERIVED` · `INFERRED` · `UNKNOWN` · `CONFLICTING` · `NOT_APPLICABLE`
Confidence: `HIGH` · `MEDIUM` · `LOW` (never a substitute for evidence)

Retention-related conclusions are tagged `RETENTION_HYPOTHESIS` unless player-analytics
data exists (it currently does not, for any of the three games).

## File map

| File | Contents |
|---|---|
| `games_registry.json` | Verified identity of each game |
| `research_progress.json` | Per-game research state, next tasks, open questions |
| `break_and_steal_an_egg.json` | Full research profile: game 1 |
| `steal_an_egg.json` | Full research profile: game 2 |
| `ride_a_pet.json` | Full research profile: game 3 |
| `mechanics_database.json` | Mechanics, cross-linked across games |
| `economy_database.json` | Currency, prices, rewards, ratios |
| `content_database.json` | Zones, eggs, pets, items, gamepasses |
| `retention_analysis.json` | Retention observations + hypotheses |
| `cross_game_comparison.json` | Side-by-side comparison of the three games |
| `update_opportunities.json` | Evidence-backed update ideas (empty until data suffices) |
| `source_registry.json` | Every source, access method, limitations |
| `unknowns_and_gaps.json` | What we do NOT know, and how to obtain it |
| `ai_research_brief.md` | Machine-readable-ish summary for future sessions/AIs |
| `manual_observation_checklist.md` | Specific in-game observations still needed |
| `research_changelog.md` | What changed, when, and why |

## Data-collection capabilities actually available in this environment

| Capability | Status | Notes |
|---|---|---|
| Local file read/write/analysis | ✅ Available | Files in this folder and any provided by the user |
| Public web sources (game pages, wikis, guides) | ✅ Available | Via web search; content often partial (snippets) |
| Image/screenshot analysis | ✅ Available | If the user provides screenshot files |
| Live in-game observation via Roblox executor MCP | ⚠️ Currently unavailable | Server returned `fetch failed` on 2026-10-18; re-check before assuming |
| Automatic detection of which game the user has open | ❌ Not available | No integration supports this |
| Player analytics / retention metrics | ❌ Not available | All retention statements stay hypotheses |
| Private source code, access-control bypass | ❌ Out of scope by policy | Never attempted |

**Important:** the executor MCP being *installed* does not mean it is *connected*. Always
verify with a live call before claiming in-game observation is possible.

## How to use

Say one of:

```
start research: break_steal_egg
start research: steal_egg
start research: ride_a_pet
continue research: [game_id]
show research progress
show missing data: [game_id]
record observation: [finding]
review evidence: [game_id]
compare all games
generate update ideas
export research brief
```

Rules when switching games: save progress first, keep the previous game's data, resume
from unfinished sections, and do not re-collect already-valid data without reason.
