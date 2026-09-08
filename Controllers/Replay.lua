local Replay = {}
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

function Replay:clickButton(button: GuiButton)
	if not self.VirtualInputManager then
		return
	end
	local position = button.AbsolutePosition + button.AbsoluteSize * 0.5
	local inset = select(1, self.GuiService:GetGuiInset())
	local screenGui = button:FindFirstAncestorOfClass("ScreenGui")
	if not screenGui or not screenGui.IgnoreGuiInset then
		position += inset
	end
	pcall(function()
		self.VirtualInputManager:SendMouseMoveEvent(position.X, position.Y, game)
		self.VirtualInputManager:SendMouseButtonEvent(position.X, position.Y, 0, true, game, 0)
		task.delay(0.04, function()
			self.VirtualInputManager:SendMouseButtonEvent(position.X, position.Y, 0, false, game, 0)
		end)
	end)
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

function Replay:tryReplayDungeon()
	local runtime = self.RuntimeState
	local now = os.clock()
	if not self.isRunning() or not self.Config.AutoReplay then return end
	local phase = runtime.ReplayPhase
	local phaseAge = now - runtime.ReplayPhaseEnteredAt
	if runtime.ReplayResultScanDirty or phase ~= "IDLE" then
		runtime.ReplayResultScanDirty = false
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
		self:setPhase("IDLE")
		return
	end
	if phase == "IDLE" then
		return
	end
	if phase == "WAIT_NEW_ROUND" then
		if runtime.DungeonIdentity ~= runtime.ReplayDungeonIdentity then
			self:setPhase("IDLE")
			return
		end
		if phaseAge > 3 then
			self:setPhase("RESULT_DETECTED")
		end
		return
	end
	if phase == "ARMED" and runtime.ReplayCompletionDetected then self:setPhase("RESULT_DETECTED"); phase = runtime.ReplayPhase end
	if phase == "RESULT_DETECTED" or phase == "ARMED" then
		local opener = runtime.ReplayOpener
		if not opener or not opener:IsDescendantOf(game) or not self.visibleGui(opener) then opener = self:findOpener(); runtime.ReplayOpener = opener end
		if opener and now - runtime.ReplayLastActionAt >= 0.75 then
			print("[REPLAY] click opener")
			self:clickButton(opener)
			runtime.ReplayLastActionAt = now
			runtime.ReplayRetries += 1
			self:setPhase("OPENING")
			return
		end
		if phaseAge > 8 then self:setPhase("IDLE") end
		return
	end
	local yes = runtime.ReplayYesButton
	if not yes or not yes:IsDescendantOf(game) or not self.visibleGui(yes) then yes = self:findButton(); runtime.ReplayYesButton = yes end
	if yes and now - runtime.ReplayLastActionAt >= 0.75 then
		print("[REPLAY] click yes")
		self:clickButton(yes)
		runtime.ReplayAwaitingClose = yes
		runtime.ReplayLastActionAt = now
		runtime.ReplayRetries += 1
		self:setPhase("CONFIRMING")
		return
	end
	if phase == "CONFIRMING" and runtime.ReplayAwaitingClose and (not runtime.ReplayAwaitingClose:IsDescendantOf(game) or not self.visibleGui(runtime.ReplayAwaitingClose)) then
		runtime.ReplayAwaitingClose = nil
		runtime.ReplayDungeonIdentity = runtime.DungeonIdentity
		print("[REPLAY] waiting new round")
		self:setPhase("WAIT_NEW_ROUND")
		return
	end
	if (phase == "OPENING" or phase == "CONFIRMING") and phaseAge > 8 then
		self:setPhase("RESULT_DETECTED")
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
