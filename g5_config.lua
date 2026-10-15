-- g5_config.lua: configuration mode (Installation Manual 6.3.2, 6.3.6, 6.3.7;
-- Maintenance Manual appendix A). Entered by holding the knob while the unit
-- powers up (or with the laminar/g5/config_mode command); "Exit Configuration
-- Mode" restarts the unit.
--
-- The pages follow the Installation Manual list. Each value is one of the
-- plugin's config keys: a change applies at once and G5.lua (hooks.set)
-- writes it to state_unit<n>.ini, where it overrides config.ini and
-- settings.ini. Scope: "unit" items belong to each unit (a second unit shows
-- only those, IM dual installation tables); "shared" items are set on unit 1
-- and used by every unit.
--
-- There are no photos of the list pages, so their layout is our own (title
-- bar, rows, value cells, cyan selection like the Setup panel). The
-- procedure screens copy Installation Manual figure 6-3: grey title bar,
-- centred lines, a Done button with a green check or a red X.

local U, G, Sys, Fail, Pfd, cfg, C

local Cfg = {}
local st

Cfg.VERSION = "XP 2026.10"
-- set by G5.lua: set(key, value, scope), n (unit number), n_units(),
-- unit_ok(n), gfc()
Cfg.hooks = nil

function Cfg.init(util, gfx, sys, fail, pfd, config)
    U, G, Sys, Fail, Pfd, cfg = util, gfx, sys, fail, pfd, config
    C = G.C
    st = Sys.st
end

local function master()
    return Cfg.hooks == nil or Cfg.hooks.n == 1
end

-----------------------------------------------------------------------------
-- Pages
-----------------------------------------------------------------------------

local function enum(label, key, opts, scope, also)
    return { kind = "enum", label = label, key = key, opts = opts, scope = scope, also = also }
end
local function num(label, key, scope, lo, hi, step, fmt)
    return { kind = "num", label = label, key = key, scope = scope, lo = lo, hi = hi, step = step, fmt = fmt }
end
-- V-speeds are kept in knots and shown / edited in the airspeed unit; 0 =
-- the aircraft's own value (`base`, the colour band limits) or not shown
local function vspd(label, key, base)
    return { kind = "vspeed", label = label, key = key, scope = "shared", base = base }
end
local function info(label, get, is_master)
    if type(get) == "string" then
        local s = get
        get = function() return s end
    end
    return { kind = "info", label = label, get = get, master = is_master }
end
local function status(label, ok, show)
    return { kind = "status", label = label, ok = ok, show = show, master = true }
end
local function action(label, proc, scope, show)
    return { kind = "action", label = label, proc = proc, scope = scope, show = show }
end

local ON_OFF = { { 1, "Enabled" }, { 0, "Disabled" } }
local SHOW = { { 1, "Show" }, { 0, "Hide" } }
local function deg1(v) return string.format("%.1f°", v) end
local function pct(v) return tostring(U.round(v * 100)) .. "%" end

local PAGES = {
    { title = "Device Information", rows = {
        info("Installation Type", "Certified Instrument"),
        info("Unit", function() return "SFD" .. (Cfg.hooks and Cfg.hooks.n or 1) end),
        info("Software Version", Cfg.VERSION),
        status("SFD1", function() return Cfg.hooks.unit_ok(1) end),
        status("SFD2", function() return Cfg.hooks.unit_ok(2) end,
            function() return Cfg.hooks.n_units() >= 2 end),
        status("GMU 11", function() return st.valid.mag end,
            function() return cfg.magnetometer ~= 0 end),
        status("GAD 13", function() return st.valid.oat end,
            function() return cfg.show_oat ~= 0 end),
        status("GPS", function() return st.valid.gps end,
            function() return cfg.gps_internal ~= 0 or cfg.gps_external ~= 0 end),
    } },
    { title = "Attitude", rows = {
        info("Indicator Type", "Normal", true),
        info("Pitch Display", "Normal", true),
        enum("Roll Display", "roll_pointer", { { "ground", "Ground Pointer" }, { "sky", "Sky Pointer" } }, "shared"),
        enum("Standard Turn Roll Ref.", "std_turn_ref", SHOW, "shared"),
        enum("Automatic Declutter", "unusual_revert", ON_OFF, "unit"),
        num("Pitch Calibration", "pitch_cal", "unit", -15, 15, 0.1, deg1),
        num("Roll Calibration", "roll_cal", "unit", -15, 15, 0.1, deg1),
        action("Calibrate Pitch/Roll", "pitch_roll", "unit"),
        action("Vibration Test", "vibration", "unit"),
    } },
    { title = "Air Data", rows = {
        info("Air Data Sensors", "Enabled", true),
        -- one switch for everything the GAD 13 provides (OAT, TAS, wind)
        enum("Outside Air Temp Sensor", "show_oat", ON_OFF, "shared", { "show_tas", "show_wind" }),
        enum("Vertical Speed Indicator", "vsi_scale", { { 15, "1500 fpm" }, { 30, "3000 fpm" } }, "shared"),
    } },
    { title = "Airspeed", rows = {
        vspd("VNE", "vne", true), vspd("VNO", "vno", true), vspd("VSO", "vso", true),
        vspd("VS1", "vs1", true), vspd("VFE", "vfe", true), vspd("VA", "va"),
        vspd("VX", "vx"), vspd("VY", "vy"), vspd("VG", "vg"), vspd("VR", "vr"),
        vspd("VMC", "vmc"), vspd("VYSE", "vyse"),
    } },
    { title = "Magnetometer", rows = {
        enum("Magnetometer", "magnetometer", ON_OFF, "shared"),
        info("Orientation", "Aft", true),
        action("Calibrate Magnetometer", "magnetometer", "shared",
            function() return cfg.magnetometer ~= 0 end),
    } },
    { title = "Flight Controls", rows = {
        info("Garmin Autopilot Servos", function() return Cfg.hooks.gfc() and "GFC 500" or "None" end, true),
        enum("GPS Steering", "gpss_menu", ON_OFF, "shared"),
        enum("Flight Director", "fd_cue", { { "single", "Single Cue" }, { "dual", "Dual Cue" } }, "shared"),
    } },
    { title = "Backlight", rows = {
        info("Current Mode", function() return st.bright_auto and "Automatic" or "Manual" end),
        enum("Default Mode", "backlight_auto_initial", { { 1, "Automatic" }, { 0, "Manual" } }, "unit"),
        num("Manual Level", "backlight_initial", "unit", 0.05, 1, 0.01, pct),
        num("Minimum Brightness", "backlight_min", "unit", 0.01, 0.5, 0.01, pct),
    } },
    { title = "Display", rows = {
        enum("HSI Page", "hsi_page", ON_OFF, "unit"),
        info("HSI Orientation", "Heading"),
        enum("Power Up Page", "startup_page", { { 1, "PFD" }, { 2, "HSI" } }, "unit"),
    } },
    { title = "Battery", rows = {
        enum("Battery", "battery_installed", { { 1, "Installed" }, { 0, "Not Installed" } }, "unit"),
        enum("Show Battery Status", "show_battery",
            { { "on_battery", "When Using Battery" }, { "always", "Always" } }, "unit"),
        enum("Automatic Power Off", "auto_power_off",
            { { "on_ground", "On Ground Only" }, { "always", "Always" }, { "never", "Never" } }, "unit"),
        info("Charge", function() return tostring(U.round(st.batt_pct or 0)) .. "%" end),
        info("Temperature", function() return tostring(U.round(st.batt_temp or 0)) .. "°C" end),
    } },
    { title = "GPS", rows = {
        enum("Internal GPS Receiver", "gps_internal", ON_OFF, "unit"),
        enum("GPS Data Fields", "show_gs", SHOW, "unit"),
        info("GPS Status", function()
            if cfg.gps_internal == 0 then return "Disabled" end
            return st.gps_int_ok and "3D GPS" or "Acquiring"
        end),
    } },
    { title = "Navigation", rows = {
        enum("Navigation Data", "nav_data", ON_OFF, "shared"),
        enum("Navigators", "nav_count", { { 1, "One" }, { 2, "Two" } }, "shared"),
    } },
    { title = "Units", rows = {
        info("Altitude", "Feet", true),
        info("Distance", "Nautical Miles", true),
        enum("Airspeed", "speed_unit", { { 0, "Knots" }, { 1, "MPH" }, { 2, "km/h" } }, "shared"),
        enum("Ground Speed", "gs_unit", { { -1, "As Airspeed" }, { 0, "Knots" }, { 1, "MPH" }, { 2, "km/h" } }, "shared"),
        info("Navigation Angle", "Magnetic", true),
        enum("Temperature", "temp_unit", { { 0, "Fahrenheit" }, { 1, "Celsius" } }, "shared"),
        info("Vertical Speed", "Feet/Minute", true),
        enum("Pressure", "baro_unit", { { 0, "inHg" }, { 1, "hPa" } }, "shared"),
    } },
    { title = "RS-232", rows = {
        info("Input Format", function() return (cfg.nav_interface == "rs232") and "Garmin VHF NAV" or "None" end),
        info("Output Format", "None"),
    } },
    { title = "ARINC 429", rows = {
        info("Input 1", function() return (cfg.nav_interface == "arinc") and "Garmin GPS" or "None" end, true),
        info("Input 2", function() return (cfg.nav_interface == "arinc") and "VOR/ILS" or "None" end, true),
        info("Output 1", "None", true),
        info("Output 2", "None", true),
    } },
}

-- every editable key and its scope (G5.lua loads / saves these)
Cfg.KEYS = {}
for _, pg in ipairs(PAGES) do
    for _, r in ipairs(pg.rows) do
        if r.key then
            Cfg.KEYS[r.key] = r.scope
            for _, k in ipairs(r.also or {}) do Cfg.KEYS[k] = r.scope end
        end
    end
end

local BACK = { kind = "back", label = "Back" }

local function row_visible(r)
    if (r.scope == "shared" or r.master) and not master() then return false end
    if r.show and not r.show() then return false end
    return true
end

local vis = {}
local function visible_rows(pg)
    for i = #vis, 1, -1 do vis[i] = nil end
    vis[1] = BACK
    for _, r in ipairs(pg.rows) do
        if row_visible(r) then vis[#vis + 1] = r end
    end
    return vis
end

local vpages = {}
local function visible_pages()
    for i = #vpages, 1, -1 do vpages[i] = nil end
    for _, pg in ipairs(PAGES) do
        for _, r in ipairs(pg.rows) do
            if row_visible(r) then
                vpages[#vpages + 1] = pg
                break
            end
        end
    end
    return vpages
end

local function selectable(r)
    return r.kind ~= "info" and r.kind ~= "status"
end

-----------------------------------------------------------------------------
-- Values
-----------------------------------------------------------------------------

local function opt_index(r, v)
    for i, o in ipairs(r.opts) do
        if tostring(o[1]) == tostring(v) then return i end
    end
    return 1
end

local function value_text(r, v, D)
    if r.kind == "enum" then
        return r.opts[opt_index(r, v)][2]
    elseif r.kind == "num" then
        return r.fmt(v)
    elseif r.kind == "vspeed" then
        if (v or 0) <= 0 then return r.base and "Aircraft" or "Off" end
        return tostring(U.round(Pfd.speed_value(v))) .. " " .. Pfd.speed_label()
    end
    return ""
end

local function step_value(r, v, dir, D)
    if r.kind == "enum" then
        return r.opts[U.clamp(opt_index(r, v) + dir, 1, #r.opts)][1]
    elseif r.kind == "num" then
        local n = U.round((v + dir * r.step) / r.step) * r.step
        return U.clamp(n, r.lo, r.hi)
    elseif r.kind == "vspeed" then
        local k = Pfd.speed_value(1)
        local disp
        if (v or 0) <= 0 then
            if dir < 0 then return 0 end
            local from = (r.base and D[r.key] or 0)
            disp = U.round(Pfd.speed_value((from > 0) and from or 60))
        else
            disp = U.round(Pfd.speed_value(v)) + dir
        end
        if disp <= 0 then return 0 end
        return math.min(disp, 999) / k
    end
    return v
end

local function commit(r, v)
    if Cfg.hooks == nil then return end
    Cfg.hooks.set(r.key, v, r.scope)
    for _, k in ipairs(r.also or {}) do Cfg.hooks.set(k, v, r.scope) end
end

-----------------------------------------------------------------------------
-- Procedures (Installation Manual 6.3.7)
-----------------------------------------------------------------------------

local function still(D)
    return D.gs < 0.5 and math.abs(D.turn_rate) < 0.5
end

local PROC = {}

-- A: pitch / roll offset. 30 s with the aircraft still (movement restarts
-- the timer); the new offsets put the current attitude at zero. Sign
-- convention of the manual: positive = nose down / left wing down, so the
-- offset is minus X-Plane's pitch / roll; the unit shows raw + calibration.
PROC.pitch_roll = {
    title = "Pitch/Roll Calibration",
    start = function(p) p.phase = "intro" end,
    lines = function(p)
        if p.phase == "intro" then
            return { "1. Level the aircraft.", "2. Keep the aircraft still.",
                "3. The unit must be installed.", "Select Start to begin." }
        elseif p.phase == "run" then
            return { "Calibration in progress...",
                string.format("%d seconds remaining", math.ceil(p.t)),
                (p.moved_t > 0) and "Aircraft movement detected" or "Keep the aircraft still" }
        end
        return { "Calibration complete.", "New Pitch Offset: " .. deg1(p.new_pitch),
            "New Roll Offset: " .. deg1(p.new_roll) }
    end,
    buttons = function(p)
        if p.phase == "intro" then return { { "Back" }, { "Start" } } end
        if p.phase == "run" then return { { "Cancel" } } end
        return { { "Done", "check" } }
    end,
    press = function(p, label)
        if label == "Start" then
            p.phase, p.t, p.n, p.sp, p.sr, p.moved_t = "run", 30, 0, 0, 0, 0
            p.btn = 1
        elseif label == "Done" then
            Cfg.hooks.set("pitch_cal", U.clamp(U.round(p.new_pitch * 10) / 10, -15, 15), "unit")
            Cfg.hooks.set("roll_cal", U.clamp(U.round(p.new_roll * 10) / 10, -15, 15), "unit")
            return true
        else
            return true
        end
    end,
    update = function(p, dt, D)
        if p.phase ~= "run" or dt <= 0 then return end
        local rp = p.prev_p and math.abs(D.pitch - p.prev_p) / dt or 0
        local rr = p.prev_r and math.abs(D.roll - p.prev_r) / dt or 0
        p.prev_p, p.prev_r = D.pitch, D.roll
        p.moved_t = math.max(0, p.moved_t - dt)
        if D.gs > 1 or rp > 1 or rr > 1 then
            p.t, p.n, p.sp, p.sr, p.moved_t = 30, 0, 0, 0, 3
            return
        end
        p.n, p.sp, p.sr = p.n + 1, p.sp + D.pitch, p.sr + D.roll
        p.t = p.t - dt
        if p.t <= 0 then
            p.phase = "done"
            p.new_pitch = -p.sp / p.n
            p.new_roll = -p.sr / p.n
            p.btn = 1
        end
    end,
}

-- B: engine run-up vibration test (figure 6-3). The unit's accelerations
-- (X-Plane g_nrml / g_side / g_axil) are high-pass filtered; the RMS of what
-- is left against vib_limit_g is the "% of maximum limit", the worst value
-- is kept until Done.
PROC.vibration = {
    title = "Engine Vibration Test",
    start = function(p) p.phase = "intro" end,
    lines = function(p)
        if p.phase == "intro" then
            return { "1. Aircraft on the ground.", "2. Run the engine from idle to full",
                "power and back in 1-2 minutes.", "Select Start to begin." }
        end
        return { "Vibration test in progress...",
            string.format("%d%% of maximum limit", U.round(p.max)),
            (p.max > 100) and "(Maximum limit exceeded)" or "",
            "Select Done to complete test" }
    end,
    buttons = function(p)
        if p.phase == "intro" then return { { "Back" }, { "Start" } } end
        return { { "Done", (p.max > 100) and "x" or "check" } }
    end,
    press = function(p, label)
        if label == "Start" then
            p.phase, p.t, p.max, p.lp, p.e = "run", 0, 0, nil, { 0, 0, 0 }
            p.btn = 1
        else
            return true
        end
    end,
    update = function(p, dt, D)
        if p.phase ~= "run" or dt <= 0 then return end
        local g = { D.g_nrml or 1, D.g_side or 0, D.g_axil or 0 }
        p.lp = p.lp or { g[1], g[2], g[3] }
        local sum = 0
        for i = 1, 3 do
            p.lp[i] = p.lp[i] + (g[i] - p.lp[i]) * math.min(1, dt / 0.5)
            local hp = g[i] - p.lp[i]
            p.e[i] = p.e[i] + (hp * hp - p.e[i]) * math.min(1, dt / 0.25)
            sum = sum + p.e[i]
        end
        p.t = p.t + dt
        if p.t > 1 then
            p.max = math.max(p.max, math.sqrt(sum) / math.max(0.01, cfg.vib_limit_g) * 100)
        end
    end,
}

-- D: GMU 11 calibration on a compass rose (6.3.7.4): start facing magnetic
-- north (+-10 deg), then turn right about 25-30 deg at a time when told,
-- stopping when told, until a full circle; clears "Magnetometer not
-- calibrated".
PROC.magnetometer = {
    title = "Magnetometer Calibration",
    start = function(p) p.phase = "intro1" end,
    lines = function(p, D)
        local done = string.format("Turned %d° of 360°", math.floor(p.total or 0))
        if p.phase == "intro1" then
            return { "1. Taxi to a compass rose.", "2. Align the aircraft with",
                "magnetic north (within 10°).", "3. Engine and avionics on." }
        elseif p.phase == "intro2" then
            return { "Turn right when instructed and", "stop when instructed, about 30°",
                "each time, for a full circle.", "Select Start to begin." }
        elseif p.phase == "north" then
            return { "Align the aircraft with", "magnetic north (within 10°).",
                string.format("Heading %03d°", U.round(D.hdg) % 360) }
        elseif p.phase == "hold" then
            return { "Hold the aircraft still.", done }
        elseif p.phase == "turn" then
            return { "Turn right.", done }
        elseif p.phase == "stop" then
            return { "Stop the aircraft.", done }
        elseif p.phase == "ok" then
            return { "Calibration: Success" }
        end
        return { "Calibration: Failed", p.why or "" }
    end,
    buttons = function(p)
        if p.phase == "intro1" then return { { "Back" }, { "Next" } } end
        if p.phase == "intro2" then return { { "Back" }, { "Start" } } end
        if p.phase == "ok" then return { { "Done", "check" } } end
        if p.phase == "fail" then return { { "Done", "x" } } end
        return { { "Cancel" } }
    end,
    press = function(p, label)
        if label == "Next" then
            p.phase, p.btn = "intro2", 2
        elseif label == "Start" then
            p.phase, p.t, p.total, p.btn = "north", 0, 0, 1
        elseif label == "Back" and p.phase == "intro2" then
            p.phase, p.btn = "intro1", 2
        else
            if p.phase == "ok" then st.fail.mag_uncal = false end
            return true
        end
    end,
    update = function(p, dt, D)
        if dt <= 0 then return end
        local quiet = still(D)
        if p.phase == "north" then
            p.t = (quiet and math.abs(U.angdiff(D.hdg, 0)) <= 10) and (p.t + dt) or 0
            if p.t >= 2 then p.phase, p.t = "hold", 0 end
        elseif p.phase == "hold" then
            p.t = quiet and (p.t + dt) or 0
            if p.t >= 4 then
                if p.total >= 360 then
                    p.phase = "ok"
                else
                    p.phase, p.from = "turn", D.hdg
                end
            end
        elseif p.phase == "turn" or p.phase == "stop" then
            local d = U.angdiff(D.hdg, p.from)
            if d < -10 then
                p.phase, p.why = "fail", "Turn right only."
            elseif p.phase == "turn" and d >= 25 then
                p.phase = "stop"
            elseif p.phase == "stop" and quiet then
                p.total = p.total + d
                p.phase, p.t = "hold", 0
            end
        end
    end,
}

-----------------------------------------------------------------------------
-- Knob
-----------------------------------------------------------------------------

local function state()
    if st.cfg == nil then st.cfg = { sel = 1, scroll = 0 } end
    return st.cfg
end

function Cfg.knob_turn(dir, D)
    local s = state()
    local p = s.proc
    if p then
        local n = #PROC[p.kind].buttons(p)
        p.btn = U.clamp((p.btn or 1) + dir, 1, n)
    elseif s.page == nil then
        s.sel = U.clamp(s.sel + dir, 1, #visible_pages() + 1)
    elseif s.edit then
        s.val = step_value(s.edit, s.val, dir, D)
    else
        local rows = visible_rows(s.page)
        local i = s.sel
        repeat
            i = i + dir
        until i < 1 or i > #rows or selectable(rows[i])
        if i >= 1 and i <= #rows then s.sel = i end
    end
end

function Cfg.knob_press(D)
    local s = state()
    local p = s.proc
    if p then
        local def = PROC[p.kind]
        local list = def.buttons(p)
        local b = list[U.clamp(p.btn or 1, 1, #list)]
        if b and def.press(p, b[1]) then s.proc = nil end
        return
    end
    if s.page == nil then
        local pages = visible_pages()
        if s.sel > #pages then
            Sys.exit_config()
        else
            s.page, s.list_sel, s.sel, s.scroll = pages[s.sel], s.sel, 1, 0
        end
        return
    end
    if s.edit then
        if tostring(s.val) ~= tostring(cfg[s.edit.key]) then commit(s.edit, s.val) end
        s.edit = nil
        return
    end
    local r = visible_rows(s.page)[s.sel]
    if r == nil or r.kind == "back" then
        s.page, s.sel, s.scroll = nil, s.list_sel or 1, 0
    elseif r.kind == "action" then
        local np = { kind = r.proc, btn = 2 }
        PROC[r.proc].start(np)
        s.proc = np
    elseif selectable(r) then
        s.edit, s.val = r, cfg[r.key] or 0
    end
end

function Cfg.update(dt, D)
    if st.mode ~= Sys.CONFIG or st.cfg == nil then return end
    local p = st.cfg.proc
    if p then PROC[p.kind].update(p, dt, D) end
end

-----------------------------------------------------------------------------
-- Drawing
-----------------------------------------------------------------------------

local ROW_TOP, PITCH, ROWS = 221, 18, 12
local CELL_X0, CELL_X1 = 192, 312
local cell_col, frame_col, btn_cols, title_cols

-- figure 6-3: 16 px bar, grey 83 at the top fading to black
local function title_bar(text, right)
    if title_cols == nil then
        title_cols = {}
        for k = 0, 15 do
            local g = math.max(0, 83 - 5.2 * k) / 255
            title_cols[k] = G.rgba(g, g, g)
        end
    end
    for k = 0, 15 do G.rect(0, 239 - k, 320, 240 - k, title_cols[k]) end
    G.rstr_c(G.rfont("xbold", 11), text, 160, 225, C.white)
    if right then G.rstr(G.rfont("bold", 8), right, 314, 228, C.grey, G.JR) end
end

local function check_mark(cx, cy, s)
    G.strip(C.green, 2.5 * s, { cx - 7 * s, cy, cx - 2 * s, cy - 5 * s, cx + 7 * s, cy + 6 * s })
end

local function red_x(cx, cy, s)
    G.red_x(cx - 7 * s, cy - 7 * s, cx + 7 * s, cy + 7 * s, 3 * s)
end

local function scroll_for(sel, n, s)
    local first = s.scroll or 0
    if sel > first + ROWS then first = sel - ROWS end
    if sel < first + 1 then first = sel - 1 end
    s.scroll = U.clamp(first, 0, math.max(0, n - ROWS))
    return s.scroll
end

local function scrollbar(first, n)
    if n <= ROWS then return end
    local top, bot = ROW_TOP, ROW_TOP - ROWS * PITCH
    local h = (top - bot) * ROWS / n
    local y = top - h - (top - bot - h) * first / (n - ROWS)
    G.rect(315, bot, 318, top, cell_col)
    G.rect(315, y, 318, y + h, C.grey)
end

local function draw_list(s)
    local pages = visible_pages()
    local n = #pages + 1
    title_bar("Configuration Mode", "SFD" .. (Cfg.hooks and Cfg.hooks.n or 1))
    local fs = G.rfont("bold", 10)
    local first = scroll_for(s.sel, n, s)
    for i = first + 1, math.min(n, first + ROWS) do
        local top = ROW_TOP - (i - first - 1) * PITCH
        local label = (i > #pages) and "Exit Configuration Mode" or pages[i].title
        G.rstr(fs, label, 12, top - 13, C.white)
        if i == s.sel then G.box(5.5, top - 16.5, 312.5, top - 0.5, C.cyan, 1.5) end
    end
    scrollbar(first, n)
end

local function draw_page(s, D)
    local rows = visible_rows(s.page)
    local n = #rows
    if s.sel > n then s.sel = 1 end
    title_bar(s.page.title)
    local fs = G.rfont("bold", 10)
    local first = scroll_for(s.sel, n, s)
    for i = first + 1, math.min(n, first + ROWS) do
        local r = rows[i]
        local top = ROW_TOP - (i - first - 1) * PITCH
        local yb = top - 13
        G.rstr(fs, r.label, 12, yb, C.white)
        local cx = (CELL_X0 + CELL_X1) / 2
        if r.kind == "info" then
            G.rstr(fs, r.get(D), CELL_X1 - 4, yb, C.grey, G.JR)
        elseif r.kind == "status" then
            if r.ok() then check_mark(cx, top - 8, 0.8) else red_x(cx, top - 8, 0.7) end
        elseif r.kind == "action" then
            G.rstr(fs, "...", CELL_X1 - 4, yb, C.white, G.JR)
        elseif r.kind ~= "back" then
            local editing = s.edit == r
            local v = editing and s.val or cfg[r.key]
            G.rect(CELL_X0, top - 16, CELL_X1, top - 1, cell_col)
            G.rstr_c(fs, value_text(r, v, D), cx, yb, editing and C.cyan or C.white)
            if editing then G.box(CELL_X0 - 0.5, top - 16.5, CELL_X1 + 0.5, top - 0.5, C.cyan, 1.5) end
        end
        if i == s.sel and not s.edit then G.box(5.5, top - 16.5, 312.5, top - 0.5, C.cyan, 1.5) end
    end
    scrollbar(first, n)
end

-- Done / Start / ... buttons (figure 6-3: 96 x 55, bottom centre)
local function button(cx, label, icon, sel)
    if btn_cols == nil then
        btn_cols = {}
        for k = 0, 10 do
            local g = (78 - 5 * k) / 255
            btn_cols[k] = G.rgba(g, g, g)
        end
    end
    local x0, x1, y0, y1 = cx - 48, cx + 48, 5, 60
    for k = 0, 10 do G.rect(x0, y1 - 5 * (k + 1), x1, y1 - 5 * k, btn_cols[k]) end
    G.box(x0 + 1, y0 + 1, x1 - 1, y1 - 1, sel and C.cyan or frame_col, sel and 2 or 1)
    local fs = G.rfont("xbold", 11)
    if icon then
        G.rstr_c(fs, label, cx, 45, C.white)
        if icon == "check" then check_mark(cx, 22, 1.3) else red_x(cx, 22, 1.3) end
    else
        G.rstr_c(fs, label, cx, 28, C.white)
    end
end

local function draw_proc(p, D)
    local def = PROC[p.kind]
    title_bar(def.title)
    local fs = G.rfont("xbold", 12)
    local lines = def.lines(p, D)
    for i, line in ipairs(lines) do
        if line ~= "" then G.rstr_c(fs, line, 160, 182 - (i - 1) * 34, C.white) end
    end
    local b = def.buttons(p)
    if #b == 1 then
        button(160, b[1][1], b[1][2], true)
    else
        for i, bb in ipairs(b) do button(i == 1 and 96 or 224, bb[1], bb[2], p.btn == i) end
    end
end

function Cfg.draw(D, st_)
    cell_col = cell_col or G.hex("1A1A1A")
    frame_col = frame_col or G.hex("808080")
    local s = state()
    G.rect(0, 0, 320, 240, C.black)
    if s.proc then
        draw_proc(s.proc, D)
    elseif s.page then
        draw_page(s, D)
    else
        draw_list(s)
    end
end

return Cfg
