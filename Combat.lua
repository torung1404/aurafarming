local CombatController = {}
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

return CombatController
