-- g5_system.lua: unit state machine. Power on/boot, shutdown, external power
-- loss, the internal battery, backlight and altitude alerting. Validity,
-- alignment and messages are in g5_fail.lua.
--
-- Battery (Pilot's Guide 2.1.7, AFMS 3-2 / 4-2, Installation Manual 1.7.2,
-- Maintenance Manual 3 / 4.2.8):
--   * energy model in Wh: draw = power_base_w + power_backlight_w x the screen
--     brightness, so "up to 4 hours" only holds at a low backlight
--   * CC/CV charging from aircraft power inside the charge temperature window
--   * the battery follows the panel temperature (OAT + offset, slow); outside
--     the operating range (-20..+60 C, Installation Manual page 5) it cannot
--     power the unit, and "Unit temperature limit exceeded" ("Unit is too hot
--     or too cold", Pilot's Guide table 1-2, AFMS 7-2) is shown while the
--     unit is on; on the battery the unit then powers off after critical_batt_s
--   * state of charge persists between flights and sessions (G5.lua writes
--     state_unit<n>.ini)
-- Power loss (Installation Manual battery page "Automatic Power Off"):
--   on_ground (default) = countdown dialog only on the ground, in the air the
--   unit goes to battery by itself; always / never. A unit switched on without
--   aircraft power runs on its battery straight away (capacity check, MM 4.2.8).

local U, Sim, cfg

local Sys = {}

Sys.OFF = -1
Sys.BOOT = 0
Sys.PFD = 1
Sys.HSI = 2
Sys.CONFIG = 3   -- configuration mode (g5_config.lua)

local st = {}
Sys.st = st

-- configured power-up page; the HSI only when the HSI page is enabled
local function startup_page()
    return (cfg.startup_page == 2 and cfg.hsi_page ~= 0) and Sys.HSI or Sys.PFD
end

function Sys.init(util, sim, config)
    U, Sim, cfg = util, sim, config
end

-- Per-flight reset: unit off, menus closed. The battery keeps its charge
-- (persisted by G5.lua); only a first start uses battery_initial_pct.
function Sys.reset()
    st.mode = Sys.OFF
    st.page = startup_page()
    st.boot_t = 0
    st.fade = 0
    st.shutting = false

    st.ext_power = false
    st.ext_power_prev = false
    st.on_battery = false        -- running from the battery (by choice or automatically)
    st.started_on_battery = false
    st.pl_active = false         -- external power lost dialog
    st.pl_t = 0
    st.on_batt_t = 0             -- time on battery power (H:MM after ~1 min)
    st.crit_t = 0
    st.overtemp = false          -- unit temperature beyond its limits (message)
    st.overtemp_t = 0

    st.batt_pct = st.batt_pct or cfg.battery_initial_pct
    st.batt_temp = st.batt_temp or 20
    st.batt_draw_w = st.batt_draw_w or (cfg.power_base_w + cfg.power_backlight_w * 0.5)
    st.charging = false
    st.cannot_charge = false
    st.batt_present = cfg.battery_installed ~= 0
    st.batt_usable = st.batt_present
    st.bus_amps = 0

    st.backlight = cfg.backlight_initial
    st.bright_auto = cfg.backlight_auto_initial ~= 0

    st.msg_low_batt = false
    st.crit_batt = false
    st.fail = st.fail or {}

    st.knob_val = 1.0            -- bezel knob animation (laminar/g5/knob_turn_val)
    st.brg = { cfg.bearing1_source, cfg.bearing2_source }

    -- input/menu state lives here too so the datarefs can see it
    st.menu_open = false
    st.menu_anim = 0
    st.menu_sel = 1
    st.menu_scroll = 0
    st.popup = nil
    st.popup_open = false
    st.popup_anim = 0
    st.popup_row = 1
    st.bright_open = false
    st.bright_anim = 0
    st.anim = {}                 -- slide curves: [key] = { lin, open } (g5_input.lua)
    st.menu_press = nil          -- menu tile drawn pressed
    st.press_age = 0
    st.press_pending = false
    st.bright_press = false      -- backlight Auto button drawn pressed
    st.bright_press_age = 0
    st.bright_toggle_pending = false
    st.bright_confirm = false    -- backlight wedge green while sliding out after a knob press
    st.pwr_down = false
    st.pwr_t = 0
    st.pwr_handled = false
    st.knob_down = false
    st.knob_t = 0
    st.knob_handled = false

    st.alt_alert_t = 0
    st.alt_alert_prev_bug = nil
    st.alt_captured = false
    st.alt_alert_phase = 0

    -- the rheostat belongs to the acting master only (update_backlight); at
    -- load a unit that is not installed, or a configured slave, leaves it
    st.rheo_last = nil
    if cfg.installed ~= 0 and (st.role_eff == nil and cfg.role == 0
        or st.role_eff == "master" or st.role_eff == "takeover") then
        Sim.set_inst_brightness(cfg.brightness_rheostat, st.backlight)
        st.rheo_last = st.backlight
    end
end

function Sys.is_on()
    return st.mode >= Sys.BOOT
end

local function batt_can_run()
    return st.batt_usable and st.batt_pct > cfg.battery_cutoff_pct
end

function Sys.start_boot()
    if st.mode ~= Sys.OFF then return end
    if cfg.installed == 0 then return end     -- its object is not in the aircraft
    if not st.ext_power and not batt_can_run() then return end
    st.mode = Sys.BOOT
    st.page = startup_page()
    st.boot_t = 0
    st.boot_config = false
    st.cfg = nil
    st.fade = 0
    st.shutting = false
    st.pl_active = false
    st.crit_t = 0
    -- switched on without aircraft power: it simply runs on the battery
    st.started_on_battery = not st.ext_power
    st.on_battery = st.started_on_battery
    st.on_batt_t = 0
    -- every power-up starts in the configured default backlight mode (Auto:
    -- AFMS section 4, Maintenance Manual section 3)
    st.bright_auto = cfg.backlight_auto_initial ~= 0
    if not st.bright_auto then st.backlight = cfg.backlight_initial end
    st.photocell = nil
    U.log("power on" .. (st.started_on_battery and " (battery)" or ""))
end

-- Restart without a power cycle (configuration mode in / out). The battery
-- and power state carry on; the menus close.
local function reboot(config)
    st.mode = Sys.BOOT
    st.boot_t = 0
    st.boot_config = config
    st.cfg = nil
    st.menu_open = false
    st.popup = nil
    st.popup_open = false
    st.bright_open = false
end

-- Configuration mode: the knob held while the unit powers up (Installation
-- Manual 6.3.2), or the laminar/g5/config_mode command.
function Sys.enter_config()
    if st.shutting then return end
    if st.mode == Sys.OFF then
        Sys.start_boot()
        if st.mode == Sys.BOOT then st.boot_config = true end
    elseif st.mode ~= Sys.CONFIG then
        reboot(true)
    end
end

-- "Exit Configuration Mode": the unit restarts with the new settings
function Sys.exit_config()
    if st.mode ~= Sys.CONFIG then return end
    st.page = startup_page()
    reboot(false)
    U.log("configuration mode: exit")
end

function Sys.shutdown()
    if st.mode == Sys.OFF or st.shutting then return end
    st.shutting = true
    st.menu_open = false
    st.popup = nil
    st.bright_open = false
    U.log("power off")
end

local function finish_shutdown()
    st.mode = Sys.OFF
    st.shutting = false
    st.fade = 0
    st.pl_active = false
    st.on_battery = false
    st.started_on_battery = false
    st.crit_batt = false
    st.crit_t = 0
    st.overtemp_t = 0
end

function Sys.set_page(p)
    -- no HSI page on an attitude-only installation (hsi_page = 0)
    if p == Sys.HSI and cfg.hsi_page == 0 then return end
    if p == Sys.PFD or p == Sys.HSI then
        st.page = p
        if st.mode == Sys.PFD or st.mode == Sys.HSI then st.mode = p end
    end
end

-- Any key during the power-lost countdown keeps the unit on battery.
function Sys.any_key()
    if st.pl_active then
        st.pl_active = false
        st.on_battery = true
        return true
    end
    return false
end

-- Power the unit draws (W): electronics plus a backlight term that follows
-- the actual screen brightness (st.screen_ratio, set by the brightness callback)
local function unit_power_w()
    return cfg.power_base_w + cfg.power_backlight_w * U.clamp(st.screen_ratio or 0.5, 0, 1)
end

local function update_battery(dt, D)
    local on = st.mode ~= Sys.OFF
    local fail = st.fail

    -- battery temperature: the panel runs warmer than the outside air, slowly
    local target = D.oat_c + cfg.battery_temp_offset + (on and 5 or 0)
    st.batt_temp = st.batt_temp + (target - st.batt_temp) * math.min(1, dt / cfg.battery_temp_tau_s)
    local t = st.batt_temp
    -- the unit's temperature (the battery follows the panel) beyond the
    -- operating range: the message (g5_fail.lua), whatever the power source
    st.overtemp = st.mode >= Sys.PFD and (t < cfg.battery_op_temp_min or t > cfg.battery_op_temp_max)

    st.batt_present = cfg.battery_installed ~= 0 and not fail.no_batt
    local good = st.batt_present and not fail.battery
    st.batt_usable = good and t >= cfg.battery_op_temp_min and t <= cfg.battery_op_temp_max

    local cap_wh = math.max(0.1, cfg.battery_wh * cfg.battery_health)
    local draw = on and unit_power_w() or 0
    local charge_w = 0
    local temp_ok = t >= cfg.battery_charge_temp_min and t <= cfg.battery_charge_temp_max

    -- running on the battery
    local from_batt = on and not st.ext_power and st.batt_usable
    if from_batt then
        st.batt_pct = st.batt_pct - draw * dt / 3600 / cap_wh * 100
        st.batt_draw_w = st.batt_draw_w + (draw - st.batt_draw_w) * math.min(1, dt / 20)
        st.on_batt_t = st.on_batt_t + dt
    else
        st.on_batt_t = 0
    end

    -- charging from aircraft power: constant current to battery_cv_pct, then
    -- tapering (constant voltage); "unable to charge" with a charger fault or
    -- outside the charge temperature window (Pilot's Guide 2.1.7)
    -- a unit that is not installed has no charger and loads no bus
    local fitted = cfg.installed ~= 0
    st.cannot_charge = fitted and st.ext_power and good and (fail.charger or not temp_ok)
    st.charging = fitted and st.ext_power and good and not fail.charger and temp_ok and st.batt_pct < 99.5
    if st.charging then
        local rate = 100 * cfg.battery_charge_c
        if st.batt_pct > cfg.battery_cv_pct then
            rate = rate * (100 - st.batt_pct) / (100 - cfg.battery_cv_pct)
        end
        local add = rate * dt / 3600
        st.batt_pct = st.batt_pct + add
        charge_w = (dt > 0) and (add / 100 * cap_wh * 3600 / dt / cfg.battery_charge_eff) or 0
    end
    st.batt_pct = U.clamp(st.batt_pct, 0, 100)

    -- current taken from the aircraft bus (for plugin_bus_load_amps)
    local volts = st.bus_volts or 0
    if fitted and st.ext_power and volts > 1 then
        st.bus_amps = (draw + charge_w) / volts
    else
        st.bus_amps = 0
    end
end

-- Remaining time on the battery (minutes) at the smoothed draw
function Sys.battery_minutes()
    local cap_wh = cfg.battery_wh * cfg.battery_health
    local usable = math.max(0, st.batt_pct - cfg.battery_cutoff_pct) / 100 * cap_wh
    return usable / math.max(0.1, st.batt_draw_w) * 60
end

local function auto_power_off_applies(D)
    local m = cfg.auto_power_off
    if m == "never" then return false end
    if m == "always" then return true end
    return D.on_ground ~= 0
end

-- real_dt: wall-clock step for what the unit's own electronics time (boot
-- screen, shutdown fade, the External Power Lost countdown and the critical
-- battery / over-temperature graces), so they run at real speed whatever the
-- time acceleration and also while X-Plane is paused
local function update_power(dt, D, real_dt)
    st.bus_volts = (D.bus_all and D.bus_all[cfg.power_bus]) or D.bus_volts or 0
    st.ext_power = st.bus_volts >= cfg.power_min_volts

    -- Real G5 powers up whenever aircraft power is applied (edge triggered so a
    -- manual shutdown on a live bus stays off).
    if cfg.auto_power_on ~= 0 and st.mode == Sys.OFF and st.ext_power and not st.ext_power_prev then
        Sys.start_boot()
    end
    st.ext_power_prev = st.ext_power

    if st.mode == Sys.BOOT then
        st.boot_t = st.boot_t + real_dt
        -- knob held during power-up: configuration mode
        if st.knob_down then st.boot_config = true end
        if st.boot_t >= cfg.boot_logo_s then
            st.mode = st.boot_config and Sys.CONFIG or st.page
            if st.boot_config then U.log("configuration mode") end
        end
    end

    local overtemp_wait = false
    if st.mode ~= Sys.OFF and not st.shutting then
        if st.ext_power then
            st.pl_active = false
            st.on_battery = false
            st.started_on_battery = false
        elseif st.fail.battery and st.batt_present then
            -- "Critical battery fault! Powering off" (Pilot's Guide table 1-2)
            st.crit_batt = true
            st.crit_t = st.crit_t + real_dt
            if st.crit_t >= cfg.critical_batt_s then Sys.shutdown() end
        elseif not st.batt_usable then
            if st.overtemp and st.batt_present then
                -- a good battery that is too cold / hot: the message first
                -- (the grace is the critical battery fault's), then a normal
                -- power-off. Our reading: the manuals give no delay.
                overtemp_wait = true
                st.overtemp_t = st.overtemp_t + real_dt
                if st.overtemp_t >= cfg.critical_batt_s then Sys.shutdown() end
            else
                finish_shutdown()  -- no battery: the screen just dies
            end
        elseif st.batt_pct <= cfg.battery_cutoff_pct then
            Sys.shutdown()         -- empty
        elseif not st.on_battery then
            if st.started_on_battery or not auto_power_off_applies(D) then
                st.on_battery = true   -- in the air: straight to battery, message only
            else
                if not st.pl_active then
                    st.pl_active = true
                    st.pl_t = cfg.power_lost_countdown_s
                end
                st.pl_t = st.pl_t - real_dt
                if st.pl_t <= 0 then
                    st.pl_active = false
                    Sys.shutdown()
                end
            end
        end
    end

    if not overtemp_wait then st.overtemp_t = 0 end

    if st.shutting then
        st.fade = st.fade + real_dt / cfg.shutdown_fade_s
        if st.fade >= 1 then finish_shutdown() end
    end
end

-- Highest backlight level: configuration mode "Maximum Display Brightness"
-- (backlight_max, default 100 %); never below backlight_min
function Sys.backlight_max()
    return U.clamp(cfg.backlight_max or 1, cfg.backlight_min, 1)
end

-- The photocell as the unit reads it: X-Plane's ambient level through a
-- first-order filter of backlight_filter_s ("Filter Time Constant"), on sim
-- time; 0 = no filter (the raw level, as before 2026-10-29). Restarts at
-- the current light at every power-up.
local function photocell()
    if (cfg.backlight_filter_s or 0) > 0 and st.photocell then return st.photocell end
    return st.ambient or 1
end

local function update_photocell(dt)
    local tau = cfg.backlight_filter_s or 0
    local raw = st.ambient or 1
    if tau <= 0 or st.photocell == nil then
        st.photocell = raw
    elseif dt > 0 then
        st.photocell = st.photocell + (raw - st.photocell) * (1 - math.exp(-dt / tau))
    end
end

-- The photocell reading, 0..1: the (filtered) ambient level ^ 0.25, about 0.39
-- at night (0.024) and 1 in daylight. Shown in % on the Backlight page.
local function photocell_reading()
    return math.max(photocell(), cfg.ambient_min) ^ 0.25
end

function Sys.photocell_pct()
    return 100 * photocell_reading()
end

-- Minimum / Maximum Photocell Input (configuration mode Backlight page), % of
-- the reading: the ends of the Auto curve on the photocell axis. The two limits
-- keep PHOTO_GAP % between them (our rule: the manuals give no range or
-- units), whatever a hand-edited config.ini or state file says.
Sys.PHOTO_GAP = 5
function Sys.photocell_limits()
    local lo = U.clamp(cfg.photocell_min or 0, 0, 100 - Sys.PHOTO_GAP)
    local hi = U.clamp(cfg.photocell_max or 100, lo + Sys.PHOTO_GAP, 100)
    return lo, hi
end

-- Auto (photocell) level: backlight_neutral at or below the Minimum Photocell
-- Input, 100 % at or above the Maximum, straight in between. The shipped
-- limits (0 / 100) make that today's curve, backlight_neutral + (1 -
-- backlight_neutral) x reading, to the last bit. Shown on the backlight page
-- (AFMS 4-2) and used as the level, so switching to Manual starts from it
-- without a jump. Capped at the Maximum Display Brightness.
function Sys.auto_level()
    local lo, hi = Sys.photocell_limits()
    lo, hi = lo / 100, hi / 100
    local t = U.clamp((photocell_reading() - lo) / (hi - lo), 0, 1)
    return U.clamp(cfg.backlight_neutral + (1 - cfg.backlight_neutral) * t, cfg.backlight_min,
        Sys.backlight_max())
end

local function update_backlight(dt, D)
    update_photocell(dt)
    if st.bright_auto then st.backlight = Sys.auto_level() end
    st.backlight = U.clamp(st.backlight, cfg.backlight_min, Sys.backlight_max())
    -- the panel rheostat follows the acting master's backlight only: two
    -- units writing the same index would fight, and a unit that is not
    -- installed has no say. Written when the value changes.
    local owner = cfg.installed ~= 0 and (st.role_eff == "master" or st.role_eff == "takeover")
    if owner and cfg.brightness_rheostat >= 0 then
        if st.rheo_last ~= st.backlight then
            Sim.set_inst_brightness(cfg.brightness_rheostat, st.backlight)
            st.rheo_last = st.backlight
        end
    else
        st.rheo_last = nil
    end
end

-- Altitude alerting (manual 2.1.3.2): flash 5 s passing within 1000 ft and
-- 200 ft of the selected altitude; yellow once captured and deviating > 200 ft.
local function update_alt_alert(dt, D)
    local bug = D.alt_bug
    if st.alt_alert_prev_bug == nil or math.abs(bug - st.alt_alert_prev_bug) > 1 then
        st.alt_alert_prev_bug = bug
        st.alt_alert_phase = 0
        st.alt_captured = false
        st.alt_alert_t = 0
    end
    local dev = math.abs(D.alt - bug)
    if st.alt_alert_phase == 0 and dev < 1000 and dev > 200 then
        st.alt_alert_phase = 1
        st.alt_alert_t = 5
    elseif st.alt_alert_phase <= 1 and dev <= 200 then
        st.alt_alert_phase = 2
        st.alt_alert_t = 5
    end
    if dev < 50 then st.alt_captured = true end
    if st.alt_captured and dev > 200 and st.alt_alert_phase ~= 3 then
        st.alt_alert_phase = 3
        st.alt_alert_t = 5
    end
    if st.alt_alert_phase == 3 and dev <= 200 then
        st.alt_alert_phase = 2
    end
    if st.alt_alert_t > 0 then st.alt_alert_t = st.alt_alert_t - dt end
end

-- dt is simulator time (frozen while paused or in replay, scaled with time
-- acceleration; see G5.lua tick); real_dt is wall-clock time (boot, fade)
function Sys.update(dt, D, real_dt)
    update_power(dt, D, real_dt or dt)
    update_battery(dt, D)
    update_backlight(dt, D)
    update_alt_alert(dt, D)

    -- unusual attitude: back to the PFD page (Pilot's Guide 1.5.1 note)
    if cfg.unusual_revert ~= 0 and st.mode == Sys.HSI and st.valid and st.valid.att
        and (math.abs(D.roll) > 60 or D.pitch > 30 or D.pitch < -20) then
        Sys.set_page(Sys.PFD)
        U.log("unusual attitude: PFD page")
    end

    -- messages, validity and alignment: g5_fail.lua
    st.msg_low_batt = st.mode >= Sys.PFD and st.batt_present and st.batt_pct <= cfg.battery_low_pct
        and not st.charging
end

-- Device brightness callback value (0..1 of the OBJ nits). `ambient` is X-Plane's
-- readable-without-glare ratio for the current light (the callback argument).
-- The screen sits at that level when the backlight is at backlight_neutral;
-- every backlight_doubling of backlight above / below doubles / halves it, so
-- the unit's % is respected and the screen still adapts to day and night.
-- Auto uses Sys.auto_level(). The result also drives the knob ring glow.
st.ambient = 1
st.screen_ratio = 0
function Sys.screen_brightness(ambient, no_store)
    local amb = (ambient ~= nil) and U.clamp(ambient, 0, 1) or st.ambient
    -- the light is read while the unit is off too: the photocell starts from
    -- the light at power-up, not from the last value seen while it was on
    if not no_store then st.ambient = amb end
    if st.mode == Sys.OFF then
        if not no_store then st.screen_ratio = 0 end
        return 0
    end
    -- in Auto the photocell (filtered, see photocell()) sets the base too:
    -- with a filter time constant the screen follows a change of light late.
    -- The popup window uses it as well (its own ambient is only the base in
    -- Manual or without a filter), so both screens show the same level.
    if st.bright_auto and (cfg.backlight_filter_s or 0) > 0 and st.photocell then amb = st.photocell end
    local base = math.max(amb, cfg.ambient_min)
    if no_store then
        local level = st.bright_auto and Sys.auto_level() or st.backlight
        return U.clamp(base * 2 ^ ((level - cfg.backlight_neutral) / cfg.backlight_doubling), 0, 1)
    end
    local level = st.bright_auto and Sys.auto_level() or st.backlight
    st.screen_ratio = U.clamp(base * 2 ^ ((level - cfg.backlight_neutral) / cfg.backlight_doubling), 0, 1)
    return st.screen_ratio
end

return Sys
