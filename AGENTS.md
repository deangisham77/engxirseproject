# AGENTS.md — Standing Instructions (Roblox reverse-engineering via executor-roblox)

## Session & mechanism (verified)
- Call MCP tools ONLY via `default.execute` + `tools["executor-roblox"]["<kebab-name>"]`.
  Discover exact signatures first with `search({query})` inside `execute`, or `tool-schema`.
- Session `8abd1053`, executor `Real 2.7.8`, account `KengPrime` (11456836185).
- Game: PlaceId `86978157069603` ("Punch and Steal an Egg" by Noodle Punchers),
  GameId `10769569690`. JobId changes on rejoin — always re-check `agent-context`.
- GUI library (mandatory): Airflow UI `https://github.com/joustingmatch/-3`,
  load via `loadstring(game:HttpGet("https://raw.githubusercontent.com/joustingmatch/-3/main/Source.luau"))()`.
- Active product: **Keng Hub** (`gethui`/`Keng Hub`, handle `getgenv()._EggPetAirWin`).
  GUI AND getgenv handles are wiped on rejoin — rebuild = re-execute canonical source,
  then verify (`guiCount`, tab list). Keep `paste == executed` byte-identical.

## Verified game facts (evidence-backed, do not re-prove without cause)
- Remotes (`ReplicatedStorage.GameShared.Remotes`): `EggPunch` (RemoteEvent, `FireServer(eggModel)`,
  needs proximity), `PetAction` (RemoteFunction → `(true, state)`, verbs:
  `state/equip/unequip/buySlot/equipBest`), `SellItems` (`InvokeServer({ItemId})`),
  `PetsState` (event), `PvpHit/PvpPunch`, `TreadmillRunning`, `GloveShop/TrailShop`.
- Pet steal flow: punch egg → `HatchedPet/Root/ProximityPrompt(Steal)` → hold full
  `HoldDuration` (`InputHoldBegin/End`) or `fireproximityprompt` in range → pet becomes
  carried Tool (`Kind=Pet`, `CanBeDropped=false`) → server auto-stores (hands empty).
- Death → respawn at own Pen `GardenSpawn` (proven). No sanctioned teleport exists
  (zero "Teleport" in 400 client scripts); treadmill-lock is the only game PivotTo.
- Zones: 10 biomes along +X (`GameConfig`), safe zone X < -98 (`SafeZoneLine`).
- Index: `ReplicatedStorage.IndexShared.IndexConfig` (10 biomes, ~165 animals, rarities).

## Hard boundaries (non-negotiable)
- NO CFrame teleport of the character: proven 267 kick + destroy-height yank-kill.
  All locomotion = `Humanoid:MoveTo` (+ PathfindingService), single mover lock.
- NO WalkSpeed changes (same detection). NO offensive PvP automation (no kill-aura).
- NO Robux purchases/transactions without explicit user approval.
- NO key-system cracking, NO copying third-party code wholesale, NO server attacks.
- Unknown verbs/remotes: enumerate call sites first; never blind-fire.

## Working method
- Read-only recon before acting; batch independent reads; one `script` call > many.
- `pcall` every loop body + feed errors to UI log; never leave silent-dead loops.
- Status lines must always narrate WHY idle; counters prove activity.
- Test live before claiming: move/punch/steal verified end-to-end this session.
- After build: verify GUI count + tabs + one behavioral probe, then report.
- Short user commands ("lanjutkan", "perbaiki", "execute") = continue from this context;
  on rejoin, rebuild hub first, then resume objective.

## PERMANENT BUILD QUALITY RULES — Roblox Studio (robloxstudio MCP)
Whenever the user requests a new map, environment, building, prop, or area,
do NOT create a basic blockout unless explicitly requested.

Before building:
1. Inspect available MCP tools, existing assets, and the current environment.
2. Search for suitable existing models/meshes (Creator Store preview + get_asset_details)
   before constructing everything from primitive Parts.
3. Use generated meshes or procedural models when supported and appropriate.
4. Plan silhouette, scale, composition, materials, lighting, and surroundings
   before placing objects.
5. Use smooth terrain, layered geometry, irregular silhouettes, natural variation.
6. Build complete visual objects, not bounding boxes: a tree = trunk + branches +
   foliage + variation; a building = roof + supports + trim + entrance + facade detail.
7. Consistent art direction per area, with varied repeated assets (no visible grids).
8. Keep paths navigable, gameplay spaces unobstructed; collisions must be intentional.
9. Verify in Studio from MULTIPLE camera angles before declaring completion.

Avoid:
- Plain rectangular floors/walls as the final visual design.
- Identical props repeated in obvious grids.
- Neon material everywhere.
- Random decoration spam without composition.
- Excessive Parts when a suitable model/mesh exists.

If a required tool/asset is unavailable, state the limitation and use the best
supported alternative. NEVER claim a mesh was generated or an asset inserted
unless the operation was verified in Studio.
