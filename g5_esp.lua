-- g5_esp.lua: the G5's side of ESP (Electronic Stability & Protection,
-- Pilot's Guide 3.5) and of the autopilot facts the port carries.
--
-- ESP is the autopilot's function. One provider package in the aircraft
-- (AFCS_ESP, a separate script package) runs it behind the laminar/afcs/ port
-- (port version 1 or 2). The G5 only shows it: the ESP
-- menu tile, the Roll Limit Indicators, the pitch engagement chevrons, "ESP
-- OFF" and the MAXSPD / MINSPD tag. While a unit has a
-- valid attitude the G5 writes the port's attitude heartbeat, so the
-- provider can arm.
--
-- Takes part in ESP only with ap_option = esp (config.esp = 1). No provider
-- (or an older port version) = no ESP on the G5; the G5 never runs ESP itself.
--
-- The port is read whatever ap_option is, for the version 2 fields that say
-- what the autopilot is (cap_digital, cap_ias_mode, ap_pft, speed_protect);
-- the heartbeat and the ESP menu stay tied to ap_option = esp.

local U, cfg

local PORT = "laminar/afcs/"
local NEED_VERSION = 1
local LOOKUP_EVERY = 20     -- frames between lookups while there is no port
-- port v2 fields: name -> the port_version that introduced it. Each is
-- looked up on its own; a missing one only means "use the G5's own setting"
local SINCE = { cap_digital = 2, cap_ias_mode = 2, ap_pft = 2, speed_protect = 2,
    esp_interrupted = 2 }

local E = {
    found = false,      -- the port is there (and new enough)
    available = false,  -- laminar/afcs/esp_available
    enabled = true,     -- the pilot's switch, as the provider holds it
    armed = false,
    roll = false,       -- roll protection engaged (the marks turn yellow)
    -- airspeed protection engaged: MAXSPD / MINSPD on the PFD (Pilot's Guide
    -- 3.4.2, 3.5.3). From the port's speed_protect field when the provider
    -- has it (autopilot on or off); else the ESP half only (esp_engaged
    -- bits 4 / 8, autopilot off: with the autopilot engaged port v1 has no
    -- field and X-Plane has no AP speed-protection dataref). The G5 does not
    -- work it out itself.
    overspeed = false,  -- high-speed protection, nose up
    underspeed = false, -- low-speed protection, nose down
    -- pitch protection engaged (esp_engaged bit 2): the pitch engagement
    -- chevrons (Pilot's Guide Rev M 3.5.2, figure 3-30). pitch_dir is the
    -- direction ESP is pushing the nose, from the provider's esp_pitch_force
    -- (+1 nose up: chevrons point up, -1 nose down: they point down, 0 = the
    -- provider gave no direction; the PFD then points them against the pitch)
    pitch = false,
    pitch_dir = 0,
    roll_limit = 45,
    live = false,       -- the provider's port_version reads >= 1 now
    -- the autopilot picture of this frame (E.picture), what the displays
    -- draw from. digital: a digital autopilot (no GPSS item, the reserved
    -- bar, the Garmin autopilot on the config page); ias_mode: the airspeed
    -- reference bug and box in IAS mode; pft: the autopilot's preflight test
    -- (0 none, 1 running, 2 failed; nil = the unit times it itself)
    pic = { digital = false, ias_mode = false, pft = nil },
}

local NAMES = { "port_version", "esp_available", "esp_enabled", "esp_armed",
    "esp_engaged", "esp_roll_limit", "attitude_heartbeat" }
-- esp_pitch_force is in port v1 but only the chevron direction
-- needs it: a provider without it still gets everything else
local OPTIONAL = { "esp_pitch_force" }
local h = {}
local v2 = {}           -- name -> handle, for the v2 fields this provider has
local seen_version = nil
local wait = 0

function E.init(util, config)
    U, cfg = util, config
    E.reset()
end

local function drop_v2()
    for n in pairs(v2) do v2[n] = nil end
    seen_version = nil
end

function E.reset()
    E.found, E.available, E.enabled, E.armed, E.roll = false, false, true, false, false
    E.overspeed, E.underspeed = false, false
    E.pitch, E.pitch_dir = false, 0
    E.live = false
    E.pic.digital, E.pic.ias_mode, E.pic.pft, E.pic.warned = false, false, nil, false
    drop_v2()
    wait = 0
end

-- every port name present: a provider that loads after the G5 (or is
-- reloaded) is picked up on a later try
local function lookup()
    for _, n in ipairs(NAMES) do
        h[n] = XPLMFindDataRef(PORT .. n)
        if h[n] == nil then return false end
    end
    for _, n in ipairs(OPTIONAL) do h[n] = XPLMFindDataRef(PORT .. n) end
    return true
end

local function geti(n)
    local ok, v = pcall(XPLMGetDatai, h[n])
    return ok and v or 0
end

-- the v2 fields, one by one: supported = the provider's port_version is at
-- least the field's Since and the name resolves. Redone when port_version
-- changes (a provider swapped by a script reload)
local function lookup_v2(version)
    drop_v2()
    for n, since in pairs(SINCE) do
        if version >= since then
            local r = XPLMFindDataRef(PORT .. n)
            if r ~= nil then v2[n] = r end
        end
    end
    seen_version = version
end

-- a v2 field is supported by the live provider ("supported and 0" is the
-- provider's answer; "not supported" means: use the G5's own setting)
function E.has(f)
    return E.live and v2[f] ~= nil
end

local function getv2(n)
    local ok, v = pcall(XPLMGetDatai, v2[n])
    return ok and v or 0
end

-- shown at all: this G5 takes part and the provider says ESP can run
function E.usable()
    return cfg.esp ~= 0 and E.found and E.available
end

-- MAXSPD / MINSPD may be shown: the port's field when the provider has it
-- (ap_option does not matter), else the ESP half (this G5 takes part in ESP)
function E.speed_tag_ok()
    return E.has("speed_protect") or E.usable()
end

-- the PFD menu item: the provider holds the switch; show the new state at once
function E.toggle()
    if not E.found then return end
    E.enabled = not E.enabled
    pcall(XPLMSetDatai, h.esp_enabled, E.enabled and 1 or 0)
end

-- One item of the picture: the installer's fixed value (fixed ~= nil), else
-- the provider's field when it supports it ("supported and 0" counts), else
-- the legacy value
local function pick(fixed, name, legacy)
    if fixed ~= nil then return fixed end
    if E.has(name) then return getv2(name) ~= 0 end
    return legacy
end

-- The autopilot picture, once per frame. mode: config gfc500 ("1" / "0" fix
-- it, anything else follows the aircraft); installed: laminar/gfc500/installed
-- as it reads now (the legacy source). Returns E.pic.
function E.picture(mode, installed)
    local p = E.pic
    local fixed
    if mode == "1" then fixed = true elseif mode == "0" then fixed = false end
    local legacy = (installed or 0) ~= 0
    p.digital = pick(fixed, "cap_digital", legacy)
    p.ias_mode = pick(fixed, "cap_ias_mode", legacy)
    if fixed == nil and E.has("ap_pft") then p.pft = getv2("ap_pft") else p.pft = nil end
    return p
end

-- ESP half of the port taken as not there (provider gone, or ESP not taken
-- part in): nothing armed, engaged or protecting
local function clear_esp()
    E.available, E.armed, E.roll = false, false, false
    E.overspeed, E.underspeed = false, false
    E.pitch, E.pitch_dir = false, 0
end

local function read_speed_protect()
    -- port v2: bit 1 high-speed, bit 2 low-speed, autopilot on or off
    local sp = getv2("speed_protect")
    E.overspeed = sp % 2 == 1
    E.underspeed = math.floor(sp / 2) % 2 == 1
end

-- att_ok: a unit showing a page has a valid attitude; now: sim time
-- (total_running_time_sec) for the heartbeat
function E.update(att_ok, now)
    if not E.found then
        wait = wait - 1
        if wait > 0 then return end
        wait = LOOKUP_EVERY
        if not lookup() then return end
    end
    -- a provider that stopped leaves its datarefs reading 0
    local pv = geti("port_version")
    if pv < NEED_VERSION then
        E.found, E.live = false, false
        clear_esp()
        drop_v2()
        return
    end
    E.found, E.live = true, true
    if pv ~= seen_version then
        -- a new or swapped provider: the v1 names again too
        if seen_version ~= nil then lookup() end
        lookup_v2(pv)
    end
    if cfg.esp == 0 then
        -- the port is read for the v2 fields only: no heartbeat, no ESP
        clear_esp()
        if E.has("speed_protect") then read_speed_protect() end
        return
    end
    if att_ok then pcall(XPLMSetDataf, h.attitude_heartbeat, now or 0) end
    E.available = geti("esp_available") ~= 0
    E.enabled = geti("esp_enabled") ~= 0
    E.armed = geti("esp_armed") ~= 0
    -- bitmask (port v1): 1 roll, 2 pitch, 4 overspeed, 8 underspeed
    local eng = geti("esp_engaged")
    E.roll = eng % 2 == 1
    E.pitch = math.floor(eng / 2) % 2 == 1
    E.pitch_dir = 0
    if E.pitch and h.esp_pitch_force ~= nil then
        local okf, f = pcall(XPLMGetDataf, h.esp_pitch_force)
        if okf and f and f > 0.01 then E.pitch_dir = 1
        elseif okf and f and f < -0.01 then E.pitch_dir = -1 end
    end
    if E.has("speed_protect") then
        read_speed_protect()
    else
        E.overspeed = math.floor(eng / 4) % 2 == 1
        E.underspeed = math.floor(eng / 8) % 2 == 1
    end
    local ok, lim = pcall(XPLMGetDataf, h.esp_roll_limit)
    if ok and lim and lim > 0 then E.roll_limit = lim end
end

return E
