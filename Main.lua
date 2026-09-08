-- Delta Executor version. Paste the complete file into Delta.
-- One Heartbeat owns movement; DODGE preempts COMBAT, DIRECT, PATH, RECOVERY, and EXPLORE.

print("[BOOT0] AUTOFARM ENTERED")

local function bootStep(name, callback)
	print("[BOOT] BEGIN " .. name)
	local ok, result = xpcall(callback, function(err)
		return debug.traceback(tostring(err), 2)
	end)
	if not ok then
		warn("[BOOT] FAIL " .. name)
		warn(result)
		return nil, false
	end
	print("[BOOT] PASS " .. name)
	return result, true
end

print("[BOOT1] SERVICES")
local Players, okPlayers = bootStep("Players", function() return game:GetService("Players") end)
local PathfindingService, okPathfinding = bootStep("PathfindingService", function() return game:GetService("PathfindingService") end)
local RunService, okRunService = bootStep("RunService", function() return game:GetService("RunService") end)
local UserInputService, okUserInput = bootStep("UserInputService", function() return game:GetService("UserInputService") end)
local HttpService, okHttp = bootStep("HttpService", function() return game:GetService("HttpService") end)
local GuiService, okGui = bootStep("GuiService", function() return game:GetService("GuiService") end)
local VirtualInputManager, okVirtualInput = bootStep("VirtualInputManager", function() return game:GetService("VirtualInputManager") end)
if not okVirtualInput then print("[CAP] VirtualInputManager=FAIL") end
if not (okPlayers and okPathfinding and okRunService and okUserInput and okHttp and okGui) then
	warn("[BOOT] critical Roblox service unavailable")
	return
end

print("[BOOT] CHECK LocalPlayer")
local Player = Players.LocalPlayer
if not Player then
	warn("[BOOT] LocalPlayer=nil")
	return
end
local PlayerGui, okPlayerGui = bootStep("PlayerGui", function() return Player:WaitForChild("PlayerGui", 10) end)
if not okPlayerGui or not PlayerGui then
	warn("[BOOT] PlayerGui unavailable")
	return
end
print("[AF] loaded")
print("[BOOT] startup begin")

print("[BOOT2] CONFIG")
local ConfigStore = require(script.Parent.Systems.ConfigStore)
local SkillFXSystem = require(script.Parent.Systems.SkillFX)
local DodgeControllerModule = require(script.Parent.Controllers.Dodge)
local ReplayControllerModule = require(script.Parent.Controllers.Replay)
local TargetingControllerModule = require(script.Parent.Controllers.Targeting)
local MovementControllerModule = require(script.Parent.Controllers.Movement)

local NavigationState = {
	IDLE = "IDLE",
	DIRECT = "DIRECT",
	STEER = "STEER",
	RETREAT = "RETREAT",
	PATH = "PATH",
	COMBAT = "COMBAT",
	RECOVERY = "RECOVERY",
	DODGE = "DODGE",
	EXPLORE = "EXPLORE",
}

local Environment = (type(getgenv) == "function" and getgenv()) or _G
local function getCapability(name: string)
	local value = Environment[name]
	if value == nil then
		value = rawget(_G, name)
	end
	print("[CAP]", name, value ~= nil and type(value) or "MISSING")
	return value
end
for _, name in ipairs({ "loadstring", "request", "http_request", "gethui", "getgenv", "isfile", "readfile", "writefile", "firesignal" }) do
	getCapability(name)
end
print("[BOOT] previous shutdown check")
if type(Environment.AutoFarmV21Shutdown) == "function" then
	local previousOk, previousErr = pcall(Environment.AutoFarmV21Shutdown)
	print("[BOOT] previous shutdown", previousOk and "PASS" or "FAIL", previousOk and "" or tostring(previousErr))
end
Environment.AutoFarmV21Shutdown = nil

local Config = ConfigStore.load(HttpService, Environment)

local RuntimeState

local function saveConfig()
	ConfigStore.save(HttpService, Config)
end

local Character: Model? = nil
local Humanoid: Humanoid? = nil
local Root: BasePart? = nil
local Target: Model? = nil
local Running = Config.FarmEnabled == true
local Enabled = true

local RespawnInProgress = false
local ResetExecuting = false

local Combat = {
	LastAttack = 0,
	NextQAt = 0,
	NextEAt = 0,
	AimAttachment = nil :: Attachment?,
	AimAlignment = nil :: AlignOrientation?,
	PlayerControls = nil,
	PlayerControlsDisabled = false,
}

local TargetingController
local MovementController
local pointIsSafeFromHazards
local refreshNearbyActiveHazards
local dodgeRouteClear
local HazardSet: { [BasePart]: boolean } = {}
local SkillFX = {
	Models = {} :: { [Model]: { Model: Model, SpawnedAt: number, Hitboxes: { [BasePart]: boolean }, Precasts: { [BasePart]: boolean }, LastSeenAt: number } },
	Hitboxes = {} :: { [BasePart]: boolean },
}
local LastTelemetry: { [string]: string } = {}
RuntimeState = require(script.Parent.Runtime).create(SkillFX)
local ActiveSkillModels = RuntimeState.ActiveSkillModels
local ActiveSkillHitboxes = RuntimeState.ActiveSkillHitboxes

print("[BOOT3] RUNTIME")

local DungeonConnections: { RBXScriptConnection } = {}
local Connections: { RBXScriptConnection } = {}
local CharacterConnections: { RBXScriptConnection } = {}
local recoverByRespawn
local setRunning
local setNavigationState
local commandMovement
local releaseMovement
local stopTranslation
local resetRuntimeForNewDungeon
local getTargetRoot
local updateObsidianStatus
local cancelPathRequest
local pathRemainingMetric
local restoreRotation

local function logPerf(name: string, startedAt: number)
	local elapsed = (os.clock() - startedAt) * 1000
	if elapsed >= 8 then
		print(string.format("[PERF] %s=%.1fms", name, elapsed))
	end
end

local function telemetry(event: string, message: string)
	if not Config.DebugTelemetry or LastTelemetry[event] == message then
		return
	end
	LastTelemetry[event] = message
	print(string.format("[AutoFarm:%s] %s", event, message))
end

RuntimeState.sendStatusWebhook = function(event: string)
	if
		not Config.WebhookEnabled
		or type(Config.WebhookURL) ~= "string"
		or not Config.WebhookURL:match("^https://discord%.com/api/webhooks/")
	then
		return
	end
	local now = os.clock()
	if now - (RuntimeState.WebhookLastByEvent[event] or -math.huge) < 2 then
		return
	end
	local requester = if type(request) == "function"
		then request
		elseif type(http_request) == "function" then http_request
		else nil
	if type(requester) ~= "function" then
		return
	end
	RuntimeState.WebhookLastByEvent[event] = now
	local targetRoot = Target and getTargetRoot(Target)
	local distance = targetRoot and Root and (targetRoot.Position - Root.Position).Magnitude or nil
	local dungeonTimer = "--"
	local timerInstance = RuntimeState.DungeonTimeInstance
	if timerInstance and timerInstance:IsDescendantOf(workspace) then
		pcall(function()
			dungeonTimer = tostring(timerInstance.Value)
		end)
	end
	local payload = {
		username = "Auto Farm V21",
		embeds = {
			{
				title = "Auto Farm status",
				description = "Runtime lifecycle event",
				fields = {
					{ name = "Player", value = tostring(Player.DisplayName), inline = true },
					{ name = "Event", value = tostring(event), inline = true },
					{ name = "Target", value = Target and Target.Name or "None", inline = true },
					{ name = "State", value = tostring(MovementController.State), inline = true },
					{ name = "Distance", value = distance and string.format("%.1f", distance) or "--", inline = true },
					{ name = "FPS", value = string.format("%.0f", RuntimeState.SmoothedFPS), inline = true },
					{ name = "Ping", value = string.format("%.0f ms", RuntimeState.PingMs), inline = true },
					{ name = "Dungeon timer", value = dungeonTimer, inline = true },
				},
			},
		},
	}
	task.spawn(function()
		local ok, response = pcall(function()
			return requester({
				Url = Config.WebhookURL,
				Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body = HttpService:JSONEncode(payload),
			})
		end)
		local status = ok and response and tonumber(response.StatusCode or response.Status) or nil
		if status and status >= 200 and status < 300 then
			print("[WEBHOOK] sent event=" .. event)
		else
			print("[WEBHOOK] failed status=" .. tostring(status or "request-error"))
		end
	end)
end

local function disconnect(connection: RBXScriptConnection?)
	if connection and connection.Connected then
		connection:Disconnect()
	end
end

local function disconnectAll(list: { RBXScriptConnection })
	for index = #list, 1, -1 do
		disconnect(list[index])
		list[index] = nil
	end
end

local function alive(): boolean
	return Character ~= nil and Humanoid ~= nil and Root ~= nil and Character.Parent ~= nil and Humanoid.Health > 0
end

local function isEnemy(model: Model): boolean
	local current: Instance? = model
	while current and current ~= workspace do
		local name = current.Name:lower()
		for _, keyword in ipairs(Config.EnemyKeywords) do
			if string.find(name, string.lower(keyword), 1, true) then
				return true
			end
		end
		current = current.Parent
	end
	return model:FindFirstChild("EnemyNameplate") ~= nil or model:FindFirstChild("Nameplate") ~= nil
end

local normalizeTargetName
local isInsideAnyEnemyFolder
local hazardNameHint
local SkillFXController
local DodgeController
local ReplayController

local function isBossTarget(model: Model): boolean
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or not model:IsDescendantOf(workspace) then
		return false
	end
	local fightingBoss = RuntimeState.FightingBossInstance
	if fightingBoss and fightingBoss:IsDescendantOf(workspace) and fightingBoss.Value and isInsideAnyEnemyFolder(model) then
		return true
	end
	local current: Instance? = model
	while current and current ~= workspace do
		local name = current.Name:lower()
		for _, keyword in ipairs(Config.BossKeywords) do
			if name:find(keyword:lower(), 1, true) then
				return true
			end
		end
		current = current.Parent
	end
	return false
end
local function skillRangeForTarget(target: Model): number
	local boss = isBossTarget(target)
	local range = boss and Config.BossSkillRange or Config.NormalSkillRange
	local signature = (boss and "BOSS" or "NORMAL") .. ":" .. tostring(range)
	if RuntimeState.LastSkillContextSignature ~= signature then
		RuntimeState.LastSkillContextSignature = signature
		print("[SKILL] context=" .. (boss and "BOSS" or "NORMAL") .. " range=" .. tostring(range))
	end
	return range
end

getTargetRoot = function(model: Model): BasePart?
	local humanoidRoot = model:FindFirstChild("HumanoidRootPart", true)
	if humanoidRoot and humanoidRoot:IsA("BasePart") then
		return humanoidRoot
	end
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	local descendantPart = model:FindFirstChildWhichIsA("BasePart", true)
	return descendantPart
end

normalizeTargetName = function(value: string): string
	return value:lower():gsub("[%s%p_]", "")
end

SkillFXController = SkillFXSystem.new({
	Config = Config,
	Models = ActiveSkillModels,
	Hitboxes = ActiveSkillHitboxes,
	NormalizeTargetName = normalizeTargetName,
	GetCharacter = function()
		return Character
	end,
	NameHint = function(part: BasePart)
		return hazardNameHint(part)
	end,
})

isInsideAnyEnemyFolder = function(model: Model): boolean
	local current: Instance? = model.Parent
	while current and current ~= workspace do
		if RuntimeState.EnemyFolders[current] or normalizeTargetName(current.Name) == "enemyfolder" then
			return true
		end
		current = current.Parent
	end
	return false
end

TargetingController = TargetingControllerModule.new({
	Config = Config,
	RuntimeState = RuntimeState,
	Players = Players,
	getCharacter = function() return Character end,
	getRoot = function() return Root end,
	getTargetRoot = getTargetRoot,
	isEnemy = isEnemy,
	isInsideAnyEnemyFolder = isInsideAnyEnemyFolder,
	isBossTarget = isBossTarget,
	skillRangeForTarget = skillRangeForTarget,
	telemetry = telemetry,
	logPerf = logPerf,
})
local EnemySet = TargetingController.EnemySet

local function isValidCombatTarget(model: Model?): boolean
	return TargetingController:isValidCombatTarget(model)
end
local function validTarget(target: Model?): boolean
	return TargetingController:validTarget(target)
end
local function registerEnemy(instance: Instance)
	TargetingController:registerEnemy(instance, Running)
end
MovementController = MovementControllerModule.new({
	Config = Config,
	RuntimeState = RuntimeState,
	PathfindingService = PathfindingService,
	NavigationState = NavigationState,
	getCharacter = function() return Character end,
	getHumanoid = function() return Humanoid end,
	getRoot = function() return Root end,
	getTarget = function() return Target end,
	getEnabled = function() return Enabled end,
	getRunning = function() return Running end,
	alive = function() return alive() end,
	getState = function() return MovementController.State end,
	setNavigationState = function(nextState) setNavigationState(nextState) end,
	getNavigationGoal = function() return MovementController.NavigationGoal end,
	getTargetRoot = getTargetRoot,
	getActiveHazard = function() return DodgeController:getActiveHazard() end,
	validTarget = validTarget,
	recoverByRespawn = function(...) return recoverByRespawn(...) end,
	isRespawnInProgress = function() return RespawnInProgress end,
	refreshNearbyActiveHazards = function() refreshNearbyActiveHazards() end,
	dodgeRouteClear = function(goal) return dodgeRouteClear(goal) end,
	telemetry = telemetry,
	pointIsSafeFromHazards = function(position) return pointIsSafeFromHazards(position) end,
})
local function makeRaycastParams(target: Model?): RaycastParams
	return MovementController:makeRaycastParams(target)
end

local function rootGroundOffset(): number
	return MovementController:rootGroundOffset()
end

local function projectToWalkableGround(position: Vector3, target: Model?): (Vector3, boolean)
	return MovementController:projectToWalkableGround(position, target)
end

local function hasGroundSupport(position: Vector3, target: Model?): boolean
	return MovementController:hasGroundSupport(position, target)
end

hazardNameHint = function(part: BasePart): boolean
	local current: Instance? = part
	while current and current ~= workspace do
		local lowerName = current.Name:lower()
		if
			lowerName:find("circle", 1, true)
			or lowerName:find("danger", 1, true)
			or lowerName:find("warning", 1, true)
			or lowerName:find("aoe", 1, true)
			or lowerName:find("telegraph", 1, true)
			or lowerName:find("indicator", 1, true)
			or lowerName:find("hitbox", 1, true)
			or lowerName:find("skill", 1, true)
			or lowerName:find("attack", 1, true)
		then
			return true
		end
		current = current.Parent
	end
	return false
end

local function isHazardCandidate(part: BasePart): boolean
	if Character and part:IsDescendantOf(Character) then
		return false
	end
	local dimensions = { part.Size.X, part.Size.Y, part.Size.Z }
	table.sort(dimensions)
	local broadAndThin = dimensions[1] <= 5 and dimensions[2] >= 5 and dimensions[3] >= 5
	local elongated = dimensions[3] >= math.max(10, dimensions[2] * 2.5) and dimensions[2] <= math.max(8, dimensions[1] * 2.5)
	return hazardNameHint(part) or (broadAndThin and not elongated)
end

local function isActiveHazardPart(part: BasePart): boolean
	return SkillFXController:isActiveHazardPart(part)
end

local hazardThreatensHeight

local function registerSkillModel(model: Model)
	SkillFXController:registerModel(model)
end

local function unregisterSkillModel(model: Model)
	SkillFXController:unregisterModel(model)
end

local function skillPartThreatens(part: BasePart, position: Vector3, padding: number): boolean
	return DodgeController:skillPartThreatens(part, position, padding)
end

local function registerHazard(instance: Instance)
	-- Cache structural candidates, not only parts that happen to be red at creation time.
	if instance:IsA("BasePart") and (isHazardCandidate(instance) or isActiveHazardPart(instance)) then
		HazardSet[instance] = true
	end
end

local function buildInitialCaches()
	local startedAt = os.clock()
	RuntimeState.refreshDungeonReferences()
	logPerf("dungeonBootstrap", startedAt)
end
local scheduleDungeonCacheRebuild
scheduleDungeonCacheRebuild = function()
	RuntimeState.DungeonCacheDirty = true
	if RuntimeState.DungeonRebuildScheduled then
		return
	end
	RuntimeState.DungeonRebuildScheduled = true
	task.delay(0.45, function()
		RuntimeState.DungeonRebuildScheduled = false
		if not Enabled or not RuntimeState.DungeonCacheDirty then
			return
		end
		RuntimeState.DungeonCacheDirty = false
		local startedAt = os.clock()
		if not RuntimeState.ActiveDungeonRoot or not RuntimeState.ActiveDungeonRoot:IsDescendantOf(workspace) then
			buildInitialCaches()
		end
		TargetingController:invalidateDecision()
		logPerf("cacheRebuild", startedAt)
	end)
end

DodgeController = DodgeControllerModule.new({
	Config = Config,
	RuntimeState = RuntimeState,
	NavigationState = NavigationState,
	ActiveSkillModels = ActiveSkillModels,
	getRoot = function() return Root end,
	getHumanoid = function() return Humanoid end,
	getTarget = function() return Target end,
	getState = function() return MovementController.State end,
	setNavigationState = function(nextState) setNavigationState(nextState) end,
	getNavigationGoal = function() return MovementController.NavigationGoal end,
	getPathWaypoints = function() return MovementController.PathWaypoints end,
	getPathIndex = function() return MovementController.PathIndex end,
	getRecoveryGoal = function() return MovementController.RecoveryGoal end,
	getExploreGoal = function() return MovementController.ExploreGoal end,
	setBestGoalMetric = function(value) MovementController:setBestGoalMetric(value) end,
	addProgressPause = function(pausedFor)
		MovementController:addProgressPause(pausedFor)
	end,
	alive = function() return Running and alive() end,
	validTarget = validTarget,
	restoreRotation = function() restoreRotation() end,
	commandMovement = function(direction, jump) commandMovement(direction, jump) end,
	cancelPathRequest = function() cancelPathRequest() end,
	makeRaycastParams = makeRaycastParams,
	projectToWalkableGround = projectToWalkableGround,
	hasGroundSupport = hasGroundSupport,
	rootGroundOffset = rootGroundOffset,
	unregisterSkillModel = unregisterSkillModel,
	telemetry = telemetry,
	pathRemainingMetric = function() return pathRemainingMetric() end,
})

RuntimeState.predictedHazardRadius = function(part: BasePart): (number, boolean)
	return DodgeController:predictedHazardRadius(part)
end

local function hazardRadius(part: BasePart): number
	return DodgeController:hazardRadius(part)
end

hazardThreatensHeight = function(part: BasePart, position: Vector3): boolean
	return DodgeController:hazardThreatensHeight(part, position)
end

refreshNearbyActiveHazards = function()
	DodgeController:refreshNearbyActiveHazards()
end

pointIsSafeFromHazards = function(position: Vector3): boolean
	return DodgeController:pointIsSafeFromHazards(position)
end

dodgeRouteClear = function(goal: Vector3): boolean
	return DodgeController:dodgeRouteClear(goal)
end

RuntimeState.exploreCellKey = function(position: Vector3): string
	return MovementController:exploreCellKey(position)
end

RuntimeState.rememberExplorePosition = function(position: Vector3)
	MovementController:rememberExplorePosition(position)
end

RuntimeState.evaluateExploreDirection = function(direction: Vector3): (Vector3?, number, string, number)
	return MovementController:evaluateExploreDirection(direction)
end

RuntimeState.chooseExploreGoal = function(): (Vector3?, Vector3?, number)
	return MovementController:chooseExploreGoal()
end

local function clearExploreObjective()
	MovementController:clearExploreObjective()
end

RuntimeState.extendDescentGoal = function(now: number): boolean
	return MovementController:extendDescentGoal(now)
end

local function directRouteClear(goal: Vector3, target: Model?): boolean
	return MovementController:directRouteClear(goal, target)
end

local function navigationGoalForTarget(enemyRoot: BasePart, target: Model): Vector3
	return MovementController:navigationGoalForTarget(enemyRoot, target)
end

local function upcomingMovementGoal(): Vector3?
	return MovementController:upcomingMovementGoal(MovementController.State, MovementController.NavigationGoal, MovementController.PathWaypoints, MovementController.PathIndex, MovementController.RecoveryGoal, MovementController.ExploreGoal)
end

local function acquireBestTarget(): Model?
	return TargetingController:acquireBestTarget()
end

local function targetMetrics(target: Model?): (number, number)
	return TargetingController:targetMetrics(target)
end

local function guiRoots(): { Instance }
	local roots: { Instance } = { PlayerGui }
	if type(gethui) == "function" then
		local ok, hiddenUi = pcall(gethui)
		if ok and typeof(hiddenUi) == "Instance" then
			table.insert(roots, hiddenUi)
		end
	end
	return roots
end

local function visibleGui(object: Instance): boolean
	local current: Instance? = object
	while current do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		elseif current:IsA("ScreenGui") and not current.Enabled then
			return false
		end
		current = current.Parent
	end
	return true
end

local function buttonHasText(button: GuiButton, expected: string): boolean
	local function matches(object: Instance): boolean
		return (object:IsA("TextButton") or object:IsA("TextLabel"))
			and visibleGui(object)
			and object.Text:lower():match("^%s*(.-)%s*$") == expected
	end
	if matches(button) then
		return true
	end
	for _, child in ipairs(button:GetDescendants()) do
		if matches(child) then
			return true
		end
	end
	return false
end

ReplayController = ReplayControllerModule.new({
	Config = Config,
	RuntimeState = RuntimeState,
	GuiService = GuiService,
	VirtualInputManager = VirtualInputManager,
	guiRoots = guiRoots,
	visibleGui = visibleGui,
	buttonHasText = buttonHasText,
	isRunning = function() return Running end,
	telemetry = telemetry,
})

local function findReplayButton(): GuiButton?
	return ReplayController:findButton()
end

local function clickReplayButton(button: GuiButton)
	ReplayController:clickButton(button)
end

local function setReplayPhase(phase: string)
	ReplayController:setPhase(phase)
end

local function findReplayResult(): GuiObject?
	return ReplayController:findResult()
end

local function findReplayOpener(): GuiButton?
	return ReplayController:findOpener()
end

local function tryReplayDungeon()
	ReplayController:tryReplayDungeon()
end

local function armReplayToken(reason: string)
	ReplayController:arm(reason)
end

local bootstrapDungeon
bootstrapDungeon = function(root: Instance)
	local startedAt = os.clock()
	disconnectAll(DungeonConnections)
		table.clear(EnemySet)
		table.clear(RuntimeState.EnemyCandidates)
	table.clear(HazardSet)
	table.clear(ActiveSkillModels)
	table.clear(ActiveSkillHitboxes)
	table.clear(RuntimeState.HazardHistory)
	table.clear(RuntimeState.DummyCache)
	RuntimeState.ActiveDungeonRoot = root
	RuntimeState.DungeonIdentity = root
	RuntimeState.EnemyFolders = {}
	RuntimeState.EnemyFolderInstance = nil
	RuntimeState.FightingBossInstance = nil
	RuntimeState.DungeonFinishedInstance = nil
	RuntimeState.DungeonTimeInstance = nil
	for _, object in ipairs(root:GetDescendants()) do
		local name = normalizeTargetName(object.Name)
		if name == "enemyfolder" and (object:IsA("Folder") or object:IsA("Model")) then
			RuntimeState.EnemyFolders[object] = true
			RuntimeState.EnemyFolderInstance = RuntimeState.EnemyFolderInstance or object
		elseif name == "fightingboss" and object:IsA("BoolValue") then
			RuntimeState.FightingBossInstance = object
		elseif name == "dungeonfinished" and object:IsA("BoolValue") then
			RuntimeState.DungeonFinishedInstance = object
		elseif (name == "timeleft" or name == "timer" or name == "dungeontime" or name == "remainingtime" or name == "time")
			and (object:IsA("NumberValue") or object:IsA("IntValue") or object:IsA("StringValue")) then
			RuntimeState.DungeonTimeInstance = object
		elseif object:IsA("Model") then
			registerEnemy(object)
			registerSkillModel(object)
		end
	end
	table.insert(DungeonConnections, root.DescendantAdded:Connect(function(object)
		local name = normalizeTargetName(object.Name)
		if name == "enemyfolder" and (object:IsA("Folder") or object:IsA("Model")) then
			RuntimeState.EnemyFolders[object] = true
			RuntimeState.EnemyFolderInstance = RuntimeState.EnemyFolderInstance or object
		end
		if name == "fightingboss" and object:IsA("BoolValue") then RuntimeState.FightingBossInstance = object end
		if name == "dungeonfinished" and object:IsA("BoolValue") then RuntimeState.DungeonFinishedInstance = object end
		if (name == "timeleft" or name == "timer" or name == "dungeontime" or name == "remainingtime" or name == "time")
			and (object:IsA("NumberValue") or object:IsA("IntValue") or object:IsA("StringValue")) then RuntimeState.DungeonTimeInstance = object end
		if object:IsA("Model") then
			registerEnemy(object)
			registerSkillModel(object)
			TargetingController:invalidateDecision()
		elseif object:IsA("BasePart") then
			local owner = object:FindFirstAncestorOfClass("Model")
			if owner then registerSkillModel(owner) end
		end
	end))
	table.insert(DungeonConnections, root.DescendantRemoving:Connect(function(object)
		if object:IsA("Model") then EnemySet[object] = nil; unregisterSkillModel(object) end
		if object:IsA("Model") then RuntimeState.EnemyCandidates[object] = nil end
		RuntimeState.EnemyFolders[object] = nil
		if object == RuntimeState.EnemyFolderInstance then RuntimeState.EnemyFolderInstance = nil end
		if object == RuntimeState.FightingBossInstance then RuntimeState.FightingBossInstance = nil end
		if object == RuntimeState.DungeonFinishedInstance then RuntimeState.DungeonFinishedInstance = nil end
		if object == RuntimeState.DungeonTimeInstance then RuntimeState.DungeonTimeInstance = nil end
	end))
	RuntimeState.DungeonBootstrapped = true
	logPerf("dungeonBootstrap", startedAt)
end
RuntimeState.refreshDungeonReferences = function()
	local activeRoot = RuntimeState.ActiveDungeonRoot
	if activeRoot and activeRoot:IsDescendantOf(workspace) then
		return
	end
	RuntimeState.ActiveDungeonRoot = nil
	RuntimeState.DungeonIdentity = nil
	disconnectAll(DungeonConnections)
	local candidate: Instance? = nil
	for _, child in ipairs(workspace:GetChildren()) do
		if normalizeTargetName(child.Name) == "dungeon" then
			candidate = child
			break
		end
	end
	if not candidate then
		local scores: { [Instance]: number } = {}
		for _, object in ipairs(workspace:GetDescendants()) do
			local name = normalizeTargetName(object.Name)
			local weight = if name == "enemyfolder" then 4 elseif name == "dungeonfinished" then 3 elseif name == "timeleft" then 2 elseif name == "fightingboss" then 1 else 0
			if weight > 0 then
				local current: Instance? = object.Parent
				local depth = 0
				while current and current ~= workspace and depth < 8 do
					if current:IsA("Folder") or current:IsA("Model") then
						scores[current] = (scores[current] or 0) + weight / (depth + 1)
					end
					current = current.Parent
					depth += 1
				end
			end
		end
		local bestScore = -math.huge
		for root, score in pairs(scores) do
			if score > bestScore then
				bestScore = score
				candidate = root
			end
		end
	end
	if candidate then
		bootstrapDungeon(candidate)
		print("[AF] dungeon resolver ready")
	end
end
RuntimeState.remainingDungeonTime = function(): number?
	RuntimeState.refreshDungeonReferences()
	local function parseTimerText(value: string): number?
		local minutes, seconds = value:match("^(%d+):(%d%d)$")
		if minutes and seconds then
			return tonumber(minutes) * 60 + tonumber(seconds)
		end
		return nil
	end
	local timeleft = RuntimeState.DungeonTimeInstance
	local resolved: number? = nil
	if timeleft and (timeleft:IsA("NumberValue") or timeleft:IsA("IntValue")) then
		resolved = timeleft.Value
	elseif timeleft and timeleft:IsA("StringValue") then
		resolved = parseTimerText(timeleft.Value)
	end
	if resolved then
		if RuntimeState.LastTimerSource ~= timeleft or RuntimeState.LastTimerValue ~= resolved then
			RuntimeState.LastTimerSource, RuntimeState.LastTimerValue = timeleft, resolved
			print("[TIMER] source=" .. timeleft:GetFullName() .. " value=" .. tostring(resolved))
		end
		return resolved
	end
	local timeText = RuntimeState.DungeonTimeText
	if (not timeText or not timeText:IsDescendantOf(game)) and os.clock() - RuntimeState.LastTimerScanAt >= 1 then
		RuntimeState.LastTimerScanAt = os.clock()
		local bestScore = -math.huge
		for _, uiRoot in ipairs(guiRoots()) do
			for _, object in ipairs(uiRoot:GetDescendants()) do
				if (object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox")) and visibleGui(object) then
					local text = object.Text
					local value = parseTimerText(text)
					local name = normalizeTargetName(object.Name)
					local score = value and (name:find("time", 1, true) or name:find("timer", 1, true) or name:find("dungeon", 1, true)) and 10 or 0
					if value and score > bestScore then
						bestScore = score
						RuntimeState.DungeonTimeText = object
					end
				end
			end
		end
		timeText = RuntimeState.DungeonTimeText
	end
	if timeText and (timeText:IsA("TextLabel") or timeText:IsA("TextButton") or timeText:IsA("TextBox")) and visibleGui(timeText) then
		local timerTextValue = timeText.Text
		pcall(function() if timeText.ContentText and timeText.ContentText ~= "" then timerTextValue = timeText.ContentText end end)
		resolved = parseTimerText(timerTextValue)
		if resolved then
			if RuntimeState.LastTimerSource ~= timeText or RuntimeState.LastTimerValue ~= resolved then
				RuntimeState.LastTimerSource, RuntimeState.LastTimerValue = timeText, resolved
				print("[TIMER] source=" .. timeText:GetFullName() .. " value=" .. tostring(resolved))
			end
			return resolved
		end
	end
	return nil
end

local function normalizeStartText(value: string): string
	return value:lower():gsub("[%s%p_]", "")
end

local function startMarkerText(object: GuiObject): string?
	if not (object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox")) then
		return nil
	end
	local content = ""
	pcall(function()
		content = object.ContentText
	end)
	return content ~= "" and content or object.Text
end

local function findStartMarker(): GuiObject?
	local nameFallback: GuiObject? = nil
	for _, uiRoot in ipairs(guiRoots()) do
		for _, object in ipairs(uiRoot:GetDescendants()) do
			if object:IsA("GuiObject") and visibleGui(object) then
				local text = startMarkerText(object)
				if text and normalizeStartText(text) == "start" then
					return object
				end
				if not nameFallback and normalizeStartText(object.Name):find("start", 1, true) then
					nameFallback = object
				end
			end
		end
	end
	return nameFallback
end

local resolveStartButton

local function cachedStartScreen(): (GuiObject?, GuiButton?)
	local marker = RuntimeState.StartMarker
	if marker and marker:IsDescendantOf(game) and visibleGui(marker) then
		local button = RuntimeState.StartButton
		if button and button:IsDescendantOf(game) and visibleGui(button) then
			return marker, button
		end
		return marker, nil
	end
	RuntimeState.StartMarker = nil
	RuntimeState.StartButton = nil
	RuntimeState.StartDebugMarker = nil
	RuntimeState.StartDebugButton = nil
	local now = os.clock()
	if now - RuntimeState.LastStartMarkerScanAt < 0.5 then
		return nil, nil
	end
	RuntimeState.LastStartMarkerScanAt = now
	marker = findStartMarker()
	RuntimeState.StartMarker = marker
	RuntimeState.StartButton = marker and resolveStartButton(marker) or nil
	return RuntimeState.StartMarker, RuntimeState.StartButton
end

resolveStartButton = function(marker: GuiObject): GuiButton?
	if marker:IsA("GuiButton") then
		return marker
	end
	local current: Instance? = marker.Parent
	for _ = 1, 8 do
		if current and current:IsA("GuiButton") then
			return current
		end
		current = current and current.Parent or nil
	end
	local center = marker.AbsolutePosition + marker.AbsoluteSize * 0.5
	for _, object in ipairs(PlayerGui:GetGuiObjectsAtPosition(center.X, center.Y)) do
		if
			object:IsA("GuiButton")
			and visibleGui(object)
			and (object == marker or object:IsDescendantOf(marker) or marker:IsDescendantOf(object))
		then
			return object
		end
	end
	return nil
end

local function getVimClickPoint(guiObject: GuiObject, xRatio: number, yRatio: number): (number, number, Vector2)
	local point = guiObject.AbsolutePosition
		+ Vector2.new(guiObject.AbsoluteSize.X * xRatio, guiObject.AbsoluteSize.Y * yRatio)
	local screenGui: ScreenGui? = nil
	local current: Instance? = guiObject
	while current do
		if current:IsA("ScreenGui") then
			screenGui = current
			break
		end
		current = current.Parent
	end
	local inset = select(1, GuiService:GetGuiInset())
	if screenGui and not screenGui.IgnoreGuiInset then
		point += inset
	end
	return point.X, point.Y, inset
end

local function setRoundPhase(phase: string)
	if RuntimeState.RoundPhase ~= phase then
		RuntimeState.RoundPhase = phase
		print("[ROUND] phase=" .. phase)
	end
end

local function tryStartDungeon(): boolean
	local marker, cachedButton = cachedStartScreen()
	if not marker then
		return false
	end
	if RuntimeState.RoundPhase == "UNKNOWN" or RuntimeState.RoundPhase == "ACTIVE" then
		setRoundPhase("PRE_START")
	end
	if not Running or not Config.AutoStart or os.clock() - RuntimeState.LastStartClickAt < 1 then
		return true
	end
	if not VirtualInputManager then
		return true
	end
	RuntimeState.LastStartClickAt = os.clock()
	local clickTarget = cachedButton or marker
	local clickX, clickY = getVimClickPoint(clickTarget, 0.5, 0.55)
	local issued = pcall(function()
		VirtualInputManager:SendMouseMoveEvent(clickX, clickY, game)
		task.delay(0.05, function()
			VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, true, game, 0)
			task.delay(0.04, function()
				VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, false, game, 0)
			end)
		end)
	end)
	if issued then
		setRoundPhase("COUNTDOWN")
		telemetry("START", clickTarget:GetFullName())
	end
	return true
end
local function clearAimObjects()
	if Combat.AimAlignment then
		Combat.AimAlignment:Destroy()
		Combat.AimAlignment = nil
	end
	if Combat.AimAttachment then
		Combat.AimAttachment:Destroy()
		Combat.AimAttachment = nil
	end
end

local function ensureAimObjects()
	if not Root or Combat.AimAlignment then
		return
	end
	Combat.AimAttachment = Instance.new("Attachment")
	Combat.AimAttachment.Name = "AutoFarmAimAttachment"
	Combat.AimAttachment.Parent = Root
	Combat.AimAlignment = Instance.new("AlignOrientation")
	Combat.AimAlignment.Name = "AutoFarmAim"
	Combat.AimAlignment.Attachment0 = Combat.AimAttachment
	Combat.AimAlignment.Mode = Enum.OrientationAlignmentMode.OneAttachment
	Combat.AimAlignment.MaxTorque = 100000
	Combat.AimAlignment.Responsiveness = 35
	Combat.AimAlignment.RigidityEnabled = false
	Combat.AimAlignment.Enabled = false
	Combat.AimAlignment.Parent = Root
end

restoreRotation = function()
	if Combat.AimAlignment then
		Combat.AimAlignment.Enabled = false
	end
	if Humanoid then
		Humanoid.AutoRotate = RuntimeState.DefaultAutoRotate
	end
end

local function faceTarget(enemyRoot: BasePart)
	if not Root or not Humanoid then
		return
	end
	local direction = Vector3.new(enemyRoot.Position.X - Root.Position.X, 0, enemyRoot.Position.Z - Root.Position.Z)
	if direction.Magnitude <= 0.01 then
		return
	end
	ensureAimObjects()
	Humanoid.AutoRotate = false
	if Combat.AimAlignment then
		Combat.AimAlignment.Enabled = true
		Combat.AimAlignment.CFrame = CFrame.lookAt(Vector3.zero, direction.Unit)
	end
end

local function updateTargetFacing()
	if Target and validTarget(Target) then
		local enemyRoot = getTargetRoot(Target)
		if enemyRoot then
			faceTarget(enemyRoot)
			return
		end
	end
	restoreRotation()
end

local function sendKey(key: Enum.KeyCode)
	if not VirtualInputManager then
		return
	end
	pcall(function()
		VirtualInputManager:SendKeyEvent(true, key, false, game)
		VirtualInputManager:SendKeyEvent(false, key, false, game)
	end)
end

local function activateSkill(toolName: string, key: Enum.KeyCode, context: string): boolean
	local function logBackend(backend: string)
		local signature = toolName .. ":" .. backend .. ":" .. context
		local stateKey = "LastSkillBackend_" .. toolName
		if RuntimeState[stateKey] ~= signature then
			RuntimeState[stateKey] = signature
			print("[SKILL] " .. toolName .. " backend=" .. backend .. " context=" .. context)
		end
	end

	if Config.UseTool and Character then
		local tool = Character:FindFirstChild(toolName)
		if tool and tool:IsA("Tool") and tool.Enabled then
			local ok = pcall(function()
				tool:Activate()
			end)
			if ok then
				logBackend("Tool")
				return true
			end
		end
	end

	if not VirtualInputManager then
		return false
	end
	local ok = pcall(function()
		VirtualInputManager:SendKeyEvent(true, key, false, game)
	end)
	if ok then
		task.delay(0.04, function()
			pcall(function()
				VirtualInputManager:SendKeyEvent(false, key, false, game)
			end)
		end)
		logBackend("VIM")
		return true
	end

	local virtualKey = if toolName == Config.SkillQToolName or key == Enum.KeyCode.Q then 0x51 else 0x45
	if type(keypress) == "function" and type(keyrelease) == "function" then
		ok = pcall(function()
			keypress(virtualKey)
		end)
		if ok then
			task.delay(0.04, function()
				pcall(function()
					keyrelease(virtualKey)
				end)
			end)
			logBackend("keypress")
			return true
		end
	end

	return false
end

local function findNearestEnemyInSkillRange(): (Model?, BasePart?, number)
	return TargetingController:findNearestEnemyInSkillRange()
end

local function useCombatSkills(enemyRoot: BasePart, distance3D: number)
	local activeSkillRange = Target and skillRangeForTarget(Target) or Config.NormalSkillRange
	if not Target or not validTarget(Target) or distance3D > activeSkillRange then
		return
	end
	local now = os.clock()
	if now >= Combat.NextQAt then
		local minimum = math.max(0.1, Config.QCooldownMin)
		local maximum = math.max(minimum, Config.QCooldownMax)
		local context = isBossTarget(Target) and "BOSS" or "NORMAL"
		if activateSkill(Config.SkillQToolName, Enum.KeyCode.Q, context) then
			Combat.NextQAt = now + minimum + math.random() * (maximum - minimum)
		end
	end
	if now >= Combat.NextEAt then
		local context = isBossTarget(Target) and "BOSS" or "NORMAL"
		if activateSkill(Config.SkillEToolName, Enum.KeyCode.E, context) then
			Combat.NextEAt = now + math.max(0.1, Config.ECooldown)
		end
	end
end

local function useNormalAttack(distance3D: number)
	if
		MovementController.State == NavigationState.DODGE
		or not validTarget(Target)
		or distance3D > Config.AttackRange
		or os.clock() - Combat.LastAttack < Config.AttackCooldown
	then
		return
	end
	Combat.LastAttack = os.clock()
	if not Character then
		return
	end
	local fallbackTool: Tool? = nil
	for _, object in ipairs(Character:GetChildren()) do
		if object:IsA("Tool") then
			fallbackTool = fallbackTool or object
			if object.Name ~= Config.SkillQToolName and object.Name ~= Config.SkillEToolName then
				object:Activate()
				return
			end
		end
	end
	if fallbackTool then
		fallbackTool:Activate()
	end
end

local function resolvePlayerControls()
	if Combat.PlayerControls then
		return Combat.PlayerControls
	end
	local playerScripts = Player:FindFirstChild("PlayerScripts")
	local playerModuleScript = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if not playerModuleScript or not playerModuleScript:IsA("ModuleScript") then
		return nil
	end
	local ok, controls = pcall(function()
		local playerModule = require(playerModuleScript)
		return playerModule:GetControls()
	end)
	if ok and controls then
		Combat.PlayerControls = controls
		return controls
	end
	return nil
end

local function disablePlayerControls()
	if Combat.PlayerControlsDisabled then
		return
	end
	local controls = resolvePlayerControls()
	if not controls or type(controls.Disable) ~= "function" then
		if Combat.PlayerControlsResolvePending then
			return
		end
		Combat.PlayerControlsResolvePending = true
		task.defer(function()
			local playerScripts = Player:WaitForChild("PlayerScripts", 5)
			if playerScripts then
				playerScripts:WaitForChild("PlayerModule", 5)
			end
			Combat.PlayerControlsResolvePending = false
			if Enabled and Running and not Combat.PlayerControlsDisabled then
				local retryControls = resolvePlayerControls()
				if retryControls and type(retryControls.Disable) == "function" then
					local ok = pcall(function()
						retryControls:Disable()
					end)
					if ok then
						Combat.PlayerControlsDisabled = true
					end
				end
			end
		end)
		return
	end
	local ok = pcall(function()
		controls:Disable()
	end)
	if ok then
		Combat.PlayerControlsDisabled = true
	end
end

local function enablePlayerControls()
	if not Combat.PlayerControlsDisabled then
		return
	end
	local controls = Combat.PlayerControls or resolvePlayerControls()
	if not controls or type(controls.Enable) ~= "function" then
		Combat.PlayerControlsDisabled = false
		return
	end
	local ok = pcall(function()
		controls:Enable()
	end)
	if ok then
		Combat.PlayerControlsDisabled = false
	end
end

local function applyMovementSpeed()
	-- Speed is owned by commandMovement; never alter Humanoid.WalkSpeed.
end

local function restoreMovementSpeed()
	-- No WalkSpeed snapshot is owned by AutoFarm.
end

commandMovement = function(direction: Vector3, owner: string?)
	MovementController:commandMovement(direction, owner)
end

releaseMovement = function()
	MovementController:releaseMovement()
end

stopTranslation = function()
	MovementController:stopTranslation()
end
local function disposePath()
	MovementController:disposePath()
end

cancelPathRequest = function()
	MovementController:cancelPathRequest()
end

setNavigationState = function(newState: string)
	MovementController:setNavigationState(newState)
end

local function resetProgress(target: Model?, goal: Vector3?)
	MovementController:resetProgress(target, goal)
end

pathRemainingMetric = function(): number
	return MovementController:pathRemainingMetric(MovementController.NavigationGoal)
end

local function markMeaningfulProgress()
	MovementController:markMeaningfulProgress()
end

local function updateProgressTracking()
	MovementController:updateProgressTracking()
end

local function rayClearance(origin: Vector3, direction: Vector3, target: Model?): number
	return MovementController:rayClearance(origin, direction, target)
end

local function chooseRecoveryDetour(goal: Vector3, retreat: boolean?): Vector3?
	return MovementController:chooseRecoveryDetour(goal, retreat, dodgeRouteClear)
end

local function beginLocalRecovery(goal: Vector3)
	MovementController:beginLocalRecovery(goal)
end

local function issueCurrentWaypoint()
	MovementController:issueCurrentWaypoint()
end

local function requestPath(goal: Vector3): boolean
	return MovementController:requestPath(goal)
end

local function runRecoveryPolicy()
	MovementController:runRecoveryPolicy()
end

local function resetNavigationForTarget(newTarget: Model?)
	RuntimeState.VerticalPathTarget = nil
	RuntimeState.VerticalPathGoal = nil
	if RuntimeState.BossDiedTarget ~= newTarget then
		if RuntimeState.BossDiedConnection then
			RuntimeState.BossDiedConnection:Disconnect()
			RuntimeState.BossDiedConnection = nil
		end
		RuntimeState.BossDiedTarget = nil
	end
	Target = newTarget
	clearExploreObjective()
	if newTarget then
		telemetry("EXPLORE_TARGET", "target=" .. newTarget:GetFullName())
		if isBossTarget(newTarget) then
			RuntimeState.sendStatusWebhook("BOSS_DETECTED")
			local bossHumanoid = newTarget:FindFirstChildOfClass("Humanoid")
			if bossHumanoid and not RuntimeState.BossDiedConnection then
				RuntimeState.BossDiedTarget = newTarget
				RuntimeState.BossDiedConnection = bossHumanoid.Died:Connect(function()
					armReplayToken("boss-died")
					RuntimeState.sendStatusWebhook("BOSS_DIED")
				end)
			end
		end
	end
	MovementController.GoalTarget = nil
	MovementController.NavigationGoal = nil
	RuntimeState.LastGoalRefreshAt = 0
	MovementController.LastDirectDecisionAt = 0
	MovementController.RecoveryGoal = nil
	MovementController.RecoveryUntil = 0
	cancelPathRequest()
	MovementController.LastPathBuildAt = -math.huge
	resetProgress(newTarget, nil)
	setNavigationState(NavigationState.IDLE)
	if not newTarget then
		restoreRotation()
	end
end

local function clearDodgeObjective()
	DodgeController:clearObjective()
end

local function leaveDodge()
	DodgeController:leave()
end

local function updateDodgeController(): boolean
	return DodgeController:update()
end

local function updateDungeonReplayState()
	local now = os.clock()
	if now - RuntimeState.LastDungeonStateCheckAt < 0.25 then
		return
	end
	RuntimeState.LastDungeonStateCheckAt = now
	RuntimeState.refreshDungeonReferences()
	local startMarker = cachedStartScreen()
	if startMarker then
		tryStartDungeon()
		return
	end
	local function hasActiveRoundEvidence(): boolean
		local root = RuntimeState.ActiveDungeonRoot
		if not root or not root:IsDescendantOf(workspace) or not RuntimeState.EnemyFolderInstance then
			return false
		end
		local timer = RuntimeState.DungeonTimeInstance
		if timer and timer:IsDescendantOf(root) then
			return true
		end
		for model in pairs(EnemySet) do
			if isValidCombatTarget(model) and model:IsDescendantOf(root) then
				return true
			end
		end
		return false
	end
	local fightingBoss = RuntimeState.FightingBossInstance
	if fightingBoss and fightingBoss:IsA("BoolValue") then
		if fightingBoss.Value then
			RuntimeState.FightingBossSeenThisRound = true
		elseif RuntimeState.LastFightingBossState and RuntimeState.FightingBossSeenThisRound then
			armReplayToken("fightingBoss-ended")
		end
		RuntimeState.LastFightingBossState = fightingBoss.Value
	else
		RuntimeState.LastFightingBossState = false
	end
	local finished = RuntimeState.DungeonFinishedInstance
	local resultObject = RuntimeState.ReplayResultScanDirty and findReplayResult() or nil
	local resultVisible = resultObject ~= nil
	if resultObject then
		RuntimeState.ReplayCompletionRoot = resultObject
	end
	if finished and finished:IsA("BoolValue") then
		local previousFinished = RuntimeState.PreviousDungeonFinishedInstance
		local newRound = RuntimeState.DungeonFinishedLastState
			and (
				not finished.Value or (previousFinished ~= nil and previousFinished ~= finished and not finished.Value)
			)
		if finished.Value and not RuntimeState.DungeonFinishedLastState then
			setRoundPhase("RESULT")
			if not RuntimeState.ReplayCompletionDetected then
				print("[REPLAY] COMPLETE")
			end
			RuntimeState.ReplayCompletionDetected = true
			armReplayToken("dungeonFinished")
			if RuntimeState.ReplayPhase == "IDLE" or RuntimeState.ReplayPhase == "ARMED" then
				setReplayPhase("RESULT_DETECTED")
			end
			RuntimeState.sendStatusWebhook("DUNGEON_FINISHED")
		end
		RuntimeState.DungeonFinishedLastState = finished.Value
		RuntimeState.PreviousDungeonFinishedInstance = finished
		if newRound and resetRuntimeForNewDungeon then
			setRoundPhase("WAIT_NEW_ROUND")
			print("[REPLAY] NEW ROUND")
			RuntimeState.sendStatusWebhook("NEW_ROUND")
			resetRuntimeForNewDungeon()
			RuntimeState.sendStatusWebhook("DUNGEON_STARTED")
			return
		end
	elseif RuntimeState.DungeonFinishedLastState then
		-- The old value was destroyed during replay; wait for the recreated value before resetting.
		RuntimeState.DungeonFinishedInstance = nil
	end
	if resultVisible then
		setRoundPhase("RESULT")
		RuntimeState.ReplayCompletionDetected = true
		armReplayToken("result-ui")
		if RuntimeState.ReplayPhase == "IDLE" or RuntimeState.ReplayPhase == "ARMED" then
			setReplayPhase("RESULT_DETECTED")
		end
	end
	if RuntimeState.RoundPhase == "RESULT" then
		tryReplayDungeon()
		if RuntimeState.ReplayPhase == "WAIT_NEW_ROUND" then
			setRoundPhase("WAIT_NEW_ROUND")
		end
		return
	end
	if RuntimeState.RoundPhase == "WAIT_NEW_ROUND" then
		if hasActiveRoundEvidence() then
			print("[REPLAY] new round evidence=active-structure")
			resetRuntimeForNewDungeon()
		end
		return
	end
	if hasActiveRoundEvidence() then
		setRoundPhase("ACTIVE")
	end
	local remaining = RuntimeState.remainingDungeonTime()
	if RuntimeState.RoundPhase == "ACTIVE" and remaining and remaining <= 20 then
		armReplayToken("remaining=" .. tostring(remaining))
	end
	tryReplayDungeon()
end

local function updateTargetAndObjective()
	if not Running or not alive() or RuntimeState.RoundPhase ~= "ACTIVE" then
		return
	end
	local now = os.clock()
	if not validTarget(Target) then
		local invalidTarget = Target
		if invalidTarget or now - TargetingController.LastTargetAcquireAt >= Config.TargetAcquireInterval then
			TargetingController.LastTargetAcquireAt = now
			local acquired = acquireBestTarget()
			if acquired then
				resetNavigationForTarget(acquired)
				MovementController.NoTargetSince = nil
			elseif invalidTarget then
				resetNavigationForTarget(nil)
				MovementController.NoTargetSince = now
			end
		end
	end
	if not Target or not Root or not Humanoid then
		MovementController.NoTargetSince = MovementController.NoTargetSince or now
		cancelPathRequest()
		MovementController.NavigationGoal = nil
		MovementController.RecoveryGoal = nil
		if RuntimeState.ActiveDungeonRoot and now - MovementController.NoTargetSince >= Config.ExploreStartDelay then
			if not MovementController.ExploreGoal or now >= MovementController.ExploreCommitUntil then
				local goal, heading = RuntimeState.chooseExploreGoal()
				if goal and heading then
					MovementController.ExploreGoal = goal
					MovementController.ExploreHeading = heading
					MovementController.ExploreBestDistance = MovementController:flatPointDistance(Root.Position, goal)
					MovementController.LastExploreMeaningfulProgressAt = now
					MovementController.ExploreCommitUntil = now + Config.ExploreCommitTime
				end
			end
			if MovementController.ExploreGoal then
				setNavigationState(NavigationState.EXPLORE)
				return
			end
		end
		setNavigationState(NavigationState.IDLE)
		stopTranslation()
		return
	end
	local enemyRoot = getTargetRoot(Target)
	local enemyHumanoid = Target:FindFirstChildOfClass("Humanoid")
	if not enemyRoot or (enemyHumanoid and enemyHumanoid.Health <= 0) then
		resetNavigationForTarget(nil)
		TargetingController.LastTargetAcquireAt = now
		local acquired = acquireBestTarget()
		if acquired then
			resetNavigationForTarget(acquired)
			MovementController.NoTargetSince = nil
		else
			MovementController.NoTargetSince = now
			setNavigationState(NavigationState.IDLE)
			stopTranslation()
		end
		return
	end
	if enemyHumanoid and isBossTarget(Target) and RuntimeState.BossDiedTarget ~= Target then
		if RuntimeState.BossDiedConnection then
			RuntimeState.BossDiedConnection:Disconnect()
		end
		RuntimeState.BossDiedTarget = Target
		RuntimeState.BossDiedConnection = enemyHumanoid.Died:Connect(function()
			armReplayToken("boss-died")
			RuntimeState.sendStatusWebhook("BOSS_DIED")
		end)
	end
	MovementController.NoTargetSince = nil
	if now - TargetingController.LastTargetAcquireAt >= Config.TargetAcquireInterval and MovementController.State ~= NavigationState.DODGE then
		TargetingController.LastTargetAcquireAt = now
		local candidate = acquireBestTarget()
		local _, currentDistance = targetMetrics(Target)
		local _, candidateDistance = targetMetrics(candidate)
		if candidate and candidate ~= Target and candidateDistance <= currentDistance - Config.TargetSwitchMargin then
			resetNavigationForTarget(candidate)
			return
		end
	end
	local distance3D = (enemyRoot.Position - Root.Position).Magnitude
	if now < RuntimeState.RespawnGraceUntil then
		if distance3D <= Config.PreferredCombatDistance then
			cancelPathRequest()
			MovementController.NavigationGoal = nil
			MovementController.RecoveryGoal = nil
			setNavigationState(NavigationState.COMBAT)
			resetProgress(Target, nil)
			return
		end
		cancelPathRequest()
		MovementController.RecoveryGoal = nil
		MovementController.SteeringTried = false
		MovementController.GoalTarget = Target
		MovementController.NavigationGoal = navigationGoalForTarget(enemyRoot, Target)
		setNavigationState(NavigationState.DIRECT)
		return
	end
	if MovementController.State == NavigationState.RETREAT and distance3D < Config.RetreatExitDistance then
		cancelPathRequest()
		MovementController.NavigationGoal = nil
		return
	elseif distance3D < Config.RetreatEnterDistance then
		cancelPathRequest()
		MovementController.NavigationGoal = nil
		setNavigationState(NavigationState.RETREAT)
		return
	end
	if distance3D <= Config.PreferredCombatDistance then
		-- Invalidate an in-flight ComputeAsync as well as any published path. Merely
		-- disposing ActivePath would still allow the old callback to publish PATH.
		if MovementController.State ~= NavigationState.COMBAT or MovementController.PathComputing or MovementController.ActivePath then
			cancelPathRequest()
		end
		MovementController.NavigationGoal = nil
		setNavigationState(NavigationState.COMBAT)
		resetProgress(Target, nil)
		return
	end
	if MovementController.State == NavigationState.COMBAT then
		setNavigationState(NavigationState.IDLE)
	end
	local flatDistance =
		Vector3.new(enemyRoot.Position.X - Root.Position.X, 0, enemyRoot.Position.Z - Root.Position.Z).Magnitude
	local verticalDifference = math.abs(enemyRoot.Position.Y - Root.Position.Y)
	local needsFloorNavigation = verticalDifference > Config.DirectVerticalTolerance
	if needsFloorNavigation then
		if RuntimeState.VerticalPathTarget ~= Target or not RuntimeState.VerticalPathGoal then
			RuntimeState.VerticalPathTarget = Target
			RuntimeState.VerticalPathGoal = navigationGoalForTarget(enemyRoot, Target)
		end
		MovementController.GoalTarget = Target
		MovementController.NavigationGoal = RuntimeState.VerticalPathGoal
		if MovementController.ProgressTarget ~= Target or MovementController.ProgressGoalAnchor ~= MovementController.NavigationGoal then
			resetProgress(Target, MovementController.NavigationGoal)
		end
		if not MovementController.PathComputing and (MovementController.State ~= NavigationState.PATH or not MovementController.PathWaypoints) then
			cancelPathRequest()
			setNavigationState(NavigationState.PATH)
			requestPath(MovementController.NavigationGoal)
		end
		updateProgressTracking()
		runRecoveryPolicy()
		return
	end
	RuntimeState.VerticalPathTarget = nil
	RuntimeState.VerticalPathGoal = nil
	if MovementController.GoalTarget ~= Target or now - RuntimeState.LastGoalRefreshAt >= Config.GoalRefreshInterval then
		RuntimeState.LastGoalRefreshAt = now
		MovementController.GoalTarget = Target
		local newGoal = navigationGoalForTarget(enemyRoot, Target)
		if not MovementController.NavigationGoal or (newGoal - MovementController.NavigationGoal).Magnitude >= Config.DirectGoalChangeDistance then
			MovementController.NavigationGoal = newGoal
		elseif MovementController.State == NavigationState.DIRECT then
			MovementController.NavigationGoal = MovementController.NavigationGoal:Lerp(newGoal, 0.35)
		end
	end
	if not MovementController.ProgressGoalAnchor then
		resetProgress(Target, MovementController.NavigationGoal)
	end
	MovementController:decideNavigation()
	updateProgressTracking()
	runRecoveryPolicy()
end

local function bindCharacter(character: Model)
	RuntimeState.CharacterBindSerial += 1
	local serial = RuntimeState.CharacterBindSerial
	local newHumanoid = character:WaitForChild("Humanoid", 8)
	local newRoot = character:WaitForChild("HumanoidRootPart", 8)
	if not Enabled or serial ~= RuntimeState.CharacterBindSerial or Player.Character ~= character then
		return
	end
	if not newHumanoid or not newHumanoid:IsA("Humanoid") or not newRoot or not newRoot:IsA("BasePart") then
		return
	end
	disconnectAll(CharacterConnections)
	clearAimObjects()
	restoreMovementSpeed()
	cancelPathRequest()
	Character = character
	Humanoid = newHumanoid
	Root = newRoot
	if Humanoid then
		RuntimeState.DefaultAutoRotate = Humanoid.AutoRotate
		RuntimeState.DefaultWalkSpeed = Humanoid.WalkSpeed
	end
	Combat.NextQAt, Combat.NextEAt, Combat.LastAttack = 0, 0, 0
	RespawnInProgress = false
	ResetExecuting = false
	MovementController.NoTargetSince = os.clock()
	clearDodgeObjective()
	resetNavigationForTarget(nil)
	if Running then
		applyMovementSpeed()
		disablePlayerControls()
	end
	for model in pairs(RuntimeState.EnemyCandidates) do
		registerEnemy(model)
	end
	if Humanoid then
		table.insert(
			CharacterConnections,
			Humanoid.Died:Connect(function()
				RuntimeState.RespawnGraceUntil = 0
				RuntimeState.sendStatusWebhook("CHARACTER_DIED")
				resetNavigationForTarget(nil)
				if Running then
					task.defer(function()
						task.wait(0.65)
						if Enabled and Running and not alive() then
							recoverByRespawn(nil, nil)
						end
					end)
				end
			end)
		)
	end
end

setRunning = function(value: boolean)
	if Running == value then
		return
	end
	Running = value
	Config.FarmEnabled = value
	saveConfig()
	if value then
		disablePlayerControls()
		applyMovementSpeed()
		TargetingController:invalidateDecision()
		MovementController.NoTargetSince = os.clock()
		resetProgress(nil, nil)
	else
		RuntimeState.RespawnGraceUntil = 0
		clearDodgeObjective()
		resetNavigationForTarget(nil)
		stopTranslation()
		restoreMovementSpeed()
		restoreRotation()
		enablePlayerControls()
	end
end

local function createObsidianUI()
	if type(loadstring) ~= "function" then
		warn("[UI] FAIL COMPILE", "loadstring unavailable")
		return
	end
	if type(game.HttpGet) ~= "function" then
		warn("[UI] FAIL HTTP", "game.HttpGet unavailable")
		return
	end
	print("[UI] BEGIN HTTP")
	local source, httpOk = bootStep("UI HTTP", function()
		return game:HttpGet("https://raw.githubusercontent.com/deividcomsono/Obsidian/refs/heads/main/Library.lua")
	end)
	if not httpOk or type(source) ~= "string" then
		warn("[UI] FAIL HTTP")
		return
	end
	print("[UI] HTTP PASS bytes=" .. tostring(#source))
	print("[UI] BEGIN COMPILE")
	local chunk, compileOk = bootStep("UI COMPILE", function()
		return loadstring(source)
	end)
	if not compileOk or type(chunk) ~= "function" then
		warn("[UI] FAIL COMPILE")
		return
	end
	print("[UI] COMPILE PASS")
	print("[UI] BEGIN EXECUTE")
	local Library, executeOk = bootStep("UI EXECUTE", chunk)
	if not executeOk or type(Library) ~= "table" then
		warn("[UI] FAIL EXECUTE")
		return
	end
	print("[UI] LIBRARY PASS")
	print("[UI] BEGIN WINDOW")
	local window, windowOk = bootStep("UI WINDOW", function()
		return Library:CreateWindow({
			Title = "Wave Auto Farm",
			Footer = "Delta",
			AutoShow = true,
			Size = UDim2.fromOffset(520, 380),
			Resizable = false,
			ToggleKeybind = Enum.KeyCode.RightShift,
			ShowToggleFrameInKeybinds = false,
			ShowMobileButtons = false,
			Animations = { ToggleWindow = false, TabSwitch = false, Groupbox = false, Dropdown = false, KeyPicker = false },
		})
	end)
	if not windowOk or not window then
		warn("[UI] FAIL WINDOW")
		return
	end
	local setupOk, setupErr = xpcall(function()
		local farmTab = window:AddTab("FARM", "bot")
		local movementTab = window:AddTab("MOVEMENT", "move")
		local statusTab = window:AddTab("STATUS", "activity")
		local settingsTab = window:AddTab("SETTINGS", "settings")
		local farmGroup = farmTab:AddGroupbox({ Side = "Left", Name = "Automation" })
		local movementGroup = movementTab:AddGroupbox({ Side = "Left", Name = "Movement" })
		local statusGroup = statusTab:AddGroupbox({ Side = "Left", Name = "Status" })
		local settingsDodge = settingsTab:AddGroupbox({ Side = "Left", Name = "Dodge" })
		local settingsCombat = settingsTab:AddGroupbox({ Side = "Right", Name = "Combat" })
		local settingsNavigation = settingsTab:AddGroupbox({ Side = "Left", Name = "Navigation" })

		farmGroup:AddToggle("AutoFarm", { Text = "Auto Farm", Default = Running }):OnChanged(function(value)
			setRunning(value)
		end)
		farmGroup:AddToggle("AutoReplay", { Text = "Auto Replay", Default = Config.AutoReplay }):OnChanged(function(value)
			Config.AutoReplay = value
			saveConfig()
		end)
		farmGroup:AddToggle("AutoStart", { Text = "Auto Start", Default = Config.AutoStart }):OnChanged(function(value)
			Config.AutoStart = value
			saveConfig()
		end)
		farmGroup:AddSlider("FarmRange", { Text = "Farm Range", Default = Config.FarmRange, Min = 100, Max = 1500, Rounding = 0 }):OnChanged(function(value)
			Config.FarmRange = value
			saveConfig()
		end)
		movementGroup:AddLabel("Walk Speed: 23 studs/s")
		settingsDodge:AddToggle("DodgeEnabled", { Text = "Dodge Enabled", Default = Config.DodgeEnabled }):OnChanged(function(value)
			Config.DodgeEnabled = value
			saveConfig()
		end)
		local dodgeSettings = {
			{ "DodgeDetectionRadius", "Detection Radius", 20, 200, 1 },
			{ "DodgeSafePadding", "Safe Padding", 0, 20, 0.5 },
			{ "DodgeTriggerPadding", "Trigger Padding", 0, 20, 0.5 },
			{ "DodgePreTriggerPadding", "Pre-Trigger Padding", 0, 30, 0.5 },
			{ "DodgeLookaheadSeconds", "Lookahead Seconds", 0.1, 3, 0.1 },
			{ "DodgeExitHysteresis", "Exit Hysteresis", 0, 2, 0.05 },
		}
		for _, spec in ipairs(dodgeSettings) do
			local key, text, minimum, maximum, rounding = spec[1], spec[2], spec[3], spec[4], spec[5]
			settingsDodge:AddSlider(key, { Text = text, Default = Config[key], Min = minimum, Max = maximum, Rounding = rounding }):OnChanged(function(value)
				Config[key] = value
				saveConfig()
			end)
		end
		local combatSettings = {
			{ "PreferredCombatDistance", "Preferred Combat", 10, 150 },
			{ "RetreatEnterDistance", "Retreat Enter", 10, 150 },
			{ "RetreatExitDistance", "Retreat Exit", 10, 180 },
			{ "NormalSkillRange", "Normal Skill Range", 10, 150 },
			{ "BossSkillRange", "Boss Skill Range", 10, 200 },
			{ "AttackRange", "Attack Range", 5, 50 },
		}
		for _, spec in ipairs(combatSettings) do
			local key, text, minimum, maximum = spec[1], spec[2], spec[3], spec[4]
			settingsCombat:AddSlider(key, { Text = text, Default = Config[key], Min = minimum, Max = maximum, Rounding = 0 }):OnChanged(function(value)
				Config[key] = value
				saveConfig()
			end)
		end
		local navigationSettings = {
			{ "FarmRange", "Farm Range", 100, 1500 },
			{ "ExploreStartDelay", "Explore Start Delay", 0, 10 },
			{ "PathRebuildCooldown", "Path Rebuild Cooldown", 0.2, 5 },
		}
		for _, spec in ipairs(navigationSettings) do
			local key, text, minimum, maximum = spec[1], spec[2], spec[3], spec[4]
			settingsNavigation:AddSlider(key, { Text = text, Default = Config[key], Min = minimum, Max = maximum, Rounding = 1 }):OnChanged(function(value)
				Config[key] = value
				saveConfig()
			end)
		end
		local labels = RuntimeState.ObsidianLabels
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
	end, function(err)
		return debug.traceback(tostring(err), 2)
	end)
	if not setupOk then
		warn("[UI] FAIL WINDOW", setupErr)
		pcall(function() Library:Unload() end)
		return
	end
	RuntimeState.ObsidianLibrary = Library
	RuntimeState.ObsidianWindow = window
	print("[UI] WINDOW PASS")
end
updateObsidianStatus = function()
	local labels = RuntimeState.ObsidianLabels
	if not RuntimeState.ObsidianLibrary or type(labels) ~= "table" then
		return
	end
	local targetRoot = Target and getTargetRoot(Target)
	local distance = targetRoot and Root and (targetRoot.Position - Root.Position).Magnitude
	local timer = RuntimeState.remainingDungeonTime()
	local timerText = timer and string.format("%02d:%02d", math.floor(timer / 60), math.floor(timer % 60)) or "--"
	local graceRemaining = math.max(0, RuntimeState.RespawnGraceUntil - os.clock())
	local hazardText = "None"
	local activeHazard = DodgeController:getActiveHazard()
	if activeHazard and activeHazard:IsDescendantOf(workspace) then
		hazardText = string.format("%s / %.1f%s", activeHazard.Name, RuntimeState.CurrentHazardRadius, RuntimeState.CurrentHazardGrowing and " / predicted-growing" or "")
	end
	local values = {
		Round = "Round: " .. tostring(RuntimeState.RoundPhase),
		Activity = "Activity: " .. tostring(RuntimeState.Activity),
		State = "State: " .. tostring(MovementController.State),
		Target = "Target: " .. (Target and Target.Name or "None"),
		Distance = "Distance: " .. (distance and string.format("%.1f", distance) or "--"),
		Timer = "Dungeon Timer: " .. timerText,
		Replay = "Replay: " .. tostring(RuntimeState.ReplayPhase),
		FPS = "FPS: " .. string.format("%.0f", RuntimeState.SmoothedFPS),
		Ping = "Ping: " .. string.format("%.0f ms", RuntimeState.PingMs),
		Dodge = "Dodge: " .. (Config.DodgeEnabled and (MovementController.State == NavigationState.DODGE and "ACTIVE" or "READY") or "OFF"),
		Grace = graceRemaining > 0 and string.format("Respawn Grace: %.1fs", graceRemaining) or "Respawn Grace: OFF",
		Hazard = "Current Hazard: " .. hazardText,
	}
	for key, text in pairs(values) do
		local label = labels[key]
		if label then
			pcall(function()
				label:SetText(text)
			end)
		end
	end
end
local function shutdown()
	Config.FarmEnabled = Running
	saveConfig()
	Enabled, Running = false, false
	RuntimeState.RespawnGraceUntil = 0
	clearDodgeObjective()
	resetNavigationForTarget(nil)
	stopTranslation()
	restoreMovementSpeed()
	restoreRotation()
	enablePlayerControls()
	disconnectAll(Connections)
	disconnectAll(CharacterConnections)
	clearAimObjects()
	local library = RuntimeState.ObsidianLibrary
	if library and not library.Unloaded and type(library.Unload) == "function" then
		pcall(function()
			library:Unload()
		end)
	end
	RuntimeState.ObsidianLibrary = nil
	RuntimeState.ObsidianWindow = nil
	table.clear(RuntimeState.ObsidianLabels)
	Environment.AutoFarmV21Shutdown = nil
end

print("[BOOT4] FUNCTIONS READY")
table.insert(
	Connections,
	workspace.DescendantAdded:Connect(function(instance)
		if not RuntimeState.ActiveDungeonRoot and instance.Parent == workspace and (instance:IsA("Model") or instance:IsA("Folder")) then
			scheduleDungeonCacheRebuild()
		end
		if RuntimeState.ActiveDungeonRoot and instance:IsA("Model") then
			registerSkillModel(instance)
		elseif RuntimeState.ActiveDungeonRoot and instance:IsA("BasePart") then
			local owner = instance:FindFirstAncestorOfClass("Model")
			if owner then registerSkillModel(owner) end
		end
	end)
)
table.insert(
	Connections,
	PlayerGui.DescendantAdded:Connect(function(instance)
		if instance:IsA("TextLabel") or instance:IsA("TextButton") then
			local text = instance.Text:lower():gsub("[%s%p_]", "")
			local name = normalizeTargetName(instance.Name)
			if text:match("^%d+:%d%d$") or name:find("timer", 1, true) or name:find("timeleft", 1, true) then
				RuntimeState.DungeonTimeText = nil
				RuntimeState.LastTimerScanAt = -math.huge
			end
			if
				text:find("completed", 1, true)
				or text:find("failed", 1, true)
				or text:find("dungeonfailed", 1, true)
				or text == "replay"
				or text == "replaydungeon"
				or text == "playagain"
				or text == "retry"
				or text == "yes"
			then
				RuntimeState.ReplayResultScanDirty = true
			end
		end
	end)
)
table.insert(
	Connections,
	PlayerGui.DescendantRemoving:Connect(function(instance)
		if instance == RuntimeState.DungeonTimeText then
			RuntimeState.DungeonTimeText = nil
			RuntimeState.LastTimerScanAt = -math.huge
		end
		RuntimeState.ReplayResultScanDirty = true
	end)
)
table.insert(
	Connections,
	workspace.DescendantRemoving:Connect(function(instance)
		if instance:IsA("Model") then
			EnemySet[instance] = nil
			RuntimeState.EnemyCandidates[instance] = nil
		end
		if instance:IsA("BasePart") then
			HazardSet[instance] = nil
		end
		if instance == RuntimeState.ActiveDungeonRoot then
			RuntimeState.ActiveDungeonRoot = nil
			RuntimeState.DungeonBootstrapped = false
		end
	end)
)

if Player.Character then
	task.defer(function()
		if Enabled and Player.Character then
			bindCharacter(Player.Character)
		end
	end)
end
table.insert(
	Connections,
	Player.CharacterAdded:Connect(function(character)
		RuntimeState.RespawnGraceUntil = os.clock() + Config.RespawnGraceDuration
		task.defer(function()
			bindCharacter(character)
			if Running then
				task.wait(0.35)
				TargetingController:invalidateDecision()
			end
		end)
	end)
)

table.insert(
	Connections,
	RunService.Heartbeat:Connect(function(dt)
		if not Enabled then
			return
		end
		if dt >= 0.1 then
			print("[PERF] FRAME_SPIKE dt=" .. tostring(dt))
		end
		if dt > 0 then
			local instantFPS = 1 / dt
			RuntimeState.SmoothedFPS = RuntimeState.SmoothedFPS > 0
					and RuntimeState.SmoothedFPS * 0.85 + instantFPS * 0.15
				or instantFPS
		end
		local heartbeatStartedAt = os.clock()
		local now = heartbeatStartedAt
		if now - RuntimeState.LastStatsSampleAt >= 1 then
			RuntimeState.LastStatsSampleAt = now
			pcall(function()
				RuntimeState.PingMs = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
			end)
		end
		local lifecycleStartedAt = os.clock()
		local lifecycleOk, lifecycleErr = xpcall(function()
			updateDungeonReplayState()
		end, function(message)
			return debug.traceback(tostring(message), 2)
		end)
		if not lifecycleOk then
			warn("[AF ERROR]", lifecycleErr)
		end
		logPerf("lifecycle", lifecycleStartedAt)
		if now - RuntimeState.LastHUDUpdateAt >= 0.2 then
			RuntimeState.LastHUDUpdateAt = now
			updateObsidianStatus()
		end
		if RuntimeState.RoundPhase ~= "ACTIVE" then
			setNavigationState(NavigationState.IDLE)
			stopTranslation()
			restoreRotation()
			return
		end
		if not Running or not alive() then
			return
		end
		if ResetExecuting then
			setNavigationState(NavigationState.IDLE)
			stopTranslation()
			return
		end
		applyMovementSpeed()
		MovementController:updateGlobalStuckJump()
		if now - RuntimeState.LastTargetDecisionAt >= Config.TargetDecisionInterval then
			RuntimeState.LastTargetDecisionAt = now
			local targetDecisionStartedAt = os.clock()
			updateTargetAndObjective()
			logPerf("targetDecision", targetDecisionStartedAt)
		end
		updateTargetFacing()
		local skillTarget, skillRoot, skillDistance = findNearestEnemyInSkillRange()
		if skillTarget and skillRoot then
			local previousTarget = Target
			Target = skillTarget
			useCombatSkills(skillRoot, skillDistance)
			Target = previousTarget
		end
		if Config.DodgeEnabled and updateDodgeController() then
			return
		end
		if Target and validTarget(Target) then
			local enemyRoot = getTargetRoot(Target)
			if enemyRoot and Root then
				local distance = (enemyRoot.Position - Root.Position).Magnitude
				useNormalAttack(distance)
			end
		end
		if MovementController.State == NavigationState.DIRECT then
			MovementController:updateDirectMovement()
		elseif MovementController.State == NavigationState.PATH then
			MovementController:updatePathNavigation()
		elseif
			MovementController.State == NavigationState.RECOVERY
			or MovementController.State == NavigationState.STEER
			or MovementController.State == NavigationState.RETREAT
		then
			MovementController:updateRecoveryMovement()
		elseif MovementController.State == NavigationState.EXPLORE then
			MovementController:updateExploreMovement()
		elseif MovementController.State == NavigationState.COMBAT or MovementController.State == NavigationState.IDLE then
			stopTranslation()
		end
		logPerf("heartbeat", heartbeatStartedAt)
	end)
)

Environment.AutoFarmV21Shutdown = shutdown
print("[BOOT5] CONNECTIONS READY")
print("[BOOT6] CORE READY")
RuntimeState.sendStatusWebhook("SCRIPT_STARTED")
task.defer(function()
	local ok, err = xpcall(createObsidianUI, debug.traceback)
	if not ok then
		warn("[UI ERROR]", err)
	end
end)
task.defer(function()
	if not Enabled then
		return
	end
	local ok, err = xpcall(buildInitialCaches, function(message)
		return debug.traceback(tostring(message), 2)
	end)
	if not ok then
		warn("[AF ERROR]", err)
		return
	end
	print("[AF] dungeon resolver ready")
	print("[BOOT] startup ready")
	print("[AF] startup complete")
end)
print("[BOOT_END] SOURCE COMPLETE")
-- VERIFY:
-- one Heartbeat
-- first executable statement is BOOT0
-- Obsidian starts after BOOT6 CORE READY
-- no full dungeon scan before CORE READY
-- final source marker present
-- AUTOFARM_PHYSICAL_EOF
