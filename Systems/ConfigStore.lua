local Defaults = require(script.Parent.Parent.Config)

local Store = {}
local FILE_NAME = "AutoFarmV21Config.json"

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = clone(item) end
    return result
end

function Store.load(httpService)
    local result = clone(Defaults)
    if type(isfile) == "function" and type(readfile) == "function" and isfile(FILE_NAME) then
        local ok, saved = pcall(function() return httpService:JSONDecode(readfile(FILE_NAME)) end)
        if ok and type(saved) == "table" then
            for key, value in pairs(saved) do
                if result[key] ~= nil and type(value) == type(result[key]) then result[key] = value end
            end
        end
    end
    return result
end

function Store.save(httpService, config)
    if type(writefile) ~= "function" then return false end
    local ok = pcall(function() writefile(FILE_NAME, httpService:JSONEncode(config)) end)
    return ok
end

return Store
