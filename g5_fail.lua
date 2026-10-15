-- g5_fail.lua: what the G5 can show (validity of each function), the AHRS
-- alignment states and the system messages. Pilot's Guide 1.4.1 / 1.6, AFMS
-- section 3.
--
-- Validity comes from three sources:
--   * external sensors and systems failed by X-Plane (config.ini [Failures]:
--     magnetometer, GPS navigator, nav receivers, OAT probe; the internal
--     AHRS / air data keys are empty by default, see note.md 2026-10-14)
--   * the G5's own faults: laminar/g5[_n]/fail_<name>, per unit, writable
--   * state: power-up initialisation, AHRS alignment, power to the magnetometer
--
-- Results in the unit state table:
--   st.valid = { att, air, gps, mag, oat, tas, hdg_mode = "hdg" | "trk" | "fail", hdg_flag }
--   st.att_state = "valid" | "aligning" | "kwl" (keep wings level) | "fail"
--   st.fail[name] = internal fault flags, st.ext[name] = external faults
--   st.msgs = active message ids in table order, st.has_msg, st.msg_unseen

local U, Sys, cfg, st

local F = {}

-- internal faults (laminar/g5[_n]/fail_<name>)
F.INTERNAL = {
    "ahrs",          -- inertial sensors: ATTITUDE FAIL
    "airdata",       -- pressure sensors: AIRSPEED / ALTITUDE FAIL
    "gps_rx",        -- internal GPS receiver
    "battery",       -- Battery fault: BATT; on battery "Critical battery fault! Powering off"
    "no_batt",       -- battery configured but not detected: NO BATT
    "charger",       -- Battery charger fault: no charging
    "overtemp",      -- Unit temperature limit exceeded
    "hardware",      -- Hardware fault (message only)
    "power_supply",  -- Power supply fault (message only)
    "display",       -- screen dead
    -- message-only conditions of table 1-2 / AFMS 7-2
    "mag_uncal", "mag_db", "sw_mismatch", "net_conflict", "comm_error", "factory_cal", "a429_cfg",
    -- GFC 500 messages (Pilot's Guide table 3-12)
    "afcs_key_stuck", "afcs_audio_db", "servo_clutch", "servo_trim_input",
}

-- external faults: config.ini key -> failure datarefs (6 = failed)
local EXTERNAL = {
    mag = "ext_fail_mag",
    gps = "ext_fail_gps",
    nav1 = "ext_fail_nav1",
    nav2 = "ext_fail_nav2",
    oat = "ext_fail_oat",
    ahrs = "ext_fail_ahrs",
    airdata = "ext_fail_airdata",
}

-- System messages (Pilot's Guide table 1-2), in display order
F.MESSAGES = {
    { "power_lost", "External Power Lost" },
    { "crit_batt", "Critical battery fault! Powering off" },
    { "batt_fault", "Battery fault" },
    { "charger_fault", "Battery charger fault" },
    { "low_batt", "Low battery" },
    { "hw_fault", "Hardware fault" },
    { "psu_fault", "Power supply fault" },
    { "overtemp", "Unit temperature limit exceeded" },
    { "mag_fault", "Magnetometer Hardware fault" },
    { "mag_uncal", "Magnetometer not calibrated" },
    { "mag_db", "Magnetic field model database out of date" },
    { "net_conflict", "Network address conflict" },
    { "comm_error", "Communication error" },
    { "factory_cal", "Factory calibration data invalid" },
    { "sw_mismatch", "Software version mismatch" },
    { "a429_cfg", "ARINC 429 interface configuration error" },
    { "afcs_key_stuck", "AFCS Controller Key Stuck" },
    { "afcs_audio_db", "AFCS Controller Audio Database Missing" },
    { "servo_clutch", "Servo Clutch Fault" },
    { "servo_trim_input", "Servo Trim Input Fault" },
    { "ext_gps", "Using external GPS data" },
    { "gps_fault", "GPS receiver fault" },
    { "no_nav", "" }, -- text depends on the navigator interface (see message_text)
}
local MSG_TEXT = {}
for _, m in ipairs(F.MESSAGES) do MSG_TEXT[m[1]] = m[2] end

function F.message_text(id)
    if id == "no_nav" then
        return (cfg.nav_interface == "rs232") and "Not receiving RS-232 data" or "Not receiving ARINC 429 data"
    end
    return MSG_TEXT[id] or id
end

local handles = {} -- external key -> { dataref handles }

local function parse_list(s)
    local out = {}
    for word in tostring(s or ""):gmatch("[^%s,;]+") do
        local name = word:find("/") and word or ("sim/operation/failures/" .. word)
        local h = U.find(name)
        if h then out[#out + 1] = h end
    end
    return out
end

function F.init(util, sys, config)
    U, Sys, cfg = util, sys, config
    st = Sys.st
    for key, cfg_key in pairs(EXTERNAL) do
        handles[key] = parse_list(cfg[cfg_key])
    end
end

function F.reset()
    st.fail = {}
    for _, k in ipairs(F.INTERNAL) do st.fail[k] = false end
    st.ext = {}
    st.valid = { att = false, air = false, gps = false, mag = false, oat = false, tas = false,
        hdg_mode = "fail", hdg_flag = false }
    st.att_state = "fail"
    st.aligning = false
    st.heading_fail = true
    st.up_t = 0          -- seconds since the unit finished booting
    st.kwl_t = 0         -- keep-wings-level phase left
    st.align_t = 0       -- aligning phase left
    st.att_was_failed = false
    st.clock = 0         -- free-running, for flashing
    st.msgs = {}
    st.msg_active = {}
    st.msg_seen = {}
    st.has_msg = false
    st.msg_unseen = false
end

local function ext_failed(key)
    local list = handles[key]
    for i = 1, #list do
        if U.geti(list[i], 0) == 6 then return true end
    end
    return false
end

-- AHRS: power-up / recovery runs "keep wings level" (no attitude shown;
-- it only progresses with the wings roughly level) and then "aligning"
-- (attitude shown, usable; faster when level). Pilot's Guide 1.4.1.1.
local function update_attitude(dt, D, failed)
    if failed then
        st.att_state = "fail"
        st.att_was_failed = true
        return
    end
    if st.att_was_failed then
        st.att_was_failed = false
        st.kwl_t = cfg.att_kwl_recover_s
        st.align_t = cfg.align_s
    end
    local level = math.abs(D.roll) < 10
    if st.kwl_t > 0 then
        if level then st.kwl_t = st.kwl_t - dt end
        st.att_state = "kwl"
    elseif st.align_t > 0 then
        st.align_t = st.align_t - dt * (level and 1 or 0.3)
        st.att_state = "aligning"
    else
        st.att_state = "valid"
    end
end

local function update_messages(dt)
    local m = st.msg_active
    local fail, ext, valid = st.fail, st.ext, st.valid
    m.power_lost = st.mode >= Sys.PFD and not st.ext_power
    m.crit_batt = st.crit_batt == true
    m.batt_fault = fail.battery
    m.charger_fault = fail.charger
    m.low_batt = st.msg_low_batt == true
    m.hw_fault = fail.hardware
    m.psu_fault = fail.power_supply
    m.mag_uncal = fail.mag_uncal
    m.mag_db = fail.mag_db
    m.net_conflict = fail.net_conflict
    m.comm_error = fail.comm_error or fail.net_conflict
    m.factory_cal = fail.factory_cal
    m.sw_mismatch = fail.sw_mismatch
    m.a429_cfg = fail.a429_cfg
    m.afcs_key_stuck = fail.afcs_key_stuck
    m.afcs_audio_db = fail.afcs_audio_db
    m.servo_clutch = fail.servo_clutch
    m.servo_trim_input = fail.servo_trim_input
    m.overtemp = fail.overtemp
    m.mag_fault = cfg.magnetometer ~= 0 and ext.mag
    m.gps_fault = cfg.gps_internal ~= 0 and fail.gps_rx
    m.ext_gps = st.gps_external_only == true
    m.no_nav = st.nav_lost == true

    local list = st.msgs
    for i = #list, 1, -1 do list[i] = nil end
    local unseen = false
    for _, def in ipairs(F.MESSAGES) do
        local id = def[1]
        if m[id] then
            list[#list + 1] = id
            if not st.msg_seen[id] then unseen = true end
        else
            st.msg_seen[id] = nil -- a message that comes back is new again
        end
    end
    st.has_msg = #list > 0
    st.msg_unseen = unseen
end

-- the message list was opened: everything in it is seen
function F.mark_seen()
    for _, id in ipairs(st.msgs) do st.msg_seen[id] = true end
    st.msg_unseen = false
end

-- [!] indicator: flashes while a message has not been viewed
function F.msg_icon_on()
    if not st.has_msg then return false end
    if not st.msg_unseen then return true end
    return math.floor(st.clock * 2) % 2 == 0
end

function F.update(dt, D)
    st.clock = st.clock + dt
    for key in pairs(EXTERNAL) do st.ext[key] = ext_failed(key) end
    local fail, ext, valid = st.fail, st.ext, st.valid

    if st.mode < Sys.PFD then
        -- off or booting: everything restarts at the next power-up
        for k in pairs(st.msg_seen) do st.msg_seen[k] = nil end
        st.up_t = 0
        st.kwl_t = cfg.att_kwl_s
        st.align_t = cfg.align_s
        st.att_was_failed = false
        st.att_state = "kwl"
    else
        st.up_t = st.up_t + dt
        update_attitude(dt, D, fail.ahrs or ext.ahrs)
    end
    local up = st.up_t

    valid.att = st.att_state == "valid" or st.att_state == "aligning"
    valid.air = not (fail.airdata or ext.airdata) and up >= cfg.air_init_s

    -- GPS: own receiver (needs time for a fix) or the navigator's position
    -- (needs aircraft power)
    local int_ok = cfg.gps_internal ~= 0 and not fail.gps_rx and up >= cfg.gps_init_s
    local ext_ok = cfg.gps_external ~= 0 and not ext.gps and st.ext_power and up >= cfg.air_init_s
    st.gps_int_ok = int_ok
    -- another unit's receiver over CAN (dual installations, G5.lua link_units)
    valid.gps = int_ok or ext_ok or st.can_gps == true
    st.gps_external_only = cfg.gps_internal ~= 0 and not int_ok and ext_ok and up >= cfg.gps_init_s

    -- magnetometer (GMU 11): installed, powered, not failed, AHRS running
    -- the GMU 11 runs from its own breaker: with an HSI installed the HSI's
    -- (magnetometer_bus), otherwise the unit's own bus (Installation Manual 4.2)
    local mag_powered
    if cfg.magnetometer_on_bus == 0 then
        mag_powered = true
    elseif cfg.magnetometer_bus >= 0 then
        mag_powered = (D.bus_all and D.bus_all[cfg.magnetometer_bus] or 0) >= cfg.power_min_volts
    else
        mag_powered = st.ext_power
    end
    valid.mag = cfg.magnetometer ~= 0 and mag_powered and not ext.mag
        and up >= cfg.hdg_init_s and valid.att
    if valid.mag then
        valid.hdg_mode = "hdg"
    elseif valid.gps then
        valid.hdg_mode = "trk"
    else
        valid.hdg_mode = "fail"
    end
    -- red-X "HDG" flag: a magnetometer is installed but its heading is lost
    valid.hdg_flag = cfg.magnetometer ~= 0 and not valid.mag
    -- OAT / TAS / winds come through the GAD 13 on the GAD breaker (gad_bus)
    local gad_ok = cfg.gad_bus < 0 or (D.bus_all and D.bus_all[cfg.gad_bus] or 0) >= cfg.power_min_volts
    valid.oat = not ext.oat and gad_ok
    valid.tas = valid.air and valid.oat

    -- the selected nav source has stopped sending
    local src = D.hsi_src
    st.nav_lost = st.mode >= Sys.PFD and ((src == 0 and ext.nav1) or (src == 1 and ext.nav2)
        or (src == 2 and ext.gps))

    st.aligning = st.att_state == "aligning" or st.att_state == "kwl"
    st.heading_fail = valid.hdg_mode == "fail"
    update_messages(dt)
end

return F
