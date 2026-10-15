-- g5_ui.lua: overlays on the 2024-2025 artwork. Menu (Menu_Option_Base +
-- PFD/HSI_Options_5/6 tile strips + PFD_Menu_Selected), popups (Pops_*),
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

-- old panels slide up 70 px over 0.3 s
local function slide(anim)
    return -70 + 70 * anim
end

local TILE_X0, TILE_PITCH = 43, 78   -- tile 1 centre / spacing in the Options strips
-- gen_LED SIZEs of the old menu values: tile values (Extra Bold) and popup displays
local XB, DISP = 0.59, 0.75

-----------------------------------------------------------------------------
-- Battery indicator
-----------------------------------------------------------------------------

local function batt_frame(pct)
    return U.clamp(math.floor(pct / 20.001), 0, 4)
end

-- (the battery status itself is drawn by the pages: Pfd.battery_box)
local function page_indicators(D, st)
end

-----------------------------------------------------------------------------
-- Menu
-----------------------------------------------------------------------------

-- tile art per item (tools/make_batch_e_art.py); labelled tiles use the
-- blank tile with the label drawn as text
local TILE_ART = { back = "Tile_Back", message = "Tile_Message", gpss = "Tile_GPSS",
    hsi = "Tile_HSI", pfd = "Tile_PFD" }

local function tile_label(item, D, st)
    if item == "heading" then
        return (st.valid.hdg_mode == "trk" or D.hdg_mode == 18) and "Track" or "Heading"
    elseif item == "altitude" then return "Altitude"
    elseif item == "course" then return (D.hsi_src == 2) and "OBS" or "Course"
    elseif item == "source" then return "Source"
    elseif item == "setup" then return "Setup"
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
            elseif item == "setup" then
                if st.brg[1] ~= 0 or st.brg[2] ~= 0 then G.pic("GPSS_ON_Bar", tx, 24.5 + off) end
            elseif item == "heading" then
                -- invalid values show as dashes (Pilot's Guide figure 1-18)
                if st.valid.hdg_mode == "fail" then
                    G.pic("Cyan_Bars_3_dashes", tx - 8, 28 + off)
                else
                    G.led("cyan_xb", Pfd.fmt_hdg(D.hdg_bug), tx - 6, 33 + off, XB)
                end
                G.rstr(G.rfont("bold", 6), "°", tx + 12, 34 + off, C.cyan)
            elseif item == "course" then
                -- the course takes the source colour (figures 2-29, 2-30)
                G.led(D.hsi_src == 2 and "magenta" or "green", Pfd.fmt_hdg(D.hsi_obs), tx - 6, 33 + off, XB)
                G.rstr(G.rfont("bold", 6), "°", tx + 12, 34 + off, D.hsi_src == 2 and C.magenta or C.green_nav)
            elseif item == "altitude" and not st.valid.air then
                G.pic("Cyan_Bars_5_dashes", tx - 6, 28 + off)
                G.pic("Menu_Altitude_Units", tx + 26, 32.5 + off, nil, 0)
            elseif item == "altitude" then
                local str = tostring(U.round(D.alt_bug))
                G.led("cyan_xb", str, tx - 6, 33 + off, XB)
                G.pic("Menu_Altitude_Units", tx - 6 + G.led_w("cyan_xb", str, XB) / 2 + 4, 32.5 + off, nil, 0)
            elseif item == "gpss" then
                if D.hdg_is_gpss ~= 0 or D.gpss_status == 2 then G.pic("GPSS_ON_Bar", tx, 24.5 + off) end
            elseif item == "bearing" then
                if st.brg[1] ~= 0 or st.brg[2] ~= 0 then G.pic("GPSS_ON_Bar", tx, 24.5 + off) end
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

-- Setup (Pilot's Guide figures 2-18 .. 2-20): Back, Bearing Pointer 1, 2
local setup_frame, setup_cell
local function setup_popup(st, off)
    setup_frame = setup_frame or G.hex("808080")
    setup_cell = setup_cell or G.hex("1A1A1A")
    local frame = setup_frame
    local h = 78
    local y0 = -h + h * st.popup_anim
    local y1 = y0 + h
    G.rect(1, y0, 319, y1, C.black)
    G.box(1, y0, 319, y1, frame, 1)
    G.pic("Pops_Title_Bar", 160, y1 - 11)
    G.rstr_c(G.rfont("bold", 9), "Setup", 160, y1 - 10, C.white)
    local fs = G.rfont("bold", 10)
    local rows = { "Back", "Bearing Pointer 1", "Bearing Pointer 2" }
    for i = 1, 3 do
        local yb = y1 - 18 - (i - 1) * 18
        G.rstr(fs, rows[i], 12, yb - 10, C.white)
        if i > 1 then
            local v = brg_name(st.brg[i - 1])
            G.rect(222, yb - 13, 312, yb - 1, setup_cell)
            G.rstr_c(fs, v, 267, yb - 10, (st.brg[i - 1] ~= 0) and C.cyan or C.white)
        end
        if st.popup_row == i then
            local x0 = (st.setup_edit and i > 1) and 221 or 6
            local x1 = (st.setup_edit and i > 1) and 313 or 313
            G.box(x0 + 0.5, yb - 13.5, x1 - 0.5, yb - 0.5, C.cyan, 1)
        end
    end
end

local function course_popup_key(D)
    if D.hsi_src == 2 then return "Pops_Menu_OBS" end
    local t = (D.hsi_src == 1) and D.nav2_type or D.nav1_type
    if t == 4 or t == 5 then return "Pops_Menu_Course" end
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
        G.led("cyan", Pfd.fmt_hdg(D.hdg_bug), 154, 26 + off, DISP)
    elseif p == "altitude" then
        G.pic("Pops_Menu_Altitude", 160.5, 35.5 + off)
        G.led_field("cyan", tostring(U.round(D.alt_bug)), 5, 152, 26 + off, DISP)
    elseif p == "course" then
        G.pic(course_popup_key(D), 160.5, 35.5 + off)
        G.led("cyan", Pfd.fmt_hdg(D.hsi_obs), 154, 26 + off, DISP)
    elseif p == "message" then
        message_list(st)
    elseif p == "setup" then
        setup_popup(st, off)
    end
end

-----------------------------------------------------------------------------
-- Backlight page
-----------------------------------------------------------------------------

local function backlight(st)
    if st.bright_anim <= 0 then return end
    local off = slide(st.bright_anim)
    G.pic("Brightness_Panel_Main", 159.5, 35.5 + off)
    if st.bright_auto then
        -- Auto (AFMS 4-2): green wedge filled to the photocell level, green
        -- bar under "Auto". Gradient x 65.5..253.5, y 10..48.
        G.pic("Brightness_Auto_Pressed", 34.5, 27.5 + off)
        G.pic("Brightness_Panel_Auto", 135.5, 28.5 + off)
        local lx = 65.5 + 188 * st.backlight
        if lx < 253.5 then G.rect(lx, 10 + off, 254, 48 + off, C.black) end
        G.pic("Brightness_Slider_Mask", 160, 29 + off)
    else
        -- grey thumb (Brightness_Pusher) at the current level on the gradient
        local x0, x1 = 60 + 19, 231 - 19
        G.pic("Brightness_Pusher", x0 + (x1 - x0) * st.backlight, 33.5 + off)
        -- "%": in Auto it is part of Brightness_Slider_Mask (x 93.5..103.5,
        -- baseline 36); Manual has no mask, so the same glyph comes from the
        -- raster font
        G.glyph_c(G.rfont("bold", 10), "%", 98.5, 36 + off, C.white)
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

local function power_off_dialog(n)
    G.pic("Shut_Ongoing", 159.5, 120.5)
    -- 321 sheet frames: blank, 1, 2, 3
    local frame = (n > 3) and 0 or n
    G.pic("321", 159, 120, nil, frame)
end

local function power_lost_dialog(st)
    G.pic("Ext_Power_Lost_UI", 159.5, 120.5)
    G.led("yellow_xb", tostring(math.max(0, math.ceil(st.pl_t))), 164, 119, 1.2)
end

function UI.boot(st)
    local a = U.clamp(st.boot_t / 0.5, 0, 1)
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
    page_indicators(D, st)
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
