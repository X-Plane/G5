-- g5_ui.lua: overlays on the 2024-2025 artwork. Menu (Menu_Option_Base +
-- one tile image per item (Tile_*) + PFD_Menu_Selected), popups (Pops_*),
-- backlight page (Brightness_*), battery (BATT_*), power-off (Shut_Ongoing +
-- 321) and power-lost (Ext_Power_Lost_UI) dialogs, boot logo.
-- Positions are the old Plane Maker POS values in screen pixels.

local U, G, Sys, In, Pfd, cfg, Fail
local C

local UI = {}

function UI.init(util, gfx, sys, input, pfd, config, fail)
    U, G, Sys, In, Pfd, cfg, Fail = util, gfx, sys, input, pfd, config, fail
    C = G.C
end

-- panels slide up 70 px; `anim` is already eased (g5_input.lua slide())
local function slide(anim)
    return -70 + 70 * anim
end

-- pressed look of a menu tile: its face turns a lighter grey (video 0:16.6,
-- Altitude tile; there is no pressed tile art)
local press_tint
local function pressed_face(x0, y0, x1, y1)
    press_tint = press_tint or G.rgba(1, 1, 1, 0.2)
    G.rect(x0, y0, x1, y1, press_tint)
end

local TILE_X0, TILE_PITCH = 43, 78   -- tile 1 centre / spacing in the Options strips
-- gen_LED SIZEs of the old menu values: tile values (Extra Bold) and popup displays
local XB, DISP = 0.59, 0.75

-----------------------------------------------------------------------------
-- Battery indicator
-----------------------------------------------------------------------------

-- the same frame (colour) rule as the pages' status box: Pfd.batt_frame
local function batt_frame(pct)
    return Pfd.batt_frame(pct)
end

-- (the battery status itself is drawn by the pages: Pfd.battery_box)
-----------------------------------------------------------------------------
-- Menu
-----------------------------------------------------------------------------

-- tile art per item; labelled tiles use the
-- blank tile with the label drawn as text
local TILE_ART = { back = "Tile_Back", message = "Tile_Message", gpss = "Tile_GPSS", esp = "Tile_BlankBar",
    hsi = "Tile_HSI", pfd = "Tile_PFD", setup = "Tile_Setup" }

local function tile_label(item, D, st)
    if item == "heading" then
        return (st.valid.hdg_mode == "trk" or D.hdg_mode == 18) and "Track" or "Heading"
    elseif item == "altitude" then return "Altitude"
    elseif item == "course" then return (D.hsi_src == 2) and "OBS" or "Course"
    elseif item == "source" then return "Source"
    elseif item == "setup" then return "Setup"
    elseif item == "pitch" then return "Pitch"
    elseif item == "esp" then return "ESP"
    end
end

local function menu(D, st)
    if st.menu_anim <= 0 then return end
    local off = slide(st.menu_anim)
    local items = In.items(D)
    local n = #items
    local s = st.menu_scroll

    G.pic("Menu_Option_Base", 159.5, 34.5 + off)
    local fs_label = G.rfont("xbold", 10)
    for i, item in ipairs(items) do
        local tx = TILE_X0 + (i - 1 - s) * TILE_PITCH
        if tx > -40 and tx < 360 then
            G.pic(TILE_ART[item] or "Tile_Blank", tx, 39 + off)
            -- Tile_* are 74 x 49 with a 2 px rim
            if st.menu_press == i then pressed_face(tx - 35, 16.5 + off, tx + 35, 61.5 + off) end
            local label = tile_label(item, D, st)
            if label then G.rstr_c(fs_label, label, tx, 48.5 + off, C.white) end
        end
    end

    for i, item in ipairs(items) do
        local tx = TILE_X0 + (i - 1 - s) * TILE_PITCH
        if tx > -40 and tx < 360 then
            if item == "source" then
                -- current source in its colour; pressing the tile steps it (AFMS 4-4)
                G.rstr_c(G.rfont("bold", 11), Pfd.nav_label(D), tx, 28 + off,
                    D.hsi_src == 2 and C.magenta or C.green_nav)
            elseif item == "pitch" then
                -- "+3.3°" cyan (real unit)
                G.rstr_c(G.rfont("xbold", 11), string.format("%+.1f°", cfg.pitch_offset or 0), tx, 27 + off, C.cyan)
            elseif item == "heading" then
                -- invalid values show as dashes (Pilot's Guide figure 1-18)
                if st.valid.hdg_mode == "fail" then
                    G.pic("Cyan_Bars_3_dashes", tx - 8, 28 + off)
                    G.rstr(G.rfont("bold", 6), "°", tx + 12, 34 + off, C.cyan)
                elseif st.hdg_sync then
                    -- Heading Bug Auto Sync Mode: "SYNC" where the value stands
                    -- (Pilot's Guide Rev M figure 3-19)
                    -- (a missing raster face gives nil: G.rstr* draw nothing then)
                    local fs = G.rfont("xbold", 13)
                    G.rstr_c(fs, "SYNC", tx, 33 + off - (fs and fs.size or 0) / 2, C.cyan)
                else
                    -- "065°": the Altitude tile's digits with a full-size degree
                    -- sign, centred as one group (Pilot's Guide 1.5.2 figure)
                    -- magenta for a selected track (ground track mode, or the
                    -- autopilot in TRK), like the bug: Pfd.bug_kind
                    local trk = Pfd.bug_kind(D, st) == "trk"
                    local font, col = trk and "magenta_xb" or "cyan_xb", trk and C.magenta or C.cyan
                    local str = Pfd.fmt_hdg(D.hdg_bug)
                    local fs = G.rfont("xbold", 14)
                    local dw = G.led_w(font, str, XB)
                    local gw = G.rstr_w(fs, "°")
                    local dcx = tx - (dw + 1 + gw) / 2 + dw / 2
                    G.led(font, str, dcx, 33 + off, XB)
                    G.rstr(fs, "°", dcx + dw / 2 + 1, 33 + off - (fs and fs.size or 0) / 2, col)
                end
            elseif item == "course" then
                -- the course takes the source colour (figures 2-29, 2-30), in
                -- the type of the Pitch value, "172°" (real unit, 2026-07-20 video)
                G.rstr_c(G.rfont("xbold", 11), Pfd.fmt_hdg(D.hsi_obs) .. "°", tx, 27 + off,
                    D.hsi_src == 2 and C.magenta or C.green_nav)
            elseif item == "altitude" and not st.valid.air then
                G.pic("Cyan_Bars_5_dashes", tx - 6, 28 + off)
                G.pic("Menu_Altitude_Units", tx + 26, 32.5 + off, nil, Pfd.alt_metric() and 1 or 0)
            elseif item == "altitude" then
                -- feet or meters (Units page); the art's second cell is the "m"
                local str = tostring(U.round(Pfd.alt_value(D.alt_bug)))
                G.led("cyan_xb", str, tx - 6, 33 + off, XB)
                G.pic("Menu_Altitude_Units", tx - 6 + G.led_w("cyan_xb", str, XB) / 2 + 4, 32.5 + off, nil,
                    Pfd.alt_metric() and 1 or 0)
            elseif item == "esp" then
                if UI.Esp.enabled then G.pic("GPSS_ON_Bar", tx, 24.5 + off) end
            elseif item == "gpss" then
                if D.hdg_is_gpss ~= 0 or D.gpss_status == 2 then G.pic("GPSS_ON_Bar", tx, 24.5 + off) end
            end
        end
    end
    G.pic("PFD_Menu_Selected", TILE_X0 + (st.menu_sel - 1 - s) * TILE_PITCH, 38.5 + off)
    if n > 4 then
        G.pic("Menu_Horizontal_Bar", 160.5 - 78 + 156 * s / (n - 4), 7.5 + off)
    end
end

-----------------------------------------------------------------------------
-- Popups
-----------------------------------------------------------------------------

-- bearing pointer sources (Pilot's Guide figure 2-20): None, GPS, VLOC1, VLOC2
local function brg_name(v)
    if v == 1 then return "GPS" end
    if v == 2 then return (cfg.nav_count >= 2) and "VLOC1" or "VLOC" end
    if v == 3 then return "VLOC2" end
    return "None"
end
UI.brg_name = brg_name

-- popup title in the Pops_Menu title bar (Pops_Menu_Blank, 130 x 70 at y 35.5)
local function popup_title(text, off)
    G.pic("Pops_Menu_Blank", 160.5, 35.5 + off)
    G.rstr_c(G.rfont("bold", 9), text, 160.5, 57 + off, C.white)
end

-- HSI Setup page (real unit, 2026-07-20 photos): a panel over the lower half
-- with the "Setup" title bar and two rows in view (Back, Bearing Pointer 1,
-- Bearing Pointer 2, Wind Vector, HSI Size); label left, value button right,
-- cyan frame on the selected row (Back) or its button; scroll bar right. A
-- pressed value row shows its list in the middle of the screen instead.
local SETUP_LABEL = { back = "Back", brg1 = "Bearing Pointer 1", brg2 = "Bearing Pointer 2",
    wind = "Wind Vector", size = "HSI Size" }
local OPT_LABEL = { off = "Off", speed_dir = "Speed/Dir", head_xwind = "Head/X-wind",
    normal = "Normal", expanded = "Expanded" }
local function opt_label(key, v)
    if key == "brg1" or key == "brg2" then return brg_name(v) end
    return OPT_LABEL[v] or tostring(v)
end
UI.opt_label = opt_label

local SETUP_TITLE, SETUP_ROW, SETUP_VIS = 18, 38, 2
local sc = nil
local function setup_cols()
    sc = sc or {
        frame = G.hex("8A8A8A"), row = G.hex("101010"), btn_top = G.hex("5A5A5A"),
        btn_bot = G.hex("2E2E2E"), btn_edge = G.hex("9A9A9A"), bar = G.hex("D8D8D8"),
    }
    return sc
end

local function value_button(x0, y0, x1, y1, text)
    local c = setup_cols()
    local ym = (y0 + y1) / 2
    G.rect(x0, y0, x1, ym, c.btn_bot)
    G.rect(x0, ym, x1, y1, c.btn_top)
    G.box(x0 + 0.5, y0 + 0.5, x1 - 0.5, y1 - 0.5, c.btn_edge, 1)
    G.rstr_c(G.rfont("bold", 10), text, (x0 + x1) / 2, ym - 5, C.white)
end

local function setup_popup(st, off)
    local c = setup_cols()
    local rows = In.SETUP_ROWS
    local h = SETUP_TITLE + SETUP_VIS * SETUP_ROW + 4
    local y1 = -h + h * st.popup_anim + h
    local y0 = y1 - h
    G.rect(0, y0, 320, y1, C.black)
    G.pic("Pops_Title_Bar", 160, y1 - 11)
    G.rstr_c(G.rfont("bold", 9), "Setup", 160, y1 - 13, C.white)
    -- first row in view keeps the selection visible
    st.setup_scroll = U.clamp(st.setup_scroll or 0, st.popup_row - SETUP_VIS, st.popup_row - 1)
    local first = st.setup_scroll
    local fs = G.rfont("bold", 10)
    for v = 1, SETUP_VIS do
        local i = first + v
        local key = rows[i]
        if key then
            local top = y1 - SETUP_TITLE - (v - 1) * SETUP_ROW
            local bot = top - SETUP_ROW + 3
            G.rect(4, bot, 308, top - 1, c.row)
            G.box(4.5, bot + 0.5, 307.5, top - 1.5, c.frame, 1)
            local ym = (top + bot) / 2
            if key == "back" then
                -- the blue back arrow (Icon_Back, cut from Tile_Back) at 0.6 x
                G.pic_k("Icon_Back", 30, ym, 0.6)
                G.rstr(fs, "Back", 54, ym - 5, C.white)
                if st.popup_row == i then G.box(4.5, bot + 0.5, 307.5, top - 1.5, C.cyan, 1.5) end
            else
                G.rstr(fs, SETUP_LABEL[key], 10, ym - 5, C.white)
                value_button(178, bot + 4, 302, top - 5, opt_label(key, In.setup_value(key)))
                if st.popup_row == i then G.box(177.5, bot + 3.5, 302.5, top - 4.5, C.cyan, 1.5) end
            end
        end
    end
    -- scroll bar
    local span_top, span_bot = y1 - SETUP_TITLE - 2, y0 + 3
    local span = span_top - span_bot
    local th = span * SETUP_VIS / #rows
    local ty = span_top - th - (span - th) * first / (#rows - SETUP_VIS)
    G.rect(311, ty, 314, ty + th, c.bar)
end

-- the list of a Setup row (real unit, 2026-07-20 video 0:45 / 1:07, measured):
-- centred, its bottom 9 px above the screen's bottom edge; title bar 22 px,
-- one framed 26 px entry per value (12 px text), cyan frame on the
-- highlighted one; as wide as its title / entries need (at least 132 px)
local LIST_BOTTOM, LIST_TITLE, LIST_ROW = 9, 22, 26
local list_title_col
local function setup_list(st)
    local c = setup_cols()
    local key = st.setup_drop
    local opts = In.setup_options(key)
    local title = SETUP_LABEL[key]
    local ft, fs = G.rfont("bold", 10), G.rfont("bold", 12)
    local w = math.max(132, G.rstr_w(ft, title) + 34)
    for _, v in ipairs(opts) do w = math.max(w, G.rstr_w(fs, opt_label(key, v)) + 40) end
    w = math.floor(w / 2 + 0.5) * 2
    local h = LIST_TITLE + #opts * LIST_ROW + 6
    local x0, x1 = 160 - w / 2, 160 + w / 2
    local y0 = LIST_BOTTOM
    local y1 = y0 + h
    list_title_col = list_title_col or G.hex("3A3A3A")
    G.rect(x0, y0, x1, y1, C.black)
    G.box(x0 + 0.5, y0 + 0.5, x1 - 0.5, y1 - 0.5, c.frame, 1)
    G.rect(x0 + 1, y1 - LIST_TITLE + 1, x1 - 1, y1 - 1, list_title_col)
    G.rstr_c(ft, title, 160, y1 - LIST_TITLE + 6, C.white)
    for i, v in ipairs(opts) do
        local top = y1 - LIST_TITLE - 1 - (i - 1) * LIST_ROW
        local bot = top - LIST_ROW + 2
        G.box(x0 + 4.5, bot + 0.5, x1 - 4.5, top - 0.5, c.frame, 1)
        G.rstr(fs, opt_label(key, v), x0 + 10, (top + bot) / 2 - 6, C.white)
        if st.drop_sel == i then G.box(x0 + 4, bot, x1 - 4, top, C.cyan, 1.5) end
    end
end

-- title from the tuned frequency, so "Localizer Course" also with NO LOC
local function course_popup_key(D)
    if D.hsi_src == 2 then return "Pops_Menu_OBS" end
    if Pfd.loc_tuned(D) then return "Pops_Menu_Course" end
    return "Pops_Menu_VOR"
end

-- Message list (Pilot's Guide figure 1-19): the title bar and frame of the
-- Pops_Msg_* art, one line per active message (white, 10 px bold), up to
-- MSG_ROWS at a time; the knob scrolls (st.msg_scroll).
local MSG_ROWS, MSG_PITCH = 5, 16
local msg_frame_col
local function message_list(st)
    local n = #st.msgs
    local rows = math.max(1, math.min(n, MSG_ROWS))
    local h = 25 + rows * MSG_PITCH + 12
    local y0 = -h + h * st.popup_anim
    local y1 = y0 + h
    msg_frame_col = msg_frame_col or G.hex("808080")
    G.rect(1, y0, 319, y1, C.black)
    G.box(1, y0, 319, y1, msg_frame_col, 1)
    -- title bar from the art (its top 22 rows)
    G.clip(0, y1 - 22, 320, y1)
    G.pic("Pops_Msg_Type_1", 160, y1 - 35)
    G.unclip()
    G.box(7.5, y0 + 5.5, 312.5, y1 - 24.5, msg_frame_col, 1)
    local fs = G.rfont("bold", 10)
    local first = U.clamp(st.msg_scroll or 0, 0, math.max(0, n - MSG_ROWS))
    for i = 1, rows do
        local id = st.msgs[first + i]
        if id then
            G.rstr(fs, Fail.message_text(id), 13, y1 - 25 - i * MSG_PITCH + 2, C.white)
        end
    end
    if n > MSG_ROWS then
        local span = (y1 - 26) - (y0 + 7)
        local th = span * MSG_ROWS / n
        local ty = (y1 - 26) - th - (span - th) * first / (n - MSG_ROWS)
        G.rect(308, ty, 311, ty + th, msg_frame_col)
    end
end

local function popup(D, st)
    local p = st.popup
    if p == nil or st.popup_anim <= 0 then return end
    local off = slide(st.popup_anim)
    if p == "heading" then
        -- "Select Heading" / "Select Ground Track" (figures 2-12, 2-13)
        local trk = st.valid.hdg_mode == "trk" or D.hdg_mode == 18
        popup_title(trk and "Select Ground Track" or "Select Heading", off)
        if st.hdg_sync then
            -- Heading Bug Auto Sync Mode: "SYNC" in the window (Rev M 3.3.5.2.1)
            local fs = G.rfont("xbold", 20)
            -- the window art has the value's degree sign baked in at the right
            G.rect(183, 25 + off, 196, 38 + off, C.black)
            G.rstr_c(fs, "SYNC", 160.5, 26 + off - (fs and fs.size or 0) / 2, C.cyan)
        else
            G.led("cyan", Pfd.fmt_hdg(D.hdg_bug), 154, 26 + off, DISP)
        end
    elseif p == "altitude" then
        -- "Select Altitude", the value and a stacked "ft" centred as one group
        -- (real unit, 2026-07-20 video 0:18)
        popup_title("Select Altitude", off)
        -- the window art has the heading's degree sign baked in at the right (see the SYNC case
        -- above): it showed between the digits and the unit, or inside the last digit of a
        -- five-digit value. Covered before the digits and the unit are drawn
        G.rect(183, 25 + off, 196, 38 + off, C.black)
        local str = tostring(U.round(Pfd.alt_value(D.alt_bug)))
        local vw = G.led_w("cyan", str, DISP)
        local uw = 8
        local cx = 160.5 - uw / 2
        G.led("cyan", str, cx, 26 + off, DISP)
        G.pic("Menu_Altitude_Units", cx + vw / 2 + 2 + uw / 2, 26 + off, nil, Pfd.alt_metric() and 1 or 0)
    elseif p == "course" then
        G.pic(course_popup_key(D), 160.5, 35.5 + off)
        G.led("cyan", Pfd.fmt_hdg(D.hsi_obs), 154, 26 + off, DISP)
    elseif p == "message" then
        message_list(st)
    elseif p == "setup" then
        if st.setup_drop then setup_list(st) else setup_popup(st, off) end
    elseif p == "pitch" then
        -- "Pitch Offset" +3.3° (video 2026-07-20 2:04)
        popup_title("Pitch Offset", off)
        G.rstr_c(G.rfont("bold", 18), string.format("%+.1f°", cfg.pitch_offset or 0), 160.5, 17 + off, C.cyan)
    end
end

-----------------------------------------------------------------------------
-- Backlight page
-----------------------------------------------------------------------------

local manual_fill, manual_rest
local function backlight(st)
    if st.bright_anim <= 0 then return end
    local off = slide(st.bright_anim)
    G.pic("Brightness_Panel_Main", 159.5, 35.5 + off)
    -- Brightness_Auto_Pressed is the light pressed face of the Auto button:
    -- shown while the power button is down, in Auto as in Manual (video
    -- 1:26.3-1:26.4, frames 2591-2593); Auto itself is the dark face with the
    -- green bar of Brightness_Panel_Auto
    if st.bright_press then G.pic("Brightness_Auto_Pressed", 34.5, 27.5 + off) end
    manual_fill = manual_fill or G.hex("26B8BC")
    manual_rest = manual_rest or G.hex("6A6A6A")
    if st.bright_auto or st.bright_confirm then
        -- Auto (AFMS 4-2): green wedge filled to the photocell level, green
        -- bar under "Auto". Gradient x 65.5..253.5, y 10..48.
        -- A knob press (confirm) in Manual shows the same green wedge, without
        -- the Auto bar, while the page slides out (video 1:29.6).
        if not st.bright_auto then G.clip(60, 0, 320, 80 + off) end
        G.pic("Brightness_Panel_Auto", 135.5, 28.5 + off)
        if not st.bright_auto then G.unclip() end
        -- beyond the level: black in Auto, the Manual grey in the confirm flash
        local lx = 65.5 + 188 * st.backlight
        if lx < 253.5 then
            G.rect(lx, 10 + off, 254, 48 + off, st.bright_auto and C.black or manual_rest)
        end
        G.pic("Brightness_Slider_Mask", 160, 29 + off)
    else
        -- Manual (video 1:26.2 / 1:28.0, frames 2588, 2640): the same wedge as
        -- Auto, flat cyan up to the level and grey beyond it, inside a 2 px
        -- cyan frame (the slider is what the knob adjusts). Panel_Main's
        -- gradient (x 66.5..253.5, y 10..48) is painted over.
        local lx = 65.5 + 188 * st.backlight
        G.rect(66.5, 10 + off, math.min(lx, 253.5), 48 + off, manual_fill)
        if lx < 253.5 then G.rect(lx, 10 + off, 253.5, 48 + off, manual_rest) end
        -- black above the wedge, and the "%" (x 93.5..103.5, baseline 36)
        G.pic("Brightness_Slider_Mask", 160, 29 + off)
        G.box(66, 9.5 + off, 254, 48.5 + off, C.cyan, 2)
    end
    G.led_field("white_lr", tostring(U.round(st.backlight * 100)), 3, 78, 41 + off, 0.84)
    -- battery cell: none without a battery (AFMS 4-2 figure)
    if st.batt_present and not st.fail.no_batt then
        G.pic("BATT_Icon_25", 287, 36 + off, nil, batt_frame(st.batt_pct))
        if st.charging then
            G.pic("BATT_Charging_Icon", 286.5, 35.5 + off)
        elseif st.cannot_charge then
            G.pic("BATT_NoCharge_Icon", 286.5, 35.5 + off)
        end
        G.led_field("white_lr", tostring(U.round(st.batt_pct)), 3, 277, 22 + off, 0.6)
    else
        G.rect(262, 8 + off, 314, 46 + off, C.black)
    end
end

-----------------------------------------------------------------------------
-- Dialogs, boot
-----------------------------------------------------------------------------

-- Shut_Ongoing is the text-free dialog; the texts
-- and the 3-2-1 count are raster text where the old art had them: 11 px
-- xbold titles (title ink centre x 155.5, as drawn in the old art), 29 px
-- bold digits (old "321" sheet: ink centre 159, baseline 106). Ink weights
-- matched against the old art: xbold text 84 %, bold digits 105-113 %.
local function power_off_dialog(n)
    G.pic("Shut_Ongoing", 159.5, 120.5)
    local fs = G.rfont("xbold", 11)
    G.rstr_c(fs, "Power Off", 155.5, 162, C.white)
    G.rstr_c(fs, "Hold To Power Off", 160, 74, C.white)
    if n >= 1 and n <= 3 then
        G.glyph_c(G.rfont("bold", 29), tostring(n), 159, 106, C.white)
    end
end

local function power_lost_dialog(st)
    G.pic("Ext_Power_Lost_UI", 159.5, 120.5)
    G.led("yellow_xb", tostring(math.max(0, math.ceil(st.pl_t))), 164, 119, 1.2)
end

function UI.boot(st)
    -- fades in over 0.5 s and out over the last 0.5 s (real unit)
    local a = math.min(U.clamp(st.boot_t / 0.5, 0, 1), U.clamp((cfg.boot_logo_s - st.boot_t) / 0.5, 0, 1))
    G.pic("G5_Garmin_Logo", 159, 121, G.rgba(1, 1, 1, a))
end

function UI.test_pattern()
    G.rect(0, 0, 320, 240, C.dkgrey)
    for x = 0, 320, 20 do G.line(x, 0, x, 240, C.grey, 1) end
    for y = 0, 240, 20 do G.line(0, y, 320, y, C.grey, 1) end
    G.box(1, 1, 319, 239, C.red, 2)
    G.poly(C.green, { 0, 240, 30, 240, 0, 210 })   -- top-left
    G.poly(C.cyan, { 320, 0, 290, 0, 320, 30 })    -- bottom-right
    G.textc("G5 TEST 320x240 TOP", 160, 225, 12, C.white, G.JC)
    G.textc("BOTTOM", 160, 12, 12, C.white, G.JC)
    G.textc("L", 10, 120, 14, C.yellow, G.JC)
    G.textc("R", 310, 120, 14, C.yellow, G.JC)
end

-- test_pattern = 2: shows which part of the device framebuffer the 3D screen samples
function UI.framebuffer_pattern(fw, fh)
    local hw, hh = fw / 2, fh / 2
    G.rect(0, 0, hw, hh, G.rgba(0.8, 0.1, 0.1))        -- bottom-left: red
    G.rect(hw, 0, fw, hh, G.rgba(0.1, 0.7, 0.1))       -- bottom-right: green
    G.rect(0, hh, hw, fh, G.rgba(0.1, 0.2, 0.9))       -- top-left: blue
    G.rect(hw, hh, fw, fh, G.rgba(0.9, 0.8, 0.1))      -- top-right: yellow
    for x = 0, fw, 40 do G.line(x, 0, x, fh, C.white, 1) end
    for y = 0, fh, 40 do G.line(0, y, fw, y, C.white, 1) end
    for x = 0, fw - 1, 80 do
        for y = 0, fh - 1, 80 do
            G.text(string.format("%d,%d", x, y), x + 3, y + 4, 10, C.white, G.JL)
        end
    end
    G.textc("FB " .. fw .. "x" .. fh, hw, hh, 16, C.black, G.JC)
end

function UI.draw(D, st)
    menu(D, st)
    popup(D, st)
    backlight(st)
    local n = In.power_off_countdown()
    if st.pl_active then
        power_lost_dialog(st)
    elseif n then
        power_off_dialog(n)
    end
end

return UI
