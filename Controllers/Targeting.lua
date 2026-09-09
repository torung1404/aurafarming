local Targeting = {}
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
