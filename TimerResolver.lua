local TimerResolver = {}
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
