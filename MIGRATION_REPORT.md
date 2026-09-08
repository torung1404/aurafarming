# Migration report

## Current checkpoint

The repository baseline has been imported from the supplied monolith. Safe
defaults, shared runtime state, and the local executor ConfigStore boundary
have been extracted without adding cloud persistence or secrets.

`Config.lua` now owns safe defaults only. `Systems/ConfigStore.lua` owns the
existing local executor persistence flow through `isfile`, `readfile`, and
`writefile`. `Main.lua` calls ConfigStore and no longer owns saved-config
loading, merge, or JSON write details.

The remaining gameplay monolith stays in `Main.lua` as the migration reference
until each subsystem is mechanically moved and validated.

## Completed modules

- `Config.lua`
- `Systems/ConfigStore.lua`
- `Runtime.lua`
- `Systems/SkillFX.lua`
- `Controllers/Dodge.lua`
- `Controllers/Replay.lua`
- `Controllers/Targeting.lua`
- `Controllers/Movement.lua` (partial: primitives, steering helpers, and pathfinding)

## Remaining monolith sections

- Movement/navigation recovery/explore and update orchestration
- Combat input
- Dungeon/timer/lifecycle resolution
- Obsidian UI

## Validation

- Read `docsdelta.txt`.
- Confirmed no real webhook is placed in source defaults.
- Added local-config ignore rules.
- `AutoFarmV21Config.json` remains local-only and is ignored by `.gitignore`.
- Stale config identifiers searched: no `CONFIG_FILE` or `SavedConfig` remains
  in `Main.lua`.
- Main gameplay Heartbeat count: 1.
- Dependency direction: `Main.lua -> Systems/ConfigStore.lua -> Config.lua`.
- Circular imports found: none in current module graph.
- Local balance audit over Lua brackets passed for current `.lua` files.
- Runtime state initializer moved out of `Main.lua`; no duplicate
  `RuntimeState = { ... }` owner remains in Main.
- SkillFX model registration, unregister, active hazard part classification,
  and hitbox/precast part-kind detection moved into `Systems/SkillFX.lua`.
  Main retains only adapter wrappers for existing call sites.
- SkillFX hardcoded enemy/skill names searched: none found.
- Dodge hazard radius, predicted radius, hazard height checks, nearby hazard
  refresh, safe-point checks, route checks, dodge goal selection, and update
  decision logic moved into `Controllers/Dodge.lua`. Main retains only adapter
  wrappers used by movement/explore call sites.
- Dodge runtime owner check: `ActiveHazard`, `DodgeGoal`,
  `LastHazardThreatAt`, and `NearbyActiveHazards` are owned by
  `Controllers/Dodge.lua`.
- Replay button discovery, replay click dispatch, replay result detection,
  opener discovery, phase transitions, retry/confirm FSM, and replay arming
  moved into `Controllers/Replay.lua`. Main retains wrappers while lifecycle
  migration is pending.
- Replay state owner check: Replay FSM state remains in `Runtime.lua` and is
  mutated only through `Controllers/Replay.lua` wrappers plus remaining
  lifecycle reset code.
- Targeting enemy cache, valid-target filtering, registration, nearest target
  acquisition, target metrics, target decision timing, and skill-range enemy
  lookup moved into `Controllers/Targeting.lua`.
- Movement primitives moved into `Controllers/Movement.lua`: movement command
  dispatch, release/stop translation, raycast params, ground projection, ground
  support checks, and direct-route clearance.
- Movement steering helpers moved into `Controllers/Movement.lua`: target
  navigation goal resolution, upcoming movement objective lookup, ray clearance,
  and recovery detour selection. Main retains thin wrappers while pathfinding
  and update orchestration are still pending.
- Movement pathfinding moved into `Controllers/Movement.lua`: active path
  ownership, waypoint state, path request serials, `ComputeAsync`, blocked-path
  handling, current waypoint issuing, rebuild flagging, and path update logic.
  Main retains thin wrappers and reads Movement-owned path state only where
  not-yet-migrated navigation logic still needs it.
- Fixed invalid `Combat` table constructor in `Main.lua`; table keys are now
  direct fields instead of `Combat.Field = value`.
- Removed duplicate `config.AutoStart = true` from `Systems/ConfigStore.lua`.
- Searched all `.lua` files for malformed `TableName.Field = value` entries
  inside table constructors; no remaining candidates found.
- Current dependency direction:
  `Main.lua -> Runtime.lua`,
  `Main.lua -> Controllers/Dodge.lua`,
  `Main.lua -> Controllers/Replay.lua`,
  `Main.lua -> Controllers/Targeting.lua`,
  `Main.lua -> Controllers/Movement.lua`,
  `Main.lua -> Systems/SkillFX.lua`,
  `Main.lua -> Systems/ConfigStore.lua -> Config.lua`.
- Static Luau CLI validation could not run because no `luau` binary is
  available in this environment.
- Runtime behavior is UNTESTED in Delta.

## Known risks

- `Main.lua` still contains most legacy gameplay implementation outside shared
  runtime state; controller and system extraction checkpoints are not complete
  yet.
- `require(script.Parent...)` assumes Roblox ModuleScript execution and must be
  validated in the target project layout before Delta loader integration.
- Runtime behavior has not been confirmed in Delta.
