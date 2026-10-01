#!/usr/bin/env lua
-- =============================================================================
-- tools/load-bindings.lua
--
-- Secure, sandboxed loader for user-customizable keybindings.
-- Evaluates ~/.config/omarchy/tablerase.ardoise/bindings.lua without allowing
-- arbitrary code execution (no os, no io, no package, no debug).
-- Serializes the resulting table to JSON on stdout.
-- =============================================================================

local filePath = arg and arg[1]
if not filePath or filePath == "" then
  print("{}")
  os.exit(0)
end

-- Resolve tilde in file path if present
if filePath:sub(1, 1) == "~" then
  local home = os.getenv("HOME") or ""
  filePath = home .. filePath:sub(2)
end

local f = io.open(filePath, "r")
if not f then
  -- File doesn't exist yet; safe default empty object
  print("{}")
  os.exit(0)
end

local content = f:read("*a")
f:close()

if not content or content:match("^%s*$") then
  print("{}")
  os.exit(0)
end

-- Lightweight JSON serializer for flat/nested string/array tables
local function to_json(val)
  local t = type(val)
  if t == "string" then
    return string.format("%q", val)
  elseif t == "number" or t == "boolean" then
    return tostring(val)
  elseif t == "table" then
    -- Detect if array or dictionary
    local is_array = true
    local n = 0
    for k, _ in pairs(val) do
      n = n + 1
      if type(k) ~= "number" or k ~= n then
        is_array = false
        break
      end
    end

    if n == 0 then
      return "{}"
    end

    if is_array then
      local parts = {}
      for i = 1, #val do
        table.insert(parts, to_json(val[i]))
      end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      local parts = {}
      for k, v in pairs(val) do
        if type(k) == "string" then
          table.insert(parts, string.format("%q:%s", k, to_json(v)))
        end
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  end
  return "null"
end

-- Sandbox environment: whitelist only safe primitives
local KNOWN_ACTIONS = {
  next_task = true,
  prev_task = true,
  cycle_left = true,
  cycle_right = true,
  jump_top = true,
  jump_bottom = true,
  toggle_done = true,
  toggle_expand = true,
  delete_task = true,
  edit_title = true,
  open_editor = true,
  git_undo = true,
  clear_completed = true,
  open_archive = true,
  focus_input = true,
  search = true,
  quick_add = true,
  help = true
}

local bindings_table = {}
local ardoise_builder = {
  bind = function(a, b)
    local act, k
    if type(a) == "string" and KNOWN_ACTIONS[a] then
      act = a
      k = b
    elseif type(b) == "string" and KNOWN_ACTIONS[b] then
      act = b
      k = a
    else
      act = a
      k = b
    end
    if type(act) == "string" and (type(k) == "string" or type(k) == "table") then
      bindings_table[act] = k
    end
  end,
  bindings = bindings_table
}

local sandbox_env = {
  tostring = tostring,
  tonumber = tonumber,
  type = type,
  pairs = pairs,
  ipairs = ipairs,
  select = select,
  table = {
    insert = table.insert,
    concat = table.concat,
    remove = table.remove,
    sort = table.sort
  },
  string = {
    byte = string.byte,
    char = string.char,
    find = string.find,
    format = string.format,
    gmatch = string.gmatch,
    gsub = string.gsub,
    len = string.len,
    lower = string.lower,
    match = string.match,
    reverse = string.reverse,
    sub = string.sub,
    upper = string.upper
  },
  math = {
    abs = math.abs,
    floor = math.floor,
    ceil = math.ceil,
    min = math.min,
    max = math.max
  },
  ardoise = ardoise_builder
}
-- Self-reference so `_G` inside sandbox doesn't escape
sandbox_env._G = sandbox_env

-- Compile chunk in sandbox environment
local chunk, load_err = load(content, filePath, "t", sandbox_env)
if not chunk then
  io.stderr:write("[Ardoise] Lua keybindings syntax error: " .. tostring(load_err) .. "\n")
  print("{}")
  os.exit(0)
end

-- Execute chunk safely
local ok, result = pcall(chunk)
if not ok then
  io.stderr:write("[Ardoise] Lua keybindings runtime error: " .. tostring(result) .. "\n")
  print("{}")
  os.exit(0)
end

-- Handle return styles: table return vs ardoise.bind() accumulation
local final_bindings = {}
if type(result) == "table" then
  final_bindings = result
elseif next(bindings_table) ~= nil then
  final_bindings = bindings_table
end

print(to_json(final_bindings))
