# Upload ONLY these missing files

Checked against the current public `torung1404/aurafarming` tree.

Existing repo files that should NOT be overwritten by this package:
- Controllers/Dodge.lua
- Controllers/Movement.lua
- Controllers/Replay.lua
- Controllers/Targeting.lua
- Systems/ConfigStore.lua
- Config.lua
- Runtime.lua
- Main.lua
- .gitignore
- MIGRATION_REPORT.md
- docsdelta.txt

Files supplied here because they are missing from the visible repo tree:
- Systems/SkillFX.lua
- Systems/DungeonResolver.lua
- Systems/TimerResolver.lua
- Controllers/Combat.lua
- Controllers/Lifecycle.lua
- UI/ObsidianUI.lua

Important:
These modules use dependency/context injection so they can be wired into the
already-migrated Main.lua without overwriting the completed Dodge/Movement/
Replay/Targeting work.

Do not upload this ZIP as a full repo replacement.
Upload/merge only the files listed above, then wire them from the current
GitHub Main.lua.
