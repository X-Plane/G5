-- g5_esp.lua: the G5's side of ESP (Electronic Stability & Protection,
-- Pilot's Guide 3.5).
--
-- ESP is the autopilot's function. One provider package in the aircraft
-- (AFCS_ESP, a separate script package) runs it behind the laminar/afcs/ port
-- (port version 1). The G5 only shows it: the ESP
-- menu tile, the Roll Limit Indicators, the pitch engagement chevrons, "ESP
-- OFF" and the MAXSPD / MINSPD tag. While a unit has a
-- valid attitude the G5 writes the port's attitude heartbeat, so the
-- provider can arm.
--
-- Takes part only with ap_option = esp (config.esp = 1). No provider (or an
-- older port version) = no ESP on the G5; the G5 never runs ESP itself.

local U, cfg

local PORT = "laminar/afcs/"
local NEED_VERSION = 1
local LOOKUP_EVERY = 20     -- frames between lookups while there is no port

local E = {
    found = false,      -- the port is there (and new enough)
    available = false,  -- laminar/afcs/esp_available
    enabled = true,     -- the pilot's switch, as the provider holds it
    armed = false,
    roll = false,       -- roll protection engaged (the marks turn yellow)
    -- airspeed protection engaged: MAXSPD / MINSPD on the PFD (Pilot's Guide
    -- 3.4.2, 3.5.3). This is the ESP half only (autopilot off). With the
    -- autopilot engaged the GFC 500 protects the speed too, but port v1 has
    -- no field for that (esp_engaged is 0 while the AP is engaged, and
    -- X-Plane has no AP speed-protection dataref); it needs a port v2 field
    -- from the AP / ESP provider, e.g. laminar/afcs/speed_protect. The G5
    -- does not work it out itself.
    overspeed = false,  -- esp_engaged bit 4: high-speed protection, nose up
    underspeed = false, -- esp_engaged bit 8: low-speed protection, nose down
    -- pitch protection engaged (esp_engaged bit 2): the pitch engagement
    -- chevrons (Pilot's Guide Rev M 3.5.2, figure 3-30). pitch_dir is the
    -- direction ESP is pushing the nose, from the provider's esp_pitch_force
    -- (+1 nose up: chevrons point up, -1 nose down: they point down, 0 = the
    -- provider gave no direction; the PFD then points them against the pitch)
    pitch = false,
    pitch_dir = 0,
    roll_limit = 45,
}

local NAMES = { "port_version", "esp_available", "esp_enabled", "esp_armed",
    "esp_engaged", "esp_roll_limit", "attitude_heartbeat" }
-- esp_pitch_force is in port v1 but only the chevron direction
-- needs it: a provider without it still gets everything else
local OPTIONAL = { "esp_pitch_force" }
local h = {}
local wait = 0

function E.init(util, config)
    U, cfg = util, config
    E.reset()
end

function E.reset()
    E.found, E.available, E.enabled, E.armed, E.roll = false, false, true, false, false
    E.overspeed, E.underspeed = false, false
    E.pitch, E.pitch_dir = false, 0
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

-- shown at all: this G5 takes part and the provider says ESP can run
function E.usable()
    return cfg.esp ~= 0 and E.found and E.available
end

-- the PFD menu item: the provider holds the switch; show the new state at once
function E.toggle()
    if not E.found then return end
    E.enabled = not E.enabled
    pcall(XPLMSetDatai, h.esp_enabled, E.enabled and 1 or 0)
end

-- att_ok: a unit showing a page has a valid attitude; now: sim time
-- (total_running_time_sec) for the heartbeat
function E.update(att_ok, now)
    if cfg.esp == 0 then
        E.found, wait = false, 0    -- look again at once when switched on
        return
    end
    if not E.found then
        wait = wait - 1
        if wait > 0 then return end
        wait = LOOKUP_EVERY
        if not lookup() then return end
    end
    -- a provider that stopped leaves its datarefs reading 0
    if geti("port_version") < NEED_VERSION then
        E.found, E.available, E.armed, E.roll = false, false, false, false
        E.overspeed, E.underspeed = false, false
        E.pitch, E.pitch_dir = false, 0
        return
    end
    E.found = true
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
    E.overspeed = math.floor(eng / 4) % 2 == 1
    E.underspeed = math.floor(eng / 8) % 2 == 1
    local ok, lim = pcall(XPLMGetDataf, h.esp_roll_limit)
    if ok and lim and lim > 0 then E.roll_limit = lim end
end

return E
