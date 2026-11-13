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

-- CSS-style cubic-bezier easing curve through (0,0), (x1,y1), (x2,y2), (1,1):
-- returns f(t) for t in 0..1 (x solved by bisection, monotonic for x1, x2 in 0..1)
function U.bezier(x1, y1, x2, y2)
    return function(t)
        if t <= 0 then return 0 end
        if t >= 1 then return 1 end
        local lo, hi, s = 0, 1, t
        for _ = 1, 24 do
            s = (lo + hi) / 2
            local u = 1 - s
            if 3 * u * u * s * x1 + 3 * u * s * s * x2 + s * s * s < t then lo = s else hi = s end
        end
        local u = 1 - s
        return 3 * u * u * s * y1 + 3 * u * s * s * y2 + s * s * s
    end
end

-- t in 0..1 with f(t) = v, for a rising curve f
function U.inverse(f, v)
    if v <= 0 then return 0 end
    if v >= 1 then return 1 end
    local lo, hi = 0, 1
    for _ = 1, 24 do
        local m = (lo + hi) / 2
        if f(m) < v then lo = m else hi = m end
    end
    return (lo + hi) / 2
end

-- on/off flashing from a running clock (s): true for the first half of each period
function U.blink(t, period)
    period = period or 1
    return (t % period) < period / 2
end

function U.sign(v)
    if v > 0 then return 1 elseif v < 0 then return -1 end
    return 0
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

-- Set one "key = value" line in an ini file in place: the first line with that
-- key (any case, any spacing) is replaced, every other line and the line
-- endings are kept; a missing key is appended. Returns false when the file
-- cannot be read or written.
function U.ini_set(path, key, value)
    local f = io.open(path, "rb")
    if not f then return false end
    local raw = f:read("*a")
    f:close()
    local nl = raw:find("\r\n", 1, true) and "\r\n" or "\n"
    if raw:sub(-1) ~= "\n" then raw = raw .. "\n" end
    local lines, done = {}, false
    for l in raw:gmatch("(.-)\r?\n") do
        local line = l
        local k = line:match("^%s*([^;#=%s]+)%s*=")
        if not done and k and string.lower(k) == string.lower(key) then
            line = key .. " = " .. value
            done = true
        end
        lines[#lines + 1] = line
    end
    if not done then lines[#lines + 1] = key .. " = " .. value end
    f = io.open(path, "wb")
    if not f then return false end
    f:write(table.concat(lines, nl), nl)
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

-- Custom int/float datarefs and command handlers. xLua keeps (persists)
-- every callback function handed to the SDK, against a budget of 500 that
-- the aircraft's xLua scripts appear to share (X-Plane crashed once when
-- another xLua script in the same aircraft ran out of it). So all of them go through a few
-- named callbacks; the refcon is the entry id, and the per-dataref /
-- per-command functions stay in Lua tables here. Setter is optional (nil =
-- read-only). Getters and setters keep the SDK argument order: (ref) and
-- (ref, value); command functions get (cmd, phase, ref).
local acc = {}           -- id -> { getter, setter }
local acc_id = {}        -- dataref handle -> id
local cmds = {}          -- id -> handler
local arrs = {}          -- id -> { n, getter, setter } (int arrays)
local next_id = 0

local function dr_get(ref)
    local e = acc[ref]
    if e == nil then return 0 end
    return e[1](ref) or 0
end

local function dr_set(ref, v)
    local e = acc[ref]
    if e and e[2] then e[2](ref, v) end
end

local function cmd_handler(cmd, phase, ref)
    local f = cmds[ref]
    if f == nil then return true end
    return f(cmd, phase, ref) ~= false
end

local function reg(name, int, getter, setter)
    next_id = next_id + 1
    local id = next_id
    acc[id] = { getter, setter }
    local set = setter and dr_set or nil
    local h
    if int then
        h = XPLMRegisterDataAccessor(name, XPLMDataTypeID.xplmType_Int, setter ~= nil,
            dr_get, set, nil, nil,
            nil, nil, nil, nil, nil, nil, nil, nil, id, id)
    else
        h = XPLMRegisterDataAccessor(name, XPLMDataTypeID.xplmType_Float, setter ~= nil,
            nil, nil, dr_get, set,
            nil, nil, nil, nil, nil, nil, nil, nil, id, id)
    end
    if h == nil then
        acc[id] = nil
    else
        acc_id[h] = id
    end
    return h
end

function U.reg_int(name, getter, setter) return reg(name, true, getter, setter) end
function U.reg_float(name, getter, setter) return reg(name, false, getter, setter) end

function U.unreg_dataref(h)
    if h == nil then return end
    XPLMUnregisterDataAccessor(h)
    local id = acc_id[h]
    if id then
        if id < 0 then arrs[-id] = nil else acc[id] = nil end
        acc_id[h] = nil
    end
end

-- returns the id to pass to U.unreg_cmd
function U.reg_cmd(cmd, fn)
    next_id = next_id + 1
    cmds[next_id] = fn
    XPLMRegisterCommandHandler(cmd, cmd_handler, true, next_id)
    return next_id
end

function U.unreg_cmd(cmd, id)
    if id == nil then return end
    XPLMUnregisterCommandHandler(cmd, cmd_handler, true, id)
    cmds[id] = nil
end

-- Int array dataref (xLua 2 array contract, example_scripts/XplmTest
-- TestGetArrayOfInts): the reader returns the element count when outvalues
-- is nil, otherwise fills outvalues[1..max] from element `offset`. The
-- writer gets (ref, values, offset, count). getter(i) / setter(i, v) use
-- 0-based element numbers.

local function dr_get_vi(ref, out, offset, max)
    local e = arrs[ref]
    if e == nil then return 0 end
    if out == nil then return e[1] end
    local m = math.min(max or e[1], e[1] - (offset or 0))
    for i = 1, m do out[i] = e[2](offset + i - 1) end
    return math.max(0, m)
end

local function dr_set_vi(ref, values, offset, count)
    local e = arrs[ref]
    if e == nil or e[3] == nil or values == nil then return end
    for i = 1, count or 0 do
        local k = (offset or 0) + i - 1
        if k >= 0 and k < e[1] and values[i] ~= nil then e[3](k, values[i]) end
    end
end

function U.reg_int_array(name, n, getter, setter)
    next_id = next_id + 1
    local id = next_id
    arrs[id] = { n, getter, setter }
    local h = XPLMRegisterDataAccessor(name, XPLMDataTypeID.xplmType_IntArray, setter ~= nil,
        nil, nil, nil, nil, nil, nil,
        dr_get_vi, setter and dr_set_vi or nil,
        nil, nil, nil, nil, id, id)
    if h == nil then
        arrs[id] = nil
    else
        acc_id[h] = -id      -- negative: an array entry
    end
    return h
end

-- Output datarefs in xLua's own storage (XLuaCreateDataRef, the engine of
-- XLua 1's create_dataref): read-only, no Lua callback handed to the SDK,
-- so they cost none of the callback budget. The script writes the value
-- (U.native_set) once per frame. nil when xLua does not offer it; the
-- caller then registers a normal accessor instead.
function U.native_ok()
    return XLuaCreateDataRef ~= nil and XLuaSetNumber ~= nil
end

function U.native_number(name)
    if not U.native_ok() then return nil end
    local ok, h = pcall(XLuaCreateDataRef, name, "number", "no", nil)
    if ok and h ~= nil then return h end
    return nil
end

function U.native_set(h, v)
    XLuaSetNumber(h, v)
end

-- writable variant (no notifier: the script polls U.native_get each frame);
-- nil when xLua does not allow it
function U.native_number_w(name)
    if not U.native_ok() or XLuaGetNumber == nil then return nil end
    local ok, h = pcall(XLuaCreateDataRef, name, "number", "yes", nil)
    if ok and h ~= nil then return h end
    return nil
end

function U.native_get(h)
    return XLuaGetNumber(h)
end

-- live entries (test-only: nothing may be left after XPluginDisable)
function U.live_callbacks()
    local n = 0
    for _ in pairs(acc) do n = n + 1 end
    for _ in pairs(cmds) do n = n + 1 end
    for _ in pairs(arrs) do n = n + 1 end
    return n
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
