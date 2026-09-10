-- AUTO-GENERATED FILE.
-- DO NOT EDIT DIRECTLY. Edit source modules/Main.lua and run scripts/build_bundle.py.
local SOURCES = {
    ["Config.lua"] = [[-- Safe defaults only. User/runtime overrides are loaded by Systems.ConfigStore.
return {
	EnemyKeywords = { "enemy", "boss", "mob", "monster", "zombie", "deity", "volcano", "protector" },
	BossKeywords = { "boss", "protector" },
	FarmRange = 700,
	TargetAcquireInterval = 0.25,
	TargetSwitchMargin = 2,
	TargetDecisionInterval = 0.25,
	GoalRefreshInterval = 0.15,
	TargetLockRangeMultiplier = 1.25,
	PreferredCombatDistance = 70,
	RetreatEnterDistance = 60,
	RetreatExitDistance = 70,
	AttackRange = 15,
	NormalSkillRange = 85,
	BossSkillRange = 100,
	RespawnGraceDuration = 6.5,
	KiteDistance = 70,
	KiteHysteresis = 3,
	AttackCooldown = 0.12,
	QCooldownMin = 0.3,
	QCooldownMax = 0.5,
	ECooldown = 0.4,
	SkillQToolName = "Q",
	SkillEToolName = "E",
	UseTool = false,
	TargetWalkSpeed = 23,
	SpeedBoostEnabled = false,
	SpeedValue = 23,
	MovementSpeedMultiplier = 1.3,
	DirectReachedDistance = 0.75,
	DirectVerticalTolerance = 7,
	DirectDecisionInterval = 0.25,
	DirectGoalChangeDistance = 5,
	GroundProbeLift = 6,
	GroundProbeDepth = 140,
	GroundSupportDepth = 24,
	PathRebuildCooldown = 1.5,
	PathGoalChangeDistance = 9,
	WaypointReachedDistance = 3.5,
	WaypointTimeout = 1.25,
	AgentRadius = 2,
	AgentHeight = 5,
	WaypointSpacing = 5,
	MeaningfulProgressDistance = 1.5,
	ProgressCheckInterval = 0.25,
	RecoveryRefreshAt = 3,
	RespawnStuckTime = 30,
	DetourProbeDistance = 13,
	DetourDuration = 1.5,
	DodgeEnabled = true,
	DodgeTriggerPadding = 2.5,
	DodgePreTriggerPadding = 3.5,
	DodgePlayerSafetyMargin = 1.5,
	DodgeLookaheadSeconds = 0.8,
	DodgeExitHysteresis = 0.25,
	DodgeSafePadding = 5,
	DodgeDetectionRadius = 60,
	DodgeRefreshInterval = 0.12,
	DodgeVerticalPadding = 6,
	DodgeCandidateCount = 8,
	ExploreCandidateCount = 12,
	ExploreStepDistance = 28,
	ExploreReachedDistance = 2,
	ExploreCommitTime = 1.25,
	ExploreStartDelay = 0.9,
	ExploreReselectAfter = 3,
	ExploreMaxVerticalStep = 4.5,
	ExploreProbeSamples = 5,
	ExploreHistoryCellSize = 18,
	ExploreHistoryLimit = 20,
	ExploreRespawnStuckTime = 30,
	DescentMinDrop = 0.5,
	DescentFlatTolerance = 1.5,
	DescentRiseReleaseCount = 2,
	DebugTelemetry = false,
	DebugHazards = false,
	AutoReplay = true,
	AutoStart = true,
	WebhookEnabled = true,
	WebhookURL = "",
	WebhookPingEveryone = false,
	WebhookPingLegend = false,
	WebhookPingUltimate = false,
	FarmEnabled = false,
	ShowHUD = true,
	HUDPosition = UDim2.fromScale(0.98, 0.04),
}
]],
    ["Controllers/Combat.lua"] = [[local CombatController = {}
CombatController.__index = CombatController

function CombatController.new(ctx)
	local self = setmetatable({}, CombatController)
	self.Ctx = ctx
	self.State = {
		LastAttack = 0,
		NextQAt = 0,
		NextEAt = 0,
		AimAttachment = nil,
		AimAlignment = nil,
		PlayerControls = nil,
		PlayerControlsDisabled = false,
		PlayerControlsResolvePending = false,
	}
	return self
end

function CombatController:clearAimObjects()
	local state = self.State
	if state.AimAlignment then
		state.AimAlignment:Destroy()
		state.AimAlignment = nil
	end
	if state.AimAttachment then
		state.AimAttachment:Destroy()
		state.AimAttachment = nil
	end
end

function CombatController:ensureAimObjects()
	local ctx, state = self.Ctx, self.State
	local root = ctx.GetRoot()
	if not root or state.AimAlignment then
		return
	end
	state.AimAttachment = Instance.new("Attachment")
	state.AimAttachment.Name = "AutoFarmAimAttachment"
	state.AimAttachment.Parent = root

	state.AimAlignment = Instance.new("AlignOrientation")
	state.AimAlignment.Name = "AutoFarmAim"
	state.AimAlignment.Attachment0 = state.AimAttachment
	state.AimAlignment.Mode = Enum.OrientationAlignmentMode.OneAttachment
	state.AimAlignment.MaxTorque = 100000
	state.AimAlignment.Responsiveness = 35
	state.AimAlignment.RigidityEnabled = false
	state.AimAlignment.Enabled = false
	state.AimAlignment.Parent = root
end

function CombatController:restoreRotation()
	local state = self.State
	if state.AimAlignment then
		state.AimAlignment.Enabled = false
	end
	local humanoid = self.Ctx.GetHumanoid()
	if humanoid then
		humanoid.AutoRotate = self.Ctx.Runtime.DefaultAutoRotate
	end
end

function CombatController:faceTarget(enemyRoot: BasePart)
	local ctx, state = self.Ctx, self.State
	local root = ctx.GetRoot()
	local humanoid = ctx.GetHumanoid()
	if not root or not humanoid then
		return
	end

	local direction = Vector3.new(
		enemyRoot.Position.X - root.Position.X,
		0,
		enemyRoot.Position.Z - root.Position.Z
	)
	if direction.Magnitude <= 0.01 then
		return
	end

	self:ensureAimObjects()
	humanoid.AutoRotate = false
	if state.AimAlignment then
		state.AimAlignment.Enabled = true
		state.AimAlignment.CFrame = CFrame.lookAt(Vector3.zero, direction.Unit)
	end
end

function CombatController:updateTargetFacing()
	local ctx = self.Ctx
	local target = ctx.GetTarget()
	if target and ctx.ValidTarget(target) then
		local enemyRoot = ctx.GetTargetRoot(target)
		if enemyRoot then
			self:faceTarget(enemyRoot)
			return
		end
	end
	self:restoreRotation()
end

function CombatController:sendKey(key: Enum.KeyCode)
	local vim = self.Ctx.VirtualInputManager
	if not vim then
		return
	end
	pcall(function()
		vim:SendKeyEvent(true, key, false, game)
		vim:SendKeyEvent(false, key, false, game)
	end)
end

function CombatController:activateSkill(toolName: string, key: Enum.KeyCode, context: string): boolean
	local ctx = self.Ctx
	local config = ctx.Config
	local character = ctx.GetCharacter()

	if config.UseTool and character then
		local tool = character:FindFirstChild(toolName)
		if tool and tool:IsA("Tool") and tool.Enabled then
			local ok = pcall(function()
				tool:Activate()
			end)
			if ok then
				return true
			end
		end
	end

	local vim = ctx.VirtualInputManager
	if not vim then
		return false
	end

	local ok = pcall(function()
		vim:SendKeyEvent(true, key, false, game)
	end)
	if ok then
		task.delay(0.04, function()
			pcall(function()
				vim:SendKeyEvent(false, key, false, game)
			end)
		end)
		return true
	end

	return false
end

function CombatController:useCombatSkills(enemyRoot: BasePart, distance3D: number)
	local ctx, state = self.Ctx, self.State
	local target = ctx.GetTarget()
	local config = ctx.Config
	local activeSkillRange = target and ctx.SkillRangeForTarget(target) or config.NormalSkillRange
	if not target or not ctx.ValidTarget(target) or distance3D > activeSkillRange then
		return
	end

	local now = os.clock()
	if now >= state.NextQAt then
		local minimum = math.max(0.1, config.QCooldownMin)
		local maximum = math.max(minimum, config.QCooldownMax)
		local context = ctx.IsBossTarget(target) and "BOSS" or "NORMAL"
		if self:activateSkill(config.SkillQToolName, Enum.KeyCode.Q, context) then
			state.NextQAt = now + minimum + math.random() * (maximum - minimum)
		end
	end

	if now >= state.NextEAt then
		local context = ctx.IsBossTarget(target) and "BOSS" or "NORMAL"
		if self:activateSkill(config.SkillEToolName, Enum.KeyCode.E, context) then
			state.NextEAt = now + math.max(0.1, config.ECooldown)
		end
	end
end

function CombatController:useNormalAttack(distance3D: number)
	local ctx, state = self.Ctx, self.State
	local target = ctx.GetTarget()
	if
		ctx.GetNavigationState() == ctx.NavigationState.DODGE
		or not ctx.ValidTarget(target)
		or distance3D > ctx.Config.AttackRange
		or os.clock() - state.LastAttack < ctx.Config.AttackCooldown
	then
		return
	end

	state.LastAttack = os.clock()
	local character = ctx.GetCharacter()
	if not character then
		return
	end

	local fallbackTool: Tool? = nil
	for _, object in ipairs(character:GetChildren()) do
		if object:IsA("Tool") then
			fallbackTool = fallbackTool or object
			if object.Name ~= ctx.Config.SkillQToolName and object.Name ~= ctx.Config.SkillEToolName then
				object:Activate()
				return
			end
		end
	end
	if fallbackTool then
		fallbackTool:Activate()
	end
end

function CombatController:resolvePlayerControls()
	local state = self.State
	if state.PlayerControls then
		return state.PlayerControls
	end

	local player = self.Ctx.Player
	local playerScripts = player:FindFirstChild("PlayerScripts")
	local playerModuleScript = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if not playerModuleScript or not playerModuleScript:IsA("ModuleScript") then
		return nil
	end

	local ok, controls = pcall(function()
		local playerModule = require(playerModuleScript)
		return playerModule:GetControls()
	end)
	if ok and controls then
		state.PlayerControls = controls
		return controls
	end
	return nil
end

function CombatController:disablePlayerControls()
	local state = self.State
	if state.PlayerControlsDisabled then
		return
	end

	local controls = self:resolvePlayerControls()
	if not controls or type(controls.Disable) ~= "function" then
		return
	end

	local ok = pcall(function()
		controls:Disable()
	end)
	if ok then
		state.PlayerControlsDisabled = true
	end
end

function CombatController:enablePlayerControls()
	local state = self.State
	if not state.PlayerControlsDisabled then
		return
	end

	local controls = state.PlayerControls or self:resolvePlayerControls()
	if not controls or type(controls.Enable) ~= "function" then
		state.PlayerControlsDisabled = false
		return
	end

	local ok = pcall(function()
		controls:Enable()
	end)
	if ok then
		state.PlayerControlsDisabled = false
	end
end

function CombatController:resetForCharacter()
	local state = self.State
	self:restoreRotation()
	self:clearAimObjects()
	state.LastAttack = 0
	state.NextQAt = 0
	state.NextEAt = 0
	if state.PlayerControlsDisabled and state.PlayerControls and type(state.PlayerControls.Enable) == "function" then
		pcall(function()
			state.PlayerControls:Enable()
		end)
	end
	state.PlayerControls = nil
	state.PlayerControlsDisabled = false
	state.PlayerControlsResolvePending = false
end

return CombatController
]],
    ["Controllers/Dodge.lua"] = [[local Dodge = {}
Dodge.__index = Dodge

function Dodge.new(context)
	local self = setmetatable({}, Dodge)
	self.Config = context.Config
	self.RuntimeState = context.RuntimeState
	self.NavigationState = context.NavigationState
	self.ActiveSkillModels = context.ActiveSkillModels
	self.getRoot = context.getRoot
	self.getHumanoid = context.getHumanoid
	self.getTarget = context.getTarget
	self.getState = context.getState
	self.setNavigationState = context.setNavigationState
	self.getNavigationGoal = context.getNavigationGoal
	self.getPathWaypoints = context.getPathWaypoints
	self.getPathIndex = context.getPathIndex
	self.getRecoveryGoal = context.getRecoveryGoal
	self.getExploreGoal = context.getExploreGoal
	self.setBestGoalMetric = context.setBestGoalMetric
	self.addProgressPause = context.addProgressPause
	self.alive = context.alive
	self.validTarget = context.validTarget
	self.restoreRotation = context.restoreRotation
	self.commandMovement = context.commandMovement
	self.cancelPathRequest = context.cancelPathRequest
	self.makeRaycastParams = context.makeRaycastParams
	self.projectToWalkableGround = context.projectToWalkableGround
	self.hasGroundSupport = context.hasGroundSupport
	self.rootGroundOffset = context.rootGroundOffset
	self.unregisterSkillModel = context.unregisterSkillModel
	self.telemetry = context.telemetry
	self.pathRemainingMetric = context.pathRemainingMetric

	self.ActiveHazard = nil
	self.DodgeGoal = nil
	self.LastHazardThreatAt = -math.huge
	self.NearbyActiveHazards = {}
	return self
end

function Dodge:getActiveHazard()
	return self.ActiveHazard
end

function Dodge:hazardRadius(part: BasePart): number
	local rightExtent = Vector2.new(part.CFrame.RightVector.X, part.CFrame.RightVector.Z).Magnitude * part.Size.X
	local upExtent = Vector2.new(part.CFrame.UpVector.X, part.CFrame.UpVector.Z).Magnitude * part.Size.Y
	local lookExtent = Vector2.new(part.CFrame.LookVector.X, part.CFrame.LookVector.Z).Magnitude * part.Size.Z
	return math.max(rightExtent, upExtent, lookExtent) * 0.5
end

function Dodge:predictedHazardRadius(part: BasePart): (number, boolean)
	local runtime = self.RuntimeState
	local config = self.Config
	local now = os.clock()
	local currentRadius = self:hazardRadius(part)
	local previous = runtime.HazardHistory[part]
	local growing = false
	local predictedRadius = currentRadius
	if previous then
		local elapsed = now - previous.LastSeenAt
		if elapsed > 0.02 and currentRadius > previous.LastRadius + 0.05 then
			growing = true
			predictedRadius += (currentRadius - previous.LastRadius) / elapsed * config.DodgeLookaheadSeconds
		end
	end
	runtime.HazardHistory[part] = {
		LastRadius = currentRadius,
		LastPosition = part.Position,
		LastSeenAt = now,
	}
	return predictedRadius, growing
end

function Dodge:flatPointDistance(first: Vector3, second: Vector3): number
	return Vector2.new(first.X - second.X, first.Z - second.Z).Magnitude
end

function Dodge:hazardVerticalHalfExtent(part: BasePart): number
	local worldUp = Vector3.yAxis
	return math.abs(part.CFrame.RightVector:Dot(worldUp)) * part.Size.X * 0.5
		+ math.abs(part.CFrame.UpVector:Dot(worldUp)) * part.Size.Y * 0.5
		+ math.abs(part.CFrame.LookVector:Dot(worldUp)) * part.Size.Z * 0.5
end

function Dodge:hazardThreatensHeight(part: BasePart, position: Vector3): boolean
	return math.abs(position.Y - part.Position.Y)
		<= self:hazardVerticalHalfExtent(part) + self.rootGroundOffset() + self.Config.DodgeVerticalPadding
end

function Dodge:playerFootprintRadius(): number
	local root = self.getRoot()
	if not root then
		return self.Config.DodgePlayerSafetyMargin
	end
	return math.max(root.Size.X, root.Size.Z) * 0.5 + self.Config.DodgePlayerSafetyMargin
end

function Dodge:skillPartThreatens(part: BasePart, position: Vector3, padding: number): boolean
	if not part:IsDescendantOf(workspace) or not self:hazardThreatensHeight(part, position) then
		return false
	end
	local localPoint = part.CFrame:PointToObjectSpace(position)
	local halfX = part.Size.X * 0.5 + padding
	local halfZ = part.Size.Z * 0.5 + padding
	return math.abs(localPoint.X) <= halfX and math.abs(localPoint.Z) <= halfZ
end

function Dodge:refreshNearbyActiveHazards()
	local config = self.Config
	local runtime = self.RuntimeState
	local root = self.getRoot()
	if not config.DodgeEnabled then
		table.clear(self.NearbyActiveHazards)
		return
	end
	if not root then
		table.clear(self.NearbyActiveHazards)
		return
	end
	local now = os.clock()
	if now - runtime.LastHazardRefreshAt < config.DodgeRefreshInterval then
		return
	end
	runtime.LastHazardRefreshAt = now
	table.clear(self.NearbyActiveHazards)
	for model, skill in pairs(self.ActiveSkillModels) do
		if not model:IsDescendantOf(workspace) then
			self.unregisterSkillModel(model)
		else
			skill.LastSeenAt = now
			for part in pairs(skill.Hitboxes) do
				if part:IsDescendantOf(workspace) and (part.Position - root.Position).Magnitude <= config.DodgeDetectionRadius + self:hazardRadius(part) then
					self.NearbyActiveHazards[part] = true
				end
			end
			for part in pairs(skill.Precasts) do
				if part:IsDescendantOf(workspace) and (part.Position - root.Position).Magnitude <= config.DodgeDetectionRadius + self:hazardRadius(part) then
					self.NearbyActiveHazards[part] = true
				end
			end
		end
	end
end

function Dodge:pointIsSafeFromHazards(position: Vector3): boolean
	if not self.Config.DodgeEnabled then
		return true
	end
	for part in pairs(self.NearbyActiveHazards) do
		if
			part:IsDescendantOf(workspace)
			and self:skillPartThreatens(part, position, self:playerFootprintRadius() + self.Config.DodgeSafePadding)
		then
			return false
		end
	end
	return true
end

function Dodge:upcomingMovementGoal(): Vector3?
	local root = self.getRoot()
	if not root then
		return nil
	end
	local state = self.getState()
	if state == self.NavigationState.DIRECT then
		return self.getNavigationGoal()
	elseif state == self.NavigationState.PATH and self.getPathWaypoints() then
		local waypoint = self.getPathWaypoints()[self.getPathIndex()]
		return waypoint and waypoint.Position or nil
	elseif state == self.NavigationState.RECOVERY or state == self.NavigationState.STEER or state == self.NavigationState.RETREAT then
		return self.getRecoveryGoal()
	elseif state == self.NavigationState.EXPLORE then
		return self.getExploreGoal()
	elseif state == self.NavigationState.DODGE then
		return self.DodgeGoal
	end
	return root.Position
end

function Dodge:segmentDistanceXZ(point: Vector3, first: Vector3, second: Vector3): number
	local segment = Vector2.new(second.X - first.X, second.Z - first.Z)
	local relative = Vector2.new(point.X - first.X, point.Z - first.Z)
	local denominator = segment:Dot(segment)
	if denominator <= 0.001 then
		return relative.Magnitude
	end
	local alpha = math.clamp(relative:Dot(segment) / denominator, 0, 1)
	return (relative - segment * alpha).Magnitude
end

function Dodge:threateningHazard(): (BasePart?, boolean, number, number)
	local root = self.getRoot()
	if not root then
		return nil, false, math.huge, math.huge
	end
	self:refreshNearbyActiveHazards()
	local nearest: BasePart? = nil
	local nearestEdge = math.huge
	local nearestPredicted = false
	local nearestRouteDistance = math.huge
	local bestThreatScore = math.huge
	local footprint = self:playerFootprintRadius()
	local movementGoal = self:upcomingMovementGoal()
	local predictedEnd = root.Position
	if movementGoal then
		local flat = Vector3.new(movementGoal.X - root.Position.X, 0, movementGoal.Z - root.Position.Z)
		local humanoid = self.getHumanoid()
		local lookahead = math.clamp((humanoid and humanoid.WalkSpeed or 16) * self.Config.DodgeLookaheadSeconds, 8, 36)
		if flat.Magnitude > 0.1 then
			predictedEnd = root.Position + flat.Unit * math.min(flat.Magnitude, lookahead)
		end
	end
	for part in pairs(self.NearbyActiveHazards) do
		if part:IsDescendantOf(workspace) and self:skillPartThreatens(part, root.Position, footprint + self.Config.DodgeSafePadding) then
			local centerDistance = self:flatPointDistance(root.Position, part.Position)
			if centerDistance <= self.Config.DodgeDetectionRadius then
				local predictedRadius, growing = self:predictedHazardRadius(part)
				local effectiveRadius = predictedRadius + footprint + self.Config.DodgeSafePadding
				local edgeDistance = centerDistance - effectiveRadius
				local routeDistance = self:segmentDistanceXZ(part.Position, root.Position, predictedEnd)
				local routeClearance = routeDistance - effectiveRadius
				local predicted = routeClearance <= self.Config.DodgePreTriggerPadding
				local threatScore = math.min(edgeDistance, routeClearance)
				if (edgeDistance <= self.Config.DodgeTriggerPadding or predicted) and threatScore < bestThreatScore then
					bestThreatScore = threatScore
					nearestEdge = edgeDistance
					nearest = part
					nearestPredicted = predicted
					nearestRouteDistance = routeDistance
					self.RuntimeState.CurrentHazardRadius = predictedRadius
					self.RuntimeState.CurrentHazardGrowing = growing
					if growing then
						print(string.format("[DODGE] expanding radius=%.1f", predictedRadius))
					end
				end
			end
		end
	end
	return nearest, nearestPredicted, nearestEdge, nearestRouteDistance
end

function Dodge:dodgeRouteClear(goal: Vector3): boolean
	local config = self.Config
	local root = self.getRoot()
	if not config.DodgeEnabled then
		return true
	end
	if not root then
		return false
	end
	local flatDelta = Vector3.new(goal.X - root.Position.X, 0, goal.Z - root.Position.Z)
	if flatDelta.Magnitude <= 0.1 then
		return true
	end
	local obstacle = workspace:Raycast(root.Position + Vector3.new(0, 2.5, 0), flatDelta, self.makeRaycastParams(nil))
	if obstacle and obstacle.Distance < flatDelta.Magnitude - 1.5 then
		return false
	end
	local previous = root.Position
	for index = 1, math.max(3, math.ceil(flatDelta.Magnitude / 3)) do
		local count = math.max(3, math.ceil(flatDelta.Magnitude / 3))
		local grounded, found = self.projectToWalkableGround(root.Position:Lerp(goal, index / count), self.getTarget())
		if not found or math.abs(grounded.Y - previous.Y) > config.ExploreMaxVerticalStep then
			return false
		end
		for hazard in pairs(self.NearbyActiveHazards) do
			if self:hazardThreatensHeight(hazard, grounded) then
				local startDistance = self:flatPointDistance(root.Position, hazard.Position)
				local radius = self:hazardRadius(hazard) + self:playerFootprintRadius()
				local sampleDistance = self:flatPointDistance(grounded, hazard.Position)
				if sampleDistance < math.min(radius, startDistance) - 0.1 then
					return false
				end
			end
		end
		previous = grounded
	end
	return self.hasGroundSupport(goal, nil)
end

function Dodge:chooseNearestSafeDodgeGoal(hazard: BasePart): Vector3?
	local root = self.getRoot()
	if not root then
		return nil
	end
	local fromCenter = Vector3.new(root.Position.X - hazard.Position.X, 0, root.Position.Z - hazard.Position.Z)
	local baseAngle = fromCenter.Magnitude > 0.1 and math.atan2(fromCenter.Z, fromCenter.X) or 0
	local bestGoal: Vector3? = nil
	local bestDistance = math.huge
	local footprint = self:playerFootprintRadius()
	local safeEdge = self:hazardRadius(hazard) + footprint + self.Config.DodgeSafePadding
	local ringDistances = { safeEdge + 2, safeEdge + 7, safeEdge + 12 }
	for ringIndex, ringDistance in ipairs(ringDistances) do
		for angleIndex = 0, self.Config.DodgeCandidateCount - 1 do
			local angle = baseAngle + angleIndex * math.pi * 2 / self.Config.DodgeCandidateCount
			local candidate = root.Position
				+ Vector3.new(math.cos(angle) * ringDistance, 0, math.sin(angle) * ringDistance)
			local grounded, foundGround = self.projectToWalkableGround(candidate, nil)
			local rejection = if not foundGround
				then "no-ground"
				elseif math.abs(grounded.Y - root.Position.Y) > self.Config.DirectVerticalTolerance then "wrong-floor"
				elseif not self:pointIsSafeFromHazards(grounded) then "hazard-overlap"
				elseif not self:dodgeRouteClear(grounded) then "blocked-or-gap"
				else nil
			if not rejection then
				local distance = self:flatPointDistance(root.Position, grounded)
				if not bestGoal or distance < bestDistance then
					bestDistance = distance
					bestGoal = grounded
				end
			else
				self.telemetry("DODGE_REJECT_" .. tostring(ringIndex) .. "_" .. tostring(angleIndex), rejection)
			end
		end
		if bestGoal then
			return bestGoal
		end
	end
	return bestGoal
end

function Dodge:clearObjective()
	self.ActiveHazard = nil
	self.DodgeGoal = nil
	self.RuntimeState.CurrentHazardRadius = 0
	self.RuntimeState.CurrentHazardGrowing = false
	self.LastHazardThreatAt = -math.huge
	self.RuntimeState.LastDodgeGoalAttemptAt = -math.huge
end

function Dodge:clearNearbyActiveHazards()
	table.clear(self.NearbyActiveHazards)
end

function Dodge:leave()
	local root = self.getRoot()
	self.telemetry("DODGE_EXIT", self.ActiveHazard and ("inactive=" .. self.ActiveHazard:GetFullName()) or "no-active-hazard")
	self.ActiveHazard = nil
	self.DodgeGoal = nil
	local pausedFor = math.max(0, os.clock() - self.RuntimeState.DodgeStartedAt)
	self.addProgressPause(pausedFor)
	self.setBestGoalMetric(self.pathRemainingMetric())
	self.setNavigationState(self.NavigationState.IDLE)
	if not self.getTarget() or not self.validTarget(self.getTarget()) then
		self.restoreRotation()
	end
end

function Dodge:update(): boolean
	local config = self.Config
	local runtime = self.RuntimeState
	local root = self.getRoot()
	local humanoid = self.getHumanoid()
	local state = self.getState()
	if not config.DodgeEnabled then
		if state == self.NavigationState.DODGE then
			self:leave()
		end
		return false
	end

	if not self.alive() or not root or not humanoid then
		return false
	end
	local hazard, predicted, edgeDistance, routeDistance = self:threateningHazard()
	if not hazard then
		if state == self.NavigationState.DODGE then
			if os.clock() - self.LastHazardThreatAt < config.DodgeExitHysteresis then
				if self.DodgeGoal then
					local direction = Vector3.new(self.DodgeGoal.X - root.Position.X, 0, self.DodgeGoal.Z - root.Position.Z)
					self.commandMovement(direction.Magnitude > 1.5 and direction.Unit or Vector3.zero, false)
				else
					self.commandMovement(Vector3.zero, false)
				end
				return true
			end
			self:leave()
		end
		return false
	end
	self.LastHazardThreatAt = os.clock()

	local needsNewGoal = state ~= self.NavigationState.DODGE
		or self.ActiveHazard ~= hazard
		or not self.DodgeGoal
		or not self:pointIsSafeFromHazards(self.DodgeGoal)
	if needsNewGoal then
		if state ~= self.NavigationState.DODGE then
			runtime.DodgeStartedAt = os.clock()
		end
		if state == self.NavigationState.DODGE and os.clock() - runtime.LastDodgeGoalAttemptAt < 0.2 then
			local escape = Vector3.new(root.Position.X - hazard.Position.X, 0, root.Position.Z - hazard.Position.Z)
			self.commandMovement(escape.Magnitude > 0.1 and escape.Unit or Vector3.new(1, 0, 0), false)
			return true
		end
		runtime.LastDodgeGoalAttemptAt = os.clock()
		self.cancelPathRequest()
		self.ActiveHazard = hazard
		self.telemetry(
			"DODGE_ENTER",
			string.format(
				"reason=%s class=%s name=%s parent=%s color=%s transparency=%.2f size=%s verticalDelta=%.1f edge=%.1f route=%.1f",
				predicted and "predicted-route" or "current-edge",
				hazard.ClassName,
				hazard.Name,
				hazard.Parent and hazard.Parent:GetFullName() or "nil",
				tostring(hazard.Color),
				hazard.Transparency,
				tostring(hazard.Size),
				math.abs(root.Position.Y - hazard.Position.Y),
				edgeDistance,
				routeDistance
			)
		)
		self.DodgeGoal = self:chooseNearestSafeDodgeGoal(hazard)
		if not self.DodgeGoal then
			local outward = Vector3.new(root.Position.X - hazard.Position.X, 0, root.Position.Z - hazard.Position.Z)
			if outward.Magnitude <= 0.1 then
				outward = Vector3.new(1, 0, 0)
			end
			local fallback = hazard.Position + outward.Unit * (self:hazardRadius(hazard) + config.DodgeSafePadding + 1)
			fallback = Vector3.new(fallback.X, root.Position.Y, fallback.Z)
			local grounded, foundGround = self.projectToWalkableGround(fallback, nil)
			if
				foundGround
				and math.abs(grounded.Y - root.Position.Y) <= config.DirectVerticalTolerance
				and self:pointIsSafeFromHazards(grounded)
				and self:dodgeRouteClear(grounded)
			then
				self.DodgeGoal = grounded
			end
		end
		self.setNavigationState(self.NavigationState.DODGE)
		self.telemetry("DODGE_GOAL", self.DodgeGoal and tostring(self.DodgeGoal) or "no-safe-goal")
	end

	if not self.DodgeGoal then
		local escape = Vector3.new(root.Position.X - hazard.Position.X, 0, root.Position.Z - hazard.Position.Z)
		if escape.Magnitude <= 0.1 then
			escape = Vector3.new(1, 0, 0)
		end
		local escapeGoal = root.Position + escape.Unit * math.max(10, self:hazardRadius(hazard) + config.DodgeSafePadding)
		local grounded, foundGround = self.projectToWalkableGround(escapeGoal, nil)
		if foundGround and math.abs(grounded.Y - root.Position.Y) <= config.DirectVerticalTolerance and self:dodgeRouteClear(grounded) then
			self.DodgeGoal = grounded
			print("[DODGE] emergency escape")
		else
			local tangent = Vector3.new(-escape.Z, 0, escape.X).Unit
			local tangentGround, tangentFound = self.projectToWalkableGround(root.Position + tangent * math.max(8, self:hazardRadius(hazard)), nil)
			if tangentFound and math.abs(tangentGround.Y - root.Position.Y) <= config.DirectVerticalTolerance and self:dodgeRouteClear(tangentGround) then
				self.DodgeGoal = tangentGround
				print("[DODGE] best-effort tangent escape")
			end
		end
		if not self.DodgeGoal then
			print("[DODGE] no perfect goal, using best-effort")
			self.commandMovement(escape.Unit, false)
			return true
		end
	end
	local direction = Vector3.new(self.DodgeGoal.X - root.Position.X, 0, self.DodgeGoal.Z - root.Position.Z)
	if direction.Magnitude <= 1.5 then
		self.commandMovement(Vector3.zero, false)
	else
		self.commandMovement(direction.Unit, false)
	end
	return true
end

return Dodge
]],
    ["Controllers/Lifecycle.lua"] = [[local Lifecycle = {}
Lifecycle.__index = Lifecycle

function Lifecycle.new(ctx)
	return setmetatable({ Ctx = ctx }, Lifecycle)
end

function Lifecycle:setRoundPhase(phase: string)
	local runtime = self.Ctx.Runtime
	if runtime.RoundPhase ~= phase then
		runtime.RoundPhase = phase
		print("[ROUND] phase=" .. phase)
	end
end

function Lifecycle:update()
	local ctx = self.Ctx
	local runtime = ctx.Runtime
	local now = os.clock()

	if now - runtime.LastDungeonStateCheckAt < 0.25 then
		return
	end
	runtime.LastDungeonStateCheckAt = now
	ctx.RefreshDungeonReferences()

	local remaining = ctx.GetRemainingDungeonTime()

	local function hasActiveRoundEvidence(): boolean
		local root = runtime.ActiveDungeonRoot
		if remaining ~= nil then
			return true
		end
		if runtime.FightingBossInstance and runtime.FightingBossInstance:IsDescendantOf(workspace) then
			return true
		end
		if root and root:IsDescendantOf(workspace) then
			local timer = runtime.DungeonTimeInstance
			if timer and timer:IsDescendantOf(root) then
				return true
			end
			if runtime.EnemyFolderInstance and runtime.EnemyFolderInstance:IsDescendantOf(root) then
				return true
			end
		end

		for model in pairs(ctx.EnemySet) do
			if ctx.IsValidCombatTarget(model) and (not root or model:IsDescendantOf(root)) then
				return true
			end
		end
		for model in pairs(runtime.EnemyCandidates) do
			if ctx.IsValidCombatTarget(model) and (not root or model:IsDescendantOf(root)) then
				return true
			end
		end
		return false
	end

	-- A generic visible "Start" label is not authoritative while a dungeon is
	-- already active. This prevents stale/unrelated GUI from starving resolver,
	-- target acquisition, and replay processing.
	local startMarker = ctx.CachedStartScreen()
	if startMarker and not hasActiveRoundEvidence() then
		ctx.TryStartDungeon()
		return
	end

	local fightingBoss = runtime.FightingBossInstance
	if fightingBoss and fightingBoss:IsA("BoolValue") then
		if fightingBoss.Value then
			runtime.FightingBossSeenThisRound = true
		elseif runtime.LastFightingBossState and runtime.FightingBossSeenThisRound then
			ctx.ArmReplayToken("fightingBoss-ended")
		end
		runtime.LastFightingBossState = fightingBoss.Value
	else
		runtime.LastFightingBossState = false
	end

	local finished = runtime.DungeonFinishedInstance
	-- Result UI discovery walks GUI descendants. Keep the first scan immediate
	-- after a dirty event, then throttle subsequent checks while the round runs.
	local replayActive = runtime.ReplayPhase ~= "IDLE" or runtime.RoundPhase == "RESULT"
	local shouldScanResult = runtime.ReplayResultScanDirty
		or (replayActive and now - runtime.ReplayLastGuiScanAt >= 0.5)
		or (runtime.RoundPhase == "ACTIVE" and now - runtime.ReplayLastGuiScanAt >= 1)
	local resultObject = nil
	if shouldScanResult then
		runtime.ReplayResultScanDirty = false
		runtime.ReplayLastGuiScanAt = now
		resultObject = ctx.FindReplayResult()
	end
	local resultVisible = resultObject ~= nil
	if resultObject then
		runtime.ReplayCompletionRoot = resultObject
	end

	if finished and finished:IsA("BoolValue") then
		local previousFinished = runtime.PreviousDungeonFinishedInstance
		local newRound = runtime.DungeonFinishedLastState
			and (
				not finished.Value
				or (previousFinished ~= nil and previousFinished ~= finished and not finished.Value)
			)

		if finished.Value and not runtime.DungeonFinishedLastState then
			self:setRoundPhase("RESULT")
			runtime.ReplayCompletionDetected = true
			ctx.ArmReplayToken("dungeonFinished")
			if runtime.ReplayPhase == "IDLE" or runtime.ReplayPhase == "ARMED" then
				ctx.SetReplayPhase("RESULT_DETECTED")
			end
		end

		runtime.DungeonFinishedLastState = finished.Value
		runtime.PreviousDungeonFinishedInstance = finished

		if newRound then
			self:setRoundPhase("WAIT_NEW_ROUND")
			ctx.ResetRuntimeForNewDungeon()
			return
		end
	elseif runtime.DungeonFinishedLastState then
		runtime.DungeonFinishedInstance = nil
	end

	if resultVisible then
		self:setRoundPhase("RESULT")
		runtime.ReplayCompletionDetected = true
		ctx.ArmReplayToken("result-ui")
		if runtime.ReplayPhase == "IDLE" or runtime.ReplayPhase == "ARMED" then
			ctx.SetReplayPhase("RESULT_DETECTED")
		end
	end

	if runtime.RoundPhase == "RESULT" then
		ctx.TryReplayDungeon()
		if runtime.ReplayPhase == "WAIT_NEW_ROUND" then
			self:setRoundPhase("WAIT_NEW_ROUND")
		end
		return
	end

	if runtime.RoundPhase == "WAIT_NEW_ROUND" then
		-- Some games reuse the same dungeon root. A confirmed replay transition
		-- plus active evidence is enough; identity change is only a bonus signal.
		if not resultVisible and hasActiveRoundEvidence() then
			ctx.ResetRuntimeForNewDungeon()
		end
		return
	end

	if hasActiveRoundEvidence() then
		self:setRoundPhase("ACTIVE")
	end

	if runtime.RoundPhase == "ACTIVE" and remaining and remaining <= 20 then
		ctx.ArmReplayToken("remaining=" .. tostring(remaining))
	end

	ctx.TryReplayDungeon()
end

return Lifecycle
]],
    ["Controllers/Movement.lua"] = [[local Movement = {}
Movement.__index = Movement

function Movement.new(context)
	local self = setmetatable({}, Movement)
	self.Config = context.Config
	self.RuntimeState = context.RuntimeState
	self.PathfindingService = context.PathfindingService
	self.getCharacter = context.getCharacter
	self.getHumanoid = context.getHumanoid
	self.getRoot = context.getRoot
	self.getTarget = context.getTarget
	self.getEnabled = context.getEnabled
	self.getRunning = context.getRunning
	self.alive = context.alive
	self.getTargetRoot = context.getTargetRoot
	self.getActiveHazard = context.getActiveHazard
	self.validTarget = context.validTarget
	self.recoverByRespawn = context.recoverByRespawn
	self.isRespawnInProgress = context.isRespawnInProgress
	self.refreshNearbyActiveHazards = context.refreshNearbyActiveHazards
	self.dodgeRouteClear = context.dodgeRouteClear
	self.telemetry = context.telemetry
	self.pointIsSafeFromHazards = context.pointIsSafeFromHazards
	self.ActivePath = nil :: Path?
	self.PathWaypoints = nil :: { PathWaypoint }?
	self.PathIndex = 2
	self.PathGoal = nil :: Vector3?
	self.PathComputing = false
	self.PathRequestSerial = 0
	self.LastPathBuildAt = -math.huge
	self.PathNeedsRebuild = false
	self.PathIssuedIndex = 0
	self.PathIssuedAt = 0
	self.PathBestWaypointDistance = math.huge
	self.ActiveWaypointIssueSerial = 0
	self.RecoveryGoal = nil :: Vector3?
	self.RecoveryUntil = 0
	self.SteeringTried = false
	self.ExploreGoal = nil :: Vector3?
	self.ExploreHeading = nil :: Vector3?
	self.ExploreCommitUntil = 0
	self.ExploreBestDistance = math.huge
	self.LastExploreMeaningfulProgressAt = os.clock()
	self.LastExploreSelectionAt = -math.huge
	self.NoTargetSince = nil :: number?
	self.DescentLocked = false
	self.DescentRiseStrikes = 0
	self.ExploredCells = {} :: { [string]: boolean }
	self.ExploredCellOrder = {} :: { string }

	self.NavigationState = context.NavigationState or {
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

	self.State = self.NavigationState.IDLE
	self.NavigationGoal = nil :: Vector3?
	self.GoalTarget = nil :: Model?
	self.LastDirectDecisionAt = 0
	self.ProgressTarget = nil :: Model?
	self.ProgressGoalAnchor = nil :: Vector3?
	self.BestGoalMetric = math.huge
	self.BestVerticalDifference = math.huge
	self.LastMeaningfulProgressAt = os.clock()
	self.LastProgressCheckAt = 0
	return self
end

function Movement:makeRaycastParams(target: Model?): RaycastParams
	local parameters = RaycastParams.new()
	parameters.FilterType = Enum.RaycastFilterType.Exclude
	local exclusions = {}
	local character = self.getCharacter()
	if character then
		table.insert(exclusions, character)
	end
	if target then
		table.insert(exclusions, target)
	end
	parameters.FilterDescendantsInstances = exclusions
	parameters.IgnoreWater = true
	parameters.RespectCanCollide = true
	return parameters
end

function Movement:flatPointDistance(first: Vector3, second: Vector3): number
	return Vector2.new(first.X - second.X, first.Z - second.Z).Magnitude
end

function Movement:rootGroundOffset(): number
	local root = self.getRoot()
	local humanoid = self.getHumanoid()
	if not root or not humanoid then
		return 3
	end
	return math.max(2.5, humanoid.HipHeight + root.Size.Y * 0.5)
end

function Movement:projectToWalkableGround(position: Vector3, target: Model?): (Vector3, boolean)
	local humanoid = self.getHumanoid()
	local origin = position + Vector3.new(0, self.Config.GroundProbeLift, 0)
	local result = workspace:Raycast(origin, Vector3.new(0, -self.Config.GroundProbeDepth, 0), self:makeRaycastParams(target))
	if not result or result.Normal.Y < math.cos(math.rad(humanoid and humanoid.MaxSlopeAngle or 45)) then
		return position, false
	end
	return Vector3.new(position.X, result.Position.Y + self:rootGroundOffset(), position.Z), true
end

function Movement:hasGroundSupport(position: Vector3, target: Model?): boolean
	local origin = position + Vector3.new(0, 7, 0)
	return workspace:Raycast(origin, Vector3.new(0, -self.Config.GroundSupportDepth, 0), self:makeRaycastParams(target)) ~= nil
end

function Movement:directRouteClear(goal: Vector3, target: Model?): boolean
	local root = self.getRoot()
	if not root then
		return false
	end
	local flatDelta = Vector3.new(goal.X - root.Position.X, 0, goal.Z - root.Position.Z)
	if flatDelta.Magnitude <= 0.1 then
		return true
	end
	local obstacle = workspace:Raycast(root.Position + Vector3.new(0, 2.5, 0), flatDelta, self:makeRaycastParams(target))
	if obstacle and obstacle.Distance < flatDelta.Magnitude - 1.5 then
		return false
	end
	local previousGround = root.Position
	for sampleIndex = 1, math.max(2, math.ceil(flatDelta.Magnitude / 6)) do
		local sample = root.Position:Lerp(goal, sampleIndex / math.max(2, math.ceil(flatDelta.Magnitude / 6)))
		local ground, found = self:projectToWalkableGround(sample, target)
		if not found or math.abs(ground.Y - previousGround.Y) > self.Config.ExploreMaxVerticalStep then
			return false
		end
		if not self.pointIsSafeFromHazards(ground) then
			return false
		end
		previousGround = ground
	end
	return self:hasGroundSupport(goal, target)
end

function Movement:navigationGoalForTarget(enemyRoot: BasePart, target: Model): Vector3
	local root = self.getRoot()
	if not root then
		return enemyRoot.Position
	end
	local flat = Vector3.new(enemyRoot.Position.X - root.Position.X, 0, enemyRoot.Position.Z - root.Position.Z)
	local height = math.abs(enemyRoot.Position.Y - root.Position.Y)
	local targetBelow = enemyRoot.Position.Y < root.Position.Y - self.Config.DirectVerticalTolerance
	if targetBelow and (flat.Magnitude <= 15 or height > flat.Magnitude) then
		local targetGround, foundTargetGround = self:projectToWalkableGround(enemyRoot.Position, target)
		if foundTargetGround then
			local chosen: Vector3? = nil
			for _, radius in ipairs({ 6, 12 }) do
				for index = 0, 7 do
					local angle = index * math.pi * 2 / 8
					local sample = enemyRoot.Position
						+ Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
					local candidate, foundCandidate = self:projectToWalkableGround(sample, target)
					if foundCandidate and math.abs(candidate.Y - targetGround.Y) <= self.Config.DirectVerticalTolerance then
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
		local horizontalHold = math.sqrt(math.max(0, self.Config.PreferredCombatDistance ^ 2 - height ^ 2))
		desired = enemyRoot.Position - flat.Unit * horizontalHold
	end
	-- Probe downward close to the target Y, avoiding the wrong upper floor that caused the 15-stud deadlock.
	local targetGround, targetGroundFound = self:projectToWalkableGround(enemyRoot.Position, target)
	local approachGround, approachGroundFound = self:projectToWalkableGround(desired, target)
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

function Movement:upcomingMovementGoal(state, navigationGoal, pathWaypoints, pathIndex, recoveryGoal, exploreGoal): Vector3?
	if state == "PATH" and pathWaypoints and pathWaypoints[pathIndex] then
		return pathWaypoints[pathIndex].Position
	end
	if state == "RECOVERY" or state == "STEER" or state == "RETREAT" then
		return recoveryGoal or navigationGoal
	end
	if state == "EXPLORE" then
		return exploreGoal
	end
	return navigationGoal
end

function Movement:rayClearance(origin: Vector3, direction: Vector3, target: Model?): number
	local result = workspace:Raycast(
		origin + Vector3.new(0, 2.5, 0),
		direction.Unit * self.Config.DetourProbeDistance,
		self:makeRaycastParams(target)
	)
	return result and result.Distance or self.Config.DetourProbeDistance
end

function Movement:chooseRecoveryDetour(goal: Vector3, retreat: boolean?, dodgeRouteClear): Vector3?
	local root = self.getRoot()
	local target = self.getTarget()
	if not root then
		return nil
	end
	local flatGoal = Vector3.new(goal.X - root.Position.X, 0, goal.Z - root.Position.Z)
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
		local clearance = self:rayClearance(root.Position, direction, target)
		local candidate = root.Position + direction * math.max(3, clearance - 1.5)
		local grounded, foundGround = self:projectToWalkableGround(candidate, target)
		if
			foundGround
			and self:directRouteClear(grounded, target)
			and dodgeRouteClear(grounded)
			and self.pointIsSafeFromHazards(grounded)
		then
			local goalGain = (goal - root.Position).Magnitude - (goal - grounded).Magnitude
			local heightGain = math.abs(goal.Y - root.Position.Y) - math.abs(goal.Y - grounded.Y)
			local score = clearance + goalGain * 2 + heightGain + forward:Dot(direction) * 3
			if score > bestScore and (not retreat or goalGain > 1) then
				bestScore, bestGoal = score, grounded
			end
		end
	end
	return bestGoal
end

function Movement:exploreCellKey(position: Vector3): string
	local size = self.Config.ExploreHistoryCellSize
	return string.format(
		"%d:%d:%d",
		math.floor(position.X / size),
		math.floor(position.Y / size),
		math.floor(position.Z / size)
	)
end

function Movement:rememberExplorePosition(position: Vector3)
	local key = self:exploreCellKey(position)
	if self.ExploredCells[key] then
		return
	end
	self.ExploredCells[key] = true
	table.insert(self.ExploredCellOrder, key)
	if #self.ExploredCellOrder > self.Config.ExploreHistoryLimit then
		local oldest = table.remove(self.ExploredCellOrder, 1)
		self.ExploredCells[oldest] = nil
	end
end

function Movement:evaluateExploreDirection(direction: Vector3): (Vector3?, number, string, number)
	local root = self.getRoot()
	if not root then
		return nil, -math.huge, "no-root", 0
	end
	local stepDistance = self.Config.ExploreStepDistance
	local obstacle =
		workspace:Raycast(root.Position + Vector3.new(0, 2.5, 0), direction * stepDistance, self:makeRaycastParams(nil))
	if obstacle and obstacle.Distance < stepDistance - 1.5 then
		return nil, -math.huge, "wall", 0
	end
	local previousGround = root.Position
	local finalGround: Vector3? = nil
	for sampleIndex = 1, self.Config.ExploreProbeSamples do
		local alpha = sampleIndex / self.Config.ExploreProbeSamples
		local sample = root.Position + direction * (stepDistance * alpha)
		local ground, foundGround = self:projectToWalkableGround(sample, nil)
		if not foundGround then
			return nil, -math.huge, "gap", 0
		end
		if math.abs(ground.Y - previousGround.Y) > self.Config.ExploreMaxVerticalStep then
			return nil, -math.huge, ground.Y < previousGround.Y and "unsafe-drop" or "unsafe-rise", 0
		end
		if not self.pointIsSafeFromHazards(ground) then
			return nil, -math.huge, "hazard", 0
		end
		previousGround = ground
		finalGround = ground
	end
	if not finalGround then
		return nil, -math.huge, "no-ground", 0
	end
	local continuity = self.ExploreHeading and math.max(-1, math.min(1, self.ExploreHeading:Dot(direction))) or 0
	local downhillDelta = root.Position.Y - finalGround.Y
	local novelty = self.ExploredCells[self:exploreCellKey(finalGround)] and -14 or 12
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

function Movement:chooseExploreGoal(): (Vector3?, Vector3?, number)
	local root = self.getRoot()
	if not root then
		return nil, nil, 0
	end
	self.refreshNearbyActiveHazards()
	local forward = self.ExploreHeading or Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
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
	for index = 0, self.Config.ExploreCandidateCount - 1 do
		local angle = baseAngle + index * math.pi * 2 / self.Config.ExploreCandidateCount
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local goal, score, reason, downhill = self:evaluateExploreDirection(direction)
		self.telemetry("EXPLORE_CANDIDATE_" .. tostring(index), reason)
		if goal and score > bestScore then
			bestGoal, bestDirection, bestScore, bestDownhill = goal, direction, score, downhill
		end
	end
	if bestGoal then
		self.telemetry("EXPLORE_GOAL", string.format("goal=%s score=%.1f", tostring(bestGoal), bestScore))
	else
		self.telemetry("EXPLORE_GOAL", "no-safe-candidate")
	end
	return bestGoal, bestDirection, bestDownhill
end

function Movement:clearExploreObjective()
	self.ExploreGoal = nil
	self.ExploreCommitUntil = 0
	self.ExploreBestDistance = math.huge
	self.DescentLocked = false
	self.DescentRiseStrikes = 0
end

function Movement:extendDescentGoal(now: number): boolean
	local root = self.getRoot()
	if not self.DescentLocked or not self.ExploreHeading or not root then
		return false
	end
	local goal, _, reason, downhill = self:evaluateExploreDirection(self.ExploreHeading)
	if not goal then
		self.telemetry("DESCENT_RELEASE", reason)
		self.DescentLocked = false
		self.DescentRiseStrikes = 0
		return false
	end
	if downhill < -self.Config.DescentFlatTolerance then
		self.DescentRiseStrikes += 1
		if self.DescentRiseStrikes >= self.Config.DescentRiseReleaseCount then
			self.telemetry("DESCENT_RELEASE", string.format("rising downhill=%.1f", downhill))
			self.DescentLocked = false
			self.DescentRiseStrikes = 0
			return false
		end
	else
		self.DescentRiseStrikes = 0
	end
	self.ExploreGoal = goal
	self.ExploreBestDistance = self:flatPointDistance(root.Position, goal)
	self.ExploreCommitUntil = now + self.Config.ExploreCommitTime
	self.telemetry("DESCENT_EXTEND", string.format("goal=%s downhill=%.1f", tostring(goal), downhill))
	return true
end

function Movement:updateExploreMovement()
	local root = self.getRoot()
	local humanoid = self.getHumanoid()
	if self.State ~= "EXPLORE" or not root or not humanoid or not self.ExploreGoal or self.getTarget() then
		return
	end
	local direction = Vector3.new(self.ExploreGoal.X - root.Position.X, 0, self.ExploreGoal.Z - root.Position.Z)
	local distance = direction.Magnitude
	if distance <= self.Config.ExploreReachedDistance then
		self:commandMovement(Vector3.zero, false)
		return
	end
	if distance <= self.ExploreBestDistance - self.Config.MeaningfulProgressDistance then
		self.ExploreBestDistance = distance
		self.LastExploreMeaningfulProgressAt = os.clock()
	end
	if os.clock() - self.LastExploreMeaningfulProgressAt >= self.Config.ExploreRespawnStuckTime and not self.isRespawnInProgress() then
		self.recoverByRespawn(nil, self.LastExploreMeaningfulProgressAt, true)
		return
	end
	self:commandMovement(direction.Unit, false)
end

function Movement:updateGlobalStuckJump()
	local root = self.getRoot()
	local humanoid = self.getHumanoid()
	if not self.getRunning() or not self.alive() or not root or not humanoid then
		self.RuntimeState.JumpStillSince = os.clock()
		self.RuntimeState.JumpBestDistance = math.huge
		self.RuntimeState.JumpBestVertical = math.huge
		return
	end
	local now = os.clock()
	local translating = self.State == "DIRECT"
		or self.State == "STEER"
		or self.State == "RETREAT"
		or self.State == "PATH"
		or self.State == "RECOVERY"
		or self.State == "EXPLORE"
	if not translating then
		self.RuntimeState.JumpStillSince = now
		self.RuntimeState.JumpBestDistance = math.huge
		self.RuntimeState.JumpBestVertical = math.huge
		return
	end
	local target = self.getTarget()
	local targetRoot = if self.validTarget(target) then self.getTargetRoot(target) else nil
	local followingVerticalPath = self.State == "PATH" and self.RuntimeState.VerticalPathTarget == target
	local objectivePosition = if followingVerticalPath
		then self:upcomingMovementGoal(self.State, self.NavigationGoal, self.PathWaypoints, self.PathIndex, self.RecoveryGoal, self.ExploreGoal)
		else if targetRoot then targetRoot.Position else self:upcomingMovementGoal(self.State, self.NavigationGoal, self.PathWaypoints, self.PathIndex, self.RecoveryGoal, self.ExploreGoal)
	if not objectivePosition then
		self.RuntimeState.JumpStillSince = now
		self.RuntimeState.JumpBestDistance = math.huge
		self.RuntimeState.JumpBestVertical = math.huge
		return
	end
	local delta = objectivePosition - root.Position
	local distance, vertical = delta.Magnitude, math.abs(delta.Y)
	if self.RuntimeState.JumpBestDistance == math.huge then
		self.RuntimeState.JumpBestDistance = distance
		self.RuntimeState.JumpBestVertical = vertical
		self.RuntimeState.JumpStillSince = now
		return
	end
	local progressThreshold = self.Config.MeaningfulProgressDistance
	local progressed = distance <= self.RuntimeState.JumpBestDistance - progressThreshold
		or vertical <= self.RuntimeState.JumpBestVertical - progressThreshold
	if progressed then
		self.RuntimeState.JumpBestDistance = math.min(self.RuntimeState.JumpBestDistance, distance)
		self.RuntimeState.JumpBestVertical = math.min(self.RuntimeState.JumpBestVertical, vertical)
		self.RuntimeState.JumpStillSince = now
	elseif now - self.RuntimeState.JumpStillSince >= 20 and not self.isRespawnInProgress() then
		self.recoverByRespawn(nil, nil, false, self.RuntimeState.JumpStillSince)
	end
end

function Movement:beginLocalRecovery(goal: Vector3)
	self.RecoveryGoal = self:chooseRecoveryDetour(goal, nil, self.dodgeRouteClear)
	self.RecoveryUntil = os.clock() + self.Config.DetourDuration
	self:setNavigationState("RECOVERY")
end

function Movement:updateRecoveryMovement()
	local root = self.getRoot()
	local humanoid = self.getHumanoid()
	local state = self.State
	local target = self.getTarget()
	if
		(state ~= "RECOVERY" and state ~= "STEER" and state ~= "RETREAT")
		or not humanoid
		or not root
	then
		return
	end
	if state == "RETREAT" and target and self.validTarget(target) then
		local enemyRoot = self.getTargetRoot(target)
		if enemyRoot then
			local away = Vector3.new(root.Position.X - enemyRoot.Position.X, 0, root.Position.Z - enemyRoot.Position.Z)
			local backward = away.Magnitude > 0.1 and away.Unit or Vector3.xAxis
			local function retreatRoute(sideSign: number): (Vector3, boolean)
				local side = Vector3.new(-backward.Z, 0, backward.X) * sideSign
				local direction = (backward + side).Unit
				local point, found = self:projectToWalkableGround(root.Position + direction * 7, target)
				return direction, found
					and math.abs(point.Y - root.Position.Y) <= self.Config.DirectVerticalTolerance
					and self:hasGroundSupport(point, target)
					and self:directRouteClear(point, target)
					and self.pointIsSafeFromHazards(point)
			end
			local sideSign = self.RuntimeState.RetreatSide or 1
			local direction, routeClear = retreatRoute(sideSign)
			if not routeClear then
				local alternate, alternateClear = retreatRoute(-sideSign)
				if alternateClear then
					self.RuntimeState.RetreatSide = -sideSign
					self.RuntimeState.RetreatSideUntil = os.clock() + 0.75
					direction, routeClear = alternate, true
				end
			end
			self:commandMovement(routeClear and direction or Vector3.zero, false)
			return
		end
	end
	if state == "STEER" and self.RecoveryGoal and os.clock() - self.LastMeaningfulProgressAt < 1 then
		local heading = Vector3.new(self.RecoveryGoal.X - root.Position.X, 0, self.RecoveryGoal.Z - root.Position.Z)
		if heading.Magnitude > 0.1 and (heading.Magnitude < 5 or os.clock() >= self.RecoveryUntil) then
			local extended, found =
				self:projectToWalkableGround(root.Position + heading.Unit * self.Config.DetourProbeDistance, target)
			if
				found
				and self:directRouteClear(extended, target)
				and self.dodgeRouteClear(extended)
				and self.pointIsSafeFromHazards(extended)
			then
				self.RecoveryGoal = extended
				self.RecoveryUntil = os.clock() + self.Config.DetourDuration
			end
		end
	end
	if self.RecoveryGoal and os.clock() < self.RecoveryUntil then
		local direction = Vector3.new(self.RecoveryGoal.X - root.Position.X, 0, self.RecoveryGoal.Z - root.Position.Z)
		if direction.Magnitude > self.Config.WaypointReachedDistance then
			self:commandMovement(direction.Unit, false)
			return
		end
	end
	self:commandMovement(Vector3.zero, false)
	if state ~= "RETREAT" and not self.PathComputing and self.NavigationGoal then
		self:requestPath(self.NavigationGoal)
	end
end

function Movement:runRecoveryPolicy()
	if
		os.clock() < self.RuntimeState.RespawnGraceUntil
		or not self.getTarget()
		or not self.NavigationGoal
		or self.State == "COMBAT"
	then
		return
	end
	local stuckFor = os.clock() - self.LastMeaningfulProgressAt
	if stuckFor >= self.Config.RespawnStuckTime then
		if not self.isRespawnInProgress() then
			self.recoverByRespawn(self.getTarget(), self.LastMeaningfulProgressAt)
		end
		return
	end
end

function Movement:disposePath()
	if self.RuntimeState.PathBlockedConnection then
		self.RuntimeState.PathBlockedConnection:Disconnect()
		self.RuntimeState.PathBlockedConnection = nil
	end
	if self.ActivePath then
		self.ActivePath:Destroy()
	end
	self.ActivePath = nil
	self.PathWaypoints = nil
	self.PathIndex = 2
	self.PathGoal = nil
	self.PathNeedsRebuild = false
	self.PathIssuedIndex = 0
	self.PathIssuedAt = 0
	self.PathBestWaypointDistance = math.huge
	self.RuntimeState.ActivePathGeneration = 0
	self.ActiveWaypointIssueSerial = 0
end

function Movement:cancelPathRequest()
	self.PathRequestSerial += 1
	self.PathComputing = false
	self:disposePath()
end

function Movement:pathRemainingMetric(navigationGoal: Vector3?): number
	local root = self.getRoot()
	if not root or not navigationGoal then
		return math.huge
	end
	if self.State ~= "PATH" or not self.PathWaypoints or not self.PathWaypoints[self.PathIndex] then
		return (navigationGoal - root.Position).Magnitude
	end
	local metric = (self.PathWaypoints[self.PathIndex].Position - root.Position).Magnitude
	for index = self.PathIndex, #self.PathWaypoints - 1 do
		metric += (self.PathWaypoints[index + 1].Position - self.PathWaypoints[index].Position).Magnitude
	end
	metric += (navigationGoal - self.PathWaypoints[#self.PathWaypoints].Position).Magnitude
	return metric
end

function Movement:issueCurrentWaypoint()
	local humanoid = self.getHumanoid()
	local root = self.getRoot()
	if self.State ~= "PATH" or not humanoid or not root or not self.PathWaypoints then
		return
	end
	local waypoint = self.PathWaypoints[self.PathIndex]
	if not waypoint then
		self:disposePath()
		self:setNavigationState("IDLE")
		return
	end
	if self.PathIssuedIndex == self.PathIndex then
		return
	end
	self.PathIssuedIndex = self.PathIndex
	self.PathIssuedAt = os.clock()
	self.PathBestWaypointDistance = (waypoint.Position - root.Position).Magnitude
	self.RuntimeState.WaypointIssueSerial += 1
	self.ActiveWaypointIssueSerial = self.RuntimeState.WaypointIssueSerial
	if waypoint.Action == Enum.PathWaypointAction.Jump then
		humanoid.Jump = true
	end
	self:commandMovement(Vector3.new(waypoint.Position.X - root.Position.X, 0, waypoint.Position.Z - root.Position.Z), "PATH")
end

function Movement:requestPath(goal: Vector3): boolean
	local root = self.getRoot()
	local target = self.getTarget()
	if not self.alive() or not target or self.PathComputing or not root then
		return false
	end
	local now = os.clock()
	if now - self.LastPathBuildAt < self.Config.PathRebuildCooldown then
		return false
	end
	self.PathRequestSerial += 1
	local requestId = self.PathRequestSerial
	local expectedTarget = target
	local expectedCharacter = self.getCharacter()
	local origin = root.Position
	self.PathComputing = true
	self.LastPathBuildAt = now
	self:disposePath()
	task.spawn(function()
		local newPath = self.PathfindingService:CreatePath({
			AgentRadius = self.Config.AgentRadius,
			AgentHeight = self.Config.AgentHeight,
			AgentCanJump = true,
			AgentCanClimb = true,
			WaypointSpacing = self.Config.WaypointSpacing,
		})
		local ok = pcall(function()
			newPath:ComputeAsync(origin, goal)
		end)
		if requestId ~= self.PathRequestSerial then
			newPath:Destroy()
			return
		end
		self.PathComputing = false
		if
			not self.getEnabled()
			or not self.getRunning()
			or not self.alive()
			or self.getTarget() ~= expectedTarget
			or self.getCharacter() ~= expectedCharacter
		then
			newPath:Destroy()
			return
		end
		local waypoints = ok and newPath.Status == Enum.PathStatus.Success and newPath:GetWaypoints() or nil
		if not waypoints or #waypoints < 2 then
			newPath:Destroy()
			self.RecoveryGoal = nil
			self.RecoveryUntil = 0
			self:setNavigationState("RECOVERY")
			return
		end
		self.ActivePath = newPath
		self.RuntimeState.ActivePathGeneration = requestId
		self.PathWaypoints = waypoints
		self.PathIndex = 2
		self.PathGoal = goal
		self.PathIssuedIndex = 0
		self.PathNeedsRebuild = false
		self.ActiveWaypointIssueSerial = 0
		self.RuntimeState.PathBlockedConnection = newPath.Blocked:Connect(function(blockedIndex)
			if
				self.RuntimeState.ActivePathGeneration == requestId
				and requestId == self.PathRequestSerial
				and blockedIndex >= self.PathIndex
			then
				self.PathNeedsRebuild = true
			end
		end)
		self:setNavigationState("PATH")
		self.LastMeaningfulProgressAt = os.clock()
		self.BestGoalMetric = self:pathRemainingMetric(self.NavigationGoal)
		-- The async compute callback publishes state only. The next Heartbeat issues MoveTo.
	end)
	return true
end

function Movement:updatePathNavigation()
	local root = self.getRoot()
	local navigationGoal = self.NavigationGoal
	if self.State ~= "PATH" or not root or not self.PathWaypoints then
		return
	end
	if self.PathNeedsRebuild then
		self:beginLocalRecovery(navigationGoal or root.Position)
		self:requestPath(navigationGoal or root.Position)
		return
	end
	local waypoint = self.PathWaypoints[self.PathIndex]
	if not waypoint then
		self:disposePath()
		self:setNavigationState("IDLE")
		return
	end
	-- A published path is not monitorable until its current waypoint has been issued.
	-- Returning here guarantees timeout/progress logic never observes PathIssuedAt == 0.
	if self.PathIssuedIndex ~= self.PathIndex or self.PathIssuedAt <= 0 or self.ActiveWaypointIssueSerial <= 0 then
		self:issueCurrentWaypoint()
		return
	end
	local waypointDistance = (waypoint.Position - root.Position).Magnitude
	-- MoveToFinished carries no path/waypoint identity. Position is the sole safe
	-- completion authority; a delayed event can therefore never advance this path.
	if waypointDistance <= self.Config.WaypointReachedDistance then
		local advanced = self.PathBestWaypointDistance - waypointDistance >= self.Config.MeaningfulProgressDistance
		self.PathIndex += 1
		self.PathIssuedIndex = 0
		self.PathIssuedAt = 0
		self.ActiveWaypointIssueSerial = 0
		if advanced then
			self.LastMeaningfulProgressAt = os.clock()
			self.BestGoalMetric = self:pathRemainingMetric(navigationGoal)
		end
		self:issueCurrentWaypoint()
		return
	end
	if waypointDistance <= self.PathBestWaypointDistance - self.Config.MeaningfulProgressDistance then
		self.PathBestWaypointDistance = waypointDistance
		self.LastMeaningfulProgressAt = os.clock()
		self.BestGoalMetric = self:pathRemainingMetric(navigationGoal)
	end
	if self.PathIssuedIndex == self.PathIndex and self.PathIssuedAt > 0 and os.clock() - self.PathIssuedAt >= self.Config.WaypointTimeout then
		self.PathNeedsRebuild = true
		return
	end
end

function Movement:getState(): string
	return self.State
end

function Movement:setNavigationState(newState: string)
	if self.State == newState then
		return
	end
	self.telemetry("STATE", self.State .. " -> " .. newState)
	self.State = newState
	local activity = ({
		IDLE = "IDLE", DIRECT = "MOVING TO ENEMY", PATH = "PATHING TO ENEMY",
		COMBAT = "ATTACKING", RECOVERY = "RECOVERING", STEER = "MOVING TO ENEMY",
		RETREAT = "RETREATING", EXPLORE = "EXPLORING", DODGE = "DODGING",
	})[newState] or newState
	self.RuntimeState.Activity = activity
	local activeHazard = self.getActiveHazard()
	self.RuntimeState.ActivityDetail = activeHazard and activeHazard:GetFullName() or ""
end

function Movement:resetProgress(target: Model?, goal: Vector3?)
	self.ProgressTarget = target
	self.ProgressGoalAnchor = goal
	self.BestGoalMetric = math.huge
	self.BestVerticalDifference = math.huge
	self.LastMeaningfulProgressAt = os.clock()
	self.LastProgressCheckAt = 0
	self.RecoveryGoal = nil
	self.RecoveryUntil = 0
	self.SteeringTried = false
end

function Movement:setBestGoalMetric(value)
	self.LastMeaningfulProgressAt = os.clock()
	self.BestGoalMetric = value
end

function Movement:addProgressPause(pausedFor: number)
	self.LastMeaningfulProgressAt += pausedFor
	self.LastExploreMeaningfulProgressAt += pausedFor
	self.LastDirectDecisionAt = 0
end

function Movement:markMeaningfulProgress()
	self.LastMeaningfulProgressAt = os.clock()
	self.BestGoalMetric = self:pathRemainingMetric(self.NavigationGoal)
end

function Movement:updateProgressTracking()
	local root = self.getRoot()
	local target = self.getTarget()
	if not root or not target or not self.NavigationGoal then
		return
	end
	local now = os.clock()
	if self.ProgressTarget ~= target or not self.ProgressGoalAnchor then
		self:resetProgress(target, self.NavigationGoal)
		return
	end
	if now - self.LastProgressCheckAt < self.Config.ProgressCheckInterval then
		return
	end
	self.LastProgressCheckAt = now
	local metric = self:pathRemainingMetric(self.NavigationGoal)
	local enemyRoot = self.getTargetRoot(target)
	local vertical = enemyRoot and math.abs(enemyRoot.Position.Y - root.Position.Y) or math.huge
	local verticalProgress = self.BestVerticalDifference < math.huge
		and vertical <= self.BestVerticalDifference - self.Config.MeaningfulProgressDistance
	if self.BestVerticalDifference == math.huge then
		self.BestVerticalDifference = vertical
	elseif verticalProgress then
		self.BestVerticalDifference = vertical
	end
	if self.BestGoalMetric == math.huge then
		self.BestGoalMetric = metric
	elseif metric <= self.BestGoalMetric - self.Config.MeaningfulProgressDistance or verticalProgress then
		self.BestGoalMetric = metric
		self.LastMeaningfulProgressAt = now
	end
end

function Movement:updateDirectMovement()
	local root = self.getRoot()
	local humanoid = self.getHumanoid()
	if self.State ~= "DIRECT" or not humanoid or not root or not self.NavigationGoal then
		return
	end
	local direction = Vector3.new(self.NavigationGoal.X - root.Position.X, 0, self.NavigationGoal.Z - root.Position.Z)
	if direction.Magnitude <= self.Config.DirectReachedDistance then
		self:commandMovement(Vector3.zero, false)
	else
		self:commandMovement(direction.Unit, false)
	end
end

function Movement:decideNavigation()
	local root = self.getRoot()
	if not self.alive() or not self.getTarget() or not self.NavigationGoal or not root then
		return
	end
	local now = os.clock()
	if self.State == "PATH" then
		if self.PathGoal and (self.NavigationGoal - self.PathGoal).Magnitude >= self.Config.PathGoalChangeDistance then
			self.PathNeedsRebuild = true
		end
		return
	end
	if
		(self.State == "RECOVERY" or self.State == "STEER") and (self.PathComputing or now < self.RecoveryUntil)
	then
		return
	end
	if now - self.LastDirectDecisionAt < self.Config.DirectDecisionInterval then
		return
	end
	self.LastDirectDecisionAt = now
	local progressing = now - self.LastMeaningfulProgressAt < self.Config.RecoveryRefreshAt
	-- A moving target route may briefly fail a local probe at an edge. Keep DIRECT
	-- while target progress proves that the current command is still productive.
	if self.State == "DIRECT" and progressing then
		return
	end
	local delta = self.NavigationGoal - root.Position
	local localGoal = root.Position
		+ (delta.Magnitude > 0.01 and delta.Unit or Vector3.zero)
			* math.min(delta.Magnitude, self.Config.DetourProbeDistance)
	local grounded = self:projectToWalkableGround(localGoal, self.getTarget())
	local safeDirect = self:directRouteClear(grounded, self.getTarget()) and self.pointIsSafeFromHazards(grounded)
	if safeDirect and (self.State ~= "DIRECT" or progressing) then
		self:disposePath()
		self.RecoveryGoal = nil
		self:setNavigationState("DIRECT")
	else
		if not self.SteeringTried then
			self.SteeringTried = true
			self:beginLocalRecovery(self.NavigationGoal)
			self:setNavigationState("STEER")
		else
			self:beginLocalRecovery(self.NavigationGoal)
			self:requestPath(self.NavigationGoal)
		end
	end
end

function Movement:commandMovement(direction: Vector3, _owner: string?)
	local root = self.getRoot()
	local humanoid = self.getHumanoid()
	if not root or not humanoid then
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude <= 0.001 then
		self:releaseMovement()
		return
	end
	if self.Config.SpeedBoostEnabled then
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(flat.Unit.X * self.Config.SpeedValue, velocity.Y, flat.Unit.Z * self.Config.SpeedValue)
		self.RuntimeState.VelocityOwned = true
	else
		humanoid:Move(flat.Unit, false)
	end
end

function Movement:releaseMovement()
	local root = self.getRoot()
	local humanoid = self.getHumanoid()
	if root and self.RuntimeState.VelocityOwned then
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
		self.RuntimeState.VelocityOwned = false
	elseif humanoid and not self.Config.SpeedBoostEnabled then
		humanoid:Move(Vector3.zero, false)
	end
end

function Movement:stopTranslation()
	self:releaseMovement()
end

return Movement
]],
    ["Controllers/Replay.lua"] = [[local Replay = {}
Replay.__index = Replay

function Replay.new(context)
	local self = setmetatable({}, Replay)
	self.Config = context.Config
	self.RuntimeState = context.RuntimeState
	self.GuiService = context.GuiService
	self.VirtualInputManager = context.VirtualInputManager
	self.guiRoots = context.guiRoots
	self.visibleGui = context.visibleGui
	self.buttonHasText = context.buttonHasText
	self.isRunning = context.isRunning
	self.telemetry = context.telemetry
	return self
end

function Replay:findButton(): GuiButton?
	local runtime = self.RuntimeState
	local context = runtime.ReplayConfirmRoot
	if context and context:IsDescendantOf(game) and self.visibleGui(context) then
		for _, object in ipairs(context:GetDescendants()) do
			if object:IsA("GuiButton") and self.visibleGui(object) and self.buttonHasText(object, "yes") then
				print("[REPLAY] confirm=" .. object:GetFullName())
				return object
			end
		end
	end
	for _, uiRoot in ipairs(self.guiRoots()) do
		for _, object in ipairs(uiRoot:GetDescendants()) do
			if object:IsA("GuiButton") and self.visibleGui(object) and self.buttonHasText(object, "yes") then
				local modal: Instance? = object.Parent
				for _ = 1, 8 do
					if not modal or not modal:IsA("GuiObject") then
						break
					end
					local hasNo = false
					local hasReplayClue = false
					for _, child in ipairs(modal:GetDescendants()) do
						if child:IsA("GuiButton") and self.visibleGui(child) then
							hasNo = hasNo or self.buttonHasText(child, "no") or self.buttonHasText(child, "cancel")
						end
						if (child:IsA("TextLabel") or child:IsA("TextButton")) and self.visibleGui(child) then
							local text = child.Text:lower()
							hasReplayClue = hasReplayClue
								or text:find("replay", 1, true) ~= nil
								or text:find("again", 1, true) ~= nil
								or text:find("retry", 1, true) ~= nil
								or text:find("dungeon", 1, true) ~= nil
						end
					end
					if hasNo and hasReplayClue then
						if runtime.ReplayConfirmRoot ~= modal then
							print("[REPLAY] confirm detected")
						end
						runtime.ReplayConfirmRoot = modal
						runtime.ReplayModal = modal
						return object
					end
					modal = modal.Parent
				end
			end
		end
	end
	return nil
end

function Replay:clickButton(button: GuiButton): boolean
	if not self.VirtualInputManager then
		return false
	end
	local position = button.AbsolutePosition + button.AbsoluteSize * 0.5
	local inset = select(1, self.GuiService:GetGuiInset())
	local screenGui = button:FindFirstAncestorOfClass("ScreenGui")
	if not screenGui or not screenGui.IgnoreGuiInset then
		position += inset
	end
	local issued = pcall(function()
		self.VirtualInputManager:SendMouseMoveEvent(position.X, position.Y, game)
		self.VirtualInputManager:SendMouseButtonEvent(position.X, position.Y, 0, true, game, 0)
		task.delay(0.04, function()
			self.VirtualInputManager:SendMouseButtonEvent(position.X, position.Y, 0, false, game, 0)
		end)
	end)
	return issued
end

function Replay:setPhase(phase: string)
	local runtime = self.RuntimeState
	if runtime.ReplayPhase ~= phase then
		runtime.ReplayPhase = phase
		runtime.ReplayPhaseEnteredAt = os.clock()
		print("[REPLAY] phase=" .. phase)
	end
end

function Replay:findResult(): GuiObject?
	local runtime = self.RuntimeState
	for _, uiRoot in ipairs(self.guiRoots()) do
		for _, object in ipairs(uiRoot:GetDescendants()) do
			if (object:IsA("TextLabel") or object:IsA("TextButton")) and self.visibleGui(object) then
				local normalized = object.Text:lower():gsub("[%s%p_]", "")
				if normalized:find("dungeoncompleted", 1, true) or normalized:find("dungeonfailed", 1, true) then
					local kind = normalized:find("dungeonfailed", 1, true) and "FAILED" or "COMPLETED"
					if runtime.ReplayResultKind ~= kind then
						runtime.ReplayResultKind = kind
						print("[REPLAY] result=" .. kind)
					end
					return object:FindFirstAncestorWhichIsA("GuiObject") or object
				end
			end
		end
	end
	return nil
end

function Replay:findOpener(): GuiButton?
	local runtime = self.RuntimeState
	local context = runtime.ReplayCompletionRoot
	if context and context:IsDescendantOf(game) and self.visibleGui(context) then
		for _, object in ipairs(context:GetDescendants()) do
			if object:IsA("GuiButton") and self.visibleGui(object)
				and (self.buttonHasText(object, "replay") or self.buttonHasText(object, "retry") or self.buttonHasText(object, "play again")) then
				print("[REPLAY] opener=" .. object:GetFullName())
				return object
			end
		end
	end
	for _, uiRoot in ipairs(self.guiRoots()) do
		for _, object in ipairs(uiRoot:GetDescendants()) do
			if (object:IsA("TextLabel") or object:IsA("TextButton")) and self.visibleGui(object) then
				local normalized = object.Text:lower():gsub("[%s%p_]", "")
				if normalized == "replay" or normalized == "replaydungeon" or normalized == "playagain" or normalized == "retry" then
					local current: Instance? = object
					for _ = 1, 8 do
						if not current then break end
						if current:IsA("GuiButton") and self.visibleGui(current) then return current end
						current = current.Parent
					end
				end
			end
		end
	end
	return nil
end

function Replay:requestManualReplay(): boolean
	local runtime = self.RuntimeState
	if runtime.ManualReplayRequested or runtime.ReplayPhase ~= "IDLE" then
		print("[REPLAY] manual=ignored")
		return false
	end
	local result = self:findResult()
	if not result then
		print("[REPLAY] manual=blocked-no-result")
		return false
	end
	runtime.ManualReplayRequested = true
	runtime.ReplayRetries = 0
	runtime.ReplayCompletionRoot = result
	runtime.ReplayCompletionDetected = true
	runtime.ReplayOpener = nil
	runtime.ReplayYesButton = nil
	runtime.ReplayConfirmRoot = nil
	runtime.ReplayResultScanDirty = false
	self:setPhase("RESULT_DETECTED")
	print("[REPLAY] manual=requested")
	return true
end

function Replay:tryReplayDungeon()
	local runtime = self.RuntimeState
	local now = os.clock()
	local automatic = self.isRunning() and self.Config.AutoReplay
	if not automatic and not runtime.ManualReplayRequested then return end
	local phase = runtime.ReplayPhase
	local phaseAge = now - runtime.ReplayPhaseEnteredAt
	if runtime.ReplayResultScanDirty or (phase ~= "IDLE" and now - runtime.ReplayLastGuiScanAt >= 0.5) then
		runtime.ReplayResultScanDirty = false
		runtime.ReplayLastGuiScanAt = now
		local result = self:findResult()
		if result then
			runtime.ReplayCompletionRoot = result
			runtime.ReplayCompletionDetected = true
			if phase == "IDLE" or phase == "ARMED" then
				self:setPhase("RESULT_DETECTED")
			end
			phase = runtime.ReplayPhase
		end
	end
	if runtime.ReplayRetries > 5 then
		-- Input issuance is not UI evidence. Keep the result armed and discard
		-- stale references instead of silently stranding AutoReplay in IDLE.
		runtime.ReplayRetries = 0
		runtime.ReplayOpener = nil
		runtime.ReplayYesButton = nil
		runtime.ReplayConfirmRoot = nil
		runtime.ReplayResultScanDirty = true
		local wasManual = runtime.ManualReplayRequested
		runtime.ManualReplayRequested = false
		self:setPhase(wasManual and "IDLE" or "RESULT_DETECTED")
		return
	end
	if phase == "IDLE" then
		return
	end
	if phase == "WAIT_NEW_ROUND" then return end
	if phase == "ARMED" and runtime.ReplayCompletionDetected then self:setPhase("RESULT_DETECTED"); phase = runtime.ReplayPhase end
	if phase == "RESULT_DETECTED" or phase == "ARMED" then
		local opener = runtime.ReplayOpener
		if not opener or not opener:IsDescendantOf(game) or not self.visibleGui(opener) then opener = self:findOpener(); runtime.ReplayOpener = opener end
		if opener and now - runtime.ReplayLastActionAt >= 0.75 then
			print("[REPLAY] click opener")
			local issued = self:clickButton(opener)
			print("[REPLAY] click-issued=" .. (issued and "YES" or "NO"))
			runtime.ReplayLastActionAt = now
			runtime.ReplayRetries += 1
			self:setPhase("OPENING")
			return
		end
		if phaseAge > 8 then
			runtime.ManualReplayRequested = false
			self:setPhase("IDLE")
		end
		return
	end
	if phase == "CONFIRMING" then
		local awaiting = runtime.ReplayAwaitingClose
		if awaiting and (not awaiting:IsDescendantOf(game) or not self.visibleGui(awaiting)) then
			runtime.ReplayAwaitingClose = nil
			runtime.ReplayDungeonIdentity = runtime.DungeonIdentity
			runtime.ManualReplayRequested = false
			print("[REPLAY] confirmation closed; waiting new round")
			self:setPhase("WAIT_NEW_ROUND")
			return
		end
		if phaseAge > 8 then
			runtime.ReplayYesButton = nil
			runtime.ReplayConfirmRoot = nil
			local wasManual = runtime.ManualReplayRequested
			runtime.ManualReplayRequested = false
			self:setPhase(wasManual and "IDLE" or "RESULT_DETECTED")
		end
		return
	end
	local yes = runtime.ReplayYesButton
	if not yes or not yes:IsDescendantOf(game) or not self.visibleGui(yes) then yes = self:findButton(); runtime.ReplayYesButton = yes end
	if yes and now - runtime.ReplayLastActionAt >= 0.75 then
		print("[REPLAY] click yes")
		local issued = self:clickButton(yes)
		print("[REPLAY] click-issued=" .. (issued and "YES" or "NO"))
		runtime.ReplayAwaitingClose = yes
		runtime.ReplayLastActionAt = now
		runtime.ReplayRetries += 1
		self:setPhase("CONFIRMING")
		return
	end
	if phase == "OPENING" and phaseAge > 8 then
		local wasManual = runtime.ManualReplayRequested
		runtime.ManualReplayRequested = false
		self:setPhase(wasManual and "IDLE" or "RESULT_DETECTED")
	end
end

function Replay:arm(reason: string)
	local runtime = self.RuntimeState
	if self.Config.AutoReplay and runtime.ReplayPhase == "IDLE" then
		runtime.ReplayArmedAt = os.clock()
		runtime.ReplayRetries = 0
		runtime.ReplayCompletionRoot = nil
		runtime.ReplayOpener = nil
		runtime.ReplayConfirmRoot = nil
		runtime.ReplayYesButton = nil
		runtime.ReplayResultScanDirty = true
		runtime.ReplayCompletionDetected = false
		self:setPhase("ARMED")
		print("[REPLAY] ARMED reason=" .. reason)
		self.telemetry("REPLAY_ARM", reason)
		runtime.sendStatusWebhook("REPLAY_ARMED")
	end
end

return Replay
]],
    ["Controllers/Targeting.lua"] = [[local Targeting = {}
Targeting.__index = Targeting

function Targeting.new(context)
	local self = setmetatable({}, Targeting)
	self.Config = context.Config
	self.RuntimeState = context.RuntimeState
	self.Players = context.Players
	self.getCharacter = context.getCharacter
	self.getRoot = context.getRoot
	self.getTargetRoot = context.getTargetRoot
	self.isEnemy = context.isEnemy
	self.isInsideAnyEnemyFolder = context.isInsideAnyEnemyFolder
	self.isBossTarget = context.isBossTarget
	self.skillRangeForTarget = context.skillRangeForTarget
	self.telemetry = context.telemetry
	self.logPerf = context.logPerf
	self.EnemySet = {}
	self.PendingEnemyModels = {}
	self.LastTargetAcquireAt = -math.huge
	return self
end

function Targeting:invalidateDecision()
	self.LastTargetAcquireAt = -math.huge
end

function Targeting:clear()
	table.clear(self.EnemySet)
	table.clear(self.PendingEnemyModels)
	self.LastTargetAcquireAt = -math.huge
end

function Targeting:remove(model: Model)
	self.EnemySet[model] = nil
end

function Targeting:isDummyTarget(model: Model): boolean
	local runtime = self.RuntimeState
	local cached = runtime.DummyCache[model]
	if cached ~= nil then
		return cached
	end
	local dummy = false
	local current: Instance? = model
	while current and current ~= workspace do
		if current.Name:lower():gsub("[%s%p_]", ""):find("dummy", 1, true) then
			dummy = true
			break
		end
		current = current.Parent
	end
	runtime.DummyCache[model] = dummy
	return dummy
end

function Targeting:isValidCombatTarget(model: Model?): boolean
	local root = self.getRoot()
	local character = self.getCharacter()
	if not model or not root or not model:IsDescendantOf(workspace) or model == character or self.Players:GetPlayerFromCharacter(model) then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local targetRoot = self.getTargetRoot(model)
	if not humanoid or humanoid.Health <= 0 or not targetRoot or (targetRoot.Position - root.Position).Magnitude > self.Config.FarmRange * self.Config.TargetLockRangeMultiplier then
		return false
	end
	if self:isDummyTarget(model) then
		self.telemetry("TARGET_REJECT", "reject=" .. model:GetFullName() .. " reason=DUMMY")
		return false
	end
	local activeRoot = self.RuntimeState.ActiveDungeonRoot
	local activeStructure = activeRoot and activeRoot:IsDescendantOf(workspace) and model:IsDescendantOf(activeRoot)
	return self.isInsideAnyEnemyFolder(model) or self.isEnemy(model) or activeStructure == true
end

function Targeting:validTarget(target: Model?): boolean
	return self:isValidCombatTarget(target)
end

function Targeting:registerEnemy(instance: Instance, running: boolean)
	local character = self.getCharacter()
	if not instance:IsA("Model") or instance == character or self.Players:GetPlayerFromCharacter(instance) then
		return
	end
	local startedAt = os.clock()
	local humanoid = instance:FindFirstChildOfClass("Humanoid")
	local root = self.getTargetRoot(instance)
	if not humanoid or humanoid.Health <= 0 or not root then
		-- Models commonly replicate before their Humanoid/root. Keep the model
		-- pending so the dungeon-level DescendantAdded retry can promote it
		-- immediately, rather than waiting for the fallback scan.
		self.PendingEnemyModels[instance] = true
		self.RuntimeState.EnemyCandidates[instance] = true
		return
	end
	self.PendingEnemyModels[instance] = nil
	self.RuntimeState.EnemyCandidates[instance] = true
	if self.getRoot() and self:isValidCombatTarget(instance) then
		local wasKnown = self.EnemySet[instance] == true
		self.EnemySet[instance] = true
		if running and not wasKnown then
			self:invalidateDecision()
		end
	end
	self.logPerf("registerEnemy", startedAt)
end

function Targeting:retryFromDescendant(instance: Instance, running: boolean)
	local model = if instance:IsA("Model") then instance else instance:FindFirstAncestorOfClass("Model")
	if model then
		self:registerEnemy(model, running)
	end
end

function Targeting:acquireBestTarget(): Model?
	local root = self.getRoot()
	if not root then
		return nil
	end
	local cheapCandidates = {}
	for model in pairs(self.EnemySet) do
		if not self:isValidCombatTarget(model) then
			self.EnemySet[model] = nil
		else
			local enemyHumanoid = model:FindFirstChildOfClass("Humanoid")
			local enemyRoot = self.getTargetRoot(model)
			if enemyHumanoid and enemyRoot and enemyHumanoid.Health > 0 then
				local delta = enemyRoot.Position - root.Position
				if delta.Magnitude <= self.Config.FarmRange then
					table.insert(cheapCandidates, {
						Model = model,
						Vertical = math.abs(delta.Y),
						Distance = delta.Magnitude,
					})
				end
			end
		end
	end
	if #cheapCandidates == 0 and os.clock() - self.RuntimeState.LastFallbackTargetScanAt >= 2 then
		local fallbackStartedAt = os.clock()
		self.RuntimeState.LastFallbackTargetScanAt = fallbackStartedAt
		self.RuntimeState.refreshDungeonReferences()
		local fallbackRoot = self.RuntimeState.ActiveDungeonRoot
		if fallbackRoot and fallbackRoot:IsDescendantOf(workspace) then
			for _, object in ipairs(fallbackRoot:GetDescendants()) do
				if object:IsA("Model") and self:isValidCombatTarget(object) then
					local enemyRoot = self.getTargetRoot(object)
					if enemyRoot then
						local delta = enemyRoot.Position - root.Position
						if delta.Magnitude <= self.Config.FarmRange then
							table.insert(cheapCandidates, { Model = object, Vertical = math.abs(delta.Y), Distance = delta.Magnitude })
						end
					end
				end
			end
		end
		self.logPerf("targetFallback", fallbackStartedAt)
	end
	table.sort(cheapCandidates, function(first, second)
		return first.Distance < second.Distance
	end)
	local best = cheapCandidates[1]
	local candidateCount = #cheapCandidates
	if self.RuntimeState.DebugTargetCandidateCount ~= candidateCount then
		self.RuntimeState.DebugTargetCandidateCount = candidateCount
		print("[TARGET] candidates=" .. tostring(candidateCount))
	end
	if not best then
		return nil
	end
	return best.Model
end

function Targeting:targetMetrics(target: Model?): (number, number)
	local root = self.getRoot()
	if not target or not root then
		return math.huge, math.huge
	end
	local enemyRoot = self.getTargetRoot(target)
	if not enemyRoot then
		return math.huge, math.huge
	end
	local delta = enemyRoot.Position - root.Position
	return math.abs(delta.Y), delta.Magnitude
end

function Targeting:findNearestEnemyInSkillRange(): (Model?, BasePart?, number)
	local root = self.getRoot()
	if not root then return nil, nil, math.huge end
	local best: Model? = nil
	local bestRoot: BasePart? = nil
	local bestDistance = math.huge
	for model in pairs(self.EnemySet) do
		if self:isValidCombatTarget(model) then
			local enemyRoot = self.getTargetRoot(model)
			if enemyRoot then
				local distance = (enemyRoot.Position - root.Position).Magnitude
				if distance <= self.skillRangeForTarget(model) and distance < bestDistance then
					best, bestRoot, bestDistance = model, enemyRoot, distance
				end
			end
		end
	end
	return best, bestRoot, bestDistance
end

return Targeting
]],
    ["Main.lua"] = [[-- Delta Executor version. Paste the complete file into Delta.
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
local cachedStartScreen
local tryStartDungeon

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
	getEnabled = function() return Enabled end,
	getRunning = function() return Running end,
	alive = alive,
	getTargetRoot = getTargetRoot,
	getActiveHazard = function()
		return DodgeController and DodgeController:getActiveHazard() or nil
	end,
	validTarget = validTarget,
	recoverByRespawn = function(...)
		return recoverByRespawn(...)
	end,
	isRespawnInProgress = function()
		return RecoveryState.RespawnInProgress
	end,
	refreshNearbyActiveHazards = function()
		return DodgeController:refreshNearbyActiveHazards()
	end,
	dodgeRouteClear = function(goal)
		return DodgeController:dodgeRouteClear(goal)
	end,
	telemetry = telemetry,
	-- DodgeController is created after MovementController. Keep this as a late
	-- binding so normal route checks use the real hazard helper once gameplay starts.
	pointIsSafeFromHazards = function(position)
		return DodgeController:pointIsSafeFromHazards(position)
	end,
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

pointIsSafeFromHazards = function(position: Vector3): boolean
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
	CachedStartScreen = function()
		return cachedStartScreen()
	end,
	TryStartDungeon = function()
		return tryStartDungeon()
	end,
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
	RequestManualReplay = function()
		return ReplayController:requestManualReplay()
	end,
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

cachedStartScreen = function(): (GuiObject?, GuiButton?)
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

tryStartDungeon = function(): boolean
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

recoverByRespawn = function(
	expectedTarget: Model?,
	expectedProgressAt: number?,
	exploreRecovery: boolean?,
	globalStuckAt: number?
)
	if RecoveryState.RespawnInProgress then
		return
	end
	RecoveryState.RespawnInProgress = true
	task.spawn(function()
		task.wait(0.4)
		if not Enabled or not Running then
			RecoveryState.RespawnInProgress = false
			return
		end
		if expectedTarget then
			if
				State == NavigationState.DODGE
				or Target ~= expectedTarget
				or LastMeaningfulProgressAt ~= expectedProgressAt
				or os.clock() - LastMeaningfulProgressAt < Config.RespawnStuckTime
			then
				RecoveryState.RespawnInProgress = false
				return
			end
		elseif exploreRecovery then
			if State == NavigationState.DODGE or Target or LastExploreMeaningfulProgressAt ~= expectedProgressAt then
				RecoveryState.RespawnInProgress = false
				return
			end
		elseif globalStuckAt then
			if RuntimeState.JumpStillSince ~= globalStuckAt then
				RecoveryState.RespawnInProgress = false
				return
			end
		elseif alive() then
			RecoveryState.RespawnInProgress = false
			return
		end
		RecoveryState.ResetExecuting = true
		resetNavigationForTarget(nil)
		local resetCharacter = Character
		for _, key in ipairs({ Enum.KeyCode.Escape, Enum.KeyCode.R, Enum.KeyCode.Return, Enum.KeyCode.Return }) do
			if not Enabled or not Running or Character ~= resetCharacter or State == NavigationState.DODGE then
				break
			end
			sendKey(key)
			task.wait(0.5)
		end
		task.wait(3)
		RecoveryState.ResetExecuting = false
		RecoveryState.RespawnInProgress = false
	end)
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
]],
    ["Runtime.lua"] = [[-- Shared in-memory runtime state. Persistence belongs exclusively to Systems.ConfigStore.

local Runtime = {}

function Runtime.create(skillFX)
local state = {
	JumpStillSince = os.clock(),
	JumpBestDistance = math.huge,
	JumpBestVertical = math.huge,
	JumpBurstUntil = 0,
	JumpBurstTaskRunning = false,
	JumpBurstGeneration = 0,
	ReplayAwaitingClose = nil :: GuiButton?,
	ReplayPhase = "IDLE",
	ReplayPhaseEnteredAt = 0,
	ReplayRetries = 0,
	ManualReplayRequested = false,
	ReplayResultScanDirty = true,
	ReplayArmedAt = 0,
	ReplayLastActionAt = -math.huge,
	ReplayModal = nil :: GuiObject?,
	ReplayCompletionRoot = nil :: GuiObject?,
	ReplayOpener = nil :: GuiButton?,
	ReplayConfirmRoot = nil :: GuiObject?,
	ReplayLastGuiScanAt = -math.huge,
	ReplayOpenerMissingReported = false,
	ReplayCompletionDetected = false,
	ReplayDungeonIdentity = nil :: Instance?,
	BossDiedConnection = nil :: RBXScriptConnection?,
	BossDiedTarget = nil :: Model?,
	StartDebugMarker = nil :: GuiObject?,
	StartDebugButton = nil :: GuiButton?,
	StartMarker = nil :: GuiObject?,
	StartButton = nil :: GuiButton?,
	LastStartMarkerScanAt = -math.huge,
	DungeonFinishedLastState = false,
	ActiveDungeonRoot = nil :: Instance?,
	DungeonIdentity = nil :: Instance?,
	EnemyFolders = {} :: { [Instance]: boolean },
	EnemyCandidates = {} :: { [Model]: boolean },
	DungeonFinishedInstance = nil :: BoolValue?,
	PreviousDungeonFinishedInstance = nil :: BoolValue?,
	FightingBossInstance = nil :: BoolValue?,
	LastFightingBossState = false,
	FightingBossSeenThisRound = false,
	EnemyFolderInstance = nil :: Instance?,
	DungeonTimeInstance = nil :: ValueBase?,
	DungeonTimeText = nil :: GuiObject?,
	LastDungeonReferenceSearchAt = -math.huge,
	LastDungeonStateCheckAt = 0,
	LastFallbackTargetScanAt = -math.huge,
	LastHUDUpdateAt = -math.huge,
	LastStatsSampleAt = -math.huge,
	PingMs = 0,
	SmoothedFPS = 0,
	WebhookLastByEvent = {} :: { [string]: number },
	ObsidianLibrary = nil,
	ObsidianWindow = nil,
	ObsidianLabels = {} :: { [string]: any },
	ReplayResultKind = nil :: string?,
	Activity = "IDLE",
	ActivityDetail = "",
	ActiveSkillModels = skillFX.Models,
	ActiveSkillHitboxes = skillFX.Hitboxes,
	ReplayYesButton = nil :: GuiButton?,
	ReplayDebugButton = nil :: GuiButton?,
	RoundResetSerial = 0,
	RespawnGraceUntil = 0,
	VerticalPathTarget = nil :: Model?,
	VerticalPathGoal = nil :: Vector3?,
	LastSkillContextSignature = "",
	RoundPhase = "UNKNOWN",
	DungeonCacheDirty = true,
	DungeonRebuildScheduled = false,
	DungeonBootstrapped = false,
	LastTargetDecisionAt = -math.huge,
	DummyCache = {} :: { [Model]: boolean },
	HazardHistory = {} :: { [BasePart]: { LastRadius: number, LastPosition: Vector3, LastSeenAt: number } },
	LastTimerSource = nil :: Instance?,
	LastTimerValue = nil :: number?,
	LastTimerScanAt = -math.huge,
	CurrentHazardRadius = 0,
	CurrentHazardGrowing = false,
	PathBlockedConnection = nil :: RBXScriptConnection?,
	ActivePathGeneration = 0,
	WaypointIssueSerial = 0,
	DodgeStartedAt = 0,
	LastStartClickAt = -math.huge,
	CharacterBindSerial = 0,
	DefaultAutoRotate = true,
	DefaultWalkSpeed = 16,
	LastGoalRefreshAt = 0,
	LastDodgeGoalAttemptAt = -math.huge,
	LastHazardRefreshAt = -math.huge,
	RetreatSide = 1,
	RetreatSideUntil = 0,
}

	return state
end

return Runtime
]],
    ["Systems/ConfigStore.lua"] = [[local Defaults = require(script.Parent.Parent.Config)

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
]],
    ["Systems/DungeonResolver.lua"] = [[local DungeonResolver = {}
DungeonResolver.__index = DungeonResolver

function DungeonResolver.new(ctx)
	return setmetatable({ Ctx = ctx }, DungeonResolver)
end

function DungeonResolver:bootstrap(root: Instance)
	local ctx = self.Ctx
	local runtime = ctx.Runtime

	ctx.DisconnectAll(ctx.DungeonConnections)
	table.clear(ctx.EnemySet)
	table.clear(runtime.EnemyCandidates)
	table.clear(runtime.EnemyFolders)

	runtime.ActiveDungeonRoot = root
	runtime.DungeonIdentity = root
	runtime.EnemyFolderInstance = nil
	runtime.FightingBossInstance = nil
	runtime.DungeonFinishedInstance = nil
	runtime.DungeonTimeInstance = nil

	for _, object in ipairs(root:GetDescendants()) do
		local name = ctx.Normalize(object.Name)
		if name == "enemyfolder" and (object:IsA("Folder") or object:IsA("Model")) then
			runtime.EnemyFolders[object] = true
			runtime.EnemyFolderInstance = runtime.EnemyFolderInstance or object
			local folderPath = runtime.EnemyFolderInstance:GetFullName()
			if runtime.DebugEnemyFolder ~= folderPath then
				runtime.DebugEnemyFolder = folderPath
				print("[DUNGEON] enemyFolder=" .. folderPath)
			end
		elseif name == "fightingboss" and object:IsA("BoolValue") then
			runtime.FightingBossInstance = object
		elseif name == "dungeonfinished" and object:IsA("BoolValue") then
			runtime.DungeonFinishedInstance = object
		elseif (
			name == "timeleft"
			or name == "timer"
			or name == "dungeontime"
			or name == "remainingtime"
			or name == "time"
		) and (
			object:IsA("NumberValue")
			or object:IsA("IntValue")
			or object:IsA("StringValue")
		) then
			runtime.DungeonTimeInstance = object
		elseif object:IsA("Model") then
			ctx.RegisterEnemy(object)
			ctx.RegisterSkillModel(object)
		end
	end

	table.insert(ctx.DungeonConnections, root.DescendantAdded:Connect(function(object)
		local name = ctx.Normalize(object.Name)
		if name == "enemyfolder" and (object:IsA("Folder") or object:IsA("Model")) then
			runtime.EnemyFolders[object] = true
			runtime.EnemyFolderInstance = runtime.EnemyFolderInstance or object
		end
		if name == "fightingboss" and object:IsA("BoolValue") then
			runtime.FightingBossInstance = object
		end
		if name == "dungeonfinished" and object:IsA("BoolValue") then
			runtime.DungeonFinishedInstance = object
		end
		if (
			name == "timeleft"
			or name == "timer"
			or name == "dungeontime"
			or name == "remainingtime"
			or name == "time"
		) and (
			object:IsA("NumberValue")
			or object:IsA("IntValue")
			or object:IsA("StringValue")
		) then
			runtime.DungeonTimeInstance = object
		end

		if object:IsA("Model") then
			ctx.RegisterEnemy(object)
			ctx.RegisterSkillModel(object)
		elseif object:IsA("Humanoid") or object:IsA("BasePart") then
			local owner = object:FindFirstAncestorOfClass("Model")
			if owner then
				ctx.RegisterEnemy(owner)
				ctx.RegisterSkillModel(owner)
			end
		end
	end))

	table.insert(ctx.DungeonConnections, root.DescendantRemoving:Connect(function(object)
		if object:IsA("Model") then
			ctx.EnemySet[object] = nil
			runtime.EnemyCandidates[object] = nil
			ctx.UnregisterSkillModel(object)
		end
		runtime.EnemyFolders[object] = nil
		if object == runtime.EnemyFolderInstance then runtime.EnemyFolderInstance = nil end
		if object == runtime.FightingBossInstance then runtime.FightingBossInstance = nil end
		if object == runtime.DungeonFinishedInstance then runtime.DungeonFinishedInstance = nil end
		if object == runtime.DungeonTimeInstance then runtime.DungeonTimeInstance = nil end
	end))

	runtime.DungeonBootstrapped = true
	local rootPath = root:GetFullName()
	local folderPath = runtime.EnemyFolderInstance and runtime.EnemyFolderInstance:GetFullName() or "nil"
	if runtime.DebugDungeonRoot ~= rootPath then
		runtime.DebugDungeonRoot = rootPath
		print("[DUNGEON] root=" .. rootPath)
	end
	if runtime.DebugEnemyFolder ~= folderPath then
		runtime.DebugEnemyFolder = folderPath
		print("[DUNGEON] enemyFolder=" .. folderPath)
	end
end

function DungeonResolver:refresh()
	local ctx = self.Ctx
	local runtime = ctx.Runtime
	local activeRoot = runtime.ActiveDungeonRoot
	if activeRoot and activeRoot:IsDescendantOf(workspace) then
		return
	end
	local now = os.clock()
	if now - runtime.LastDungeonReferenceSearchAt < 1 then
		return
	end
	runtime.LastDungeonReferenceSearchAt = now

	runtime.ActiveDungeonRoot = nil
	runtime.DungeonIdentity = nil
	ctx.DisconnectAll(ctx.DungeonConnections)

	local candidate: Instance? = nil
	for _, child in ipairs(workspace:GetChildren()) do
		if ctx.Normalize(child.Name) == "dungeon" then
			candidate = child
			break
		end
	end

	if not candidate then
		local scores: { [Instance]: number } = {}
		for _, object in ipairs(workspace:GetDescendants()) do
			local name = ctx.Normalize(object.Name)
			local weight =
				if name == "enemyfolder" then 4
				elseif name == "dungeonfinished" then 3
				elseif name == "timeleft" then 2
				elseif name == "fightingboss" then 1
				elseif object:IsA("Humanoid")
					and object.Health > 0
					and object.Parent
					and object.Parent:IsA("Model")
					and not ctx.IsPlayerCharacter(object.Parent) then 2
				else 0

			if weight > 0 then
				local current: Instance? = if object:IsA("Humanoid") then object.Parent.Parent else object.Parent
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
		self:bootstrap(candidate)
	else
		if runtime.DebugDungeonRoot ~= "nil" then
			runtime.DebugDungeonRoot = "nil"
			print("[DUNGEON] root=nil")
		end
		if runtime.DebugEnemyFolder ~= "nil" then
			runtime.DebugEnemyFolder = "nil"
			print("[DUNGEON] enemyFolder=nil")
		end
	end
end

return DungeonResolver
]],
    ["Systems/SkillFX.lua"] = [[local SkillFX = {}
SkillFX.__index = SkillFX

function SkillFX.new(options)
	local self = setmetatable({}, SkillFX)
	self.Config = options.Config
	self.Models = options.Models
	self.Hitboxes = options.Hitboxes
	self.NormalizeTargetName = options.NormalizeTargetName
	self.GetCharacter = options.GetCharacter
	self.NameHint = options.NameHint
	return self
end

function SkillFX:partKind(instance: Instance): string?
	local name = self.NormalizeTargetName(instance.Name)
	if name == "hitbox" or name == "damagebox" or name == "damagepart" then
		return "hitbox"
	end
	if name == "aoe" or name == "indicator" or name == "precast" then
		return "precast"
	end
	return nil
end

function SkillFX:isActiveHazardPart(part: BasePart): boolean
	local character = self.GetCharacter()
	if not part:IsDescendantOf(workspace) or (character and part:IsDescendantOf(character)) then
		return false
	end
	if part.Transparency >= 0.98 then
		return false
	end

	local dimensions = { part.Size.X, part.Size.Y, part.Size.Z }
	table.sort(dimensions)
	local thinAxis = dimensions[1]
	local middleAxis = dimensions[2]
	local longAxis = dimensions[3]
	local namedTelegraph = self.NameHint(part)
	local pillarLike = longAxis >= math.max(10, middleAxis * 2.5)
		and middleAxis <= math.max(8, thinAxis * 2.5)

	if pillarLike and not namedTelegraph then
		return false
	end

	local broadAndThin = thinAxis <= 5
		and middleAxis >= 5
		and longAxis >= 5
		and longAxis <= middleAxis * 2.5
	local floorCylinder = part:IsA("Part")
		and part.Shape == Enum.PartType.Cylinder
		and not pillarLike

	return namedTelegraph or broadAndThin or floorCylinder
end

function SkillFX:registerModel(model: Model)
	local character = self.GetCharacter()
	if not model:IsDescendantOf(workspace) or (character and model == character) then
		return
	end

	local hitboxes: { [BasePart]: boolean } = {}
	local precasts: { [BasePart]: boolean } = {}

	for _, child in ipairs(model:GetChildren()) do
		local kind = self:partKind(child)
		if kind and child:IsA("BasePart") then
			if kind == "hitbox" then
				hitboxes[child] = true
			else
				precasts[child] = true
			end
			self.Hitboxes[child] = true
		end
	end

	if not next(hitboxes) and not next(precasts) then
		return
	end

	local now = os.clock()
	local previous = self.Models[model]
	if previous then
		for part in pairs(previous.Hitboxes) do
			self.Hitboxes[part] = nil
		end
		for part in pairs(previous.Precasts) do
			self.Hitboxes[part] = nil
		end
	end

	self.Models[model] = {
		Model = model,
		SpawnedAt = previous and previous.SpawnedAt or now,
		Hitboxes = hitboxes,
		Precasts = precasts,
		LastSeenAt = now,
	}
end

function SkillFX:unregisterModel(model: Model)
	local skill = self.Models[model]
	if not skill then
		return
	end
	for part in pairs(skill.Hitboxes) do
		self.Hitboxes[part] = nil
	end
	for part in pairs(skill.Precasts) do
		self.Hitboxes[part] = nil
	end
	self.Models[model] = nil
end

return SkillFX
]],
    ["Systems/TimerResolver.lua"] = [[local TimerResolver = {}
TimerResolver.__index = TimerResolver

function TimerResolver.new(ctx)
	return setmetatable({ Ctx = ctx }, TimerResolver)
end

local function parseTimerText(value: string): number?
	local minutes, seconds = value:match("^(%d+):(%d%d)$")
	if minutes and seconds then
		return tonumber(minutes) * 60 + tonumber(seconds)
	end
	return nil
end

function TimerResolver:getRemainingTime(): number?
	local ctx = self.Ctx
	local runtime = ctx.Runtime
	ctx.RefreshDungeonReferences()

	local source = runtime.DungeonTimeInstance
	local resolved: number? = nil

	if source and (source:IsA("NumberValue") or source:IsA("IntValue")) then
		resolved = source.Value
	elseif source and source:IsA("StringValue") then
		resolved = parseTimerText(source.Value)
	end

	if resolved then
		runtime.LastTimerSource = source
		runtime.LastTimerValue = resolved
		return resolved
	end

	local timeText = runtime.DungeonTimeText
	if (not timeText or not timeText:IsDescendantOf(game))
		and os.clock() - runtime.LastTimerScanAt >= 1
	then
		runtime.LastTimerScanAt = os.clock()
		local bestScore = -math.huge
		for _, uiRoot in ipairs(ctx.GuiRoots()) do
			for _, object in ipairs(uiRoot:GetDescendants()) do
				if (
					object:IsA("TextLabel")
					or object:IsA("TextButton")
					or object:IsA("TextBox")
				) and ctx.VisibleGui(object) then
					local value = parseTimerText(object.Text)
					local name = ctx.Normalize(object.Name)
					local score = value
						and (
							name:find("time", 1, true)
							or name:find("timer", 1, true)
							or name:find("dungeon", 1, true)
						)
						and 10
						or 0
					if value and score > bestScore then
						bestScore = score
						runtime.DungeonTimeText = object
					end
				end
			end
		end
		timeText = runtime.DungeonTimeText
	end

	if timeText and (
		timeText:IsA("TextLabel")
		or timeText:IsA("TextButton")
		or timeText:IsA("TextBox")
	) and ctx.VisibleGui(timeText) then
		local timerTextValue = timeText.Text
		pcall(function()
			if timeText.ContentText and timeText.ContentText ~= "" then
				timerTextValue = timeText.ContentText
			end
		end)

		resolved = parseTimerText(timerTextValue)
		if resolved then
			runtime.LastTimerSource = timeText
			runtime.LastTimerValue = resolved
			return resolved
		end
	end

	return nil
end

return TimerResolver
]],
    ["UI/ObsidianUI.lua"] = [=[local ObsidianUI = {}
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
]=],
}

local Node = {}
Node.__index = function(self, key) return rawget(self, "_children")[key] end
local function newNode(name, path, parent)
    return setmetatable({ Name = name, _path = path, Parent = parent, _children = {} }, Node)
end
local Root, Nodes = newNode("aurafarming", nil, nil), {}
local function addPath(path)
    local current = Root
    local parts = string.split(path, "/")
    for index, part in ipairs(parts) do
        local name = part:gsub("%.lua$", "")
        local child = current._children[name]
        if not child then
            child = newNode(name, index == #parts and path or nil, current)
            current._children[name] = child
        end
        current = child
    end
    Nodes[path] = current
end
for path in pairs(SOURCES) do addPath(path) end
local Cache, Loading, moduleRequire = {}, {}, nil
local function runNode(node)
    local path = node and node._path
    assert(path and SOURCES[path], "invalid bundled module")
    if Cache[path] ~= nil then return Cache[path] end
    assert(not Loading[path], "circular require: " .. path)
    Loading[path] = true
    local chunk, compileError = loadstring(SOURCES[path], "@" .. path)
    assert(chunk, compileError)
    local environment = setmetatable({ script = node, require = function(target) return moduleRequire(target) end }, { __index = getfenv() })
    setfenv(chunk, environment)
    local ok, result = xpcall(chunk, debug.traceback)
    Loading[path] = nil
    assert(ok, result)
    Cache[path] = result
    return result
end
moduleRequire = function(target)
    if type(target) == "table" and target._path then return runNode(target) end
    return require(target)
end
return runNode(assert(Nodes["Main.lua"], "Main.lua missing"))
