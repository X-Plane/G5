--[[ XLua 2.0 ]]
--[[
*****************************************************************************************
* Program Script Name : Garmin G5 (2026, XPLM 4 Panel Graphics)
*
* Author Name         : Eric Xu / erix@x-plane.com
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
*   g5_assets.lua   PNG manifest     Textures/      1:1 artwork from the old G5
*   g5_rfont_data.lua  raster font metrics (generated; glyphs in Textures/RFont)
*   settings.ini    user settings: power, page, units (GI-260 style)
*   config.ini      per-aircraft settings
*   state_unit<n>.ini  written by the plugin: battery state and the values
*                   changed in configuration mode (override the two above)
*****************************************************************************************
*        COPYRIGHT @ 2024-2026 ERIC XU / Laminar Research - ALL RIGHTS RESERVED
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
    boot_logo_s = 1.0,
    shutdown_fade_s = 0.4,
    magnetometer_on_bus = 1,

    -- power-up / AHRS (g5_fail.lua)
    att_kwl_s = 0,
    att_kwl_recover_s = 10,
    align_s = 40,
    air_init_s = 3,
    hdg_init_s = 5,
    gps_init_s = 20,
    magnetometer = 1,
    gps_internal = 1,
    gps_external = 1,
    nav_interface = "arinc",
    nav_count = 2,
    gpss_menu = 1,
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
    backlight_neutral = 0.78,
    backlight_doubling = 0.2,
    ambient_min = 0.002,
    brightness_rheostat = 6,

    speed_unit = 0,
    temp_unit = 0,
    baro_unit = 0,
    vx = 30,
    vy = 50,
    va = 60,
    vg = 40,
    -- configuration mode Airspeed page (knots): band limits 0 = from the
    -- aircraft (acf); VR / VMC / VYSE 0 = not shown
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
    vib_limit_g = 0.3,
    speed_tape_min = 30,
    speed_alive_hyst = 2,
    speed_tape_range = 60,
    speed_trend_s = 6,
    pitch_px_per_deg = 3.6,
    vsi_scale = 15,

    show_tas = 1,
    show_oat = 1,
    show_gs = 1,
    show_hdg_box = 0,
    show_ap_bar = 1,
    ap_bar_reserved = 1,
    afcs_pft_s = 5,
    fd_cue = "single",
    roll_pointer = "ground",
    std_turn_ref = 1,

    bearing1_source = 0,
    bearing2_source = 0,

    screen_scale = 1,
    -- 3D device framebuffer = the whole 2048x1024 G5 texture, 1:1 to its pixels;
    -- the 320x240 screen UV island is at px x 1032..1352, y 8..248 from the top
    -- (tools/blender/uv_screen_1to1.py), i.e. this origin (y up)
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

    -- number of G5 units: 1 = attitude only (G5.obj), 2 = + HSI below (G5_2.obj)
    units = 1,
    -- per-unit values, set from settings.ini (unit_config picks unit<n>_<key>)
    unit2_startup_page = 2,
    unit2_auto_power_on = 1,
}

-- Keys a unit can override with unit<n>_<key> in config.ini (the dual
-- installation tables give unit 2 its own bus, battery, GPS and backlight
-- settings). "" = not set: the shared value is used.
local PER_UNIT = { "power_bus", "battery_installed", "show_battery", "auto_power_off",
    "gps_internal", "backlight_auto_initial", "backlight_initial", "battery_wh",
    "battery_health", "battery_initial_pct", "unusual_revert", "hsi_page" }
for _, k in ipairs(PER_UNIT) do
    for n = 1, 2 do
        if config["unit" .. n .. "_" .. k] == nil then config["unit" .. n .. "_" .. k] = "" end
    end
end
-- real dual installations disable unit 2's own GPS receiver: it gets GPS
-- from unit 1 over CAN (Installation Manual dual tables)
config.unit2_gps_internal = "0"

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
local BARO = { inhg = 0, hpa = 1, mb = 1 }
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

local units = {}
local flight_loop = nil
local heartbeat = 0
local gfc_installed = 0
local last_error = nil
local error_count = 0
local global_dr = {}

local function report_error(where, err)
    error_count = error_count + 1
    local msg = where .. ": " .. tostring(err)
    if msg ~= last_error or error_count % 600 == 0 then
        log("ERROR " .. msg)
        last_error = msg
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
    u.Pick.init(U, u.cfg)
    u.Cfg.init(U, G, u.Sys, u.Fail, u.Pfd, u.cfg)
    u.In.Cfg = u.Cfg
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
        -- calibration, no CDI / VDI with Navigation Data disabled
        local p, r, sh, sv = D.pitch, D.roll, D.hsi_show_h, D.hsi_show_v
        D.pitch, D.roll = p + cfg.pitch_cal, r + cfg.roll_cal
        if cfg.nav_data == 0 then D.hsi_show_h, D.hsi_show_v = 0, 0 end
        local ok, err
        if st.mode == Sys.PFD then
            ok, err = pcall(u.Pfd.draw, D, st, gfc_installed ~= 0)
        else
            ok, err = pcall(u.Hsi.draw, D, st)
        end
        D.pitch, D.roll, D.hsi_show_h, D.hsi_show_v = p, r, sh, sv
        if not ok then error(err, 0) end
        u.UI.draw(D, st)
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
    for _, name in ipairs(u.Fail.INTERNAL) do
        local key = "fail_" .. name .. "_toggle"
        u.commands[key] = XPLMCreateCommand(u.prefix .. key, u.name .. " toggle internal fault: " .. name)
        u.handlers[key] = function(cmd, phase, ref)
            if phase == BEGIN then u.st.fail[name] = not u.st.fail[name] end
            return true
        end
    end
    for _, c in ipairs(COMMAND_LIST) do
        local fn = c[3]
        u.commands[c[1]] = XPLMCreateCommand(u.prefix .. c[1], u.name .. " " .. c[2])
        u.handlers[c[1]] = function(cmd, phase, ref)
            fn(u, phase)
            return true
        end
    end
end

local function register_handlers(u)
    for name, cmd in pairs(u.commands) do
        XPLMRegisterCommandHandler(cmd, u.handlers[name], true, nil)
    end
end

local function unregister_handlers(u)
    for name, cmd in pairs(u.commands) do
        XPLMUnregisterCommandHandler(cmd, u.handlers[name], true, nil)
    end
end

-----------------------------------------------------------------------------
-- Custom datarefs (per unit)
-----------------------------------------------------------------------------

local function register_datarefs(u)
    local R, P, st, Sys = u.drs, u.prefix, u.st, u.Sys
    -- the unit's own faults (g5_fail.lua): 1 = failed
    for _, name in ipairs(u.Fail.INTERNAL) do
        R[#R + 1] = U.reg_int(P .. "fail_" .. name,
            function() return st.fail[name] and 1 or 0 end,
            function(ref, v) st.fail[name] = (v ~= 0) end)
    end
    R[#R + 1] = U.reg_int(P .. "main_mode",
        function() return st.mode end,
        function(ref, v)
            if v == Sys.OFF then Sys.shutdown()
            elseif v == Sys.BOOT then Sys.start_boot()
            else Sys.set_page(v) end
        end)
    R[#R + 1] = U.reg_float(P .. "knob_turn_val",
        function() return st.knob_val end,
        function(ref, v) st.knob_val = v end)
    R[#R + 1] = U.reg_int(P .. "hsi_bearing_pointer",
        function() return (st.brg[1] ~= 0 or st.brg[2] ~= 0) and 1 or 0 end,
        function(ref, v) st.brg[1] = (v ~= 0) and 1 or 0 end)
    R[#R + 1] = U.reg_int(P .. "bearing1_source",
        function() return st.brg[1] end,
        function(ref, v) st.brg[1] = math.floor(v) % 4 end)
    R[#R + 1] = U.reg_int(P .. "bearing2_source",
        function() return st.brg[2] end,
        function(ref, v) st.brg[2] = math.floor(v) % 4 end)
    -- bezel push animations (same names as the old G5.System)
    R[#R + 1] = U.reg_int(P .. "knob_button_status",
        function() return st.knob_down and 1 or 0 end)
    R[#R + 1] = U.reg_int(P .. "power_button_status",
        function() return st.pwr_down and 1 or 0 end)
    R[#R + 1] = U.reg_int(P .. "unit_on",
        function() return (st.mode ~= Sys.OFF) and 1 or 0 end)
    R[#R + 1] = U.reg_int(P .. "in_config_mode",
        function() return (st.mode == Sys.CONFIG) and 1 or 0 end,
        function(ref, v)
            if v ~= 0 then Sys.enter_config() else Sys.exit_config() end
        end)
    R[#R + 1] = U.reg_int(P .. "aligning_mode",
        function() return st.aligning and 1 or 0 end)
    R[#R + 1] = U.reg_int(P .. "heading_fail",
        function() return st.heading_fail and 1 or 0 end)
    R[#R + 1] = U.reg_float(P .. "batt_percentage",
        function() return st.batt_pct end)
    R[#R + 1] = U.reg_int(P .. "batt_charging",
        function() return st.charging and 1 or 0 end)
    R[#R + 1] = U.reg_float(P .. "batt_temp_c",
        function() return st.batt_temp or 0 end)
    R[#R + 1] = U.reg_float(P .. "batt_minutes",
        function() return Sys.battery_minutes() end)
    R[#R + 1] = U.reg_int(P .. "on_battery",
        function() return (st.mode ~= Sys.OFF and not st.ext_power) and 1 or 0 end)
    R[#R + 1] = U.reg_float(P .. "bus_amps",
        function() return st.bus_amps or 0 end)
    R[#R + 1] = U.reg_float(P .. "backlight",
        function() return st.backlight end,
        function(ref, v) st.backlight = U.clamp(v, 0, 1) end)
    -- read-only: X-Plane's ambient level, the screen ratio sent back, and
    -- the knob ring glow (ATTR_light_level in G5.obj, same as the screen)
    R[#R + 1] = U.reg_float(P .. "ambient_brightness", function() return st.ambient end)
    R[#R + 1] = U.reg_float(P .. "screen_brightness", function() return st.screen_ratio end)
    R[#R + 1] = U.reg_float(P .. "knob_ring_brightness", function() return st.screen_ratio end)
    R[#R + 1] = U.reg_int(P .. "brightness_auto",
        function() return st.bright_auto and 1 or 0 end,
        function(ref, v) st.bright_auto = (v ~= 0) end)
    R[#R + 1] = U.reg_int(P .. "ap_disc_alert",
        function() return u.Pfd.disc_alert(st) end)
    R[#R + 1] = U.reg_int(P .. "has_message",
        function() return st.has_msg and 1 or 0 end)
    R[#R + 1] = U.reg_int(P .. "popup_visible",
        function() return u.popup_visible and 1 or 0 end)
end

local function unregister_datarefs(R)
    for i = #R, 1, -1 do
        if R[i] then XPLMUnregisterDataAccessor(R[i]) end
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

local prev_on1 = nil
local prev_m2 = nil
local save_t = 0

-- Links between the units: GPS position shared over CAN (a unit without its
-- own receiver uses another unit's), and AFMS 3-2: when the attitude unit
-- (#1) powers down, the HSI unit reverts to the attitude page and stays there.
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
    if #units < 2 then return end
    local u1, u2 = units[1], units[2]
    local on1 = u1.st.mode ~= u1.Sys.OFF
    local m2 = u2.st.mode
    -- unit 1 goes off, or unit 2 starts (power-up, configuration mode exit)
    -- on the HSI page while unit 1 is off
    local came_up = prev_m2 ~= nil and prev_m2 ~= u2.Sys.HSI and prev_m2 ~= u2.Sys.PFD
    if m2 == u2.Sys.HSI and not on1 and (prev_on1 or came_up) then
        u2.Sys.set_page(u2.Sys.PFD)
        log("unit 1 off: unit 2 reverts to the PFD")
    end
    prev_on1 = on1
    prev_m2 = u2.st.mode
end

local function tick(dt)
    Sim.read()
    local sdt = sim_step(dt)
    link_units()
    for _, u in ipairs(units) do
        u.In.gfc = gfc_installed ~= 0
        u.Hsi.gfc = gfc_installed ~= 0
        u.Sys.update(sdt, D, dt)
        u.Fail.update(sdt, D)
        u.In.update(dt, D)     -- menus and button holds run in real time
        u.Pfd.update(sdt, D)
        u.Cfg.update(sdt, D)
        u.Pick.update()
    end
    -- what the units draw from the aircraft buses
    if config.bus_load ~= 0 then
        local per = {}
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

function XPluginStart()
    log("XPluginStart, script dir: " .. script_dir)
    U.read_ini(script_dir .. "/config.ini", config)
    U.read_ini(script_dir .. "/settings.ini", settings)
    apply_settings()
    config.nav_interface = string.lower(tostring(config.nav_interface))
    config.auto_power_off = string.lower(tostring(config.auto_power_off))
    config.fd_cue = string.lower(tostring(config.fd_cue))
    config.show_battery = string.lower(tostring(config.show_battery))
    config.roll_pointer = string.lower(tostring(config.roll_pointer))
    -- VSI range: only the two scales there is artwork for
    if config.vsi_scale ~= 15 and config.vsi_scale ~= 30 then
        log("config.ini: vsi_scale = " .. tostring(config.vsi_scale) .. " is not valid (15 | 30), using 15")
        config.vsi_scale = 15
    end
    if config.roll_pointer ~= "ground" and config.roll_pointer ~= "sky" then
        log("config.ini: roll_pointer = '" .. config.roll_pointer .. "' is not valid, using ground")
        config.roll_pointer = "ground"
    end

    G.set_scale(config.screen_scale)
    G.init_colors()
    G.init_fonts(config.font_bold, config.font_cond)
    G.load_images(U.xp_relative(script_dir), A, log)
    Sim.init(U, config)

    local n_units = math.max(1, math.min(2, math.floor(config.units)))
    for n = 1, n_units do
        units[n] = make_unit(n)
        create_commands(units[n])
    end
    log(string.format("%d unit(s)", n_units))

    gfc_dr = U.reg_int("laminar/gfc500/installed",
        function() return gfc_installed end,
        function(ref, v) gfc_installed = v end)
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

function XPluginEnable()
    log("XPluginEnable")
    global_dr[#global_dr + 1] = U.reg_int("laminar/g5/xlua_loaded", function() return 1 end)
    global_dr[#global_dr + 1] = U.reg_int("laminar/g5/xlua_heartbeat", function() return heartbeat end)
    global_dr[#global_dr + 1] = U.reg_int("laminar/g5/unit_count", function() return #units end)

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

function XPluginDisable()
    log("XPluginDisable")
    for _, u in ipairs(units) do pcall(save_state, u) end
    for i = 0, 5 do pcall(Sim.set_bus_load, i, 0) end
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
end

function XPluginStop()
    log("XPluginStop")
    if gfc_dr then
        XPLMUnregisterDataAccessor(gfc_dr)
        gfc_dr = nil
    end
    G.destroy_images()
    G.destroy_fonts()
end

local MSG_PLANE_LOADED = XPLM_MSG_PLANE_LOADED or 102
local MSG_AIRPORT_LOADED = XPLM_MSG_AIRPORT_LOADED or 103

function XPluginReceiveMessage(from, msg, param)
    if from ~= XPLM_PLUGIN_XPLANE then return end
    -- new flight: same reset the old flight_start() did
    if msg == MSG_AIRPORT_LOADED or (msg == MSG_PLANE_LOADED and (param == 0 or param == nil)) then
        for _, u in ipairs(units) do
            pcall(save_state, u)
            u.Sys.reset()
            u.Fail.reset()
        end
        prev_on1 = nil
        prev_m2 = nil
    end
end
