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

## Remaining monolith sections

- Runtime mutable state
- SkillFX tracking
- Dodge decisions
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
- Static Luau CLI validation could not run because no `luau` binary is
  available in this environment.
- Runtime behavior is UNTESTED in Delta.

## Known risks

- `Main.lua` still contains most legacy gameplay implementation; controller and
  system extraction checkpoints are not complete yet.
- `require(script.Parent...)` assumes Roblox ModuleScript execution and must be
  validated in the target project layout before Delta loader integration.
- Runtime behavior has not been confirmed in Delta.
