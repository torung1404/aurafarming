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

## Remaining monolith sections

- Replay FSM
- Targeting/enemy cache
- Movement/navigation
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
- Fixed invalid `Combat` table constructor in `Main.lua`; table keys are now
  direct fields instead of `Combat.Field = value`.
- Removed duplicate `config.AutoStart = true` from `Systems/ConfigStore.lua`.
- Searched all `.lua` files for malformed `TableName.Field = value` entries
  inside table constructors; no remaining candidates found.
- Current dependency direction:
  `Main.lua -> Runtime.lua`,
  `Main.lua -> Controllers/Dodge.lua`,
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
