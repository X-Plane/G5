--[[ XLua 2.0 ]]
--[[
*****************************************************************************************
* Program Script Name : Garmin G5 (2026, XPLM 4 Panel Graphics)
*
* Author Name         : Eric Xu
*
* Drawn directly into an ATTR_cockpit_device screen ("laminar_g5") with the
* XPLMPanelGraphics API. Replaces the 2024-2025 Plane Maker generic-instrument
* G5 (G5.System + ~160 PNG layers in the .acf).
*
* Files (same folder):
*   G5.lua          this master script: lifecycle, devices, datarefs, commands
*   g5_util.lua     helpers          g5_sim.lua     sim dataref snapshot
*   g5_gfx.lua      vector layer     g5_system.lua  power / battery / backlight
*   g5_input.lua    knob + menus     g5_pfd.lua     PFD page
*   g5_hsi.lua      HSI page         g5_ui.lua      menus, popups, dialogs
*   g5_fail.lua     validity, failures, alignment, system messages
*   g5_config.lua   configuration mode (pages, calibrations)
*   g5_esp.lua      ESP display side: reads the laminar/afcs/ port (AFCS_ESP)
*   g5_assets.lua   PNG manifest     Textures/      1:1 artwork from the old G5
*   g5_rfont_data.lua  raster font metrics (generated; glyphs in Textures/RFont)
*   settings.ini    user settings: power, page, units
*   config.ini      per-aircraft settings
*   state_unit<n>.ini  written by the plugin: battery state and the values
*                   changed in configuration mode (override the two above)
*****************************************************************************************
*        Copyright (c) 2024-2026 Eric Xu / Laminar Research. MIT License, see LICENSE.
*****************************************************************************************
--]]

require("XPLMDefs")
require("XPLMDataAccess")
require("XPLMDisplay")
require("XPLMPanelGraphics")
require("XPLMPlanes")
require("XPLMProcessing")
require("XPLMUtilities")

local DESIGN_W, DESIGN_H = 320, 240
local DEVICE_ID = "laminar_g5"
local PREFIX = "laminar/g5/"
local SCRIPT_NAME = "G5"

-----------------------------------------------------------------------------
-- Configuration defaults (overridden by config.ini, see comments there)
-----------------------------------------------------------------------------

local config = {
    startup_page = 1,
    auto_power_on = 1,
    power_bus = 0,
    power_min_volts = 10,
    power_lost_countdown_s = 45,
    auto_power_off = "on_ground",
    power_off_hold_s = 5,
    boot_logo_s = 2.0,
    shutdown_fade_s = 0.4,
    magnetometer_on_bus = 1,

    -- power-up / AHRS (g5_fail.lua)
    att_kwl_s = 0,
    att_kwl_recover_s = 10,
    align_s = 11,
    air_init_s = 0,
    hdg_init_s = 0,
    gps_init_s = 20,
    magnetometer = 1,
    gps_internal = 1,
    gps_external = 1,
    nav_interface = "arinc",
    nav_count = 2,
    gpss_menu = 0,      -- derived from ap_option (not a config.ini key any more)
    hsi_page = 1,
    unusual_revert = 1,
    show_wind = 1,
    show_density_alt = 1,
    ext_fail_mag = "rel_g_magmtr",
    ext_fail_gps = "rel_gps",
    ext_fail_nav1 = "rel_nav1, rel_navcom1",
    ext_fail_nav2 = "rel_nav2, rel_navcom2",
    ext_fail_oat = "rel_g_oat",
    ext_fail_ahrs = "",
    ext_fail_airdata = "",
    ext_fail_gps_rx = "",
    ext_fail_mag_degraded = "",

    -- battery (g5_system.lua)
    battery_installed = 1,
    battery_wh = 6.8,
    battery_health = 1.0,
    battery_initial_pct = 95,
    power_base_w = 1.6,
    power_backlight_w = 1.6,
    battery_charge_c = 0.6,
    battery_cv_pct = 80,
    battery_charge_eff = 0.85,
    battery_temp_offset = 15,
    battery_temp_tau_s = 1200,
    battery_op_temp_min = -20,
    battery_op_temp_max = 60,
    battery_charge_temp_min = 0,
    battery_charge_temp_max = 45,
    battery_low_pct = 20,
    battery_cutoff_pct = 1,
    critical_batt_s = 3,
    show_battery = "on_battery",
    bus_load = 1,
    magnetometer_bus = -1,
    gad_bus = -1,

    backlight_initial = 0.78,
    backlight_auto_initial = 1,
    backlight_min = 0.05,
    -- configuration mode Backlight page (Installation Manual 5.x tables,
    -- "Default"): Maximum Display Brightness caps the level (Auto and the
    -- knob); Filter Time Constant smooths the photocell in Auto, s (0 = none)
    backlight_max = 1.0,
    backlight_filter_s = 0,
    -- Minimum / Maximum Photocell Input ("Default" in the Installation Manual
    -- tables): the two ends of the Auto curve on the photocell axis, in % of the
    -- photocell reading (100 x the ambient level ^ 0.25, about 39 % at night,
    -- 100 % in daylight). 0 / 100 = today's curve (backlight_neutral at the
    -- bottom, 100 % at the top); g5_system.lua Sys.auto_level
    photocell_min = 0,
    photocell_max = 100,
    backlight_neutral = 0.78,
    backlight_doubling = 0.2,
    ambient_min = 0.002,
    brightness_rheostat = 6,

    speed_unit = 0,
    temp_unit = 0,
    baro_unit = 0,      -- 0 inHg, 1 hPa, 2 mb (settings.ini / configuration mode Units page)
    -- configuration mode Units page (Installation Manual 6.3.6): altitude
    -- 0 feet, 1 meters; vertical speed 0 ft/min, 1 m/s
    alt_unit = 0,
    vs_unit = 0,
    -- configuration mode Airspeed page (knots): 0 = the aircraft's own (acf);
    -- VR 0 = not shown (no .acf value)
    vx = 0,
    vy = 0,
    va = 0,
    vg = 0,
    vne = 0,
    vno = 0,
    vso = 0,
    vs1 = 0,
    vfe = 0,
    vr = 0,
    vmc = 0,
    vyse = 0,
    gs_unit = -1,
    pitch_cal = 0,
    roll_cal = 0,
    nav_data = 1,
    -- Selected Course (Installation Manual 5.x Navigation page, note "Select
    -- Disabled if mechanical CDI or HSI is connected to the navigator,
    -- otherwise Enabled"): 1 = the G5 sets the course (Course / OBS menu item,
    -- writes hsi_obs), 0 = it does not
    selected_course = 1,
    -- VNAV Deviation Scale (Installation Manual 5.3.1 note 5): the full-scale
    -- vertical deviation of the VNAV chevron, ft, at the outer dot: 500 | 1000
    vnav_dev_scale = 500,
    vib_limit_g = 0.3,

    -- Autopilot option: esp (ESP from a Garmin autopilot, Pilot's Guide 3.5;
    -- the ESP itself is the AFCS_ESP provider's, g5_esp.lua) | gpss (GPS
    -- steering for an analog autopilot, 4.1) | none. A real G5 never has both:
    -- ESP needs a Garmin autopilot and the GPSS item is never shown with one.
    ap_option = "esp",
    esp = 0,            -- derived from ap_option
    speed_tape_min = 30,
    speed_tape_floor = 20,
    speed_alive_hyst = 2,
    speed_tape_range = 60,
    speed_trend_s = 6,
    pitch_px_per_deg = 3.6,
    -- configuration mode Attitude page "Pitch Display": normal (3.6 px / deg,
    -- "10" labels) | expanded (our name for the second option of Pilot's
    -- Guide figures 2-5 / 2-6: about 7.4 px / deg, "5" / "10" labels)
    pitch_display = "normal",
    vsi_scale = 15,

    show_tas = 1,
    show_oat = 1,
    show_gs = 1,
    show_hdg_box = 0,
    -- Heading Bug Auto Sync Mode (Pilot's Guide Rev M 3.3.5.2.1, "if
    -- configured"; the manuals do not say where the real unit configures it,
    -- so: this key and a row on the configuration page Flight Controls).
    -- 0 = off: the Heading menu and the knob hold behave as before
    hdg_sync = 0,
    show_ap_bar = 1,
    ap_bar_reserved = 1,
    afcs_pft_s = 5,
    fd_cue = "single",
    roll_pointer = "ground",
    std_turn_ref = 1,

    bearing1_source = 0,
    bearing2_source = 0,
    -- pilot settings changed on the unit are written back here (save_setting):
    -- HSI Setup (Wind Vector, HSI Size) and the PFD menu Pitch offset
    wind_vector = "speed_dir",   -- off | speed_dir | head_xwind
    hsi_size = "normal",         -- normal | expanded
    pitch_offset = 0,            -- deg, attitude display offset (PFD menu "Pitch")

    screen_scale = 1,
    -- 3D device framebuffer = the whole 2048x1024 G5 texture, 1:1 to its pixels;
    -- the 320x240 screen UV island is at px x 1032..1352, y 8..248 from the top
    -- (the screen UV island of the G5 model), i.e. this origin (y up)
    screen_fb_w = 2048,
    screen_fb_h = 1024,
    screen_origin_x = 1032,
    screen_origin_y = 776,
    content_clip = 1,
    lcd_lines = 0.15,
    lcd_period = 3,
    enable_popup = 1,
    popup_initial = 0,
    font_bold = "Resources/fonts/Roboto-Bold.ttf",
    font_cond = "Resources/fonts/RobotoCondensed-Regular.ttf",
    test_pattern = 0,

    -- knob / button clicks done by the plugin (G5.obj is not the cockpit object)
    pick_mode = 1,
    pick_pass_misses = 0,
    pick_debug = 0,

    -- number of G5 units: auto = the G5.obj / G5_2.obj attached in the .acf;
    -- 1 = attitude only (G5.obj), 2 = + HSI below (G5_2.obj)
    units = "auto",
    -- 0 = master, 1 = slave (per unit: unit<n>_role; unit 2 is a slave)
    role = 0,
    -- GFC 500 installed: auto = what GFC500.System writes into
    -- laminar/gfc500/installed; 0 / 1 = fixed
    gfc500 = "auto",
    -- per-unit values, set from settings.ini (unit_config picks unit<n>_<key>)
    unit2_startup_page = 2,
    unit2_auto_power_on = 1,
}

-- Keys a unit can override with unit<n>_<key> in config.ini (the dual
-- installation tables give unit 2 its own bus, battery, GPS and backlight
-- settings). "" = not set: the shared value is used.
local PER_UNIT = { "power_bus", "battery_installed", "show_battery", "auto_power_off",
    "gps_internal", "backlight_auto_initial", "backlight_initial", "backlight_max",
    "backlight_filter_s", "photocell_min", "photocell_max", "battery_wh",
    "battery_health", "battery_initial_pct", "unusual_revert", "hsi_page", "role" }
for _, k in ipairs(PER_UNIT) do
    for n = 1, 2 do
        if config["unit" .. n .. "_" .. k] == nil then config["unit" .. n .. "_" .. k] = "" end
    end
end
-- real dual installations disable unit 2's own GPS receiver: it gets GPS
-- from unit 1 over CAN (Installation Manual dual tables)
config.unit2_gps_internal = "0"
-- the second unit (the HSI) is a slave of the attitude unit
config.unit2_role = "1"
-- Automatic Declutter (back to the PFD in an unusual attitude): enabled on the
-- attitude unit, disabled on the HSI unit (Installation Manual dual tables)
config.unit2_unusual_revert = "0"

-- settings.ini: the user-facing settings (power, page, units). Strings as
-- typed; apply_settings() turns them into the config values above.
local settings = {
    unit1_power = "on",
    unit2_power = "on",
    unit1_page = "AI",
    unit2_page = "HSI",
    units = "imperial",
    speed_unit = "",
    baro_unit = "",
    temp_unit = "",
}

-- value tables: settings word -> config number
local POWER = { on = 1, off = 0, ["1"] = 1, ["0"] = 0, yes = 1, no = 0, ["true"] = 1, ["false"] = 0 }
local PAGE = { ai = 1, pfd = 1, attitude = 1, ["1"] = 1, hsi = 2, ["2"] = 2 }
local SPEED = { kt = 0, kts = 0, knots = 0, mph = 1, kmh = 2, ["km/h"] = 2, kph = 2 }
-- mb = hPa in value, but labelled "mb" (Pilot's Guide 2.1.3.1); until
-- 2026-10-29 "mb" gave hPa
local BARO = { inhg = 0, hpa = 1, mb = 2 }
local TEMP = { f = 0, c = 1 }
local PRESETS = {
    imperial = { speed_unit = 0, baro_unit = 0, temp_unit = 0 },
    metric   = { speed_unit = 2, baro_unit = 1, temp_unit = 1 },
}

-----------------------------------------------------------------------------
-- Module loading. Helpers are loaded with loadfile() from this folder and run
-- in this script's environment; `require` is the fallback.
-----------------------------------------------------------------------------

local script_dir = ""

local units
local aircraft_dir = ""

local function normalize(p) return (p or ""):gsub("\\", "/") end

local function discover_script_dir()
    local info = debug and debug.getinfo and debug.getinfo(1, "S")
    local src = info and info.source or ""
    if string.sub(src, 1, 1) == "@" then
        local d = normalize(string.sub(src, 2)):match("^(.*)/[^/]*$")
        if d and d ~= "" then return d end
    end
    local model = XPLMGetNthAircraftModel(0)
    local acf = ""
    if type(model) == "table" then acf = normalize(model.outPath or model[2] or "") end
    aircraft_dir = acf:match("^(.*)/[^/]*$") or "."
    for _, sub in ipairs({ "plugins/xlua/scripts/" .. SCRIPT_NAME, "plugins/xlua2/scripts/" .. SCRIPT_NAME }) do
        local d = aircraft_dir .. "/" .. sub
        local f = io.open(d .. "/" .. SCRIPT_NAME .. ".lua", "r")
        if f then
            f:close()
            return d
        end
    end
    return aircraft_dir .. "/plugins/xlua/scripts/" .. SCRIPT_NAME
end

local function load_module(name)
    local path = script_dir .. "/" .. name .. ".lua"
    if loadfile then
        local chunk, err = loadfile(path)
        if chunk then
            if setfenv and getfenv then setfenv(chunk, getfenv(1)) end
            return chunk()
        end
        print("[G5 XLua2] loadfile failed: " .. tostring(err))
    end
    if package and package.path and not string.find(package.path, script_dir, 1, true) then
        package.path = script_dir .. "/?.lua;" .. package.path
    end
    return require(name)
end

script_dir = discover_script_dir()

-- shared by all units
local A   = load_module("g5_assets")
A.RFONT   = load_module("g5_rfont_data")
local U   = load_module("g5_util")
local G   = load_module("g5_gfx")
local Sim = load_module("g5_sim")
local Esp = load_module("g5_esp")

-- per-unit modules: every call runs the file again, so each unit gets its own
-- module state (require would hand back the cached first instance)
local function load_fresh(name)
    local path = script_dir .. "/" .. name .. ".lua"
    local chunk, err = loadfile(path)
    if not chunk then error("loadfile " .. path .. ": " .. tostring(err)) end
    if setfenv and getfenv then setfenv(chunk, getfenv(1)) end
    return chunk()
end

local log = U.log
local D = Sim.D

-----------------------------------------------------------------------------
-- Runtime handles
-----------------------------------------------------------------------------

units = {}
local flight_loop = nil
local heartbeat = 0
local gfc_installed = 0
local error_seen = {}     -- message -> how often it came up
local error_keys = 0      -- distinct messages in error_seen
local ERROR_KEYS_MAX = 200
local global_dr = {}

-- Each distinct message is logged once, then every 600th repeat (two errors
-- that alternate every frame must not flood Log.txt). A message with a
-- changing number in it is a new key every frame: the table starts over at
-- ERROR_KEYS_MAX keys so it cannot grow for the whole session.
local function report_error(where, err)
    local msg = where .. ": " .. tostring(err)
    local n = error_seen[msg]
    if n == nil then
        if error_keys >= ERROR_KEYS_MAX then
            error_seen, error_keys = {}, 0
        end
        error_keys = error_keys + 1
        n = 0
    end
    n = n + 1
    error_seen[msg] = n
    if n == 1 or n % 600 == 0 then
        log("ERROR " .. msg .. (n > 1 and (" (x" .. n .. ")") or ""))
    end
end

-----------------------------------------------------------------------------
-- Units. Unit 1 keeps the original names (laminar_g5, laminar/g5/, G5.obj);
-- unit n > 1 adds _n (laminar_g5_2, laminar/g5_2/, G5_2.obj).
-----------------------------------------------------------------------------

local function unit_config(n)
    local c = {}
    for k, v in pairs(config) do c[k] = v end
    if n > 1 then
        for _, key in ipairs({ "startup_page", "auto_power_on" }) do
            local v = config["unit" .. n .. "_" .. key]
            if v ~= nil then c[key] = v end
        end
    end
    for _, key in ipairs(PER_UNIT) do
        local v = config["unit" .. n .. "_" .. key]
        if v ~= nil and v ~= "" then
            if type(config[key]) == "number" then
                c[key] = tonumber(v) or config[key]
            else
                c[key] = string.lower(tostring(v))
            end
        end
    end
    return c
end

-- Persistent unit state (battery charge, temperature): state_unit<n>.ini next
-- to the scripts, written on unload, on a new flight and every minute.
local function state_path(u)
    return script_dir .. "/state_unit" .. u.n .. ".ini"
end

-- every key g5_config.lua can change, read as text ("" = not in the file)
local function read_state_file(n, keys)
    local s = { batt_pct = -1, batt_temp = -999 }
    for k in pairs(keys) do s[k] = "" end
    U.read_ini(script_dir .. "/state_unit" .. n .. ".ini", s)
    return s
end

-- Battery state, and the configuration mode values: the unit's own ("unit")
-- from its file, the shared ones from unit 1's file. They are applied over
-- config.ini / settings.ini before the unit starts.
local function load_state(u)
    local keys = u.Cfg.KEYS
    local own = read_state_file(u.n, keys)
    local master = (u.n == 1) and own or read_state_file(1, keys)
    if own.batt_pct >= 0 then u.st.batt_pct = U.clamp(own.batt_pct, 0, 100) end
    if own.batt_temp > -999 then u.st.batt_temp = own.batt_temp end
    u.cfg_set = {}
    for k, scope in pairs(keys) do
        local v = ((scope == "shared") and master or own)[k]
        if v ~= nil and v ~= "" then
            if type(u.cfg[k]) == "number" then v = tonumber(v) else v = string.lower(v) end
            if v ~= nil then
                u.cfg[k] = v
                if scope ~= "shared" or u.n == 1 then u.cfg_set[k] = true end
            end
        end
    end
end

local function save_state(u)
    if u.cfg.installed == 0 then return end     -- not in the aircraft: no state file
    local out = {
        { "batt_pct", string.format("%.2f", u.st.batt_pct or 0) },
        { "batt_temp", string.format("%.1f", u.st.batt_temp or 20) },
    }
    local keys = {}
    for k in pairs(u.cfg_set or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = u.cfg[k]
        out[#out + 1] = { k, (type(v) == "number") and string.format("%g", v) or tostring(v) }
    end
    U.write_ini(state_path(u), out, "Garmin G5 unit " .. u.n
        .. " state (written by the plugin; configuration mode values override config.ini)")
end

-- settings.ini -> config. A value that is not in its table is logged and
-- the default is kept.
local function apply_settings()
    local function pick(key, tbl, default)
        local v = string.lower(settings[key] or "")
        if v == "" then return default end
        if tbl[v] ~= nil then return tbl[v] end
        log("settings.ini: " .. key .. " = '" .. settings[key] .. "' is not valid, using the default")
        return default
    end
    config.auto_power_on = pick("unit1_power", POWER, 1)
    config.unit2_auto_power_on = pick("unit2_power", POWER, 1)
    config.startup_page = pick("unit1_page", PAGE, 1)
    config.unit2_startup_page = pick("unit2_page", PAGE, 2)
    local preset = PRESETS[string.lower(settings.units)]
    if preset == nil then
        log("settings.ini: units = '" .. settings.units .. "' is not valid, using imperial")
        preset = PRESETS.imperial
    end
    config.speed_unit = pick("speed_unit", SPEED, preset.speed_unit)
    config.baro_unit = pick("baro_unit", BARO, preset.baro_unit)
    config.temp_unit = pick("temp_unit", TEMP, preset.temp_unit)
    log(string.format("settings: power %d/%d, page %d/%d, speed %d, baro %d, temp %d",
        config.auto_power_on, config.unit2_auto_power_on, config.startup_page,
        config.unit2_startup_page, config.speed_unit, config.baro_unit, config.temp_unit))
end

-- Which G5s this aircraft has (units = auto): the .acf attachments of
-- G5.obj (unit 1) and G5_2.obj (unit 2), the same records g5_pick.lua reads.
-- A unit whose object is not attached is created but never powers up, so a
-- lone G5_2.obj still works (it takes over as master). units = 1 / 2 in
-- config.ini skips the scan.
local function acf_path()
    local model = XPLMGetNthAircraftModel(0)
    local acf = type(model) == "table" and U.unwrap_string(model.outPath or model[2]) or tostring(model or "")
    return U.normalize_path(acf)
end

local function detect_units()
    local want = string.lower(tostring(config.units))
    if want == "1" or want == "2" then
        local n = tonumber(want)
        return n, { true, true }
    end
    local f = io.open(acf_path(), "r")
    if not f then
        log("units = auto: cannot read the .acf, assuming one unit")
        return 1, { true, false }
    end
    local found = { false, false }
    for line in f:lines() do
        local file = line:match("^P _obja/%d+/_v10_att_file_stl (.-)%s*$")
        if file then
            local base = string.lower(file:gsub("\\", "/"):match("([^/]*)$") or "")
            if base == "g5.obj" then found[1] = true end
            if base == "g5_2.obj" then found[2] = true end
        end
    end
    f:close()
    local n = found[2] and 2 or 1
    if not found[1] and not found[2] then
        log("units = auto: no G5.obj / G5_2.obj attached in the .acf, assuming one unit")
        found[1] = true
    end
    log(string.format("units = auto: G5.obj %s, G5_2.obj %s -> %d unit(s)",
        found[1] and "attached" or "not attached", found[2] and "attached" or "not attached", n))
    return n, found
end

-- V-speed references that X-Plane has no dataref for (Plane Maker writes
-- them only into the .acf): D.vx / vy / va / vg, knots, 0 = not in the file.
-- configuration mode values (> 0) override them; g5_pfd.lua drops a marker
-- whose value is out of range.
local ACF_VSPEEDS = { vx = "_Vx_kts", vy = "_Vy_kts", va = "_Va_kts", vg = "_Vbg_kts" }

local function read_acf_vspeeds()
    local by_name = {}
    for key, name in pairs(ACF_VSPEEDS) do
        D[key] = 0
        by_name[name] = key
    end
    local f = io.open(acf_path(), "r")
    if not f then
        log("V-speeds: cannot read the .acf, Vx / Vy / Va / Vg not shown")
        return
    end
    for line in f:lines() do
        local name, v = line:match("^P acf/(_V%w+_kts) (%S+)")
        if name and by_name[name] then D[by_name[name]] = tonumber(v) or 0 end
    end
    f:close()
    log(string.format("V-speeds (.acf, kt): Vx %g, Vy %g, Va %g, Vg %g", D.vx, D.vy, D.va, D.vg))
end

-- A pilot setting changed on the unit (PFD menu Pitch, HSI Setup): applied to
-- every unit and written to config.ini, so it is there at the next load. Only
-- that key's line is rewritten (U.ini_set); the rest of the file is kept.
local function save_setting(key, value)
    config[key] = value
    for _, u in ipairs(units or {}) do u.cfg[key] = value end
    local txt = (type(value) == "number") and string.format("%g", value) or tostring(value)
    local ok, err = pcall(U.ini_set, script_dir .. "/config.ini", key, txt)
    if not ok or err == false then
        log("config.ini: could not save " .. key .. " = " .. txt .. " (" .. tostring(err) .. ")")
    end
end

local function make_unit(n)
    local sfx = (n == 1) and "" or ("_" .. n)
    local u = {
        n = n,
        prefix = "laminar/g5" .. sfx .. "/",
        device = DEVICE_ID .. sfx,
        obj = script_dir .. "/3D/G5" .. sfx .. ".obj",
        name = (n == 1) and "Garmin G5" or ("Garmin G5 #" .. n),
        cfg = unit_config(n),
        popup_visible = false,
        commands = {}, handlers = {}, drs = {},
    }
    u.Sys = load_fresh("g5_system")
    u.Fail = load_fresh("g5_fail")
    u.In  = load_fresh("g5_input")
    u.Pfd = load_fresh("g5_pfd")
    u.Hsi = load_fresh("g5_hsi")
    u.UI  = load_fresh("g5_ui")
    u.Pick = load_fresh("g5_pick")
    u.Cfg = load_fresh("g5_config")
    u.Sys.init(U, Sim, u.cfg)
    u.Fail.init(U, u.Sys, u.cfg)
    u.In.init(U, Sim, u.Sys, u.cfg, u.Fail)
    u.Pfd.init(U, G, u.Sys, u.cfg)
    u.Hsi.init(U, G, u.Sys, u.Pfd, u.cfg)
    u.UI.init(U, G, u.Sys, u.In, u.Pfd, u.cfg, u.Fail)
    u.Hsi.brg_name = u.UI.brg_name
    -- no other G5 installed (HSI-only installation test, Installation Manual 6.3.9)
    u.Hsi.sole_unit = function()
        for _, o in ipairs(units) do
            if o ~= u and (o.cfg.installed or 1) ~= 0 then return false end
        end
        return true
    end
    u.Pick.init(U, u.cfg)
    u.Cfg.init(U, G, u.Sys, u.Fail, u.Pfd, u.cfg)
    u.In.Cfg = u.Cfg
    u.In.Esp, u.Pfd.Esp, u.UI.Esp = Esp, Esp, Esp
    u.In.save_setting = save_setting
    u.Cfg.hooks = {
        n = n,
        n_units = function() return #units end,
        unit_ok = function(k)
            local o = units[k]
            return o ~= nil and o.st.mode >= o.Sys.PFD and not o.st.fail.hardware
        end,
        gfc = function() return gfc_installed ~= 0 end,
        -- a confirmed change: applied at once, saved to the state file
        set = function(key, value, scope)
            if scope == "shared" then
                for _, o in ipairs(units) do o.cfg[key] = value end
                units[1].cfg_set[key] = true
                pcall(save_state, units[1])
            else
                u.cfg[key] = value
                u.cfg_set[key] = true
                pcall(save_state, u)
            end
            log(string.format("unit %d config: %s = %s", n, key, tostring(value)))
        end,
    }
    u.st = u.Sys.st
    u.st.batt_pct = u.cfg.battery_initial_pct
    load_state(u)
    u.Sys.reset()
    u.Fail.reset()
    return u
end

-----------------------------------------------------------------------------
-- Software version mismatch (Pilot's Guide table 1-2, AFMS 7-2: "Cross fill
-- of baro, heading and altitude bugs is disabled"). All units read and write
-- one set of sim datarefs, so cross-fill is normally implicit. While the
-- mismatch is on (link_units, cross_fill), the acting master keeps the sim
-- datarefs (the autopilot and X-Plane's altimeter follow them) and every
-- other unit has private copies, u.priv = { baro, hdg_bug, alt_bug }, taken
-- when the mismatch starts. g5_input writes a unit's knob edits there
-- (In.priv); view_begin / view_end put them into the shared D around the
-- unit's update, drawing and commands, with its altitude corrected for its
-- own baro. When the mismatch clears the copies are dropped and the unit
-- shows the sim's (the master's) values again.
-----------------------------------------------------------------------------

local FT_PER_INHG = 1000     -- altimeter: ~1000 ft per inHg near sea level

-- the unit's view of D; returns what to give back to view_end (nil: none)
local function view_begin(u)
    local p = u.priv
    if p == nil then return nil end
    local saved = { D.baro, D.hdg_bug, D.alt_bug, D.alt }
    D.alt = D.alt + (p.baro - D.baro) * FT_PER_INHG
    D.baro, D.hdg_bug, D.alt_bug = p.baro, p.hdg_bug, p.alt_bug
    return saved
end

local function view_end(saved)
    if saved then D.baro, D.hdg_bug, D.alt_bug, D.alt = saved[1], saved[2], saved[3], saved[4] end
end

-----------------------------------------------------------------------------
-- VFR CDI scale (Pilot's Guide p.23 table 2-1: "VFR" with 0.25 / 1.25 /
-- 5.00 nm; p.26: with a GPS the CDI full scale is the GPS's distance). The
-- guide does not say when which applies; our rule follows X-Plane's current
-- GPS scale: X-Plane full scale (gps_hdef_nm_per_dot x 2.5 dots) up to
-- 0.5 nm -> 0.25 nm, up to 1.5 nm -> 1.25 nm, above -> 5.00 nm. The full
-- scale is the main test rather than gps_cdi_sensitivity because in the
-- the C172 X-Plane's CDI phase stays TERM on the final while the navigator's
-- nm per dot shrinks; without nm per dot the phase decides (OCN / ENR 5.00,
-- TERM / DPRT / MAPR 1.25, approach phases 0.25). A phase change jumps to the
-- new scale (no smoothing, our rule). The cross-track distance is
-- |hdef| x nm per dot; with X-Plane's needle at its stop a non-zero gps_xtk
-- is taken if it is larger (en route the VFR full scale is wider than
-- X-Plane's), but not while a plugin drives the GPS CDI (override_gps:
-- nothing writes gps_xtk then). X-Plane 12.4 always reports gps_xtk as 0.0
-- (never nil), which counts as not available: the fallback is the distance
-- to the waypoint x sin(bearing - desired track). The sign is hdef's.
-- Returns the deflection in dots for the draw, or nil when no distance can
-- be had (left unscaled).
-----------------------------------------------------------------------------

local VFR = {
    FS_APR = 0.25, FS_TERM = 1.25, FS_ENR = 5.00,   -- nm (Pilot's Guide table 2-1)
    -- X-Plane full scale (nm) at which the next VFR scale takes over (our
    -- rule; measured in X-Plane 12.4.4: terminal 1.0 nm, en route 2.0 nm,
    -- approach 0.3 nm full scale)
    XP_FS_APR = 0.99, XP_FS_TERM = 1.5,
    -- |hdef| from which X-Plane's needle counts as at its stop, so gps_xtk
    -- may say more (full scale 2.5 dots; measured in X-Plane 12.4.4: hdef
    -- stops at 2.5 dots and gps_xtk stays 0)
    XP_PEG_DOTS = 2.49,
    logged = false,
}

local function vfr_dots(D)
    local npd = D.gps_nm_dot or 0
    local fs
    if npd > 0 then
        local fs_xp = npd * 2.5
        fs = (fs_xp <= VFR.XP_FS_APR and VFR.FS_APR) or (fs_xp <= VFR.XP_FS_TERM and VFR.FS_TERM) or VFR.FS_ENR
    else
        local c = D.gps_cdi or 1
        fs = (c <= 1 and VFR.FS_ENR) or (c <= 4 and VFR.FS_TERM) or VFR.FS_APR
    end
    local hdef = D.hsi_hdef
    -- gps_xtk is 0.0, not nil, in X-Plane 12.4: zero means not available
    local xtk_ok = D.gps_xtk ~= nil and D.override_gps == 0 and math.abs(D.gps_xtk) > 1e-6
    local xtk
    if npd > 0 then
        xtk = math.abs(hdef) * npd
        if math.abs(hdef) >= VFR.XP_PEG_DOTS then
            -- X-Plane's needle is at its stop: gps_xtk if it says anything,
            -- else (it stays 0 in X-Plane 12.4) the distance to the active
            -- waypoint x sin(bearing to it - desired track); magnitude only,
            -- the sign is hdef's and U.angdiff handles the 360 wrap
            local x = xtk_ok and math.abs(D.gps_xtk) or 0
            if x < 1e-6 and D.override_gps == 0 and D.gps_dme > 0 then
                x = D.gps_dme * math.abs(math.sin(math.rad(U.angdiff(D.gps_brg, D.gps_dtk))))
            end
            xtk = math.max(xtk, x)
        end
    elseif xtk_ok then
        xtk = math.abs(D.gps_xtk)
    else
        if not VFR.logged then
            VFR.logged = true
            log("VFR CDI scale: no gps_hdef_nm_per_dot and no usable gps_xtk, the deflection stays X-Plane's")
        end
        return nil
    end
    local sign = (hdef > 0 and 1) or (hdef < 0 and -1) or 0
    return sign * xtk / fs * 2.5
end

-----------------------------------------------------------------------------
-- Drawing
-----------------------------------------------------------------------------

-- The 3D device framebuffer spans the whole 2:1 texture of G5.obj; the screen
-- UV island is where the 320x240 content goes. The popup device shows its
-- framebuffer as is, so it is exactly 320x240.
local function draw_screen(u, ref)
    local cfg, st, Sys = u.cfg, u.st, u.Sys
    local ox, oy, fw, fh = 0, 0, DESIGN_W, DESIGN_H
    if ref == "3d" then
        ox, oy = cfg.screen_origin_x, cfg.screen_origin_y
        fw, fh = cfg.screen_fb_w, cfg.screen_fb_h
    end
    G.reset_clip()
    G.set_origin(0, 0)
    G.rect(0, 0, fw, fh, G.C.black)
    G.set_origin(ox, oy)
    G.push()
    G.translate(ox, oy)
    if cfg.content_clip ~= 0 then G.clip(0, 0, DESIGN_W, DESIGN_H) end
    G.rect(0, 0, DESIGN_W, DESIGN_H, G.C.black)

    if st.fail.display and cfg.test_pattern == 0 then
        -- dead display (laminar/g5/fail_display): nothing but black
    elseif cfg.test_pattern == 2 then
        -- diagnostic: the whole framebuffer, quadrant colours + coordinates
        if cfg.content_clip ~= 0 then G.unclip() end
        G.pop()
        G.set_origin(0, 0)
        u.UI.framebuffer_pattern(fw, fh)
        G.push()
        if cfg.content_clip ~= 0 then G.clip(0, 0, fw, fh) end
    elseif cfg.test_pattern ~= 0 then
        u.UI.test_pattern()
    elseif st.mode == Sys.BOOT then
        u.UI.boot(st)
    elseif st.mode == Sys.CONFIG then
        u.Cfg.draw(D, st)
        u.UI.draw(D, st)
    elseif st.mode == Sys.PFD or st.mode == Sys.HSI then
        -- this unit's view of the shared snapshot: its pitch / roll
        -- calibration, no CDI / VDI with Navigation Data disabled, no GPS
        -- navigation at all once neither ARINC 429 (GAD 29) nor RS-232 GPS
        -- data come in (Maintenance Manual 5.1.7.1: a source
        -- that is installed but sends nothing is removed): no course needle,
        -- DTK, DIST or GPS bearing pointer. Its own baro and bugs while
        -- cross-fill is off (view_begin)
        local p, r = D.pitch, D.roll
        local gdme, ghas, hdme, hhas = D.gps_dme, D.gps_has_dme, D.hsi_dme, D.hsi_has_dme
        D.pitch, D.roll = p + cfg.pitch_cal, r + cfg.roll_cal
        -- (the same rule masks the mode flashes in Pfd.update)
        local sh, sv, ng = u.Pfd.mask_nav(D, st)
        -- VFR (no ARINC 429 GPS data, g5_fail): the GPS CDI on the VFR
        -- scale, for the draw only (no dataref is written: the autopilot
        -- keeps X-Plane's deviation)
        local hdef = D.hsi_hdef
        if st.gps_vfr and D.hsi_src == 2 and D.hsi_show_h ~= 0 then
            -- protected: an error must not leave the masked state unrestored
            local okv, dots = pcall(vfr_dots, D)
            D.hsi_hdef = (okv and dots) or hdef
        end
        if st.gps_nav_lost then
            D.gps_removed = true
            D.gps_dme, D.gps_has_dme = 0, 0
            if D.hsi_src == 2 then D.hsi_dme, D.hsi_has_dme = 0, 0 end
        end
        local view = view_begin(u)
        local ok, err
        if st.mode == Sys.PFD then
            ok, err = pcall(u.Pfd.draw, D, st, gfc_installed ~= 0)
        else
            ok, err = pcall(u.Hsi.draw, D, st)
        end
        D.pitch, D.roll, D.hsi_hdef = p, r, hdef
        u.Pfd.unmask_nav(D, sh, sv, ng)
        D.gps_dme, D.gps_has_dme, D.hsi_dme, D.hsi_has_dme = gdme, ghas, hdme, hhas
        D.gps_removed = nil
        -- menus and popups in the same view (Select Heading / Altitude)
        if ok then ok, err = pcall(u.UI.draw, D, st) end
        view_end(view)
        if not ok then error(err, 0) end
    end

    -- LCD column structure: thin dark lines over the emitted image, so they
    -- scale with the screen brightness and vanish with the image when it is off
    if ref == "3d" and cfg.lcd_lines > 0 and cfg.test_pattern == 0 then
        local col = G.black_alpha(cfg.lcd_lines)
        local step = math.max(2, math.floor(cfg.lcd_period))
        for x = step - 1, DESIGN_W - 1, step do
            G.rect(x, 0, x + 1, DESIGN_H, col)
        end
    end

    if st.fade > 0 then
        G.rect(0, 0, DESIGN_W, DESIGN_H, G.black_alpha(st.fade))
    end
    if cfg.content_clip ~= 0 then G.unclip() end
    G.pop()
    G.set_origin(0, 0)
end

-- refcon: { unit, "3d" | "popup" }
local function screen_draw_cb(ref)
    local ok, err = pcall(draw_screen, ref[1], ref[2])
    if not ok then
        report_error("draw", err)
        -- keep the transform / scissor stacks balanced after a failure
        pcall(G.unwind)
    end
end

local function bezel_draw_cb(r, g, b, ref)
    G.rect(0, 0, DESIGN_W, DESIGN_H, G.C.black)
end

local function brightness_cb(rheo, ambient, bus, ref)
    local u = ref[1]
    if u.cfg.test_pattern ~= 0 then return 1 end
    -- the popup gets the same level but does not overwrite the unit's
    -- ambient / screen ratio (battery draw, knob ring) with its own ambient
    return u.Sys.screen_brightness(ambient, ref[2] == "popup")
end

-----------------------------------------------------------------------------
-- Popup window
-----------------------------------------------------------------------------

local function lock_popup_aspect(u)
    if not u.popup then return end
    local ok, geom = pcall(XPLMGetAvionicsGeometry, u.popup)
    if not ok or type(geom) ~= "table" then return end
    local left = tonumber(tostring(geom.outLeft)) or 100
    local top = tonumber(tostring(geom.outTop)) or 600
    local bottom = tonumber(tostring(geom.outBottom)) or (top - 360)
    local h = math.abs(top - bottom)
    if h < 120 then h = 360 end
    XPLMSetAvionicsGeometry(u.popup, math.floor(left), math.floor(top),
        math.floor(left + h * DESIGN_W / DESIGN_H), math.floor(top - h))
end

local function set_popup_visible(u, v)
    u.popup_visible = (v and u.cfg.enable_popup ~= 0) and true or false
    if u.popup then
        XPLMSetAvionicsPopupVisible(u.popup, u.popup_visible)
        if u.popup_visible then lock_popup_aspect(u) end
    end
end

-----------------------------------------------------------------------------
-- Commands (per unit)
-----------------------------------------------------------------------------

local BEGIN = XPLMCommandPhase.xplm_CommandBegin

local COMMAND_LIST = {
    { "knob_left",        "knob turn left",           function(u, p) if p == BEGIN then u.In.knob_turn(-1, D) end end },
    { "knob_right",       "knob turn right",          function(u, p) if p == BEGIN then u.In.knob_turn(1, D) end end },
    { "press_knob",       "knob press",               function(u, p) u.In.knob_press(p, D) end },
    { "power_press_knob", "power / backlight button", function(u, p) u.In.power_press(p, D) end },
    { "pfd_mode",         "show PFD page",            function(u, p) if p == BEGIN then u.Sys.set_page(u.Sys.PFD) end end },
    { "hsi_mode",         "show HSI page",            function(u, p) if p == BEGIN then u.Sys.set_page(u.Sys.HSI) end end },
    { "loading_mode",     "power on (boot)",          function(u, p) if p == BEGIN then u.Sys.start_boot() end end },
    { "off_mode",         "power off",                function(u, p) if p == BEGIN then u.Sys.shutdown() end end },
    { "config_mode",      "restart in / exit configuration mode", function(u, p)
        if p == BEGIN then
            if u.st.mode == u.Sys.CONFIG then u.Sys.exit_config() else u.Sys.enter_config() end
        end
    end },
    { "popup_toggle",     "toggle popup window",      function(u, p) if p == BEGIN then set_popup_visible(u, not u.popup_visible) end end },
}

local function create_commands(u)
    for _, c in ipairs(COMMAND_LIST) do
        if c[4] ~= "unit1" or u.n == 1 then
            local fn = c[3]
            u.commands[c[1]] = XPLMCreateCommand(u.prefix .. c[1], u.name .. " " .. c[2])
            u.handlers[c[1]] = function(cmd, phase, ref)
                -- knob edits start from the unit's own values (view_begin)
                local view = view_begin(u)
                local ok, err = pcall(fn, u, phase)
                view_end(view)
                if not ok then error(err, 0) end
                return true
            end
        end
    end
end

-- through U.reg_cmd: one shared xLua callback, the refcon picks the handler
local function register_handlers(u)
    u.cmd_ids = u.cmd_ids or {}
    for name, cmd in pairs(u.commands) do
        u.cmd_ids[name] = U.reg_cmd(cmd, u.handlers[name])
    end
end

local function unregister_handlers(u)
    for name, id in pairs(u.cmd_ids or {}) do
        U.unreg_cmd(u.commands[name], id)
        u.cmd_ids[name] = nil
    end
end

-----------------------------------------------------------------------------
-- Custom datarefs (per unit)
-----------------------------------------------------------------------------

-- Output datarefs (whitelist): read-only, computed from X-Plane data or the
-- unit's own state, never written from outside. They live in xLua's own
-- storage when xLua offers it (U.native_number, created once in
-- XPluginStart) and are written once per frame (push_outputs), which costs
-- none of xLua's callback budget; otherwise they get a normal read-only
-- accessor in XPluginEnable. Everything that takes input (writable) keeps
-- an accessor. { name, "i" | "f", value(u, st) }
local OUT_UNIT = {
    -- bezel push animations (same names as the old G5.System)
    { "knob_button_status", "i", function(u, st) return st.knob_down and 1 or 0 end },
    { "power_button_status", "i", function(u, st) return st.pwr_down and 1 or 0 end },
    { "unit_on", "i", function(u, st) return (st.mode ~= u.Sys.OFF) and 1 or 0 end },
    { "aligning_mode", "i", function(u, st) return st.aligning and 1 or 0 end },
    { "heading_fail", "i", function(u, st) return st.heading_fail and 1 or 0 end },
    { "batt_percentage", "f", function(u, st) return st.batt_pct or 0 end },
    { "batt_charging", "i", function(u, st) return st.charging and 1 or 0 end },
    { "batt_temp_c", "f", function(u, st) return st.batt_temp or 0 end },
    { "batt_minutes", "f", function(u, st) return u.Sys.battery_minutes() end },
    { "on_battery", "i", function(u, st) return (st.mode ~= u.Sys.OFF and not st.ext_power) and 1 or 0 end },
    { "bus_amps", "f", function(u, st) return st.bus_amps or 0 end },
    -- X-Plane's ambient level, the screen ratio sent back, and the knob ring
    -- glow (ATTR_light_level in G5.obj, same as the screen)
    { "ambient_brightness", "f", function(u, st) return st.ambient or 0 end },
    { "screen_brightness", "f", function(u, st) return st.screen_ratio or 0 end },
    -- knob ring glow (ATTR_light_level on the ring's LIT): the backlight level,
    -- not the ambient-scaled screen ratio, which falls to ~0.002 at night and
    -- left the ring dark; 0 while the unit is off
    { "knob_ring_brightness", "f", function(u, st)
        if (st.screen_ratio or 0) <= 0 then return 0 end
        return st.backlight or 0
    end },
    { "ap_disc_alert", "i", function(u, st) return u.Pfd.disc_alert(st) end },
    { "has_message", "i", function(u, st) return st.has_msg and 1 or 0 end },
    { "popup_visible", "i", function(u, st) return u.popup_visible and 1 or 0 end },
}

local OUT_GLOBAL = {
    { "xlua_loaded", "i", function() return 1 end },
    { "xlua_heartbeat", "i", function() return heartbeat end },
    { "unit_count", "i", function() return #units end },
}

-- Writable values where a bad outside write gains nothing and cannot upset
-- the unit (it is clamped / overwritten): native storage too, polled each
-- frame for outside writes. { name, value(u, st), apply(u, st, v) }
local NATIVE_W_UNIT = {
    { "knob_turn_val", function(u, st) return st.knob_val end,
        function(u, st, v) st.knob_val = v % 1 end },
    { "backlight", function(u, st) return st.backlight end,
        function(u, st, v) st.backlight = U.clamp(v, 0, 1) end },
    { "brightness_auto", function(u, st) return st.bright_auto and 1 or 0 end,
        function(u, st, v) st.bright_auto = (v ~= 0) end },
}

local out_global = {}   -- name -> native handle (nil: accessor)
local gfc_native = nil  -- laminar/gfc500/installed in xLua storage

-- XPluginStart: native storage for the whitelist, where xLua offers it
local function create_outputs()
    for _, d in ipairs(OUT_GLOBAL) do
        out_global[d[1]] = U.native_number("laminar/g5/" .. d[1])
    end
    for _, u in ipairs(units) do
        u.out = {}
        for _, d in ipairs(OUT_UNIT) do
            u.out[d[1]] = U.native_number(u.prefix .. d[1])
        end
        u.outw = {}
        for _, d in ipairs(NATIVE_W_UNIT) do
            local h = U.native_number_w(u.prefix .. d[1])
            if h then u.outw[d[1]] = { h = h, last = nil } end
        end
    end
end

local function reg_out(R, name, kind, fn)
    if kind == "i" then
        R[#R + 1] = U.reg_int(name, fn)
    else
        R[#R + 1] = U.reg_float(name, fn)
    end
end

-- every frame: the values of the native outputs
local function push_outputs()
    for _, d in ipairs(OUT_GLOBAL) do
        local h = out_global[d[1]]
        if h then U.native_set(h, d[3]()) end
    end
    for _, u in ipairs(units) do
        local st = u.st
        for _, d in ipairs(OUT_UNIT) do
            local h = u.out[d[1]]
            if h then U.native_set(h, d[3](u, st)) end
        end
        for _, d in ipairs(NATIVE_W_UNIT) do
            local w = u.outw[d[1]]
            if w then
                local cur = U.native_get(w.h)
                if w.last ~= nil and cur ~= w.last then d[3](u, st, cur) end
                local v = d[2](u, st)
                U.native_set(w.h, v)
                w.last = v
            end
        end
    end
end

local function register_datarefs(u)
    local R, P, st, Sys = u.drs, u.prefix, u.st, u.Sys
    -- the unit's own faults (g5_fail.lua): one int array, element i is
    -- Fail.INTERNAL[i + 1] (index list in config.ini [Failures]), 1 = failed
    local names = u.Fail.INTERNAL
    R[#R + 1] = U.reg_int_array(P .. "fail", #names,
        function(i) return st.fail[names[i + 1]] and 1 or 0 end,
        function(i, v) st.fail[names[i + 1]] = (v ~= 0) end)
    R[#R + 1] = U.reg_int(P .. "main_mode",
        function() return st.mode end,
        function(ref, v)
            if v == Sys.OFF then Sys.shutdown()
            elseif v == Sys.BOOT then Sys.start_boot()
            else Sys.set_page(v) end
        end)
    R[#R + 1] = U.reg_int(P .. "hsi_bearing_pointer",
        function() return (st.brg[1] ~= 0 or st.brg[2] ~= 0) and 1 or 0 end,
        function(ref, v)
            if v ~= 0 then st.brg[1] = 1 else st.brg[1], st.brg[2] = 0, 0 end
        end)
    R[#R + 1] = U.reg_int(P .. "bearing1_source",
        function() return st.brg[1] end,
        function(ref, v) st.brg[1] = math.floor(v) % 4 end)
    R[#R + 1] = U.reg_int(P .. "bearing2_source",
        function() return st.brg[2] end,
        function(ref, v) st.brg[2] = math.floor(v) % 4 end)
    R[#R + 1] = U.reg_int(P .. "in_config_mode",
        function() return (st.mode == Sys.CONFIG) and 1 or 0 end,
        function(ref, v)
            if v ~= 0 then Sys.enter_config() else Sys.exit_config() end
        end)
    -- the polled native values, as accessors when xLua has no storage for them
    for _, d in ipairs(NATIVE_W_UNIT) do
        if not (u.outw and u.outw[d[1]]) then
            local get, apply = d[2], d[3]
            if d[1] == "brightness_auto" then
                R[#R + 1] = U.reg_int(P .. d[1], function() return get(u, st) end,
                    function(ref, v) apply(u, st, v) end)
            else
                R[#R + 1] = U.reg_float(P .. d[1], function() return get(u, st) end,
                    function(ref, v) apply(u, st, v) end)
            end
        end
    end
    -- whitelisted outputs without native storage
    for _, d in ipairs(OUT_UNIT) do
        if not (u.out and u.out[d[1]]) then
            local fn = d[3]
            reg_out(R, P .. d[1], d[2], function() return fn(u, st) end)
        end
    end
end

local function unregister_datarefs(R)
    for i = #R, 1, -1 do
        if R[i] then U.unreg_dataref(R[i]) end
        R[i] = nil
    end
end

-- GFC500.System (xLua 1) looks this up and writes 1 every frame. The old
-- G5.System owned it, so it is created in XPluginStart, before that script
-- runs its find_dataref.
local gfc_dr = nil

-----------------------------------------------------------------------------
-- Flight loop
-----------------------------------------------------------------------------

-- Simulator time step: frozen while paused or in replay, scaled by time
-- acceleration; a jump (new situation) counts as one frame.
local last_run_time = nil
local function sim_step(real_dt)
    local t = D.run_time or 0
    local d = 0
    if last_run_time ~= nil and t > last_run_time then d = t - last_run_time end
    last_run_time = t
    if D.paused ~= 0 or D.replay ~= 0 then return 0 end
    if d > 5 then d = real_dt end
    return d
end

local save_t = 0

-- Links between the units:
--  * GPS position shared over CAN: a unit without its own receiver uses
--    another unit's.
--  * Master / slave (config role, 0 = master): the acting master is the
--    first live unit with role 0; with none (not installed, off, failed,
--    both configured as slaves) the first live unit takes over. Every other
--    live unit is a slave: it uses the master's sensor data as its primary
--    source and its own where the master's item is invalid (g5_fail.lua), so
--    each unit's failures still show on their own.
--  * AFMS 3-2: when no configured master is up any more, a unit on the HSI
--    page reverts to the attitude page; also when it comes up (power-up,
--    configuration mode exit) with no configured master.
local acting_master = nil
local prev_cfg_master_up = nil
local prev_mode = {}

local function unit_up(u)
    return u.cfg.installed ~= 0 and (u.st.mode == u.Sys.PFD or u.st.mode == u.Sys.HSI)
        and not u.st.fail.hardware
end

-- Cross-fill of baro, heading bug and selected altitude (see view_begin):
-- off while either installed unit has the sw_mismatch fault and two are
-- installed; then the message shows on both units (st.mismatch_link,
-- g5_fail.lua). One unit alone has nothing to cross-fill and no partner to
-- mismatch with: no message either.
local function cross_fill(m)
    local n_inst, mismatch = 0, false
    for _, u in ipairs(units) do
        if u.cfg.installed ~= 0 then
            n_inst = n_inst + 1
            if u.st.fail.sw_mismatch then mismatch = true end
        end
    end
    mismatch = mismatch and n_inst >= 2
    for _, u in ipairs(units) do
        u.st.mismatch_link = mismatch
        if mismatch and u ~= m then
            if u.priv == nil then
                u.priv = { baro = D.baro, hdg_bug = D.hdg_bug, alt_bug = D.alt_bug }
                log(string.format("software version mismatch: unit %d keeps its own baro and bugs", u.n))
            end
        elseif u.priv ~= nil then
            u.priv = nil
            log(string.format("unit %d: cross-fill of baro and bugs again", u.n))
        end
        u.In.priv = u.priv
    end
end

local function link_units()
    for i, u in ipairs(units) do
        local can = false
        for j, o in ipairs(units) do
            if j ~= i and (o.st.mode == o.Sys.PFD or o.st.mode == o.Sys.HSI) and o.st.gps_int_ok then
                can = true
            end
        end
        u.st.can_gps = can
    end

    local m, cfg_master_up = nil, false
    for _, u in ipairs(units) do
        if u.cfg.role == 0 and unit_up(u) then
            m = m or u
            cfg_master_up = true
        end
    end
    local takeover = false
    if m == nil then
        for _, u in ipairs(units) do
            if unit_up(u) then
                m, takeover = u, true
                break
            end
        end
    end
    if m ~= acting_master then
        if #units < 2 then
            -- one unit: nothing to report
        elseif m then
            log(string.format("unit %d is the master%s", m.n, takeover and " (take-over)" or ""))
        elseif acting_master then
            log("no G5 is up: no master")
        end
        acting_master = m
    end
    for _, u in ipairs(units) do
        if u == m then
            u.primary = nil
            u.st.role_eff = takeover and "takeover" or "master"
        else
            u.primary = (m and unit_up(u)) and m.st or nil
            u.st.role_eff = "slave"
        end
    end

    if #units >= 2 then
        for _, u in ipairs(units) do
            local pm = prev_mode[u.n]
            local came_up = pm ~= nil and pm ~= u.Sys.HSI and pm ~= u.Sys.PFD
            if u.st.mode == u.Sys.HSI and u.cfg.role ~= 0 and not cfg_master_up
                and (prev_cfg_master_up or came_up) then
                u.Sys.set_page(u.Sys.PFD)
                log(string.format("no master up: unit %d reverts to the PFD", u.n))
            end
            prev_mode[u.n] = u.st.mode
        end
    end
    prev_cfg_master_up = cfg_master_up
    cross_fill(m)
end

local function read_gfc()
    if config.gfc500 == "1" then
        gfc_installed = 1
    elseif config.gfc500 == "0" then
        gfc_installed = 0
    elseif gfc_native then
        gfc_installed = (U.native_get(gfc_native) or 0) ~= 0 and 1 or 0
    end
end

local function update_unit(u, sdt, dt)
    u.In.gfc = gfc_installed ~= 0
    u.Hsi.gfc = gfc_installed ~= 0
    u.Sys.update(sdt, D, dt)
    u.Fail.update(sdt, D, u.primary)
    u.In.update(dt, D)     -- menus and button holds run in real time
    u.Pfd.update(sdt, D)
    -- Heading Bug Auto Sync Mode (g5_input.lua); nothing to do while it is
    -- off in config and not running
    if u.cfg.hdg_sync ~= 0 or u.st.hdg_sync then
        u.In.hdg_sync_update(D, u.Pfd.afcs_modes(D))
    else
        u.st.hdg_sync_ok = false
    end
    u.Cfg.update(sdt, D)
    u.Pick.update()
end

-- tables reused every frame
local tick_order, tick_bus = {}, {}

local function tick(dt)
    Sim.read()
    read_gfc()
    local sdt = sim_step(dt)
    -- NO GP runs on simulator time (stops while paused / in replay)
    Sim.update_no_gp(D, sdt)
    link_units()
    -- the master first, so its slaves see this frame's data
    local order = tick_order
    for i = #order, 1, -1 do order[i] = nil end
    if acting_master then order[1] = acting_master end
    for _, u in ipairs(units) do
        if u ~= acting_master then order[#order + 1] = u end
    end
    for _, u in ipairs(order) do
        -- the unit's own baro and bugs while cross-fill is off (alerting,
        -- knob holds)
        local view = view_begin(u)
        local ok, err = pcall(update_unit, u, sdt, dt)
        view_end(view)
        if not ok then error(err, 0) end
    end
    -- the ESP provider needs a valid attitude from a unit showing a page, and
    -- one that has finished aligning (no ESP during ALIGNING)
    local att_ok = false
    for _, u in ipairs(units) do
        if (u.st.mode == u.Sys.PFD or u.st.mode == u.Sys.HSI) and u.st.valid.att and not u.st.aligning then
            att_ok = true
        end
    end
    Esp.update(att_ok, D.run_time)
    push_outputs()
    -- what the units draw from the aircraft buses
    if config.bus_load ~= 0 then
        local per = tick_bus
        for k in pairs(per) do per[k] = nil end
        for _, u in ipairs(units) do
            local b = u.cfg.power_bus
            per[b] = (per[b] or 0) + (u.st.bus_amps or 0)
        end
        for i = 0, 5 do Sim.set_bus_load(i, per[i] or 0) end
    end
    save_t = save_t + dt
    if save_t >= 60 then
        save_t = 0
        for _, u in ipairs(units) do pcall(save_state, u) end
    end
end

local function flight_loop_cb(since_call, since_loop, counter, refcon)
    heartbeat = heartbeat + 1
    local dt = U.clamp(since_call or 0, 0.0, 0.1)
    local ok, err = pcall(tick, dt)
    if not ok then report_error("update", err) end
    return -1
end

-----------------------------------------------------------------------------
-- Lifecycle
-----------------------------------------------------------------------------

local function start()
    U.read_ini(script_dir .. "/config.ini", config)
    U.read_ini(script_dir .. "/settings.ini", settings)
    apply_settings()
    config.nav_interface = string.lower(tostring(config.nav_interface))
    if config.nav_interface ~= "arinc" and config.nav_interface ~= "rs232" then
        log("config.ini: nav_interface = '" .. config.nav_interface .. "' is not valid (arinc | rs232), using arinc")
        config.nav_interface = "arinc"
    end
    -- divisors: a zero or negative value would divide by zero
    for key, min in pairs({ battery_charge_eff = 0.05, backlight_doubling = 0.01, battery_temp_tau_s = 1 }) do
        local v = tonumber(config[key])
        if v == nil or v < min then
            log("config.ini: " .. key .. " = " .. tostring(config[key]) .. " is too small, using " .. min)
            config[key] = min
        end
    end
    config.auto_power_off = string.lower(tostring(config.auto_power_off))
    config.fd_cue = string.lower(tostring(config.fd_cue))
    config.show_battery = string.lower(tostring(config.show_battery))
    config.roll_pointer = string.lower(tostring(config.roll_pointer))
    -- ap_option -> the internal esp / gpss_menu switches. The old config.ini
    -- keys esp / gpss_menu are still read but ap_option decides.
    local legacy_esp, legacy_gpss = config.esp, config.gpss_menu
    local opt = string.lower(tostring(config.ap_option))
    if opt ~= "esp" and opt ~= "gpss" and opt ~= "none" then
        log("config.ini: ap_option = '" .. tostring(config.ap_option) .. "' is not valid (esp | gpss | none), using esp")
        opt = "esp"
    end
    config.ap_option = opt
    config.esp = (opt == "esp") and 1 or 0
    config.gpss_menu = (opt == "gpss") and 1 or 0
    if legacy_esp ~= 0 or legacy_gpss ~= 0 then
        log("config.ini: esp / gpss_menu are replaced by ap_option (" .. opt .. ")")
    end
    -- VSI range: only the two scales there is artwork for
    if config.vsi_scale ~= 15 and config.vsi_scale ~= 30 then
        log("config.ini: vsi_scale = " .. tostring(config.vsi_scale) .. " is not valid (15 | 30), using 15")
        config.vsi_scale = 15
    end
    if config.roll_pointer ~= "ground" and config.roll_pointer ~= "sky" then
        log("config.ini: roll_pointer = '" .. config.roll_pointer .. "' is not valid, using ground")
        config.roll_pointer = "ground"
    end
    config.pitch_display = string.lower(tostring(config.pitch_display))
    if config.pitch_display ~= "normal" and config.pitch_display ~= "expanded" then
        log("config.ini: pitch_display = '" .. config.pitch_display .. "' is not valid (normal | expanded), using normal")
        config.pitch_display = "normal"
    end
    if config.vnav_dev_scale ~= 500 and config.vnav_dev_scale ~= 1000 then
        log("config.ini: vnav_dev_scale = " .. tostring(config.vnav_dev_scale) .. " is not valid (500 | 1000), using 500")
        config.vnav_dev_scale = 500
    end

    G.set_scale(config.screen_scale)
    G.init_colors()
    G.init_fonts(config.font_bold, config.font_cond)
    G.load_images(U.xp_relative(script_dir), A, log)
    Sim.init(U, config)
    Esp.init(U, config)
    read_acf_vspeeds()

    local n_units, installed = detect_units()
    for n = 1, n_units do
        units[n] = make_unit(n)
        units[n].cfg.installed = installed[n] and 1 or 0
        create_commands(units[n])
    end
    log(string.format("%d unit(s)", n_units))

    -- GFC500.System (xLua 1) finds laminar/gfc500/installed and writes 1 into
    -- it every frame, so it must exist. In xLua storage it costs no callback;
    -- gfc500 = 0 / 1 in config.ini fixes the value instead of reading it.
    config.gfc500 = string.lower(tostring(config.gfc500))
    gfc_native = U.native_number_w("laminar/gfc500/installed")
    if gfc_native == nil then
        gfc_dr = U.reg_int("laminar/gfc500/installed",
            function() return gfc_installed end,
            function(ref, v) gfc_installed = v end)
    end
    create_outputs()
    local nn = 0
    for _ in pairs(out_global) do nn = nn + 1 end
    for _, u in ipairs(units) do for _ in pairs(u.out) do nn = nn + 1 end end
    log(string.format("output datarefs in xLua storage: %d (%s)", nn,
        U.native_ok() and "XLuaCreateDataRef" or "not offered, accessors"))
end

function XPluginStart()
    log("XPluginStart, script dir: " .. script_dir)
    local ok, err = pcall(start)
    if not ok then
        log("ERROR XPluginStart failed: " .. tostring(err))
        if gfc_dr then
            pcall(U.unreg_dataref, gfc_dr)
            gfc_dr = nil
        end
        return false
    end
    return true
end

local function create_devices(u)
    local cfg = u.cfg
    local fb_w = cfg.screen_fb_w * cfg.screen_scale
    local fb_h = cfg.screen_fb_h * cfg.screen_scale
    u.avionic = XPLMCreateAvionicsEx({
        screenWidth = fb_w,
        screenHeight = fb_h,
        bezelWidth = fb_w,
        bezelHeight = fb_h,
        screenOffsetX = 0,
        screenOffsetY = 0,
        bezelDrawCallback = bezel_draw_cb,
        drawCallback = screen_draw_cb,
        brightnessCallback = brightness_cb,
        deviceID = u.device,
        deviceName = u.name,
        refcon = { u, "3d" },
        contentType = XPLMWindowContentType.xplm_WindowContentTypePanelGraphics,
    })
    XPLMSetAvionicsBrightnessRheo(u.avionic, 1.0)
    XPLMSetAvionicsPopupVisible(u.avionic, false)

    -- A separate device for the popup: one device shares one framebuffer.
    if cfg.enable_popup ~= 0 then
        u.popup = XPLMCreateAvionicsEx({
            screenWidth = DESIGN_W * cfg.screen_scale,
            screenHeight = DESIGN_H * cfg.screen_scale,
            bezelWidth = DESIGN_W * cfg.screen_scale,
            bezelHeight = DESIGN_H * cfg.screen_scale,
            screenOffsetX = 0,
            screenOffsetY = 0,
            bezelDrawCallback = bezel_draw_cb,
            drawCallback = screen_draw_cb,
            brightnessCallback = brightness_cb,
            deviceID = u.device .. "_popup",
            deviceName = u.name .. " Popup",
            refcon = { u, "popup" },
            contentType = XPLMWindowContentType.xplm_WindowContentTypePanelGraphics,
        })
        XPLMSetAvionicsBrightnessRheo(u.popup, 1.0)
        set_popup_visible(u, cfg.popup_initial ~= 0 and u.n == 1)
    end
end

-- the Level command observer (enable): declared before teardown, which undoes it
local lvl_cmd, lvl_id = nil, nil

-- Everything XPluginEnable sets up, torn down in reverse; safe to run on a
-- half-finished enable (every handle is stored as soon as it exists).
local function teardown()
    if flight_loop then
        XPLMDestroyFlightLoop(flight_loop)
        flight_loop = nil
    end
    for _, u in ipairs(units) do
        pcall(u.Pick.disable)
        if u.popup then
            XPLMDestroyAvionics(u.popup)
            u.popup = nil
        end
        if u.avionic then
            XPLMDestroyAvionics(u.avionic)
            u.avionic = nil
        end
        unregister_handlers(u)
        unregister_datarefs(u.drs)
    end
    unregister_datarefs(global_dr)
    if lvl_cmd and lvl_id then U.unreg_cmd(lvl_cmd, lvl_id) end
    lvl_cmd, lvl_id = nil, nil
end

local function enable()
    -- observe the Level command (display only; passed on unchanged): g5_sim LVL
    lvl_cmd = U.find_cmd("sim/autopilot/return_to_level")
    if lvl_cmd then
        lvl_id = U.reg_cmd(lvl_cmd, function(cmd, phase)
            if phase == BEGIN then Sim.note_lvl() end
        end)
    end
    -- the whitelisted outputs without native storage
    for _, d in ipairs(OUT_GLOBAL) do
        if not out_global[d[1]] then reg_out(global_dr, "laminar/g5/" .. d[1], d[2], d[3]) end
    end

    -- the aircraft's own cockpit object keeps all native clicks; the G5 knob and
    -- button are picked by the plugin (see g5_pick.lua)
    local model = XPLMGetNthAircraftModel(0)
    local acf = type(model) == "table" and U.unwrap_string(model.outPath or model[2]) or tostring(model or "")
    acf = U.normalize_path(acf)

    for _, u in ipairs(units) do
        register_datarefs(u)
        register_handlers(u)
        create_devices(u)
        local ok, err = pcall(u.Pick.load, u.obj, acf)
        if ok then ok, err = pcall(u.Pick.enable) end
        if not ok then report_error("pick " .. u.n, err) end
    end

    flight_loop = XPLMCreateFlightLoop({
        phase = XPLMFlightLoopPhaseType.xplm_FlightLoop_Phase_AfterFlightModel,
        callbackFunc = flight_loop_cb,
        refcon = nil,
    })
    XPLMScheduleFlightLoop(flight_loop, -1, true)
    return true
end


-- A failure half-way (e.g. xLua's callback budget running out) must not
-- leave datarefs or handlers registered: X-Plane would keep calling
-- closures xLua has already released, which crashed the sim on 2026-10-16.
-- So undo everything and report the plugin as not enabled.
function XPluginEnable()
    log("XPluginEnable")
    local ok, err = pcall(enable)
    if not ok then
        log("ERROR XPluginEnable failed, everything unregistered: " .. tostring(err))
        pcall(teardown)
        return false
    end
    return true
end

function XPluginDisable()
    log("XPluginDisable")
    for _, u in ipairs(units) do pcall(save_state, u) end
    for i = 0, 5 do pcall(Sim.set_bus_load, i, 0) end
    teardown()
end

function XPluginStop()
    log("XPluginStop")
    if gfc_dr then
        U.unreg_dataref(gfc_dr)
        gfc_dr = nil
    end
    G.destroy_images()
    G.destroy_fonts()
end

local MSG_PLANE_LOADED = XPLM_MSG_PLANE_LOADED or 102
local MSG_AIRPORT_LOADED = XPLM_MSG_AIRPORT_LOADED or 103

local PLUGIN_XPLANE = XPLM_PLUGIN_XPLANE or 0

function XPluginReceiveMessage(from, msg, param)
    if from ~= PLUGIN_XPLANE then return end
    -- new flight: same reset the old flight_start() did
    if msg == MSG_AIRPORT_LOADED or (msg == MSG_PLANE_LOADED and (param == 0 or param == nil)) then
        for _, u in ipairs(units) do
            pcall(save_state, u)
            u.Sys.reset()
            u.Fail.reset()
        end
        prev_cfg_master_up = nil
        prev_mode = {}
        Esp.reset()
    end
end
