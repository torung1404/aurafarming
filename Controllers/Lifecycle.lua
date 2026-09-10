local Lifecycle = {}
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
