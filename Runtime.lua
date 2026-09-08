-- Shared in-memory state. Persistence belongs exclusively to ConfigStore.
return {
    Character = nil, Humanoid = nil, Root = nil, Target = nil,
    RoundPhase = "IDLE", Activity = "", ActivityDetail = "",
    Dungeon = {}, Replay = {}, EnemyCache = {}, SkillFX = {}, Respawn = {},
    Connections = {}, ObsidianLabels = {},
}
