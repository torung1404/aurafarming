local Movement = {}
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
			local direction = away.Magnitude > 0.1 and away.Unit or Vector3.xAxis
			local retreatPoint, foundGround = self:projectToWalkableGround(root.Position + direction * 7, target)
			if
				foundGround
				and math.abs(retreatPoint.Y - root.Position.Y) <= self.Config.DirectVerticalTolerance
				and self:hasGroundSupport(retreatPoint, target)
				and self:directRouteClear(retreatPoint, target)
			then
				self:commandMovement(direction, false)
			else
				self:commandMovement(Vector3.zero, false)
			end
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
	if self.Config.SpeedEnabled then
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(flat.Unit.X * self.Config.MoveSpeed, velocity.Y, flat.Unit.Z * self.Config.MoveSpeed)
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
	elseif humanoid and not self.Config.SpeedEnabled then
		humanoid:Move(Vector3.zero, false)
	end
end

function Movement:stopTranslation()
	self:releaseMovement()
end

return Movement
