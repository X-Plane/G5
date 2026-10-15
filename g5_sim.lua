-- g5_sim.lua: every sim dataref the G5 reads or writes, looked up once,
-- sampled once per frame into the plain table `D` so drawing code never calls
-- into the sim.

local U -- set by init()

local Sim = {}

local H = {}  -- dataref handles
local CMD = {} -- sim commands
Sim.H = H
Sim.CMD = CMD

-- Values sampled each frame
local D = {}
Sim.D = D

local REFS = {
    -- AHRS / air data (pilot side, same sources the old G5.System used)
    pitch        = "sim/cockpit2/gauges/indicators/pitch_AHARS_deg_pilot",
    roll         = "sim/cockpit2/gauges/indicators/roll_AHARS_deg_pilot",
    hdg          = "sim/cockpit2/gauges/indicators/heading_AHARS_deg_mag_pilot",
    track        = "sim/cockpit2/gauges/indicators/ground_track_mag_pilot",
    ias          = "sim/cockpit2/gauges/indicators/airspeed_kts_pilot",
    tas          = "sim/cockpit2/gauges/indicators/true_airspeed_kts_pilot",
    gs           = "sim/cockpit2/gauges/indicators/ground_speed_kt",
    ias_accel    = "sim/cockpit2/gauges/indicators/airspeed_acceleration_kts_sec_pilot",
    alt          = "sim/cockpit2/gauges/indicators/altitude_ft_pilot",
    vs           = "sim/flightmodel/position/vh_ind_fpm",
    baro         = "sim/cockpit2/gauges/actuators/barometer_setting_in_hg_pilot",
    oat_c        = "sim/cockpit2/temperature/outside_air_temp_degc",
    slip         = "sim/cockpit2/gauges/indicators/slip_deg",
    turn_rate    = "sim/cockpit2/gauges/indicators/turn_rate_heading_deg_pilot",
    wind_dir     = "sim/cockpit2/gauges/indicators/wind_heading_deg_mag",
    wind_spd     = "sim/cockpit2/gauges/indicators/wind_speed_kts",
    -- accelerations at the CG (vibration test, configuration mode)
    g_nrml       = "sim/flightmodel/forces/g_nrml",
    g_side       = "sim/flightmodel/forces/g_side",
    g_axil       = "sim/flightmodel/forces/g_axil",

    -- Airframe V-speeds (Plane Maker, knots)
    vso          = "sim/aircraft/view/acf_Vso",
    vs1          = "sim/aircraft/view/acf_Vs",
    vfe          = "sim/aircraft/view/acf_Vfe",
    vno          = "sim/aircraft/view/acf_Vno",
    vne          = "sim/aircraft/view/acf_Vne",

    -- Electrical / lighting
    bus_volts    = "sim/cockpit2/electrical/bus_volts",
    battery_on   = "sim/cockpit2/electrical/battery_on",
    inst_bright  = "sim/cockpit2/switches/instrument_brightness_ratio",
    replay       = "sim/time/is_in_replay",
    paused       = "sim/time/paused",
    run_time     = "sim/time/total_running_time_sec",
    on_ground    = "sim/flightmodel/failures/onground_any",
    bus_load     = "sim/cockpit2/electrical/plugin_bus_load_amps",

    -- Autopilot / flight director
    ap_mode      = "sim/cockpit/autopilot/autopilot_mode",       -- 0 off, 1 FD, 2 AP
    ap_on        = "sim/cockpit2/autopilot/autopilot_on",
    -- servos engaged (autopilot_on is also 1 with the flight director alone)
    servos_on    = "sim/cockpit2/autopilot/servos_on",
    fd_pitch     = "sim/cockpit2/autopilot/flight_director_pitch_deg",
    fd_roll      = "sim/cockpit2/autopilot/flight_director_roll_deg",
    hdg_mode     = "sim/cockpit2/autopilot/heading_mode",
    alt_mode     = "sim/cockpit2/autopilot/altitude_mode",
    nav_status   = "sim/cockpit2/autopilot/nav_status",
    gpss_status  = "sim/cockpit2/autopilot/gpss_status",
    gs_status    = "sim/cockpit2/autopilot/glideslope_status",
    vnav_status  = "sim/cockpit2/autopilot/vnav_status",
    alt_armed    = "sim/cockpit2/autopilot/altitude_hold_armed",
    hdg_is_gpss  = "sim/cockpit2/autopilot/heading_is_gpss",
    yd_on        = "sim/cockpit2/switches/yaw_damper_on",
    -- per-mode status (0 off, 1 armed, 2 active) for the AFCS status box
    hdg_status   = "sim/cockpit2/autopilot/heading_status",
    hdg_hold_status = "sim/cockpit2/autopilot/heading_hold_status",
    track_status = "sim/cockpit2/autopilot/track_status",
    vvi_status   = "sim/cockpit2/autopilot/vvi_status",
    speed_status = "sim/cockpit2/autopilot/speed_status",
    fpa_status   = "sim/cockpit2/autopilot/fpa_status",
    alt_hold_status = "sim/cockpit2/autopilot/altitude_hold_status",
    bc_status    = "sim/cockpit2/autopilot/backcourse_status",
    apr_status   = "sim/cockpit2/autopilot/approach_status",
    toga_status  = "sim/cockpit2/autopilot/TOGA_status",
    toga_lat_status = "sim/cockpit2/autopilot/TOGA_lateral_status",
    fpa          = "sim/cockpit2/autopilot/fpa",
    -- autopilot health and trim
    otto_fail_warn = "sim/cockpit2/autopilot/otto_fail_warn",
    ap_has_power = "sim/cockpit2/autopilot/autopilot_has_power",
    trim_fail    = "sim/cockpit2/autopilot/autopilot_trim_fail",
    trim_up      = "sim/cockpit2/annunciators/autopilot_trim_up",
    trim_down    = "sim/cockpit2/annunciators/autopilot_trim_down",
    rel_otto     = "sim/operation/failures/rel_otto",
    rel_servos   = "sim/operation/failures/rel_auto_servos",
    hdg_bug      = "sim/cockpit2/autopilot/heading_dial_deg_mag_pilot",
    alt_bug      = "sim/cockpit2/autopilot/altitude_dial_ft",
    alt_hold     = "sim/cockpit2/autopilot/altitude_hold_ft",
    spd_bug      = "sim/cockpit2/autopilot/airspeed_dial_kts",
    vs_bug       = "sim/cockpit2/autopilot/vvi_dial_fpm",

    -- HSI (whatever source the pilot HSI is slaved to: 0 NAV1, 1 NAV2, 2 GPS)
    hsi_src      = "sim/cockpit2/radios/actuators/HSI_source_select_pilot",
    hsi_obs      = "sim/cockpit2/radios/actuators/hsi_obs_deg_mag_pilot",
    hsi_hdef     = "sim/cockpit2/radios/indicators/hsi_hdef_dots_pilot",
    hsi_vdef     = "sim/cockpit2/radios/indicators/hsi_vdef_dots_pilot",
    hsi_fromto   = "sim/cockpit2/radios/indicators/hsi_flag_from_to_pilot",  -- 0 off, 1 to, 2 from
    hsi_show_h   = "sim/cockpit2/radios/indicators/hsi_display_horizontal_pilot",
    hsi_show_v   = "sim/cockpit2/radios/indicators/hsi_display_vertical_pilot",
    hsi_gs_flag  = "sim/cockpit2/radios/indicators/hsi_flag_glideslope_pilot",
    hsi_has_dme  = "sim/cockpit2/radios/indicators/hsi_has_dme_pilot",
    hsi_dme      = "sim/cockpit2/radios/indicators/hsi_dme_distance_nm_pilot",
    nav1_freq    = "sim/cockpit2/radios/actuators/nav1_frequency_hz",  -- 10 kHz units (11030 = 110.30)
    nav2_freq    = "sim/cockpit2/radios/actuators/nav2_frequency_hz",
    nav1_type    = "sim/cockpit2/radios/indicators/nav1_type",
    nav2_type    = "sim/cockpit2/radios/indicators/nav2_type",
    nav1_show_h  = "sim/cockpit2/radios/indicators/nav1_display_horizontal",
    nav2_show_h  = "sim/cockpit2/radios/indicators/nav2_display_horizontal",
    nav1_brg     = "sim/cockpit2/radios/indicators/nav1_bearing_deg_mag",
    nav2_brg     = "sim/cockpit2/radios/indicators/nav2_bearing_deg_mag",
    nav1_dme     = "sim/cockpit2/radios/indicators/nav1_dme_distance_nm",
    nav2_dme     = "sim/cockpit2/radios/indicators/nav2_dme_distance_nm",
    nav1_has_dme = "sim/cockpit2/radios/indicators/nav1_has_dme",
    nav2_has_dme = "sim/cockpit2/radios/indicators/nav2_has_dme",
    gps_brg      = "sim/cockpit2/radios/indicators/gps_bearing_deg_mag",
    gps_dme      = "sim/cockpit2/radios/indicators/gps_dme_distance_nm",
    gps_has_dme  = "sim/cockpit2/radios/indicators/gps_has_dme",
    gps_cdi      = "sim/cockpit/radios/gps_cdi_sensitivity",
    gps_dtk      = "sim/cockpit/radios/gps_obs_degm",          -- desired track
    gps_seq      = "sim/cockpit/radios/gps_sequencing",        -- 1 = OBS mode
    altv_armed   = "sim/cockpit2/autopilot/altv_armed",
}

local COMMANDS = {
    gpss        = "sim/autopilot/gpss",
    hdg_sync    = "sim/autopilot/heading_sync",
    src_nav1    = "sim/autopilot/hsi_select_nav_1",
    src_nav2    = "sim/autopilot/hsi_select_nav_2",
    src_gps     = "sim/autopilot/hsi_select_gps",
}

local cfg

function Sim.init(util, config)
    U = util
    cfg = config
    for k, name in pairs(REFS) do
        H[k] = U.find(name)
    end
    for k, name in pairs(COMMANDS) do
        CMD[k] = U.find_cmd(name)
    end
end

local getf, geti = nil, nil

function Sim.read()
    getf, geti = U.getf, U.geti
    local getfa, getia = U.getfa, U.getia

    D.pitch     = getf(H.pitch, 0)
    D.roll      = getf(H.roll, 0)
    D.hdg       = U.wrap360(getf(H.hdg, 0))
    D.track     = U.wrap360(getf(H.track, D.hdg))
    -- helicopters can show negative IAS when flying backwards (old G5.System used abs())
    D.ias       = math.abs(getf(H.ias, 0))
    D.tas       = getf(H.tas, 0)
    D.gs        = getf(H.gs, 0)
    D.ias_accel = getf(H.ias_accel, 0)
    D.alt       = getf(H.alt, 0)
    D.vs        = getf(H.vs, 0)
    D.baro      = getf(H.baro, 29.92)
    D.oat_c     = getf(H.oat_c, 15)
    D.slip      = getf(H.slip, 0)
    D.turn_rate = getf(H.turn_rate, 0)
    D.wind_dir  = getf(H.wind_dir, 0)
    D.wind_spd  = getf(H.wind_spd, 0)
    D.g_nrml    = getf(H.g_nrml, 1)
    D.g_side    = getf(H.g_side, 0)
    D.g_axil    = getf(H.g_axil, 0)

    D.vso = getf(H.vso, 0)
    D.vs1 = getf(H.vs1, 0)
    D.vfe = getf(H.vfe, 0)
    D.vno = getf(H.vno, 0)
    D.vne = getf(H.vne, 0)

    -- every bus: each unit picks its own (config power_bus, per unit)
    D.bus_all = D.bus_all or {}
    for i = 0, 5 do D.bus_all[i] = getfa(H.bus_volts, i, 0) end
    D.bus_volts  = D.bus_all[cfg.power_bus] or 0
    D.battery_on = getia(H.battery_on, 0, 0)
    D.replay     = geti(H.replay, 0)
    D.paused     = geti(H.paused, 0)
    D.run_time   = getf(H.run_time, 0)
    D.on_ground  = geti(H.on_ground, 1)

    D.ap_mode     = geti(H.ap_mode, 0)
    D.ap_on       = geti(H.ap_on, 0)
    D.servos_on   = geti(H.servos_on, D.ap_mode >= 2 and 1 or 0)
    D.fd_pitch    = getf(H.fd_pitch, 0)
    D.fd_roll     = getf(H.fd_roll, 0)
    D.hdg_mode    = geti(H.hdg_mode, 0)
    D.alt_mode    = geti(H.alt_mode, 0)
    D.nav_status  = geti(H.nav_status, 0)
    D.gpss_status = geti(H.gpss_status, 0)
    D.gs_status   = geti(H.gs_status, 0)
    D.vnav_status = geti(H.vnav_status, 0)
    D.alt_armed   = geti(H.alt_armed, 0)
    D.hdg_is_gpss = geti(H.hdg_is_gpss, 0)
    D.yd_on       = geti(H.yd_on, 0)
    D.hdg_status  = geti(H.hdg_status, 0)
    D.hdg_hold_status = geti(H.hdg_hold_status, 0)
    D.track_status = geti(H.track_status, 0)
    D.vvi_status  = geti(H.vvi_status, 0)
    D.speed_status = geti(H.speed_status, 0)
    D.fpa_status  = geti(H.fpa_status, 0)
    D.alt_hold_status = geti(H.alt_hold_status, 0)
    D.bc_status   = geti(H.bc_status, 0)
    D.apr_status  = geti(H.apr_status, 0)
    D.toga_status = geti(H.toga_status, 0)
    D.toga_lat_status = geti(H.toga_lat_status, 0)
    D.fpa         = getf(H.fpa, 0)
    D.otto_fail_warn = geti(H.otto_fail_warn, 0)
    D.ap_has_power = geti(H.ap_has_power, 1)
    D.trim_fail   = geti(H.trim_fail, 0)
    D.trim_up     = geti(H.trim_up, 0)
    D.trim_down   = geti(H.trim_down, 0)
    D.otto_failed = geti(H.rel_otto, 0) == 6
    D.servos_failed = geti(H.rel_servos, 0) == 6
    D.hdg_bug     = U.wrap360(getf(H.hdg_bug, 0))
    D.alt_bug     = getf(H.alt_bug, 0)
    D.alt_hold    = getf(H.alt_hold, D.alt_bug)
    D.spd_bug     = getf(H.spd_bug, 0)
    D.vs_bug      = getf(H.vs_bug, 0)

    D.hsi_src     = geti(H.hsi_src, 0)
    D.hsi_obs     = U.wrap360(getf(H.hsi_obs, 0))
    D.hsi_hdef    = getf(H.hsi_hdef, 0)
    D.hsi_vdef    = getf(H.hsi_vdef, 0)
    D.hsi_fromto  = geti(H.hsi_fromto, 0)
    D.hsi_show_h  = geti(H.hsi_show_h, 0)
    D.hsi_show_v  = geti(H.hsi_show_v, 0)
    D.hsi_gs_flag = geti(H.hsi_gs_flag, 0)
    D.hsi_has_dme = geti(H.hsi_has_dme, 0)
    D.hsi_dme     = getf(H.hsi_dme, 0)
    D.nav1_freq   = geti(H.nav1_freq, 0)
    D.nav2_freq   = geti(H.nav2_freq, 0)
    D.nav1_type   = geti(H.nav1_type, 0)
    D.nav2_type   = geti(H.nav2_type, 0)
    D.nav1_show_h = geti(H.nav1_show_h, 0)
    D.nav2_show_h = geti(H.nav2_show_h, 0)
    D.nav1_brg    = getf(H.nav1_brg, 0)
    D.nav2_brg    = getf(H.nav2_brg, 0)
    D.nav1_dme    = getf(H.nav1_dme, 0)
    D.nav2_dme    = getf(H.nav2_dme, 0)
    D.nav1_has_dme = geti(H.nav1_has_dme, 0)
    D.nav2_has_dme = geti(H.nav2_has_dme, 0)
    D.gps_brg     = getf(H.gps_brg, 0)
    D.gps_dme     = getf(H.gps_dme, 0)
    D.gps_has_dme = geti(H.gps_has_dme, 0)
    D.gps_cdi     = geti(H.gps_cdi, 1)
    D.gps_dtk     = U.wrap360(getf(H.gps_dtk, D.hsi_obs))
    D.gps_seq     = geti(H.gps_seq, 0)
    D.altv_armed  = geti(H.altv_armed, 0)
end

-----------------------------------------------------------------------------
-- Writers (the knob changes these)
-----------------------------------------------------------------------------

function Sim.set_baro(inhg)
    U.setf(H.baro, U.clamp(inhg, 22.0, 32.5))
end

function Sim.set_hdg_bug(deg)
    U.setf(H.hdg_bug, U.wrap360(deg))
end

function Sim.set_alt_bug(ft)
    U.setf(H.alt_bug, U.clamp(ft, -1000, 50000))
end

function Sim.set_course(deg)
    U.setf(H.hsi_obs, U.wrap360(deg))
end

function Sim.set_inst_brightness(index, v)
    if index ~= nil and index >= 0 then
        U.setfa(H.inst_bright, index, U.clamp(v, 0, 1))
    end
end

function Sim.get_inst_brightness(index, fallback)
    if index == nil or index < 0 then return fallback end
    return U.getfa(H.inst_bright, index, fallback)
end

-- Our share of a bus's plugin load: X-Plane keeps the value, so every
-- plugin adjusts it by the change in its own contribution.
local bus_share = {}
function Sim.set_bus_load(index, amps)
    if H.bus_load == nil or index == nil or index < 0 or index > 5 then return end
    local prev = bus_share[index] or 0
    if math.abs(amps - prev) < 1e-4 then return end
    local cur = U.getfa(H.bus_load, index, 0)
    U.setfa(H.bus_load, index, math.max(0, cur - prev + amps))
    bus_share[index] = amps
end

function Sim.cmd(name)
    U.cmd_once(CMD[name])
end

return Sim
