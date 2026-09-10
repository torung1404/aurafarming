local ObsidianUI = {}
ObsidianUI.__index = ObsidianUI

function ObsidianUI.new(ctx)
	return setmetatable({ Ctx = ctx }, ObsidianUI)
end

function ObsidianUI:create()
	local ctx = self.Ctx
	if type(loadstring) ~= "function" or type(game.HttpGet) ~= "function" then
		return
	end

	local source = game:HttpGet(
		"https://raw.githubusercontent.com/deividcomsono/Obsidian/refs/heads/main/Library.lua"
	)
	local chunk = loadstring(source)
	if type(chunk) ~= "function" then
		return
	end
	local Library = chunk()
	if type(Library) ~= "table" then
		return
	end

	local window = Library:CreateWindow({
		Title = "Wave Auto Farm",
		Footer = "Delta",
		AutoShow = true,
		Size = UDim2.fromOffset(520, 380),
		Resizable = false,
		ToggleKeybind = Enum.KeyCode.RightShift,
		ShowToggleFrameInKeybinds = false,
		ShowMobileButtons = false,
		Animations = {
			ToggleWindow = false,
			TabSwitch = false,
			Groupbox = false,
			Dropdown = false,
			KeyPicker = false,
		},
	})

	local farmTab = window:AddTab("FARM", "bot")
	local movementTab = window:AddTab("MOVEMENT", "move")
	local combatTab = window:AddTab("COMBAT", "swords")
	local dodgeTab = window:AddTab("DODGE", "shield")
	local webhookTab = window:AddTab("WEBHOOK", "send")
	local statusTab = window:AddTab("STATUS", "activity")

	local farmGroup = farmTab:AddGroupbox({ Side = "Left", Name = "Farm" })
	local movementGroup = movementTab:AddGroupbox({ Side = "Left", Name = "Movement" })
	local combatGroup = combatTab:AddGroupbox({ Side = "Left", Name = "Combat" })
	local dodgeGroup = dodgeTab:AddGroupbox({ Side = "Left", Name = "Dodge" })
	local webhookGroup = webhookTab:AddGroupbox({ Side = "Left", Name = "Webhook" })
	local statusGroup = statusTab:AddGroupbox({ Side = "Left", Name = "Runtime Status" })
	local saveGeneration = 0
	local function queueSave()
		saveGeneration += 1
		local generation = saveGeneration
		task.delay(0.5, function()
			if generation == saveGeneration then
				ctx.SaveConfig()
			end
		end)
	end

	farmGroup:AddToggle("AutoFarm", {
		Text = "Auto Farm",
		Default = ctx.GetRunning(),
	}):OnChanged(function(value)
		ctx.SetRunning(value)
	end)

	farmGroup:AddToggle("AutoReplay", {
		Text = "Auto Replay",
		Default = ctx.Config.AutoReplay,
	}):OnChanged(function(value)
		ctx.Config.AutoReplay = value
		ctx.SaveConfig()
	end)

	farmGroup:AddButton({
		Text = "Replay Now",
		Func = function()
			ctx.RequestManualReplay()
		end,
	})

	farmGroup:AddToggle("AutoStart", {
		Text = "Auto Start",
		Default = ctx.Config.AutoStart,
	}):OnChanged(function(value)
		ctx.Config.AutoStart = value
		ctx.SaveConfig()
	end)

	farmGroup:AddSlider("FarmRange", {
		Text = "Farm Range",
		Default = ctx.Config.FarmRange,
		Min = 100,
		Max = 1500,
		Rounding = 0,
	}):OnChanged(function(value)
		ctx.Config.FarmRange = value
		queueSave()
	end)

	movementGroup:AddToggle("SpeedBoostEnabled", {
		Text = "Speed Boost",
		Default = ctx.Config.SpeedBoostEnabled,
	}):OnChanged(function(value)
		ctx.Config.SpeedBoostEnabled = value
		ctx.SaveConfig()
	end)
	movementGroup:AddSlider("SpeedValue", {
		Text = "Speed",
		Default = ctx.Config.SpeedValue,
		Min = 20,
		Max = 100,
		Rounding = 0,
	}):OnChanged(function(value)
		ctx.Config.SpeedValue = value
		queueSave()
	end)
	for _, spec in ipairs({
		{ "PreferredCombatDistance", "Preferred Combat Distance", 10, 150 },
		{ "RetreatEnterDistance", "Retreat Enter", 5, 140 },
		{ "RetreatExitDistance", "Retreat Exit", 10, 160 },
	}) do
		movementGroup:AddSlider(spec[1], {
			Text = spec[2],
			Default = ctx.Config[spec[1]],
			Min = spec[3],
			Max = spec[4],
			Rounding = 0,
		}):OnChanged(function(value)
			ctx.Config[spec[1]] = value
			queueSave()
		end)
	end

	for _, spec in ipairs({
		{ "NormalSkillRange", "Normal Skill Range", 10, 150 },
		{ "BossSkillRange", "Boss Skill Range", 10, 200 },
		{ "AttackRange", "Attack Range", 5, 50 },
	}) do
		combatGroup:AddSlider(spec[1], {
			Text = spec[2],
			Default = ctx.Config[spec[1]],
			Min = spec[3],
			Max = spec[4],
			Rounding = 0,
		}):OnChanged(function(value)
			ctx.Config[spec[1]] = value
			queueSave()
		end)
	end

	dodgeGroup:AddToggle("DodgeEnabled", {
		Text = "Dodge Enabled",
		Default = ctx.Config.DodgeEnabled,
	}):OnChanged(function(value)
		ctx.Config.DodgeEnabled = value
		ctx.SaveConfig()
	end)

	webhookGroup:AddToggle("WebhookEnabled", {
		Text = "Enabled",
		Default = ctx.Config.WebhookEnabled,
	}):OnChanged(function(value)
		ctx.Config.WebhookEnabled = value
		ctx.SaveConfig()
	end)
	webhookGroup:AddInput("WebhookURL", {
		Text = "URL",
		Default = ctx.Config.WebhookURL,
		Numeric = false,
		Finished = true,
	}):OnChanged(function(value)
		ctx.Config.WebhookURL = value
		ctx.SaveConfig()
	end)
	for _, spec in ipairs({
		{ "WebhookPingEveryone", "Ping Everyone" },
		{ "WebhookPingLegend", "Ping Legend" },
		{ "WebhookPingUltimate", "Ping Ultimate" },
	}) do
		webhookGroup:AddToggle(spec[1], {
			Text = spec[2],
			Default = ctx.Config[spec[1]],
		}):OnChanged(function(value)
			ctx.Config[spec[1]] = value
			ctx.SaveConfig()
		end)
	end

	local labels = ctx.Runtime.ObsidianLabels
	labels.Round = statusGroup:AddLabel("Round: --")
	labels.Activity = statusGroup:AddLabel("Activity: IDLE")
	labels.State = statusGroup:AddLabel("State: --")
	labels.Target = statusGroup:AddLabel("Target: None")
	labels.Distance = statusGroup:AddLabel("Distance: --")
	labels.Timer = statusGroup:AddLabel("Dungeon Timer: --")
	labels.Replay = statusGroup:AddLabel("Replay: --")
	labels.FPS = statusGroup:AddLabel("FPS: --")
	labels.Ping = statusGroup:AddLabel("Ping: --")
	labels.Dodge = statusGroup:AddLabel("Dodge: --")
	labels.Grace = statusGroup:AddLabel("Respawn Grace: OFF")
	labels.Hazard = statusGroup:AddLabel("Current Hazard: None")

	ctx.Runtime.ObsidianLibrary = Library
	ctx.Runtime.ObsidianWindow = window
end

function ObsidianUI:update()
	local ctx = self.Ctx
	local runtime = ctx.Runtime
	local labels = runtime.ObsidianLabels
	if not runtime.ObsidianLibrary or type(labels) ~= "table" then
		return
	end

	local target = ctx.GetTarget()
	local root = ctx.GetRoot()
	local targetRoot = target and ctx.GetTargetRoot(target)
	local distance = targetRoot and root and (targetRoot.Position - root.Position).Magnitude
	local timer = ctx.GetRemainingDungeonTime()
	local timerText = timer
		and string.format("%02d:%02d", math.floor(timer / 60), math.floor(timer % 60))
		or "--"
	local graceRemaining = math.max(0, runtime.RespawnGraceUntil - os.clock())
	local activeHazard = ctx.GetActiveHazard and ctx.GetActiveHazard() or nil
	local hazardName = activeHazard and activeHazard:IsDescendantOf(workspace) and activeHazard.Name or "None"

	local values = {
		Round = "Round: " .. tostring(runtime.RoundPhase),
		Activity = "Activity: " .. tostring(runtime.Activity),
		State = "State: " .. tostring(ctx.GetNavigationState()),
		Target = "Target: " .. (target and target.Name or "None"),
		Distance = "Distance: " .. (distance and string.format("%.1f", distance) or "--"),
		Timer = "Dungeon Timer: " .. timerText,
		Replay = "Replay: " .. tostring(runtime.ReplayPhase),
		FPS = "FPS: " .. string.format("%.0f", runtime.SmoothedFPS),
		Ping = "Ping: " .. string.format("%.0f ms", runtime.PingMs),
		Dodge = "Dodge: " .. (
			ctx.Config.DodgeEnabled
			and (ctx.GetNavigationState() == ctx.NavigationState.DODGE and "ACTIVE" or "READY")
			or "OFF"
		),
		Grace = graceRemaining > 0
			and string.format("Respawn Grace: %.1fs", graceRemaining)
			or "Respawn Grace: OFF",
		Hazard = "Current Hazard: " .. hazardName,
	}

	for key, value in pairs(values) do
		local label = labels[key]
		if label then
			pcall(function()
				label:SetText(value)
			end)
		end
	end
end

return ObsidianUI
