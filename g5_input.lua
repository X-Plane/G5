-- g5_input.lua: knob / power button behaviour, menus and popups.
--
-- Behaviour follows the old G5_Knob_*_handler / G5_Power_Knob_Down_handler and
-- the G5 Pilot's Guide (190-01112-12 Rev A):
--   knob turn   : baro (clean PFD), heading bug (clean HSI), menu selection,
--                 popup value, backlight (backlight page, manual mode)
--   knob press  : open menu / select item / close popup or backlight page
--   knob hold   : sync heading (or selected altitude in the Altitude popup)
--   power press : off -> power on; on -> backlight page; on backlight page -> Auto
--   power hold  : power-off countdown, unit off after power_off_hold_s
--   any key during "External Power Lost" keeps the unit on battery power.

local U, Sim, Sys, cfg, st, Fail

local In = {}

local HOLD_S = 0.5           -- knob hold-to-sync threshold (old: 0.5 s)
local PWR_SHORT_MAX_S = 1.3  -- longest press still counted as a click (old: 1.3 s)
-- Slides of the menu, popups and backlight page, measured frame by frame (30 fps)
-- from a video of a G5 8.60 (2026-07-20): sliding in fits CSS "ease" over 0.3 s (quick start, long soft stop); sliding
-- out is faster, about 0.12-0.15 s, soft at both ends.
local OPEN_S, CLOSE_S = 0.3, 0.15
local EASE_IN, EASE_OUT      -- curves of the shown position (0 hidden .. 1 in place)
-- a pressed tile / button shows its pressed look this long before it acts
-- (2 video frames)
local PRESS_S = 0.07

function In.init(util, sim, sys, config, fail)
    U, Sim, Sys, cfg, Fail = util, sim, sys, config, fail
    st = Sys.st
    EASE_IN = U.bezier(0.25, 0.1, 0.25, 1)
    -- sliding out runs this curve backwards (lin 1 -> 0), soft at both ends
    EASE_OUT = U.bezier(0.42, 0, 0.58, 1)
end

-- st[key] = shown position 0..1. A linear clock runs in st.anim[key] and the
-- curve depends on the direction; when the direction flips mid-slide the clock
-- is re-mapped so the panel continues from where it is.
local function slide(key, open, dt)
    local a = st.anim[key]
    if a == nil then
        a = { lin = st[key], open = open }
        st.anim[key] = a
    end
    if a.open ~= open then
        a.lin = U.inverse(open and EASE_IN or EASE_OUT, st[key])
        a.open = open
    end
    a.lin = U.approach(a.lin, open and 1 or 0, 1 / (open and OPEN_S or CLOSE_S), dt)
    st[key] = (open and EASE_IN or EASE_OUT)(a.lin)
end

-----------------------------------------------------------------------------
-- Menu model
-----------------------------------------------------------------------------

-- Labels for drawing. `value` items get their value line from the UI module.
-- Menu contents (Pilot's Guide 1.5.2, 2.2.1.1, 2.3.5, 4.1; AFMS 4-4):
--   PFD: Back, (Message), Heading | Track, Altitude, (GPSS), (HSI)
--   HSI: Back, (Message), Heading | Track, Altitude, (Course | OBS), (Source),
--        (GPSS), PFD, Setup
-- Course shows with a VOR / LOC source (received or not), OBS while the GPS is in OBS
-- mode (neither with Selected Course disabled); Source with two navigators; GPSS with an analog autopilot interface
-- (not with a GFC 500); HSI only when the HSI page is enabled.
local items = {}

-- Selected Course (configuration mode Navigation page; Installation Manual:
-- "Disabled" if a mechanical CDI or HSI is connected to the navigator): when
-- it is off the course is set on that instrument, so the G5 has no Course /
-- OBS item and never writes the course (hsi_obs; this is its only writer).
-- The course it shows (needle, DTK, PFD marker) is unchanged.
function In.course_enabled()
    return cfg.selected_course ~= 0
end

-- Course: whenever the source is a VOR / LOC navigator, received or not (the
-- real unit lists it with NO LOC, 2026-07-20 video); OBS with a GPS source
-- only in OBS mode; never with Selected Course disabled
function In.course_item(D)
    if not In.course_enabled() then return false end
    if D.hsi_src == 2 then return D.gps_seq == 1 end
    return true
end

function In.items(D)
    for i = #items, 1, -1 do items[i] = nil end
    items[#items + 1] = "back"
    if st.has_msg then items[#items + 1] = "message" end
    items[#items + 1] = "heading"
    items[#items + 1] = "altitude"
    local gpss = cfg.gpss_menu ~= 0 and not In.gfc
    if st.mode == Sys.HSI then
        if In.course_item(D) then items[#items + 1] = "course" end
        if cfg.nav_count >= 2 then items[#items + 1] = "source" end
        if gpss then items[#items + 1] = "gpss" end
        items[#items + 1] = "pfd"
        items[#items + 1] = "setup"
    else
        -- real unit (2026-07-20): ... Altitude | Pitch | Course | ... | HSI
        items[#items + 1] = "pitch"
        if In.course_item(D) then items[#items + 1] = "course" end
        -- ESP on / off from the PFD menu (Pilot's Guide 3.5, figure 3-25)
        if In.Esp and In.Esp.usable() then items[#items + 1] = "esp" end
        if gpss then items[#items + 1] = "gpss" end
        if cfg.hsi_page ~= 0 then items[#items + 1] = "hsi" end
    end
    return items
end

-- HSI source: NAV1 -> NAV2 -> GPS (the navigators' CDI keys, AFMS 4-4)
local SRC_NEXT = { [0] = "src_nav2", [1] = "src_gps", [2] = "src_nav1" }

-- HSI Setup page (real unit, 2026-07-20 photos): Back, Bearing Pointer 1,
-- Bearing Pointer 2, Wind Vector, HSI Size. Pressing a value row opens its
-- list (In.setup_options); picking an entry applies it, writes it to
-- config.ini and returns to the HSI.
In.SETUP_ROWS = { "back", "brg1", "brg2", "wind", "size" }
local WIND = { "off", "speed_dir", "head_xwind" }
local SIZE = { "normal", "expanded" }
local function listed(list, v)
    for _, o in ipairs(list) do if o == v then return true end end
    return false
end
-- config.ini strings and bearing sources checked against their option lists
-- (once per bad value, one log line): wind_vector / hsi_size are lowercased,
-- unknown values fall back to the default; a bearing source that is not
-- offered (e.g. NAV2 with one navigator) falls back to Off
local warned = {}
local function warn_once(key, v, using)
    local id = key .. "=" .. tostring(v)
    if warned[id] then return end
    warned[id] = true
    U.log("config.ini: " .. key .. " = '" .. tostring(v) .. "' is not valid, using " .. tostring(using))
end
local function check_string(key, list, default)
    local v = string.lower(tostring(cfg[key]))
    if not listed(list, v) then
        warn_once(key, cfg[key], default)
        v = default
    end
    cfg[key] = v
end
local function check_choices()
    check_string("wind_vector", WIND, "speed_dir")
    check_string("hsi_size", SIZE, "normal")
    for i = 1, 2 do
        local key = "brg" .. i
        local v = st.brg[i]
        local ok = false
        for _, o in ipairs(In.setup_options(key)) do if o == v then ok = true end end
        if not ok then
            warn_once("bearing" .. i .. "_source", v, 0)
            st.brg[i] = 0
        end
    end
end
-- the values check_choices last ran on: it runs again only when the number
-- of navigators, a bearing source or one of the two strings changes (not
-- every frame: In.setup_options builds a table per call)
local chk_nav, chk_b1, chk_b2, chk_wind, chk_size
local function check_choices_on_change()
    if cfg.nav_count == chk_nav and st.brg[1] == chk_b1 and st.brg[2] == chk_b2
        and cfg.wind_vector == chk_wind and cfg.hsi_size == chk_size then return end
    check_choices()
    chk_nav, chk_b1, chk_b2 = cfg.nav_count, st.brg[1], st.brg[2]
    chk_wind, chk_size = cfg.wind_vector, cfg.hsi_size
end
function In.setup_options(key)
    if key == "brg1" or key == "brg2" then
        local o = { 0, 1, 2 }
        if cfg.nav_count >= 2 then o[4] = 3 end
        return o
    elseif key == "wind" then return WIND
    elseif key == "size" then return SIZE end
    return {}
end
function In.setup_value(key)
    if key == "brg1" then return st.brg[1]
    elseif key == "brg2" then return st.brg[2]
    elseif key == "wind" then return cfg.wind_vector
    elseif key == "size" then return cfg.hsi_size end
end
local function setup_apply(key, v)
    local save = In.save_setting or function() end
    if key == "brg1" or key == "brg2" then
        local i = (key == "brg1") and 1 or 2
        st.brg[i] = v
        save("bearing" .. i .. "_source", v)
    elseif key == "wind" then
        save("wind_vector", v)
    elseif key == "size" then
        save("hsi_size", v)
    end
end

local PITCH_MAX = 10   -- deg either way

local function open_popup(name)
    st.popup = name
    st.popup_open = true
    st.popup_row = 1
    st.setup_drop = nil
    st.menu_open = false
    if name == "message" then
        st.msg_scroll = 0
        Fail.mark_seen()
    end
end

-- Pitch Offset is written to config.ini whenever its popup goes from open to
-- closed, whatever closed it (knob press, power button, mode drop below PFD,
-- shutdown, which clears the popup from g5_system): In.update calls
-- pitch_watch_step every frame
local pitch_watch = false
local function save_pitch()
    pitch_watch = false
    if In.save_setting then
        In.save_setting("pitch_offset", U.round((cfg.pitch_offset or 0) * 10) / 10)
    end
end
local function pitch_watch_step()
    if st.popup_open and st.popup == "pitch" then
        pitch_watch = true
    elseif pitch_watch then
        save_pitch()
    end
end

local function close_popup()
    if st.popup == "pitch" then save_pitch() end
    st.popup_open = false
end

local function close_menu()
    st.menu_open = false
end

local function activate(item, D)
    if item == "back" then
        close_menu()
    elseif item == "course" and not In.course_enabled() then
        close_menu()    -- (not listed with Selected Course disabled; only a stale tile index gets here)
    elseif item == "message" or item == "heading" or item == "altitude"
        or item == "course" or item == "setup" or item == "pitch" then
        open_popup(item)
    elseif item == "source" then
        Sim.cmd(SRC_NEXT[D.hsi_src] or "src_nav1")
    elseif item == "gpss" then
        -- GPSS on / off (Pilot's Guide 4.1). X-Plane's sim/autopilot/gpss only
        -- engages GPSS; off hands the autopilot back to the heading bug (HDG)
        if D.gpss_status ~= 0 or D.hdg_is_gpss ~= 0 then
            Sim.cmd("heading")
        else
            Sim.cmd("gpss")
        end
    elseif item == "esp" then
        In.Esp.toggle()
    elseif item == "hsi" then
        Sys.set_page(Sys.HSI)
        close_menu()
    elseif item == "pfd" then
        Sys.set_page(Sys.PFD)
        close_menu()
    end
end

-----------------------------------------------------------------------------
-- Knob
-----------------------------------------------------------------------------

-- Baro, heading bug and selected altitude: the sim's, or this unit's own
-- copies while cross-fill is off (software version mismatch: G5.lua
-- cross_fill sets In.priv on every unit but the acting master)
In.priv = nil
local function set_baro(inhg)
    if In.priv then In.priv.baro = U.clamp(inhg, 22.0, 32.5) else Sim.set_baro(inhg) end
end
local function write_hdg_bug(deg)
    if In.priv then In.priv.hdg_bug = U.wrap360(deg) else Sim.set_hdg_bug(deg) end
end
-- the pilot picks a heading with the knob: that ends Heading Bug Auto Sync
-- Mode (Pilot's Guide Rev M 3.3.5.2.1, "Rotate the HDG Knob to select a new
-- heading"). A knob hold only syncs the bug and leaves the mode alone.
local function set_hdg_bug(deg)
    st.hdg_sync = nil
    write_hdg_bug(deg)
end

-- Heading Bug Auto Sync Mode (Rev M 3.3.5.2.1, "if configured": config
-- hdg_sync). Menu > Heading > hold the Selection Knob keeps the heading bug on
-- the aircraft heading (the ground track in track mode, as the one-shot sync
-- does) for as long as the autopilot is engaged and the flight director's
-- lateral mode is a navigation mode (GPS / VOR / LOC / BC). It ends when the
-- pilot turns the bug (here: the knob; or from outside: the GMC 507 HDG knob,
-- seen as the bug no longer where this unit put it), the autopilot goes off,
-- the lateral mode is no longer a navigation mode, or hdg_sync is switched off.
-- st.hdg_sync: active; st.hdg_sync_ok: it could be switched on now.
local NAV_LAT = { GPS = true, VOR = true, LOC = true, BC = true }
local SYNC_TOL_DEG = 1.5      -- a bug further than this from our last write was moved by someone else

-- the bug syncs to the ground track, not the heading, while the unit shows a
-- track (no magnetic heading) or the autopilot is in TRK mode (heading_mode 18
-- or track_status 2: the TRK annunciation, whose bug is magenta)
local function sync_to_track(D)
    return st.valid.hdg_mode == "trk" or D.hdg_mode == 18 or D.track_status == 2
end

local function sync_target(D)
    return U.wrap360(U.round(sync_to_track(D) and D.track or D.hdg))
end

-- every frame (G5.lua update_unit), after Pfd.update. modes = Pfd.afcs_modes(D)
function In.hdg_sync_update(D, modes)
    local ok = cfg.hdg_sync ~= 0 and (st.mode == Sys.PFD or st.mode == Sys.HSI) and not st.shutting
        and modes ~= nil and modes.ap == true and NAV_LAT[modes.lat] == true
        and st.valid.hdg_mode ~= "fail"
    st.hdg_sync_ok = ok
    if not st.hdg_sync then return end
    if not ok then
        st.hdg_sync = nil
        return
    end
    -- the frame it was switched on: D still holds the bug from before the write
    if st.hdg_sync_fresh then
        st.hdg_sync_fresh = nil
    elseif math.abs(U.angdiff(D.hdg_bug, st.hdg_sync_val)) > SYNC_TOL_DEG then
        st.hdg_sync = nil
        return
    end
    local v = sync_target(D)
    if math.abs(U.angdiff(D.hdg_bug, v)) >= 0.5 then write_hdg_bug(v) end
    st.hdg_sync_val = v
end
local function set_alt_bug(ft)
    if In.priv then In.priv.alt_bug = U.clamp(ft, -1000, 50000) else Sim.set_alt_bug(ft) end
end

-- hPa and mb step 1 (the same value), inHg 0.01
local function baro_step(dir, D)
    if cfg.baro_unit == 1 or cfg.baro_unit == 2 then
        local hpa = U.round(D.baro * 33.8639) + dir
        set_baro(hpa / 33.8639)
    else
        set_baro(U.round(D.baro * 100 + dir) / 100)
    end
end

function In.knob_turn(dir, D)
    st.knob_val = (st.knob_val + 0.05 * dir) % 1
    if st.mode < Sys.PFD or st.shutting then return end
    Sys.any_key()

    if st.mode == Sys.CONFIG then
        In.Cfg.knob_turn(dir, D)
    elseif st.bright_open then
        -- turning the knob adjusts the level; in Auto it switches to Manual
        -- from the current Auto level (AFMS 4-1, Maintenance Manual 3)
        if st.bright_auto then
            st.bright_auto = false
            st.backlight = Sys.auto_level()
        end
        st.backlight = U.clamp(st.backlight + 0.01 * dir, cfg.backlight_min, Sys.backlight_max())
    elseif st.popup_open then
        local p = st.popup
        if p == "heading" then
            set_hdg_bug(U.round(D.hdg_bug) + dir)
        elseif p == "altitude" then
            if cfg.alt_unit == 1 then
                -- meters (Units page): 50 m a detent, on whole 50 m (our
                -- choice; the manuals give only the 100 ft step)
                set_alt_bug((U.round(D.alt_bug * 0.3048 / 50) * 50 + 50 * dir) / 0.3048)
            else
                set_alt_bug(U.round(D.alt_bug / 100) * 100 + 100 * dir)
            end
        elseif p == "course" then
            if In.course_enabled() then Sim.set_course(U.round(D.hsi_obs) + dir) end
        elseif p == "pitch" then
            -- clockwise = nose up, 0.1 deg per detent (real unit)
            cfg.pitch_offset = U.clamp(U.round((cfg.pitch_offset or 0) * 10 + dir) / 10, -PITCH_MAX, PITCH_MAX)
        elseif p == "setup" then
            if st.setup_drop then
                st.drop_sel = U.clamp(st.drop_sel + dir, 1, #In.setup_options(st.setup_drop))
            else
                st.popup_row = U.clamp(st.popup_row + dir, 1, #In.SETUP_ROWS)
            end
        elseif p == "message" then
            st.msg_scroll = U.clamp((st.msg_scroll or 0) + dir, 0, math.max(0, #st.msgs - 5))
        end
    elseif st.menu_open then
        -- the selection stops at both ends (real unit: no roll-over); a tile
        -- already pressed keeps it
        if not st.press_pending then
            st.menu_sel = U.clamp(st.menu_sel + dir, 1, #In.items(D))
        end
    elseif st.mode == Sys.PFD then
        baro_step(dir, D)
    elseif st.mode == Sys.HSI then
        set_hdg_bug(U.round(D.hdg_bug) + dir)
    end
end

local function knob_click(D)
    if st.mode == Sys.CONFIG then
        In.Cfg.knob_press(D)
    elseif st.bright_open then
        -- confirm: the wedge turns green while the page slides out (video 1:29.6)
        st.bright_open = false
        st.bright_confirm = true
    elseif st.popup_open then
        if st.popup == "setup" and st.setup_drop then
            -- pick: apply, save, back to the HSI
            local key = st.setup_drop
            setup_apply(key, In.setup_options(key)[st.drop_sel])
            st.setup_drop = nil
            close_popup()
        elseif st.popup == "setup" and st.popup_row > 1 then
            -- open the row's list on its current value
            local key = In.SETUP_ROWS[st.popup_row]
            local opts, cur = In.setup_options(key), In.setup_value(key)
            st.drop_sel = 1
            for i, v in ipairs(opts) do if v == cur then st.drop_sel = i end end
            st.setup_drop = key
        else
            close_popup()
        end
    elseif st.menu_open then
        -- the tile shows pressed first; In.update activates it after PRESS_S
        if not st.press_pending then
            if st.menu_press ~= st.menu_sel then st.press_age = 0 end
            st.menu_press = st.menu_sel
            st.press_pending = true
        end
    else
        st.menu_open = true
        st.menu_sel = 1
        st.menu_press = nil
    end
end

local function knob_hold(D)
    if st.mode == Sys.CONFIG then
        return
    elseif st.popup_open and st.popup == "altitude" then
        -- sync: to the 10 ft, or to the whole meter
        if cfg.alt_unit == 1 then
            set_alt_bug(U.round(D.alt * 0.3048) / 0.3048)
        else
            set_alt_bug(U.round(D.alt / 10) * 10)
        end
    elseif st.popup_open and st.popup == "heading" then
        write_hdg_bug(sync_target(D))
        -- with hdg_sync on and the autopilot in a navigation mode the hold
        -- starts Heading Bug Auto Sync Mode (the "SYNC" in the window); else it
        -- is the one-shot sync as before
        if st.hdg_sync_ok then
            st.hdg_sync, st.hdg_sync_fresh = true, true
            st.hdg_sync_val = sync_target(D)
        end
    elseif not st.menu_open and not st.popup_open and not st.bright_open then
        -- sync to the current heading, or to the ground track in track mode
        -- or with the autopilot in TRK (Pilot's Guide 2.1.5 / 2.2.2); the
        -- sim's sync only for the sim's bug
        if sync_to_track(D) then
            write_hdg_bug(sync_target(D))
        elseif In.priv then
            write_hdg_bug(U.round(D.hdg))
        else
            Sim.cmd("hdg_sync")
        end
    end
end

function In.knob_press(phase, D)
    -- knob_down also drives the bezel push animation, so track it even when off
    local active = st.mode >= Sys.PFD and not st.shutting
    if phase == XPLMCommandPhase.xplm_CommandBegin then
        st.knob_down = true
        st.knob_t = 0
        st.knob_handled = (not active) or Sys.any_key()
        -- the selected menu tile looks pressed while the knob is down
        if not st.knob_handled and st.mode ~= Sys.CONFIG and st.menu_open
            and not st.popup_open and not st.bright_open and not st.press_pending then
            st.menu_press = st.menu_sel
            st.press_age = 0
        end
    elseif phase == XPLMCommandPhase.xplm_CommandEnd then
        if active and st.knob_down and not st.knob_handled then knob_click(D) end
        -- held into a sync (or nothing to do): the tile pops back up
        if not st.press_pending and st.menu_open then st.menu_press = nil end
        st.knob_down = false
    end
end

-----------------------------------------------------------------------------
-- Power button
-----------------------------------------------------------------------------

function In.power_press(phase, D)
    if phase == XPLMCommandPhase.xplm_CommandBegin then
        st.pwr_down = true
        st.pwr_t = 0
        st.pwr_handled = false
        if st.mode == Sys.OFF then
            Sys.start_boot()
            st.pwr_handled = true
        elseif Sys.any_key() then
            st.pwr_handled = true
        elseif st.bright_open and not st.bright_toggle_pending then
            -- the on-screen Auto button looks pressed while the button is down
            st.bright_press = true
            st.bright_press_age = 0
        end
    elseif phase == XPLMCommandPhase.xplm_CommandEnd then
        if st.pwr_down and not st.pwr_handled and st.pwr_t <= PWR_SHORT_MAX_S
            and (st.mode == Sys.PFD or st.mode == Sys.HSI) and not st.shutting then
            if st.bright_open then
                -- Auto toggles once the pressed look has shown (In.update)
                if not st.bright_toggle_pending then
                    if not st.bright_press then st.bright_press_age = 0 end
                    st.bright_press = true
                    st.bright_toggle_pending = true
                end
            else
                st.bright_open = true
                st.bright_confirm = false
                st.menu_open = false
                st.popup_open = false
                st.press_pending = false
            end
        end
        -- held into the power-off countdown: the button pops back up
        if not st.bright_toggle_pending then st.bright_press = false end
        st.pwr_down = false
        st.pwr_t = 0
    end
end

-- Seconds shown in the "Power Off" dialog, or nil when not shown. The dialog
-- (Shut_Ongoing + a raster 3-2-1 count, g5_ui power_off_dialog) shows for the last 3 s of
-- the hold, so it always counts 3-2-1 whatever power_off_hold_s is.
function In.power_off_countdown()
    if st.pwr_down and not st.pwr_handled and st.mode >= Sys.BOOT
        and st.pwr_t >= math.max(1.0, cfg.power_off_hold_s - 3) then
        return math.max(1, math.ceil(cfg.power_off_hold_s - st.pwr_t))
    end
    return nil
end

-----------------------------------------------------------------------------
-- Per-frame
-----------------------------------------------------------------------------

function In.update(dt, D)
    if st.knob_down then
        st.knob_t = st.knob_t + dt
        if not st.knob_handled and st.knob_t >= HOLD_S then
            knob_hold(D)
            st.knob_handled = true
        end
    end
    if st.pwr_down and st.mode ~= Sys.OFF then
        st.pwr_t = st.pwr_t + dt
        if not st.pwr_handled and st.pwr_t >= cfg.power_off_hold_s then
            st.pwr_handled = true
            Sys.shutdown()
        end
    end

    pitch_watch_step()
    -- a course window left open when Course is no longer a menu item (Selected
    -- Course switched off, source changed, GPS left OBS mode) goes away
    if st.popup_open and st.popup == "course" and not In.course_item(D) then close_popup() end
    check_choices_on_change()

    -- keep the selection valid when the item list changes (message appears, nav source changes)
    local n = #In.items(D)
    if st.menu_sel > n then st.menu_sel = n end
    if not st.menu_open and st.menu_anim <= 0 then st.menu_sel = 1 end

    -- a pressed menu tile acts once its pressed look has shown for PRESS_S
    if st.menu_press then
        st.press_age = st.press_age + dt
        if st.press_pending and st.press_age >= PRESS_S then
            st.press_pending = false
            if st.menu_open then activate(In.items(D)[st.menu_press] or "back", D) end
            -- items that keep the menu open (Source, GPSS, ESP) pop back up
            if st.menu_open then st.menu_press = nil end
        end
    end
    -- the backlight Auto button the same way (power button)
    if st.bright_press then
        st.bright_press_age = st.bright_press_age + dt
        if st.bright_toggle_pending and st.bright_press_age >= PRESS_S then
            st.bright_toggle_pending = false
            st.bright_press = false
            if st.bright_open then st.bright_auto = not st.bright_auto end
        end
    end

    slide("menu_anim", st.menu_open, dt)
    slide("popup_anim", st.popup_open, dt)
    slide("bright_anim", st.bright_open, dt)
    if not st.popup_open and st.popup_anim <= 0 then st.popup = nil end
    if not st.menu_open and st.menu_anim <= 0 and not st.press_pending then st.menu_press = nil end
    if not st.bright_open and st.bright_anim <= 0 then st.bright_confirm = false end

    -- 4 tiles visible; scroll so the selection stays on screen
    local first = math.floor(st.menu_scroll + 0.5)
    if st.menu_sel > first + 4 then first = st.menu_sel - 4 end
    if st.menu_sel < first + 1 then first = st.menu_sel - 1 end
    first = U.clamp(first, 0, math.max(0, n - 4))
    st.menu_scroll = U.approach(st.menu_scroll, first, 10, dt)

    if st.mode < Sys.PFD then
        st.menu_open = false
        st.popup_open = false
        st.bright_open = false
        st.press_pending = false
        st.bright_toggle_pending = false
        st.bright_press = false
    end
    pitch_watch_step()
end

return In
