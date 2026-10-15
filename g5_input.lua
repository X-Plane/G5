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
local ANIM_S = 0.3           -- slide-in time of menus / popups (old: 0.3 s)

function In.init(util, sim, sys, config, fail)
    U, Sim, Sys, cfg, Fail = util, sim, sys, config, fail
    st = Sys.st
end

-----------------------------------------------------------------------------
-- Menu model
-----------------------------------------------------------------------------

-- Labels for drawing. `value` items get their value line from the UI module.
-- Menu contents (Pilot's Guide 1.5.2, 2.2.1.1, 2.3.5, 4.1; AFMS 4-4):
--   PFD: Back, (Message), Heading | Track, Altitude, (GPSS), (HSI)
--   HSI: Back, (Message), Heading | Track, Altitude, (Course | OBS), (Source),
--        (GPSS), PFD, Setup
-- Course shows while VOR / LOC data is received, OBS while the GPS is in OBS
-- mode; Source with two navigators; GPSS with an analog autopilot interface
-- (not with a GFC 500); HSI only when the HSI page is enabled.
local items = {}

function In.course_item(D)
    if D.hsi_src == 2 then return D.gps_seq == 1 end
    local t = (D.hsi_src == 1) and D.nav2_type or D.nav1_type
    return t ~= 0 or D.hsi_show_h ~= 0
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
        if gpss then items[#items + 1] = "gpss" end
        if cfg.hsi_page ~= 0 then items[#items + 1] = "hsi" end
    end
    return items
end

-- HSI source: NAV1 -> NAV2 -> GPS (the navigators' CDI keys, AFMS 4-4)
local SRC_NEXT = { [0] = "src_nav2", [1] = "src_gps", [2] = "src_nav1" }

local function open_popup(name)
    st.popup = name
    st.popup_open = true
    st.popup_row = 1
    st.menu_open = false
    if name == "message" then
        st.msg_scroll = 0
        Fail.mark_seen()
    end
end

local function close_popup()
    st.popup_open = false
end

local function close_menu()
    st.menu_open = false
end

local function activate(item, D)
    if item == "back" then
        close_menu()
    elseif item == "message" or item == "heading" or item == "altitude"
        or item == "course" or item == "setup" then
        open_popup(item)
        if item == "setup" then st.setup_edit = false end
    elseif item == "source" then
        Sim.cmd(SRC_NEXT[D.hsi_src] or "src_nav1")
    elseif item == "gpss" then
        Sim.cmd("gpss")
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

local function baro_step(dir, D)
    if cfg.baro_unit == 1 then
        local hpa = U.round(D.baro * 33.8639) + dir
        Sim.set_baro(hpa / 33.8639)
    else
        Sim.set_baro(U.round(D.baro * 100 + dir) / 100)
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
        st.backlight = U.clamp(st.backlight + 0.01 * dir, cfg.backlight_min, 1)
    elseif st.popup_open then
        local p = st.popup
        if p == "heading" then
            Sim.set_hdg_bug(U.round(D.hdg_bug) + dir)
        elseif p == "altitude" then
            Sim.set_alt_bug(U.round(D.alt_bug / 100) * 100 + 100 * dir)
        elseif p == "course" then
            Sim.set_course(U.round(D.hsi_obs) + dir)
        elseif p == "setup" then
            -- rows: 1 Back, 2 Bearing Pointer 1, 3 Bearing Pointer 2; while a
            -- row is being edited the knob steps None / GPS / VLOC1 / VLOC2
            if st.setup_edit then
                local i = st.popup_row - 1
                st.brg[i] = (st.brg[i] + dir) % 4
            else
                st.popup_row = U.clamp(st.popup_row + dir, 1, 3)
            end
        elseif p == "message" then
            st.msg_scroll = U.clamp((st.msg_scroll or 0) + dir, 0, math.max(0, #st.msgs - 5))
        end
    elseif st.menu_open then
        local list = In.items(D)
        st.menu_sel = U.clamp(st.menu_sel + dir, 1, #list)
    elseif st.mode == Sys.PFD then
        baro_step(dir, D)
    elseif st.mode == Sys.HSI then
        Sim.set_hdg_bug(U.round(D.hdg_bug) + dir)
    end
end

local function knob_click(D)
    if st.mode == Sys.CONFIG then
        In.Cfg.knob_press(D)
    elseif st.bright_open then
        st.bright_open = false
    elseif st.popup_open then
        if st.popup == "setup" and st.popup_row > 1 then
            st.setup_edit = not st.setup_edit
        else
            close_popup()
        end
    elseif st.menu_open then
        local list = In.items(D)
        activate(list[st.menu_sel] or "back", D)
    else
        st.menu_open = true
        st.menu_sel = 1
    end
end

local function knob_hold(D)
    if st.mode == Sys.CONFIG then
        return
    elseif st.popup_open and st.popup == "altitude" then
        Sim.set_alt_bug(U.round(D.alt / 10) * 10)
    elseif st.popup_open and st.popup == "heading" then
        Sim.set_hdg_bug(U.round(st.valid.hdg_mode == "trk" and D.track or D.hdg))
    elseif not st.menu_open and not st.popup_open and not st.bright_open then
        -- sync to the current heading, or to the ground track in track mode
        -- (Pilot's Guide 2.1.5 / 2.2.2)
        if st.valid.hdg_mode == "trk" then
            Sim.set_hdg_bug(U.round(D.track))
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
    elseif phase == XPLMCommandPhase.xplm_CommandEnd then
        if active and st.knob_down and not st.knob_handled then knob_click(D) end
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
        end
    elseif phase == XPLMCommandPhase.xplm_CommandEnd then
        if st.pwr_down and not st.pwr_handled and st.pwr_t <= PWR_SHORT_MAX_S
            and (st.mode == Sys.PFD or st.mode == Sys.HSI) and not st.shutting then
            if st.bright_open then
                st.bright_auto = not st.bright_auto
            else
                st.bright_open = true
                st.menu_open = false
                st.popup_open = false
            end
        end
        st.pwr_down = false
        st.pwr_t = 0
    end
end

-- Seconds shown in the "Power Off" dialog, or nil when not shown. The dialog
-- (Shut_Ongoing + the "321" sheet: blank, 1, 2, 3) shows for the last 3 s of
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

    -- keep the selection valid when the item list changes (message appears, nav source changes)
    local n = #In.items(D)
    if st.menu_sel > n then st.menu_sel = n end
    if not st.menu_open and st.menu_anim <= 0 then st.menu_sel = 1 end

    st.menu_anim = U.approach(st.menu_anim, st.menu_open and 1 or 0, 1 / ANIM_S, dt)
    st.popup_anim = U.approach(st.popup_anim, st.popup_open and 1 or 0, 1 / ANIM_S, dt)
    st.bright_anim = U.approach(st.bright_anim, st.bright_open and 1 or 0, 1 / ANIM_S, dt)
    if not st.popup_open and st.popup_anim <= 0 then st.popup = nil end

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
    end
end

return In
