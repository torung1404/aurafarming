#!/usr/bin/env python3
"""Deterministically package Luau source for Delta's loadstring entrypoint."""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Bundle.lua"
EXCLUDED = {"Bundle.lua", "LOADSTRING.lua"}
MAX_MAIN_TOP_LEVEL_LOCAL_BINDINGS = 160


def quote_luau(source: str) -> str:
    level = 0
    while True:
        opener = "[" + "=" * level + "["
        closer = "]" + "=" * level + "]"
        if closer not in source:
            return opener + source + closer
        level += 1


def top_level_local_bindings(source: str) -> int:
    """Conservatively count Main.lua bindings that share the chunk register pool."""
    bindings = 0
    for line in source.splitlines():
        if line.startswith("local function "):
            bindings += 1
            continue
        if not line.startswith("local ") or "=" not in line:
            continue
        left = line[6 : line.index("=")].strip()
        if left and not left.startswith("function "):
            bindings += len(left.split(","))
    return bindings


def main() -> None:
    paths = sorted(
        path for path in ROOT.rglob("*.lua")
        if path.name not in EXCLUDED and ".git" not in path.parts
    )
    main_source = (ROOT / "Main.lua").read_text(encoding="utf-8")
    main_bindings = top_level_local_bindings(main_source)
    if main_bindings > MAX_MAIN_TOP_LEVEL_LOCAL_BINDINGS:
        raise SystemExit(
            "Main.lua has "
            f"{main_bindings} top-level local bindings; limit is "
            f"{MAX_MAIN_TOP_LEVEL_LOCAL_BINDINGS}. Group state or move logic into its controller before bundling."
        )
    chunks = [
        "-- AUTO-GENERATED FILE.\n",
        "-- DO NOT EDIT DIRECTLY. Edit source modules/Main.lua and run scripts/build_bundle.py.\n",
        "local SOURCES = {\n",
    ]
    for path in paths:
        relative = path.relative_to(ROOT).as_posix()
        chunks.append(f'    ["{relative}"] = {quote_luau(path.read_text(encoding="utf-8"))},\n')
    chunks.append("}\n\n")
    chunks.append(r'''local Node = {}
Node.__index = function(self, key) return rawget(self, "_children")[key] end
local function newNode(name, path, parent)
    return setmetatable({ Name = name, _path = path, Parent = parent, _children = {} }, Node)
end
local Root, Nodes = newNode("aurafarming", nil, nil), {}
local function addPath(path)
    local current = Root
    local parts = string.split(path, "/")
    for index, part in ipairs(parts) do
        local name = part:gsub("%.lua$", "")
        local child = current._children[name]
        if not child then
            child = newNode(name, index == #parts and path or nil, current)
            current._children[name] = child
        end
        current = child
    end
    Nodes[path] = current
end
for path in pairs(SOURCES) do addPath(path) end
local Cache, Loading, moduleRequire = {}, {}, nil
local function runNode(node)
    local path = node and node._path
    assert(path and SOURCES[path], "invalid bundled module")
    if Cache[path] ~= nil then return Cache[path] end
    assert(not Loading[path], "circular require: " .. path)
    Loading[path] = true
    local chunk, compileError = loadstring(SOURCES[path], "@" .. path)
    assert(chunk, compileError)
    local environment = setmetatable({ script = node, require = function(target) return moduleRequire(target) end }, { __index = getfenv() })
    setfenv(chunk, environment)
    local ok, result = xpcall(chunk, debug.traceback)
    Loading[path] = nil
    assert(ok, result)
    Cache[path] = result
    return result
end
moduleRequire = function(target)
    if type(target) == "table" and target._path then return runNode(target) end
    return require(target)
end
return runNode(assert(Nodes["Main.lua"], "Main.lua missing"))
''')
    OUTPUT.write_text("".join(chunks), encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
