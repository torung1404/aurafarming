local Defaults = require(script.Parent.Parent.Config)

local Store = {}
local FILE_NAME = "AutoFarmV21Config.json"
local NUMERIC_OR_BOOLEAN_KEYS = {
    "AutoReplay",
    "AutoStart",
    "FarmRange",
    "DodgeEnabled",
    "DodgeDetectionRadius",
    "DodgeSafePadding",
    "DodgeTriggerPadding",
    "DodgePreTriggerPadding",
    "DodgeLookaheadSeconds",
    "DodgeExitHysteresis",
    "PreferredCombatDistance",
    "RetreatEnterDistance",
    "RetreatExitDistance",
    "NormalSkillRange",
    "BossSkillRange",
    "AttackRange",
    "ExploreStartDelay",
    "PathRebuildCooldown",
    "SpeedBoostEnabled",
    "SpeedValue",
    "WebhookEnabled",
    "WebhookPingEveryone",
    "WebhookPingLegend",
    "WebhookPingUltimate",
}

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = clone(item) end
    return result
end

local function readSaved(httpService)
    local saved = {}
    if type(isfile) == "function" and type(readfile) == "function" and isfile(FILE_NAME) then
        local ok, decoded = pcall(function()
            return httpService:JSONDecode(readfile(FILE_NAME))
        end)
        if ok and type(decoded) == "table" then
            saved = decoded
        end
    end
    return saved
end

function Store.load(httpService, environment)
    local saved = readSaved(httpService)
    local config = environment.AutoFarmConfigV21
        or {
            FarmEnabled = false,
            ShowHUD = true,
            HUDPosition = UDim2.fromScale(0.98, 0.04),
        }
    environment.AutoFarmConfigV21 = config

    config.HUDPosition = UDim2.fromScale(0.98, 0.04)
    for key, value in pairs(clone(Defaults)) do
        if config[key] == nil then
            config[key] = value
        end
    end

    for _, key in ipairs(NUMERIC_OR_BOOLEAN_KEYS) do
        if type(saved[key]) == "boolean" then
            config[key] = saved[key]
        elseif tonumber(saved[key]) then
            config[key] = tonumber(saved[key])
        end
    end
	if type(saved.WebhookURL) == "string" then
		config.WebhookURL = saved.WebhookURL
	end

    config.RespawnStuckTime = 30
    config.TargetWalkSpeed = 23
    config.MovementSpeedMultiplier = Defaults.MovementSpeedMultiplier
    config.ApproachDistance = nil
    config.KiteDistance = 70
    config.SkillRange = nil
    config.UseTool = false
	config.FarmRange = tonumber(saved.FarmRange) or tonumber(config.FarmRange) or 700
    if type(saved.FarmEnabled) == "boolean" then
        config.FarmEnabled = saved.FarmEnabled
    end

    config.CombatDistance = nil
    config.RetreatDistance = nil
    config.StuckDistance = nil
    config.StuckLimit = nil
    config.StuckCheckInterval = nil
    config.DirectMoveRefresh = nil
    config.VerticalTravelThreshold = nil
    config.VerticalRespawnHeight = nil
    config.VerticalRespawnCooldown = nil
    config.PathFailureLimit = nil
    config.PathWatchInterval = nil
    config.MeleeVerticalTolerance = nil
    config.RecoveryDetourAt = nil
    config.RecoveryPathAt = nil
    config.RecoveryAlternateAt = nil

    return config
end

function Store.save(httpService, config)
    if type(writefile) ~= "function" then return false end
    local ok = pcall(function()
        writefile(
            FILE_NAME,
            httpService:JSONEncode({
                FarmEnabled = config.FarmEnabled == true,
                AutoReplay = config.AutoReplay == true,
                FarmRange = config.FarmRange,
                DodgeEnabled = config.DodgeEnabled == true,
                DodgeDetectionRadius = config.DodgeDetectionRadius,
                DodgeSafePadding = config.DodgeSafePadding,
                DodgeTriggerPadding = config.DodgeTriggerPadding,
                DodgePreTriggerPadding = config.DodgePreTriggerPadding,
                DodgeLookaheadSeconds = config.DodgeLookaheadSeconds,
                DodgeExitHysteresis = config.DodgeExitHysteresis,
                PreferredCombatDistance = config.PreferredCombatDistance,
                RetreatEnterDistance = config.RetreatEnterDistance,
                RetreatExitDistance = config.RetreatExitDistance,
                AutoStart = config.AutoStart,
                AttackRange = config.AttackRange,
                NormalSkillRange = config.NormalSkillRange,
                BossSkillRange = config.BossSkillRange,
                ExploreStartDelay = config.ExploreStartDelay,
                PathRebuildCooldown = config.PathRebuildCooldown,
                SpeedBoostEnabled = config.SpeedBoostEnabled == true,
                SpeedValue = config.SpeedValue,
                WebhookEnabled = config.WebhookEnabled == true,
                WebhookURL = config.WebhookURL,
                WebhookPingEveryone = config.WebhookPingEveryone == true,
                WebhookPingLegend = config.WebhookPingLegend == true,
                WebhookPingUltimate = config.WebhookPingUltimate == true,
            })
        )
    end)
    return ok
end

return Store
