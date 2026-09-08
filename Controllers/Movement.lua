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
	self.getState = context.getState
	self.setNavigationState = context.setNavigationState
	self.getNavigationGoal = context.getNavigationGoal
	self.beginLocalRecovery = context.beginLocalRecovery
	self.setBestGoalMetric = context.setBestGoalMetric
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
	if self.getState() ~= "PATH" or not self.PathWaypoints or not self.PathWaypoints[self.PathIndex] then
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
	if self.getState() ~= "PATH" or not humanoid or not root or not self.PathWaypoints then
		return
	end
	local waypoint = self.PathWaypoints[self.PathIndex]
	if not waypoint then
		self:disposePath()
		self.setNavigationState("IDLE")
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
			self.beginLocalRecovery(nil, 0)
			self.setNavigationState("RECOVERY")
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
		self.setNavigationState("PATH")
		self.setBestGoalMetric(self:pathRemainingMetric(self.getNavigationGoal()))
		-- The async compute callback publishes state only. The next Heartbeat issues MoveTo.
	end)
	return true
end

function Movement:updatePathNavigation()
	local root = self.getRoot()
	local navigationGoal = self.getNavigationGoal()
	if self.getState() ~= "PATH" or not root or not self.PathWaypoints then
		return
	end
	if self.PathNeedsRebuild then
		self.beginLocalRecovery(navigationGoal or root.Position)
		self:requestPath(navigationGoal or root.Position)
		return
	end
	local waypoint = self.PathWaypoints[self.PathIndex]
	if not waypoint then
		self:disposePath()
		self.setNavigationState("IDLE")
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
			self.setBestGoalMetric(self:pathRemainingMetric(navigationGoal))
		end
		self:issueCurrentWaypoint()
		return
	end
	if waypointDistance <= self.PathBestWaypointDistance - self.Config.MeaningfulProgressDistance then
		self.PathBestWaypointDistance = waypointDistance
		self.setBestGoalMetric(self:pathRemainingMetric(navigationGoal))
	end
	if self.PathIssuedIndex == self.PathIndex and self.PathIssuedAt > 0 and os.clock() - self.PathIssuedAt >= self.Config.WaypointTimeout then
		self.PathNeedsRebuild = true
		return
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
