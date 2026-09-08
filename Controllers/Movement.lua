local Movement = {}
Movement.__index = Movement

function Movement.new(context)
	local self = setmetatable({}, Movement)
	self.Config = context.Config
	self.RuntimeState = context.RuntimeState
	self.getCharacter = context.getCharacter
	self.getHumanoid = context.getHumanoid
	self.getRoot = context.getRoot
	self.getTarget = context.getTarget
	self.pointIsSafeFromHazards = context.pointIsSafeFromHazards
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
