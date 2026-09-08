local SkillFX = {}
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
