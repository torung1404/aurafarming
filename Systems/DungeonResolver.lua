local DungeonResolver = {}
DungeonResolver.__index = DungeonResolver

function DungeonResolver.new(ctx)
	return setmetatable({ Ctx = ctx }, DungeonResolver)
end

function DungeonResolver:bootstrap(root: Instance)
	local ctx = self.Ctx
	local runtime = ctx.Runtime

	ctx.DisconnectAll(ctx.DungeonConnections)
	table.clear(ctx.EnemySet)
	table.clear(runtime.EnemyCandidates)
	table.clear(runtime.EnemyFolders)

	runtime.ActiveDungeonRoot = root
	runtime.DungeonIdentity = root
	runtime.EnemyFolderInstance = nil
	runtime.FightingBossInstance = nil
	runtime.DungeonFinishedInstance = nil
	runtime.DungeonTimeInstance = nil

	for _, object in ipairs(root:GetDescendants()) do
		local name = ctx.Normalize(object.Name)
		if name == "enemyfolder" and (object:IsA("Folder") or object:IsA("Model")) then
			runtime.EnemyFolders[object] = true
			runtime.EnemyFolderInstance = runtime.EnemyFolderInstance or object
		elseif name == "fightingboss" and object:IsA("BoolValue") then
			runtime.FightingBossInstance = object
		elseif name == "dungeonfinished" and object:IsA("BoolValue") then
			runtime.DungeonFinishedInstance = object
		elseif (
			name == "timeleft"
			or name == "timer"
			or name == "dungeontime"
			or name == "remainingtime"
			or name == "time"
		) and (
			object:IsA("NumberValue")
			or object:IsA("IntValue")
			or object:IsA("StringValue")
		) then
			runtime.DungeonTimeInstance = object
		elseif object:IsA("Model") then
			ctx.RegisterEnemy(object)
			ctx.RegisterSkillModel(object)
		end
	end

	table.insert(ctx.DungeonConnections, root.DescendantAdded:Connect(function(object)
		local name = ctx.Normalize(object.Name)
		if name == "enemyfolder" and (object:IsA("Folder") or object:IsA("Model")) then
			runtime.EnemyFolders[object] = true
			runtime.EnemyFolderInstance = runtime.EnemyFolderInstance or object
		end
		if name == "fightingboss" and object:IsA("BoolValue") then
			runtime.FightingBossInstance = object
		end
		if name == "dungeonfinished" and object:IsA("BoolValue") then
			runtime.DungeonFinishedInstance = object
		end
		if (
			name == "timeleft"
			or name == "timer"
			or name == "dungeontime"
			or name == "remainingtime"
			or name == "time"
		) and (
			object:IsA("NumberValue")
			or object:IsA("IntValue")
			or object:IsA("StringValue")
		) then
			runtime.DungeonTimeInstance = object
		end

		if object:IsA("Model") then
			ctx.RegisterEnemy(object)
			ctx.RegisterSkillModel(object)
		elseif object:IsA("BasePart") then
			local owner = object:FindFirstAncestorOfClass("Model")
			if owner then
				ctx.RegisterSkillModel(owner)
			end
		end
	end))

	table.insert(ctx.DungeonConnections, root.DescendantRemoving:Connect(function(object)
		if object:IsA("Model") then
			ctx.EnemySet[object] = nil
			runtime.EnemyCandidates[object] = nil
			ctx.UnregisterSkillModel(object)
		end
		runtime.EnemyFolders[object] = nil
		if object == runtime.EnemyFolderInstance then runtime.EnemyFolderInstance = nil end
		if object == runtime.FightingBossInstance then runtime.FightingBossInstance = nil end
		if object == runtime.DungeonFinishedInstance then runtime.DungeonFinishedInstance = nil end
		if object == runtime.DungeonTimeInstance then runtime.DungeonTimeInstance = nil end
	end))

	runtime.DungeonBootstrapped = true
end

function DungeonResolver:refresh()
	local ctx = self.Ctx
	local runtime = ctx.Runtime
	local activeRoot = runtime.ActiveDungeonRoot
	if activeRoot and activeRoot:IsDescendantOf(workspace) then
		return
	end

	runtime.ActiveDungeonRoot = nil
	runtime.DungeonIdentity = nil
	ctx.DisconnectAll(ctx.DungeonConnections)

	local candidate: Instance? = nil
	for _, child in ipairs(workspace:GetChildren()) do
		if ctx.Normalize(child.Name) == "dungeon" then
			candidate = child
			break
		end
	end

	if not candidate then
		local scores: { [Instance]: number } = {}
		for _, object in ipairs(workspace:GetDescendants()) do
			local name = ctx.Normalize(object.Name)
			local weight =
				if name == "enemyfolder" then 4
				elseif name == "dungeonfinished" then 3
				elseif name == "timeleft" then 2
				elseif name == "fightingboss" then 1
				else 0

			if weight > 0 then
				local current: Instance? = object.Parent
				local depth = 0
				while current and current ~= workspace and depth < 8 do
					if current:IsA("Folder") or current:IsA("Model") then
						scores[current] = (scores[current] or 0) + weight / (depth + 1)
					end
					current = current.Parent
					depth += 1
				end
			end
		end

		local bestScore = -math.huge
		for root, score in pairs(scores) do
			if score > bestScore then
				bestScore = score
				candidate = root
			end
		end
	end

	if candidate then
		self:bootstrap(candidate)
	end
end

return DungeonResolver
