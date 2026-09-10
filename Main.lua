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
local CombatControllerModule = require(script.Parent.Controllers.Combat)
local LifecycleControllerModule = require(script.Parent.Controllers.Lifecycle)
local DungeonResolverModule = require(script.Parent.Systems.DungeonResolver)
local TimerResolverModule = require(script.Parent.Systems.TimerResolver)
local ObsidianUIModule = require(script.Parent.UI.ObsidianUI)

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

local State = NavigationState.IDLE
local NavigationGoal: Vector3? = nil
local NavigationMeta = {
	GoalTarget = nil :: Model?,
	LastDirectDecisionAt = 0,
	PathGoal = nil :: Vector3?,
	LastPathBuildAt = -math.huge,
	PathNeedsRebuild = false,
	ActiveWaypointIssueSerial = 0,
	SteeringTried = false,
}

local ActivePath: Path? = nil
local PathWaypoints: { PathWaypoint }? = nil
local PathIndex = 2
local PathComputing = false
local PathRequestSerial = 0
local PathIssuedIndex = 0
local PathIssuedAt = 0
local PathBestWaypointDistance = math.huge

local RecoveryGoal: Vector3? = nil
local RecoveryUntil = 0
local RecoveryState = {
	RespawnInProgress = false,
	ResetExecuting = false,
}

local BestGoalMetric = math.huge
local BestVerticalDifference = math.huge
local LastMeaningfulProgressAt = os.clock()
local ProgressState = {
	Target = nil :: Model?,
	GoalAnchor = nil :: Vector3?,
	LastCheckAt = 0,
}

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
local HazardSet: { [BasePart]: boolean } = {}
local SkillFX = {
	Models = {} :: { [Model]: { Model: Model, SpawnedAt: number, Hitboxes: { [BasePart]: boolean }, Precasts: { [BasePart]: boolean }, LastSeenAt: number } },
	Hitboxes = {} :: { [BasePart]: boolean },
}
local ExploreGoal: Vector3? = nil
local ExploreBestDistance = math.huge
local LastExploreMeaningfulProgressAt = os.clock()
local ExploreState = {
	Heading = nil :: Vector3?,
	CommitUntil = 0,
	LastSelectionAt = -math.huge,
	NoTargetSince = nil :: number?,
	DescentLocked = false,
	DescentRiseStrikes = 0,
	Cells = {} :: { [string]: boolean },
	CellOrder = {} :: { string },
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
local clearDodgeObjective
local getTargetRoot
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
	local requester = if type(request) == "function" then request else nil
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
					{ name = "State", value = tostring(State), inline = true },
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
local ObsidianUI
local TimerResolver
local DungeonResolver
local LifecycleController
local CombatController

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
	getState = function() return State end,
	setNavigationState = function(nextState) setNavigationState(nextState) end,
	getNavigationGoal = function() return NavigationGoal end,
	getPathWaypoints = function() return PathWaypoints end,
	getPathIndex = function() return PathIndex end,
	getRecoveryGoal = function() return RecoveryGoal end,
	getExploreGoal = function() return ExploreGoal end,
	setBestGoalMetric = function(value) BestGoalMetric = value end,
	addProgressPause = function(pausedFor)
		LastMeaningfulProgressAt += pausedFor
		LastExploreMeaningfulProgressAt += pausedFor
		NavigationMeta.LastDirectDecisionAt = 0
	end,
	alive = function() return Running and alive() end,
	validTarget = validTarget,
	restoreRotation = function() CombatController:restoreRotation() end,
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

local function refreshNearbyActiveHazards()
	DodgeController:refreshNearbyActiveHazards()
end

local function pointIsSafeFromHazards(position: Vector3): boolean
	return DodgeController:pointIsSafeFromHazards(position)
end

local function dodgeRouteClear(goal: Vector3): boolean
	return DodgeController:dodgeRouteClear(goal)
end

RuntimeState.exploreCellKey = function(position: Vector3): string
	local size = Config.ExploreHistoryCellSize
	return string.format(
		"%d:%d:%d",
		math.floor(position.X / size),
		math.floor(position.Y / size),
		math.floor(position.Z / size)
	)
end

RuntimeState.rememberExplorePosition = function(position: Vector3)
	local key = RuntimeState.exploreCellKey(position)
	if ExploreState.Cells[key] then
		return
	end
	ExploreState.Cells[key] = true
	table.insert(ExploreState.CellOrder, key)
	if #ExploreState.CellOrder > Config.ExploreHistoryLimit then
		local oldest = table.remove(ExploreState.CellOrder, 1)
		ExploreState.Cells[oldest] = nil
	end
end

RuntimeState.evaluateExploreDirection = function(direction: Vector3): (Vector3?, number, string, number)
	if not Root then
		return nil, -math.huge, "no-root", 0
	end
	local stepDistance = Config.ExploreStepDistance
	local obstacle =
		workspace:Raycast(Root.Position + Vector3.new(0, 2.5, 0), direction * stepDistance, makeRaycastParams(nil))
	if obstacle and obstacle.Distance < stepDistance - 1.5 then
		return nil, -math.huge, "wall", 0
	end
	local previousGround = Root.Position
	local finalGround: Vector3? = nil
	for sampleIndex = 1, Config.ExploreProbeSamples do
		local alpha = sampleIndex / Config.ExploreProbeSamples
		local sample = Root.Position + direction * (stepDistance * alpha)
		local ground, foundGround = projectToWalkableGround(sample, nil)
		if not foundGround then
			return nil, -math.huge, "gap", 0
		end
		if math.abs(ground.Y - previousGround.Y) > Config.ExploreMaxVerticalStep then
			return nil, -math.huge, ground.Y < previousGround.Y and "unsafe-drop" or "unsafe-rise", 0
		end
		if not pointIsSafeFromHazards(ground) then
			return nil, -math.huge, "hazard", 0
		end
		previousGround = ground
		finalGround = ground
	end
	if not finalGround then
		return nil, -math.huge, "no-ground", 0
	end
	local continuity = ExploreState.Heading and math.max(-1, math.min(1, ExploreState.Heading:Dot(direction))) or 0
	local downhillDelta = Root.Position.Y - finalGround.Y
	local novelty = ExploreState.Cells[RuntimeState.exploreCellKey(finalGround)] and -14 or 12
	local downhillBonus = math.clamp(downhillDelta * 1.25, -5, 7)
	local score = 30 + continuity * 8 + novelty + downhillBonus
	return finalGround,
		score,
		string.format(
			"score=%.1f continuity=%.2f novelty=%.1f downhill=%.1f",
			score,
			continuity,
			novelty,
			downhillDelta
		),
		downhillDelta
end

RuntimeState.chooseExploreGoal = function(): (Vector3?, Vector3?, number)
	if not Root then
		return nil, nil, 0
	end
	refreshNearbyActiveHazards()
	local forward = ExploreState.Heading or Vector3.new(Root.CFrame.LookVector.X, 0, Root.CFrame.LookVector.Z)
	if forward.Magnitude <= 0.1 then
		forward = Vector3.new(0, 0, -1)
	else
		forward = forward.Unit
	end
	local baseAngle = math.atan2(forward.Z, forward.X)
	local bestGoal: Vector3? = nil
	local bestDirection: Vector3? = nil
	local bestScore = -math.huge
	local bestDownhill = 0
	for index = 0, Config.ExploreCandidateCount - 1 do
		local angle = baseAngle + index * math.pi * 2 / Config.ExploreCandidateCount
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local goal, score, reason, downhill = RuntimeState.evaluateExploreDirection(direction)
		telemetry("EXPLORE_CANDIDATE_" .. tostring(index), reason)
		if goal and score > bestScore then
			bestGoal, bestDirection, bestScore, bestDownhill = goal, direction, score, downhill
		end
	end
	if bestGoal then
		telemetry("EXPLORE_GOAL", string.format("goal=%s score=%.1f", tostring(bestGoal), bestScore))
	else
		telemetry("EXPLORE_GOAL", "no-safe-candidate")
	end
	return bestGoal, bestDirection, bestDownhill
end

local function clearExploreObjective()
	ExploreGoal = nil
	ExploreState.CommitUntil = 0
	ExploreBestDistance = math.huge
	ExploreState.DescentLocked = false
	ExploreState.DescentRiseStrikes = 0
end

RuntimeState.extendDescentGoal = function(now: number): boolean
	if not ExploreState.DescentLocked or not ExploreState.Heading or not Root then
		return false
	end
	local goal, _, reason, downhill = RuntimeState.evaluateExploreDirection(ExploreState.Heading)
	if not goal then
		telemetry("DESCENT_RELEASE", reason)
		ExploreState.DescentLocked = false
		ExploreState.DescentRiseStrikes = 0
		return false
	end
	if downhill < -Config.DescentFlatTolerance then
		ExploreState.DescentRiseStrikes += 1
		if ExploreState.DescentRiseStrikes >= Config.DescentRiseReleaseCount then
			telemetry("DESCENT_RELEASE", string.format("rising downhill=%.1f", downhill))
			ExploreState.DescentLocked = false
			ExploreState.DescentRiseStrikes = 0
			return false
		end
	else
		ExploreState.DescentRiseStrikes = 0
	end
	ExploreGoal = goal
	ExploreBestDistance = flatPointDistance(Root.Position, goal)
	ExploreState.CommitUntil = now + Config.ExploreCommitTime
	telemetry("DESCENT_EXTEND", string.format("goal=%s downhill=%.1f", tostring(goal), downhill))
	return true
end

local function updateExploreMovement()
	if State ~= NavigationState.EXPLORE or not Root or not Humanoid or not ExploreGoal or Target then
		return
	end
	local direction = Vector3.new(ExploreGoal.X - Root.Position.X, 0, ExploreGoal.Z - Root.Position.Z)
	local distance = direction.Magnitude
	if distance <= Config.ExploreReachedDistance then
		commandMovement(Vector3.zero, false)
		return
	end
	if distance <= ExploreBestDistance - Config.MeaningfulProgressDistance then
		ExploreBestDistance = distance
		LastExploreMeaningfulProgressAt = os.clock()
	end
	if os.clock() - LastExploreMeaningfulProgressAt >= Config.ExploreRespawnStuckTime and not RecoveryState.RespawnInProgress then
		recoverByRespawn(nil, LastExploreMeaningfulProgressAt, true)
		return
	end
	commandMovement(direction.Unit, false)
end

local function directRouteClear(goal: Vector3, target: Model?): boolean
	return MovementController:directRouteClear(goal, target)
end

local function navigationGoalForTarget(enemyRoot: BasePart, target: Model): Vector3
	if not Root then
		return enemyRoot.Position
	end
	local flat = Vector3.new(enemyRoot.Position.X - Root.Position.X, 0, enemyRoot.Position.Z - Root.Position.Z)
	local height = math.abs(enemyRoot.Position.Y - Root.Position.Y)
	local targetBelow = enemyRoot.Position.Y < Root.Position.Y - Config.DirectVerticalTolerance
	if targetBelow and (flat.Magnitude <= 15 or height > flat.Magnitude) then
		local targetGround, foundTargetGround = projectToWalkableGround(enemyRoot.Position, target)
		if foundTargetGround then
			local chosen: Vector3? = nil
			for _, radius in ipairs({ 6, 12 }) do
				for index = 0, 7 do
					local angle = index * math.pi * 2 / 8
					local sample = enemyRoot.Position
						+ Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
					local candidate, foundCandidate = projectToWalkableGround(sample, target)
					if foundCandidate and math.abs(candidate.Y - targetGround.Y) <= Config.DirectVerticalTolerance then
						chosen = candidate
						break
					end
				end
				if chosen then
					break
				end
			end
			return chosen or targetGround
		end
	end
	local desired = enemyRoot.Position
	if flat.Magnitude > 0.01 then
		local horizontalHold = math.sqrt(math.max(0, Config.PreferredCombatDistance ^ 2 - height ^ 2))
		desired = enemyRoot.Position - flat.Unit * horizontalHold
	end
	-- Probe downward close to the target Y, avoiding the wrong upper floor that caused the 15-stud deadlock.
	local targetGround, targetGroundFound = projectToWalkableGround(enemyRoot.Position, target)
	local approachGround, approachGroundFound = projectToWalkableGround(desired, target)
	if targetGroundFound and (not approachGroundFound or math.abs(approachGround.Y - targetGround.Y) > 6) then
		return targetGround
	end
	if approachGroundFound then
		return approachGround
	end
	if targetGroundFound then
		return targetGround
	end
	return desired
end

local function acquireBestTarget(): Model?
	return TargetingController:acquireBestTarget()
end

local function targetMetrics(target: Model?): (number, number)
	return TargetingController:targetMetrics(target)
end

local function updateGlobalStuckJump()
	if not Running or not alive() or not Root or not Humanoid then
		RuntimeState.JumpStillSince = os.clock()
		RuntimeState.JumpBestDistance = math.huge
		RuntimeState.JumpBestVertical = math.huge
		return
	end
	local now = os.clock()
	local translating = State == NavigationState.DIRECT
		or State == NavigationState.STEER
		or State == NavigationState.RETREAT
		or State == NavigationState.PATH
		or State == NavigationState.RECOVERY
		or State == NavigationState.EXPLORE
	if not translating then
		RuntimeState.JumpStillSince = now
		RuntimeState.JumpBestDistance = math.huge
		RuntimeState.JumpBestVertical = math.huge
		return
	end
	local targetRoot = if validTarget(Target) then getTargetRoot(Target) else nil
	local followingVerticalPath = State == NavigationState.PATH and RuntimeState.VerticalPathTarget == Target
	local objectivePosition = if followingVerticalPath
		then upcomingMovementGoal()
		else if targetRoot then targetRoot.Position else upcomingMovementGoal()
	if not objectivePosition then
		RuntimeState.JumpStillSince = now
		RuntimeState.JumpBestDistance = math.huge
		RuntimeState.JumpBestVertical = math.huge
		return
	end
	local delta = objectivePosition - Root.Position
	local distance, vertical = delta.Magnitude, math.abs(delta.Y)
	if RuntimeState.JumpBestDistance == math.huge then
		RuntimeState.JumpBestDistance = distance
		RuntimeState.JumpBestVertical = vertical
		RuntimeState.JumpStillSince = now
		return
	end
	local progressThreshold = Config.MeaningfulProgressDistance
	local progressed = distance <= RuntimeState.JumpBestDistance - progressThreshold
		or vertical <= RuntimeState.JumpBestVertical - progressThreshold
	if progressed then
		RuntimeState.JumpBestDistance = math.min(RuntimeState.JumpBestDistance, distance)
		RuntimeState.JumpBestVertical = math.min(RuntimeState.JumpBestVertical, vertical)
		RuntimeState.JumpStillSince = now
	elseif now - RuntimeState.JumpStillSince >= 20 and not RecoveryState.RespawnInProgress then
		recoverByRespawn(nil, nil, false, RuntimeState.JumpStillSince)
	end
end

local function guiRoots(): { Instance }
	local roots: { Instance } = { PlayerGui }
	local okCoreGui, coreGui = pcall(function()
		return game:GetService("CoreGui")
	end)
	if okCoreGui and coreGui then
		table.insert(roots, coreGui)
	end
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


CombatController = CombatControllerModule.new({
	Config = Config,
	Runtime = RuntimeState,
	Player = Player,
	VirtualInputManager = VirtualInputManager,
	GetCharacter = function() return Character end,
	GetHumanoid = function() return Humanoid end,
	GetRoot = function() return Root end,
	GetTarget = function() return Target end,
	GetTargetRoot = getTargetRoot,
	ValidTarget = validTarget,
	IsBossTarget = isBossTarget,
	SkillRangeForTarget = skillRangeForTarget,
	-- Main owns live navigation until the incomplete Movement migration is done.
	GetNavigationState = function() return State end,
	NavigationState = NavigationState,
})

DungeonResolver = DungeonResolverModule.new({
	Runtime = RuntimeState,
	EnemySet = EnemySet,
	DungeonConnections = DungeonConnections,
	Normalize = normalizeTargetName,
	DisconnectAll = disconnectAll,
	RegisterEnemy = registerEnemy,
	RegisterSkillModel = registerSkillModel,
	UnregisterSkillModel = unregisterSkillModel,
	IsPlayerCharacter = function(model: Model)
		return model == Character or Players:GetPlayerFromCharacter(model) ~= nil
	end,
})

TimerResolver = TimerResolverModule.new({
	Runtime = RuntimeState,
	RefreshDungeonReferences = function()
		if DungeonResolver and DungeonResolver.refresh then
			return DungeonResolver:refresh()
		elseif RuntimeState.refreshDungeonReferences then
			return RuntimeState.refreshDungeonReferences()
		end
	end,
	GuiRoots = guiRoots,
	VisibleGui = visibleGui,
	Normalize = normalizeTargetName,
})

LifecycleController = LifecycleControllerModule.new({
	Runtime = RuntimeState,
	EnemySet = EnemySet,
	IsValidCombatTarget = isValidCombatTarget,
	RefreshDungeonReferences = function()
		if DungeonResolver and DungeonResolver.refresh then
			return DungeonResolver:refresh()
		elseif RuntimeState.refreshDungeonReferences then
			return RuntimeState.refreshDungeonReferences()
		end
	end,
	CachedStartScreen = cachedStartScreen,
	TryStartDungeon = tryStartDungeon,
	TryReplayDungeon = tryReplayDungeon,
	ArmReplayToken = armReplayToken,
	FindReplayResult = findReplayResult,
	SetReplayPhase = setReplayPhase,
	ResetRuntimeForNewDungeon = function()
		if resetRuntimeForNewDungeon then
			return resetRuntimeForNewDungeon()
		end
	end,
	GetRemainingDungeonTime = function()
		if TimerResolver and TimerResolver.getRemainingTime then
			return TimerResolver:getRemainingTime()
		elseif RuntimeState.remainingDungeonTime then
			return RuntimeState.remainingDungeonTime()
		end
	end,
})

ObsidianUI = ObsidianUIModule.new({
	Config = Config,
	Runtime = RuntimeState,
	Player = Player,
	GetRunning = function() return Running end,
	SetRunning = function(value) return setRunning(value) end,
	SaveConfig = saveConfig,
	GetTarget = function() return Target end,
	GetRoot = function() return Root end,
	GetTargetRoot = getTargetRoot,
	GetNavigationState = function() return State end,
	GetActiveHazard = function() return DodgeController:getActiveHazard() end,
	NavigationState = NavigationState,
	GetRemainingDungeonTime = function()
		if TimerResolver and TimerResolver.getRemainingTime then
			return TimerResolver:getRemainingTime()
		elseif RuntimeState.remainingDungeonTime then
			return RuntimeState.remainingDungeonTime()
		end
	end,
})

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
				if not nameFallback then
					local normalizedName = normalizeStartText(object.Name)
					if normalizedName == "start"
						or normalizedName == "startbutton"
						or normalizedName == "startlabel"
						or normalizedName == "startimage"
					then
						nameFallback = object
					end
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
	local markerName = marker and marker:GetFullName() or "nil"
	local buttonName = RuntimeState.StartButton and RuntimeState.StartButton:GetFullName() or "nil"
	local signature = markerName .. "|" .. buttonName
	if RuntimeState.StartDebugSignature ~= signature then
		RuntimeState.StartDebugSignature = signature
		print("[START] marker=" .. markerName)
		print("[START] button=" .. buttonName)
	end
	return RuntimeState.StartMarker, RuntimeState.StartButton
end

-- Canonical module compatibility boundary. Legacy callers keep their API, but
-- resolver/timer state now has one owner instead of two competing scanners.
RuntimeState.refreshDungeonReferences = function()
	return DungeonResolver:refresh()
end
RuntimeState.remainingDungeonTime = function(): number?
	return TimerResolver:getRemainingTime()
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
		local blocked = if not Running then "not-running" elseif not Config.AutoStart then "auto-start-disabled" else "cooldown"
		if RuntimeState.StartDebugBlockState ~= blocked then
			RuntimeState.StartDebugBlockState = blocked
			print("[START] blocked=" .. blocked)
		end
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
		if RuntimeState.StartDebugClickState ~= "PASS" then
			RuntimeState.StartDebugClickState = "PASS"
			print("[START] click=PASS")
		end
		telemetry("START", clickTarget:GetFullName())
	else
		if RuntimeState.StartDebugClickState ~= "FAIL" then
			RuntimeState.StartDebugClickState = "FAIL"
			print("[START] click=FAIL")
		end
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
	CombatController:restoreRotation()
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
		State == NavigationState.DODGE
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
	disconnect(RuntimeState.PathBlockedConnection)
	RuntimeState.PathBlockedConnection = nil
	if ActivePath then
		ActivePath:Destroy()
	end
	ActivePath = nil
	PathWaypoints = nil
	PathIndex = 2
	NavigationMeta.PathGoal = nil
	NavigationMeta.PathNeedsRebuild = false
	PathIssuedIndex = 0
	PathIssuedAt = 0
	PathBestWaypointDistance = math.huge
	RuntimeState.ActivePathGeneration = 0
	NavigationMeta.ActiveWaypointIssueSerial = 0
end

cancelPathRequest = function()
	PathRequestSerial += 1
	PathComputing = false
	disposePath()
end

setNavigationState = function(newState: string)
	if State == newState then
		return
	end
	telemetry("STATE", State .. " -> " .. newState)
	State = newState
	-- MovementController is presently a helper provider, not a second state
	-- authority. Mirror Main's authoritative state for any helper that reads it.
	if MovementController then
		MovementController.State = newState
	end
	local activity = ({
		IDLE = "IDLE", DIRECT = "MOVING TO ENEMY", PATH = "PATHING TO ENEMY",
		COMBAT = "ATTACKING", RECOVERY = "RECOVERING", STEER = "MOVING TO ENEMY",
		RETREAT = "RETREATING", EXPLORE = "EXPLORING", DODGE = "DODGING",
	})[newState] or newState
	RuntimeState.Activity = activity
	local activeHazard = DodgeController:getActiveHazard()
	RuntimeState.ActivityDetail = activeHazard and activeHazard:GetFullName() or ""
end

local function resetProgress(target: Model?, goal: Vector3?)
	ProgressState.Target = target
	ProgressState.GoalAnchor = goal
	BestGoalMetric = math.huge
	BestVerticalDifference = math.huge
	LastMeaningfulProgressAt = os.clock()
	ProgressState.LastCheckAt = 0
	RecoveryGoal = nil
	RecoveryUntil = 0
	NavigationMeta.SteeringTried = false
end

pathRemainingMetric = function(): number
	if not Root or not NavigationGoal then
		return math.huge
	end
	if State ~= NavigationState.PATH or not PathWaypoints or not PathWaypoints[PathIndex] then
		return (NavigationGoal - Root.Position).Magnitude
	end
	local metric = (PathWaypoints[PathIndex].Position - Root.Position).Magnitude
	for index = PathIndex, #PathWaypoints - 1 do
		metric += (PathWaypoints[index + 1].Position - PathWaypoints[index].Position).Magnitude
	end
	metric += (NavigationGoal - PathWaypoints[#PathWaypoints].Position).Magnitude
	return metric
end

local function markMeaningfulProgress()
	LastMeaningfulProgressAt = os.clock()
	BestGoalMetric = pathRemainingMetric()
end

local function updateProgressTracking()
	if not Root or not Target or not NavigationGoal then
		return
	end
	local now = os.clock()
	if ProgressState.Target ~= Target or not ProgressState.GoalAnchor then
		resetProgress(Target, NavigationGoal)
		return
	end
	if now - ProgressState.LastCheckAt < Config.ProgressCheckInterval then
		return
	end
	ProgressState.LastCheckAt = now
	local metric = pathRemainingMetric()
	local enemyRoot = getTargetRoot(Target)
	local vertical = enemyRoot and math.abs(enemyRoot.Position.Y - Root.Position.Y) or math.huge
	local verticalProgress = BestVerticalDifference < math.huge
		and vertical <= BestVerticalDifference - Config.MeaningfulProgressDistance
	if BestVerticalDifference == math.huge then
		BestVerticalDifference = vertical
	elseif verticalProgress then
		BestVerticalDifference = vertical
	end
	if BestGoalMetric == math.huge then
		BestGoalMetric = metric
	elseif metric <= BestGoalMetric - Config.MeaningfulProgressDistance or verticalProgress then
		BestGoalMetric = metric
		LastMeaningfulProgressAt = now
	end
end

local function rayClearance(origin: Vector3, direction: Vector3, target: Model?): number
	local result = workspace:Raycast(
		origin + Vector3.new(0, 2.5, 0),
		direction.Unit * Config.DetourProbeDistance,
		makeRaycastParams(target)
	)
	return result and result.Distance or Config.DetourProbeDistance
end

local function chooseRecoveryDetour(goal: Vector3, retreat: boolean?): Vector3?
	if not Root then
		return nil
	end
	local flatGoal = Vector3.new(goal.X - Root.Position.X, 0, goal.Z - Root.Position.Z)
	if flatGoal.Magnitude <= 0.01 then
		return nil
	end
	local forward = flatGoal.Unit
	local candidates = {}
	local angle = math.atan2(forward.Z, forward.X)
	for index = 0, 11 do
		local heading = angle + index * math.pi / 6
		table.insert(candidates, Vector3.new(math.cos(heading), 0, math.sin(heading)))
	end
	local bestGoal: Vector3? = nil
	local bestScore = -math.huge
	for _, direction in ipairs(candidates) do
		local clearance = rayClearance(Root.Position, direction, Target)
		local candidate = Root.Position + direction * math.max(3, clearance - 1.5)
		local grounded, foundGround = projectToWalkableGround(candidate, Target)
		if
			foundGround
			and directRouteClear(grounded, Target)
			and dodgeRouteClear(grounded)
			and pointIsSafeFromHazards(grounded)
		then
			local goalGain = (goal - Root.Position).Magnitude - (goal - grounded).Magnitude
			local heightGain = math.abs(goal.Y - Root.Position.Y) - math.abs(goal.Y - grounded.Y)
			local score = clearance + goalGain * 2 + heightGain + forward:Dot(direction) * 3
			if score > bestScore and (not retreat or goalGain > 1) then
				bestScore, bestGoal = score, grounded
			end
		end
	end
	return bestGoal
end

local function beginLocalRecovery(goal: Vector3)
	RecoveryGoal = chooseRecoveryDetour(goal)
	RecoveryUntil = os.clock() + Config.DetourDuration
	setNavigationState(NavigationState.RECOVERY)
end

local function issueCurrentWaypoint()
	if State ~= NavigationState.PATH or not Humanoid or not Root or not PathWaypoints then
		return
	end
	local waypoint = PathWaypoints[PathIndex]
	if not waypoint then
		disposePath()
		setNavigationState(NavigationState.IDLE)
		return
	end
	if PathIssuedIndex == PathIndex then
		return
	end
	PathIssuedIndex = PathIndex
	PathIssuedAt = os.clock()
	PathBestWaypointDistance = (waypoint.Position - Root.Position).Magnitude
	RuntimeState.WaypointIssueSerial += 1
	NavigationMeta.ActiveWaypointIssueSerial = RuntimeState.WaypointIssueSerial
	if waypoint.Action == Enum.PathWaypointAction.Jump then
		Humanoid.Jump = true
	end
	commandMovement(Vector3.new(waypoint.Position.X - Root.Position.X, 0, waypoint.Position.Z - Root.Position.Z), NavigationState.PATH)
end

local function requestPath(goal: Vector3): boolean
	if not alive() or not Target or PathComputing then
		return false
	end
	local now = os.clock()
	if now - NavigationMeta.LastPathBuildAt < Config.PathRebuildCooldown then
		return false
	end
	PathRequestSerial += 1
	local requestId = PathRequestSerial
	local expectedTarget = Target
	local expectedCharacter = Character
	local origin = Root.Position
	PathComputing = true
	NavigationMeta.LastPathBuildAt = now
	disposePath()
	task.spawn(function()
		local newPath = PathfindingService:CreatePath({
			AgentRadius = Config.AgentRadius,
			AgentHeight = Config.AgentHeight,
			AgentCanJump = true,
			AgentCanClimb = true,
			WaypointSpacing = Config.WaypointSpacing,
		})
		local ok = pcall(function()
			newPath:ComputeAsync(origin, goal)
		end)
		if requestId ~= PathRequestSerial then
			newPath:Destroy()
			return
		end
		PathComputing = false
		if not Enabled or not Running or not alive() or Target ~= expectedTarget or Character ~= expectedCharacter then
			newPath:Destroy()
			return
		end
		local waypoints = ok and newPath.Status == Enum.PathStatus.Success and newPath:GetWaypoints() or nil
		if not waypoints or #waypoints < 2 then
			newPath:Destroy()
			RecoveryGoal = nil
			RecoveryUntil = 0
			setNavigationState(NavigationState.RECOVERY)
			return
		end
		ActivePath = newPath
		RuntimeState.ActivePathGeneration = requestId
		PathWaypoints = waypoints
		PathIndex = 2
		NavigationMeta.PathGoal = goal
		PathIssuedIndex = 0
		NavigationMeta.PathNeedsRebuild = false
		NavigationMeta.ActiveWaypointIssueSerial = 0
		RuntimeState.PathBlockedConnection = newPath.Blocked:Connect(function(blockedIndex)
			if RuntimeState.ActivePathGeneration == requestId and requestId == PathRequestSerial and blockedIndex >= PathIndex then
				NavigationMeta.PathNeedsRebuild = true
			end
		end)
		setNavigationState(NavigationState.PATH)
		BestGoalMetric = pathRemainingMetric()
		-- The async compute callback publishes state only. The next Heartbeat issues MoveTo.
	end)
	return true
end

local function updatePathNavigation()
	if State ~= NavigationState.PATH or not Root or not PathWaypoints then
		return
	end
	if NavigationMeta.PathNeedsRebuild then
		beginLocalRecovery(NavigationGoal or Root.Position)
		requestPath(NavigationGoal or Root.Position)
		return
	end
	local waypoint = PathWaypoints[PathIndex]
	if not waypoint then
		disposePath()
		setNavigationState(NavigationState.IDLE)
		return
	end
	-- A published path is not monitorable until its current waypoint has been issued.
	-- Returning here guarantees timeout/progress logic never observes PathIssuedAt == 0.
	if PathIssuedIndex ~= PathIndex or PathIssuedAt <= 0 or NavigationMeta.ActiveWaypointIssueSerial <= 0 then
		issueCurrentWaypoint()
		return
	end
	local waypointDistance = (waypoint.Position - Root.Position).Magnitude
	-- MoveToFinished carries no path/waypoint identity. Position is the sole safe
	-- completion authority; a delayed event can therefore never advance this path.
	if waypointDistance <= Config.WaypointReachedDistance then
		local advanced = PathBestWaypointDistance - waypointDistance >= Config.MeaningfulProgressDistance
		PathIndex += 1
		PathIssuedIndex = 0
		PathIssuedAt = 0
		NavigationMeta.ActiveWaypointIssueSerial = 0
		if advanced then
			markMeaningfulProgress()
		end
		issueCurrentWaypoint()
		return
	end
	if waypointDistance <= PathBestWaypointDistance - Config.MeaningfulProgressDistance then
		PathBestWaypointDistance = waypointDistance
		markMeaningfulProgress()
	end
	if PathIssuedIndex == PathIndex and PathIssuedAt > 0 and os.clock() - PathIssuedAt >= Config.WaypointTimeout then
		NavigationMeta.PathNeedsRebuild = true
		return
	end
end

local function updateDirectMovement()
	if State ~= NavigationState.DIRECT or not Humanoid or not Root or not NavigationGoal then
		return
	end
	local direction = Vector3.new(NavigationGoal.X - Root.Position.X, 0, NavigationGoal.Z - Root.Position.Z)
	if direction.Magnitude <= Config.DirectReachedDistance then
		commandMovement(Vector3.zero, false)
	else
		commandMovement(direction.Unit, false)
	end
end

local function updateRecoveryMovement()
	if
		(State ~= NavigationState.RECOVERY and State ~= NavigationState.STEER and State ~= NavigationState.RETREAT)
		or not Humanoid
		or not Root
	then
		return
	end
	if State == NavigationState.RETREAT and Target and validTarget(Target) then
		local enemyRoot = getTargetRoot(Target)
		if enemyRoot then
			local away = Vector3.new(Root.Position.X - enemyRoot.Position.X, 0, Root.Position.Z - enemyRoot.Position.Z)
			local backward = away.Magnitude > 0.1 and away.Unit or Vector3.xAxis
			local function retreatRoute(sideSign: number): (Vector3, boolean)
				local side = Vector3.new(-backward.Z, 0, backward.X) * sideSign
				local direction = (backward + side).Unit
				local point, found = projectToWalkableGround(Root.Position + direction * 7, Target)
				return direction, found
					and math.abs(point.Y - Root.Position.Y) <= Config.DirectVerticalTolerance
					and hasGroundSupport(point, Target)
					and directRouteClear(point, Target)
					and pointIsSafeFromHazards(point)
			end
			local sideSign = RuntimeState.RetreatSide or 1
			local direction, routeClear = retreatRoute(sideSign)
			if not routeClear then
				local alternate, alternateClear = retreatRoute(-sideSign)
				if alternateClear then
					RuntimeState.RetreatSide = -sideSign
					RuntimeState.RetreatSideUntil = os.clock() + 0.75
					direction, routeClear = alternate, true
				end
			end
			commandMovement(routeClear and direction or Vector3.zero, false)
			return
		end
	end
	if State == NavigationState.STEER and RecoveryGoal and os.clock() - LastMeaningfulProgressAt < 1 then
		local heading = Vector3.new(RecoveryGoal.X - Root.Position.X, 0, RecoveryGoal.Z - Root.Position.Z)
		if heading.Magnitude > 0.1 and (heading.Magnitude < 5 or os.clock() >= RecoveryUntil) then
			local extended, found =
				projectToWalkableGround(Root.Position + heading.Unit * Config.DetourProbeDistance, Target)
			if
				found
				and directRouteClear(extended, Target)
				and dodgeRouteClear(extended)
				and pointIsSafeFromHazards(extended)
			then
				RecoveryGoal = extended
				RecoveryUntil = os.clock() + Config.DetourDuration
			end
		end
	end
	if RecoveryGoal and os.clock() < RecoveryUntil then
		local direction = Vector3.new(RecoveryGoal.X - Root.Position.X, 0, RecoveryGoal.Z - Root.Position.Z)
		if direction.Magnitude > Config.WaypointReachedDistance then
			commandMovement(direction.Unit, false)
			return
		end
	end
	commandMovement(Vector3.zero, false)
	if State ~= NavigationState.RETREAT and not PathComputing and NavigationGoal then
		requestPath(NavigationGoal)
	end
end

local function decideNavigation()
	if not alive() or not Target or not NavigationGoal then
		return
	end
	local now = os.clock()
	if State == NavigationState.PATH then
		if NavigationMeta.PathGoal and (NavigationGoal - NavigationMeta.PathGoal).Magnitude >= Config.PathGoalChangeDistance then
			NavigationMeta.PathNeedsRebuild = true
		end
		return
	end
	if
		(State == NavigationState.RECOVERY or State == NavigationState.STEER) and (PathComputing or now < RecoveryUntil)
	then
		return
	end
	if now - NavigationMeta.LastDirectDecisionAt < Config.DirectDecisionInterval then
		return
	end
	NavigationMeta.LastDirectDecisionAt = now
	local progressing = now - LastMeaningfulProgressAt < Config.RecoveryRefreshAt
	-- A moving target route may briefly fail a local probe at an edge. Keep DIRECT
	-- while target progress proves that the current command is still productive.
	if State == NavigationState.DIRECT and progressing then
		return
	end
	local delta = NavigationGoal - Root.Position
	local localGoal = Root.Position
		+ (delta.Magnitude > 0.01 and delta.Unit or Vector3.zero)
			* math.min(delta.Magnitude, Config.DetourProbeDistance)
	local grounded = projectToWalkableGround(localGoal, Target)
	local safeDirect = directRouteClear(grounded, Target) and pointIsSafeFromHazards(grounded)
	if safeDirect and (State ~= NavigationState.DIRECT or progressing) then
		disposePath()
		RecoveryGoal = nil
		setNavigationState(NavigationState.DIRECT)
	else
		if not NavigationMeta.SteeringTried then
			NavigationMeta.SteeringTried = true
			beginLocalRecovery(NavigationGoal)
			setNavigationState(NavigationState.STEER)
		else
			beginLocalRecovery(NavigationGoal)
			requestPath(NavigationGoal)
		end
	end
end

local function resetNavigationForTarget(newTarget: Model?)
	local previousTarget = Target
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
	if previousTarget ~= newTarget then
		print("[TARGET] selected=" .. (newTarget and newTarget:GetFullName() or "nil"))
	end
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
	NavigationMeta.GoalTarget = nil
	NavigationGoal = nil
	RuntimeState.LastGoalRefreshAt = 0
	NavigationMeta.LastDirectDecisionAt = 0
	RecoveryGoal = nil
	RecoveryUntil = 0
	cancelPathRequest()
	NavigationMeta.LastPathBuildAt = -math.huge
	resetProgress(newTarget, nil)
	setNavigationState(NavigationState.IDLE)
	if not newTarget then
		CombatController:restoreRotation()
	end
end

resetRuntimeForNewDungeon = function()
	if RecoveryState.ResetExecuting then
		return
	end
	RecoveryState.ResetExecuting = true
	cancelPathRequest()
	clearDodgeObjective()
	resetNavigationForTarget(nil)
	TargetingController:clear()
	disconnectAll(DungeonConnections)
	table.clear(RuntimeState.EnemyCandidates)
	table.clear(RuntimeState.EnemyFolders)
	table.clear(RuntimeState.DummyCache)
	RuntimeState.ActiveDungeonRoot = nil
	RuntimeState.DungeonIdentity = nil
	RuntimeState.EnemyFolderInstance = nil
	RuntimeState.FightingBossInstance = nil
	RuntimeState.DungeonFinishedInstance = nil
	RuntimeState.DungeonTimeInstance = nil
	RuntimeState.DungeonTimeText = nil
	RuntimeState.DungeonBootstrapped = false
	RuntimeState.DungeonCacheDirty = true
	RuntimeState.LastDungeonReferenceSearchAt = -math.huge
	RuntimeState.LastDungeonStateCheckAt = 0
	RuntimeState.LastFallbackTargetScanAt = -math.huge
	RuntimeState.LastTargetDecisionAt = -math.huge
	RuntimeState.DungeonFinishedLastState = false
	RuntimeState.PreviousDungeonFinishedInstance = nil
	RuntimeState.ReplayDungeonIdentity = nil
	RuntimeState.ReplayCompletionDetected = false
	RuntimeState.ReplayResultScanDirty = true
	setReplayPhase("IDLE")
	setRoundPhase("UNKNOWN")
	stopTranslation()
	RecoveryState.ResetExecuting = false
	task.defer(function()
		if Enabled and DungeonResolver then
			DungeonResolver:refresh()
		end
	end)
end

clearDodgeObjective = function()
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
				ExploreState.NoTargetSince = nil
			elseif invalidTarget then
				resetNavigationForTarget(nil)
				ExploreState.NoTargetSince = now
			end
		end
	end
	if not Target or not Root or not Humanoid then
		ExploreState.NoTargetSince = ExploreState.NoTargetSince or now
		cancelPathRequest()
		NavigationGoal = nil
		RecoveryGoal = nil
		if RuntimeState.ActiveDungeonRoot and now - ExploreState.NoTargetSince >= Config.ExploreStartDelay then
			if not ExploreGoal or now >= ExploreState.CommitUntil then
				local goal, heading = RuntimeState.chooseExploreGoal()
				if goal and heading then
					ExploreGoal = goal
					ExploreState.Heading = heading
					ExploreBestDistance = flatPointDistance(Root.Position, goal)
					LastExploreMeaningfulProgressAt = now
					ExploreState.CommitUntil = now + Config.ExploreCommitTime
				end
			end
			if ExploreGoal then
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
			ExploreState.NoTargetSince = nil
		else
			ExploreState.NoTargetSince = now
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
	ExploreState.NoTargetSince = nil
	if now - TargetingController.LastTargetAcquireAt >= Config.TargetAcquireInterval and State ~= NavigationState.DODGE then
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
			NavigationGoal = nil
			RecoveryGoal = nil
			setNavigationState(NavigationState.COMBAT)
			resetProgress(Target, nil)
			return
		end
		cancelPathRequest()
		RecoveryGoal = nil
		NavigationMeta.SteeringTried = false
		NavigationMeta.GoalTarget = Target
		NavigationGoal = navigationGoalForTarget(enemyRoot, Target)
		setNavigationState(NavigationState.DIRECT)
		return
	end
	if State == NavigationState.RETREAT and distance3D < Config.RetreatExitDistance then
		cancelPathRequest()
		NavigationGoal = nil
		return
	elseif distance3D < Config.RetreatEnterDistance then
		cancelPathRequest()
		NavigationGoal = nil
		if RuntimeState.RetreatSide == nil or now >= (RuntimeState.RetreatSideUntil or 0) then
			RuntimeState.RetreatSide = RuntimeState.RetreatSide or 1
			RuntimeState.RetreatSideUntil = now + 0.75
		end
		setNavigationState(NavigationState.RETREAT)
		return
	end
	if distance3D <= Config.PreferredCombatDistance then
		-- Invalidate an in-flight ComputeAsync as well as any published path. Merely
		-- disposing ActivePath would still allow the old callback to publish PATH.
		if State ~= NavigationState.COMBAT or PathComputing or ActivePath then
			cancelPathRequest()
		end
		NavigationGoal = nil
		setNavigationState(NavigationState.COMBAT)
		resetProgress(Target, nil)
		return
	end
	if State == NavigationState.COMBAT then
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
		NavigationMeta.GoalTarget = Target
		NavigationGoal = RuntimeState.VerticalPathGoal
		if ProgressState.Target ~= Target or ProgressState.GoalAnchor ~= NavigationGoal then
			resetProgress(Target, NavigationGoal)
		end
		if not PathComputing and (State ~= NavigationState.PATH or not PathWaypoints) then
			cancelPathRequest()
			setNavigationState(NavigationState.PATH)
			requestPath(NavigationGoal)
		end
		updateProgressTracking()
		runRecoveryPolicy()
		return
	end
	RuntimeState.VerticalPathTarget = nil
	RuntimeState.VerticalPathGoal = nil
	if NavigationMeta.GoalTarget ~= Target or now - RuntimeState.LastGoalRefreshAt >= Config.GoalRefreshInterval then
		RuntimeState.LastGoalRefreshAt = now
		NavigationMeta.GoalTarget = Target
		local newGoal = navigationGoalForTarget(enemyRoot, Target)
		if not NavigationGoal or (newGoal - NavigationGoal).Magnitude >= Config.DirectGoalChangeDistance then
			NavigationGoal = newGoal
		elseif State == NavigationState.DIRECT then
			NavigationGoal = NavigationGoal:Lerp(newGoal, 0.35)
		end
	end
	if not ProgressState.GoalAnchor then
		resetProgress(Target, NavigationGoal)
	end
	decideNavigation()
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
	CombatController:resetForCharacter()
	restoreMovementSpeed()
	cancelPathRequest()
	Character = character
	Humanoid = newHumanoid
	Root = newRoot
	if Humanoid then
		RuntimeState.DefaultAutoRotate = Humanoid.AutoRotate
		RuntimeState.DefaultWalkSpeed = Humanoid.WalkSpeed
	end
	RecoveryState.RespawnInProgress = false
	RecoveryState.ResetExecuting = false
	ExploreState.NoTargetSince = os.clock()
	clearDodgeObjective()
	resetNavigationForTarget(nil)
	if Running then
		applyMovementSpeed()
		CombatController:disablePlayerControls()
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
		CombatController:disablePlayerControls()
		applyMovementSpeed()
		TargetingController:invalidateDecision()
		ExploreState.NoTargetSince = os.clock()
		resetProgress(nil, nil)
	else
		RuntimeState.RespawnGraceUntil = 0
		clearDodgeObjective()
		resetNavigationForTarget(nil)
		stopTranslation()
		restoreMovementSpeed()
		CombatController:restoreRotation()
		CombatController:enablePlayerControls()
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
	CombatController:restoreRotation()
	CombatController:enablePlayerControls()
	disconnectAll(Connections)
	disconnectAll(CharacterConnections)
	disconnectAll(DungeonConnections)
	cancelPathRequest()
	if RuntimeState.BossDiedConnection then
		disconnect(RuntimeState.BossDiedConnection)
		RuntimeState.BossDiedConnection = nil
	end
	CombatController:clearAimObjects()
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
			LifecycleController:update()
		end, function(message)
			return debug.traceback(tostring(message), 2)
		end)
		if not lifecycleOk then
			warn("[AF ERROR]", lifecycleErr)
		end
		logPerf("lifecycle", lifecycleStartedAt)
		if now - RuntimeState.LastHUDUpdateAt >= 0.2 then
			RuntimeState.LastHUDUpdateAt = now
			ObsidianUI:update()
		end
		if RuntimeState.RoundPhase ~= "ACTIVE" then
			setNavigationState(NavigationState.IDLE)
			stopTranslation()
			CombatController:restoreRotation()
			return
		end
		if not Running or not alive() then
			return
		end
		if RecoveryState.ResetExecuting then
			setNavigationState(NavigationState.IDLE)
			stopTranslation()
			return
		end
		applyMovementSpeed()
		updateGlobalStuckJump()
		if now - RuntimeState.LastTargetDecisionAt >= Config.TargetDecisionInterval then
			RuntimeState.LastTargetDecisionAt = now
			local targetDecisionStartedAt = os.clock()
			updateTargetAndObjective()
			logPerf("targetDecision", targetDecisionStartedAt)
		end
		CombatController:updateTargetFacing()
		local skillTarget, skillRoot, skillDistance = findNearestEnemyInSkillRange()
		if skillTarget and skillRoot then
			local previousTarget = Target
			Target = skillTarget
			CombatController:useCombatSkills(skillRoot, skillDistance)
			Target = previousTarget
		end
		if Config.DodgeEnabled and updateDodgeController() then
			return
		end
		if Target and validTarget(Target) then
			local enemyRoot = getTargetRoot(Target)
			if enemyRoot and Root then
				local distance = (enemyRoot.Position - Root.Position).Magnitude
				CombatController:useNormalAttack(distance)
			end
		end
		if State == NavigationState.DIRECT then
			updateDirectMovement()
		elseif State == NavigationState.PATH then
			updatePathNavigation()
		elseif
			State == NavigationState.RECOVERY
			or State == NavigationState.STEER
			or State == NavigationState.RETREAT
		then
			updateRecoveryMovement()
		elseif State == NavigationState.EXPLORE then
			updateExploreMovement()
		elseif State == NavigationState.COMBAT or State == NavigationState.IDLE then
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
	local ok, err = xpcall(function() ObsidianUI:create() end, debug.traceback)
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
