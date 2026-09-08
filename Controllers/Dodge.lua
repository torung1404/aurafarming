local Dodge = {}
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
