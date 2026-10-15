-- g5_util.lua: math, paths, config.ini, dataref/command helpers.
-- Loaded by G5.lua through load_module(); shares the master script's environment.

local U = {}

U.LOG_PREFIX = "[G5 XLua2] "

function U.log(msg)
    print(U.LOG_PREFIX .. tostring(msg))
end

-----------------------------------------------------------------------------
-- Math
-----------------------------------------------------------------------------

function U.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function U.wrap360(a)
    a = a % 360
    if a < 0 then a = a + 360 end
    return a
end

-- signed a - b in [-180, 180)
function U.angdiff(a, b)
    local d = (a - b + 180) % 360
    if d < 0 then d = d + 360 end
    return d - 180
end

-- move v toward target at rate units/second
function U.approach(v, target, rate, dt)
    local step = rate * dt
    if v < target then
        v = v + step
        if v > target then v = target end
    elseif v > target then
        v = v - step
        if v < target then v = target end
    end
    return v
end

-- on/off flashing from a running clock (s): true for the first half of each period
function U.blink(t, period)
    period = period or 1
    return (t % period) < period / 2
end

function U.round(v)
    return math.floor(v + 0.5)
end

-----------------------------------------------------------------------------
-- Paths
-----------------------------------------------------------------------------

function U.unwrap_string(v)
    if type(v) == "table" then
        return v[1] or v.outPath or v.outFileName or v.outSystemPath or ""
    end
    return v or ""
end

function U.normalize_path(path)
    local p = (path or ""):gsub("\\", "/")
    return p
end

function U.dirname(path)
    path = U.normalize_path(path)
    return path:match("^(.*)/[^/]*$") or ""
end

function U.join(a, b)
    if a == "" then return b end
    if string.sub(a, -1) == "/" then return a .. b end
    return a .. "/" .. b
end

function U.file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

-- Atlas/font paths must be X-Plane-root relative with forward slashes.
function U.xp_relative(path)
    path = U.normalize_path(path)
    local sys = XPLMGetSystemPath()
    local root = U.normalize_path(U.unwrap_string(type(sys) == "table" and sys.outSystemPath or sys))
    if root ~= "" then
        if string.sub(root, -1) ~= "/" then root = root .. "/" end
        if string.lower(string.sub(path, 1, #root)) == string.lower(root) then
            return string.sub(path, #root + 1)
        end
    end
    return path
end

-----------------------------------------------------------------------------
-- config.ini / settings.ini: [section] lines ignored, ';' and '#' comments, key = value.
-- Only keys that already exist in `defaults` are accepted, coerced to the
-- default's type.
-----------------------------------------------------------------------------

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function U.read_ini(path, defaults)
    local f = io.open(path, "r")
    if not f then
        U.log(path:match("[^/\\]+$") .. " not found, using defaults: " .. path)
        return false
    end
    for line in f:lines() do
        local s = trim((line:gsub("[;#].*$", "")))
        if s ~= "" and string.sub(s, 1, 1) ~= "[" then
            local key, value = s:match("^([^=]+)=(.*)$")
            if key then
                key = string.lower(trim(key))
                value = trim(value)
                local d = defaults[key]
                if d == nil then
                    U.log(path:match("[^/\\]+$") .. ": unknown key '" .. key .. "' ignored")
                elseif type(d) == "number" then
                    defaults[key] = tonumber(value) or d
                elseif type(d) == "boolean" then
                    local v = string.lower(value)
                    defaults[key] = (v == "1" or v == "true" or v == "yes" or v == "on")
                else
                    defaults[key] = value
                end
            end
        end
    end
    f:close()
    return true
end

-- Write `pairs` ({ {key, value}, ... }) as "key = value" lines, with an
-- optional comment header. Returns false when the file cannot be written.
function U.write_ini(path, pairs, header)
    local f = io.open(path, "w")
    if not f then return false end
    if header then f:write("; " .. header .. "\n") end
    for _, kv in ipairs(pairs) do
        f:write(kv[1] .. " = " .. tostring(kv[2]) .. "\n")
    end
    f:close()
    return true
end

-----------------------------------------------------------------------------
-- Datarefs
-----------------------------------------------------------------------------

function U.find(name)
    local h = XPLMFindDataRef(name)
    if h == nil then
        U.log("dataref not found: " .. name)
    end
    return h
end

function U.getf(h, fallback)
    if h == nil then return fallback end
    return XPLMGetDataf(h)
end

function U.geti(h, fallback)
    if h == nil then return fallback end
    return XPLMGetDatai(h)
end

local scratch = {}

function U.getfa(h, index, fallback)
    if h == nil then return fallback end
    local n = XPLMGetDatavf(h, scratch, index, 1)
    if not n or n < 1 or scratch[1] == nil then return fallback end
    return scratch[1]
end

function U.getia(h, index, fallback)
    if h == nil then return fallback end
    local n = XPLMGetDatavi(h, scratch, index, 1)
    if not n or n < 1 or scratch[1] == nil then return fallback end
    return scratch[1]
end

function U.setf(h, v)
    if h ~= nil then XPLMSetDataf(h, v) end
end

function U.seti(h, v)
    if h ~= nil then XPLMSetDatai(h, v) end
end

function U.setfa(h, index, v)
    if h ~= nil then XPLMSetDatavf(h, { v }, index, 1) end
end

-- Read a byte-array string dataref (nav ids). Returns "" on failure.
-- The binding fills a caller table with byte values (same convention as
-- XPLMGetDatavf); tolerate a string result too in case that changes.
local bytes = {}
function U.gets(h, max_len)
    if h == nil then return "" end
    for i = #bytes, 1, -1 do bytes[i] = nil end
    local ok, ret = pcall(XPLMGetDatab, h, bytes, 0, max_len or 16)
    if not ok then return "" end
    if type(ret) == "string" then return (ret:gsub("%z.*$", "")) end
    local chars = {}
    for i = 1, #bytes do
        local b = bytes[i]
        if type(b) ~= "number" or b == 0 then break end
        chars[#chars + 1] = string.char(b)
    end
    return table.concat(chars)
end

-- Custom int/float datarefs. Setter is optional (nil = read-only).
function U.reg_int(name, getter, setter)
    return XPLMRegisterDataAccessor(name, XPLMDataTypeID.xplmType_Int, setter ~= nil,
        getter, setter,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil)
end

function U.reg_float(name, getter, setter)
    return XPLMRegisterDataAccessor(name, XPLMDataTypeID.xplmType_Float, setter ~= nil,
        nil, nil,
        getter, setter,
        nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil)
end

-----------------------------------------------------------------------------
-- Commands
-----------------------------------------------------------------------------

function U.find_cmd(name)
    local c = XPLMFindCommand(name)
    if c == nil then
        U.log("command not found: " .. name)
    end
    return c
end

function U.cmd_once(c)
    if c ~= nil then XPLMCommandOnce(c) end
end

return U
