-- g5_hsi.lua: HSI page (Pilot's Guide 2.2 / 2.3) on the 2024-2025 artwork:
-- HSI_BG, HSI_Round_Marks (rotating rose), HSI_Nums, HSI_Fixed (lubber ticks
-- and the bearing-pointer ring), HSI_HDG_Box, HSI_HDG_Bug, HSI_HDG_Bug_Box,
-- HSI_AC_Icon, HSI_Circles_Rot (CDI dots), Vert_GS_Box (VDI).
-- Course pointer, deviation bar, TO/FROM, bearing pointers and the track
-- marker have no artwork and are vector drawn.
--
-- Navigation geometry is X-Plane's: the pilot HSI datarefs already follow the
-- selected source (NAV1 / NAV2 / GPS), this page only renders them.

local U, G, Sys, Pfd, cfg
local C

local H = {}

local CX, CY = 159.5, 109.5   -- rose centre (old POS 166.5, 1259.5)
local R = 104                 -- HSI_Round_Marks radius
local R_LABEL = 74            -- HSI_Nums radius
local R_BUG = 107             -- HSI_HDG_Bug radius
local RING = 60               -- HSI_Fixed inner ring
local DOT = 25                -- HSI_Circles_Rot dot spacing

local LABELS = { "N", "3", "6", "E", "12", "15", "S", "21", "24", "W", "30", "33" }

-- X-Plane gps_cdi_sensitivity -> the G5's CDI scale words (Pilot's Guide
-- table 2-1 has no DPRT / MAPR / RNPAR / GLS: departure and missed approach
-- scale as TERM, RNP AR and GLS as APR)
local CDI_SCALE = { [0] = "OCN", "ENR", "TERM", "TERM", "TERM", "APR", "APR", "LNAV",
    "LNAV+V", "LNAV/VNAV", "LP", "LPV", "LP+V", "APR" }

function H.init(util, gfx, sys, pfd, config)
    U, G, Sys, Pfd, cfg = util, gfx, sys, pfd, config
    C = G.C
end

-- start a frame rotated to compass angle `rel` (clockwise, 0 = up) about
-- the rose centre; close it with G.pop()
local function rotated(rel)
    G.push()
    G.rotate(CX, CY, -rel)
end

-- rose labels: upright, white 12 px xbold raster text (ink weight of the old
-- art: bold 82%, xbold 96%), ink centred where the old
-- 12 px tall HSI_Nums images were centred
local function rose(hdg)
    G.pic_rot("HSI_Round_Marks", CX, CY, -hdg)
    local fs = G.rfont("xbold", 12)
    for k = 0, 11 do
        local x, y = G.polar(CX, CY, R_LABEL, k * 30 - hdg)
        G.rstr_c(fs, LABELS[k + 1], x, y - 6, C.white)
    end
end

-- 1 = single line, 2 = double line (Pilot's Guide fig 2-16 / 2-17)
local function bearing_pointer(rel, kind)
    rotated(rel)
    do
        local col = C.cyan
        local tip, r_in = CY + R - 14, CY + RING + 2
        local tail_out, tail_in = CY - R + 14, CY - RING - 2
        if kind == 1 then
            G.line(CX, r_in, CX, tip - 2, col, 1.5)
            G.strip(col, 1.5, { CX - 6, tip - 8, CX, tip, CX + 6, tip - 8 })
            G.line(CX, tail_in, CX, tail_out, col, 1.5)
        else
            G.line(CX - 3, r_in, CX - 3, tip - 6, col, 1.5)
            G.line(CX + 3, r_in, CX + 3, tip - 6, col, 1.5)
            G.strip(col, 1.5, { CX - 8, tip - 10, CX, tip, CX + 8, tip - 10 })
            G.line(CX - 3, tail_in, CX - 3, tail_out, col, 1.5)
            G.line(CX + 3, tail_in, CX + 3, tail_out, col, 1.5)
        end
    end
    G.pop()
end

local function bearing_for(src, D)
    if src == 1 then
        if D.gps_has_dme ~= 0 or D.gps_dme > 0 then return D.gps_brg end
    elseif src == 2 then
        if D.nav1_type ~= 0 then return D.nav1_brg end
    elseif src == 3 then
        if D.nav2_type ~= 0 then return D.nav2_brg end
    end
    return nil
end

local track_line_col
local function track_marker(rel)
    rotated(rel)
    G.poly(C.magenta, { CX, CY + R - 2, CX + 5, CY + R - 11, CX - 5, CY + R - 11 })
    -- the line is grey; only the marker on the rim is magenta (figure 2-16)
    track_line_col = track_line_col or G.hex("B0B0B0")
    G.dashed(CX, CY + 18, CX, CY + R - 11, track_line_col, 4, 1.5)
    G.pop()
end

local function course_and_cdi(D, hdg)
    local col = Pfd.nav_color(D)
    rotated(D.hsi_obs - hdg)
    do
        G.line(CX, CY + 46, CX, CY + R - 24, col, 3)
        G.poly(col, { CX, CY + R - 14, CX + 7, CY + R - 28, CX - 7, CY + R - 28 })
        G.line(CX, CY - 46, CX, CY - R + 14, col, 3)
        G.pic("HSI_Circles_Rot", CX, CY)
        if D.hsi_show_h ~= 0 then
            local x = CX + U.clamp(D.hsi_hdef, -2.4, 2.4) * DOT
            G.line(x, CY - 42, x, CY + 42, col, 3)
            if D.hsi_fromto == 1 then
                G.poly(col, { CX, CY + 34, CX + 7, CY + 24, CX - 7, CY + 24 })
            elseif D.hsi_fromto == 2 then
                G.poly(col, { CX, CY - 34, CX - 7, CY - 24, CX + 7, CY - 24 })
            end
        end
    end
    G.pop()
end

-- kind from Pfd.bug_kind: "hollow" (GPSS), "trk" (magenta selected track), "hdg"
local function heading_bug(rel, kind)
    local x, y = G.polar(CX, CY, R_BUG, rel)
    local key = (kind == "hollow") and "HSI_HDG_Bug_Hollow" or ((kind == "trk") and "HSI_TRK_Bug" or "HSI_HDG_Bug")
    G.pic_rot(key, x, y, rel)
end

local function vdi(D)
    local x = 296
    if D.hsi_show_v ~= 0 then
        local col = Pfd.nav_color(D)
        G.pic("Vert_GS_Box", x, CY)
        local y = CY + U.clamp(D.hsi_vdef, -2.4, 2.4) * 22
        G.poly(col, { x, y + 6, x + 5, y, x, y - 6, x - 5, y })
        -- label inside the box's top cell: magenta "G" for a GPS glidepath,
        -- empty for an ILS glideslope (figures 2-24, 2-26)
        if D.hsi_src == 2 then G.rstr_c(G.rfont("bold", 8), "G", x, CY + 46, C.magenta) end
    elseif D.hsi_src ~= 2 and D.hsi_show_h ~= 0 then
        local t = (D.hsi_src == 1) and D.nav2_type or D.nav1_type
        if t == 4 or t == 5 then
            G.textc("NO GS", x, CY, 8, C.amber, G.JC, G.font_cond)
        end
    end
end

local frame_col
local function frame_box(x0, y0, x1, y1)
    frame_col = frame_col or G.hex("808080")
    G.rect(x0, y0, x1, y1, C.black)
    G.box(x0 + 0.5, y0 + 0.5, x1 - 0.5, y1 - 0.5, frame_col, 1)
end

-- Wind (GAD 13, Pilot's Guide figure 2-15 / 4-6): an arrow the way the wind
-- blows relative to the nose, speed over direction; NO WIND DATA without OAT,
-- air data, GPS or heading (AFMS 3-3).
local function wind_box(D, st, top)
    local y0 = top - 31
    frame_box(0, y0, 70, top)
    local fs = G.rfont("bold", 8)
    local ok = st.valid.oat and st.valid.air and st.valid.gps and st.valid.hdg_mode ~= "fail"
    if not ok then
        G.rstr_c(fs, "NO WIND", 35, y0 + 17, C.white)
        G.rstr_c(fs, "DATA", 35, y0 + 6, C.white)
        return
    end
    local rel = D.wind_dir + 180 - Pfd.dir_value(D, st)
    local cx, cy = 14, y0 + 15.5
    local tx, ty = G.polar(cx, cy, 7, rel)
    local bx, by = G.polar(cx, cy, 7, rel + 180)
    G.line(bx, by, tx, ty, C.white, 2)
    local lx, ly = G.polar(tx, ty, 6, rel + 150)
    local rx, ry = G.polar(tx, ty, 6, rel - 150)
    G.poly(C.white, { tx, ty, lx, ly, rx, ry })
    G.rstr(fs, tostring(U.round(Pfd.speed_value(D.wind_spd))) .. " " .. Pfd.speed_label(), 28, y0 + 18, C.white)
    G.rstr(fs, Pfd.fmt_hdg(D.wind_dir) .. "°", 28, y0 + 6, C.white)
end

-- bearing pointer source boxes (figures 2-15 .. 2-17, Installation Manual
-- figure 6-5): pointer 1 bottom-left (single line arrow), pointer 2
-- bottom-right (double line), cut corner towards the rose
local function bearing_source_boxes(D, st, UIname)
    frame_col = frame_col or G.hex("808080")
    local fs = G.rfont("bold", 10)
    if st.brg[1] ~= 0 then
        G.poly(C.black, { 0, 20, 70, 20, 70, 40, 56, 54, 0, 54 })
        G.loop(frame_col, 1, { 0.5, 20.5, 69.5, 20.5, 69.5, 40, 56, 53.5, 0.5, 53.5 })
        G.line(8, 46, 30, 46, C.cyan, 1.5)
        G.poly(C.cyan, { 30, 46, 25, 50, 25, 42 })
        G.rstr(fs, UIname(st.brg[1]), 4, 25, C.cyan)
    end
    if st.brg[2] ~= 0 then
        G.poly(C.black, { 250, 20, 319, 20, 319, 54, 264, 54, 250, 40 })
        G.loop(frame_col, 1, { 250.5, 20.5, 318.5, 20.5, 318.5, 53.5, 264, 53.5, 250.5, 40 })
        G.line(292, 44, 312, 44, C.cyan, 1.5)
        G.line(292, 48, 312, 48, C.cyan, 1.5)
        G.strip(C.cyan, 1.5, { 296, 51, 290, 46, 296, 41 })
        G.rstr(fs, UIname(st.brg[2]), 315, 25, C.cyan, G.JR)
    end
end

local function corner_info(D, st)
    local col = Pfd.nav_color(D)
    local fs7, fs13 = G.rfont("bold", 7), G.rfont("bold", 13)
    -- top-right: "DIST 21.9nm" (figure 2-15)
    if D.hsi_has_dme ~= 0 or (D.hsi_src == 2 and D.gps_dme > 0) then
        local nm = D.hsi_dme
        if D.hsi_src == 2 and nm <= 0 then nm = D.gps_dme end
        local s = (nm < 100) and string.format("%.1f", nm) or tostring(U.round(nm))
        frame_box(221, 220, 320, 240)
        G.rstr(fs7, "DIST", 226, 226, C.white)
        G.rstr(fs13, s, 304, 224, col, G.JR)
        Pfd.stacked("n", "m", 309.5, 224, col, 4)
    end
    -- bottom-left: DTK with a GPS source (figure 2-15), otherwise ground
    -- speed (figure 2-17); red X without GPS; nothing when no GPS is
    -- configured (Maintenance Manual 8)
    if D.hsi_src == 2 and st.valid.gps then
        frame_box(0, 0, 70, 20)
        G.rstr(fs7, "DTK", 4, 5, C.white)
        G.rstr(fs13, Pfd.fmt_hdg(D.gps_dtk) .. "°", 24, 4, C.magenta)
    elseif cfg.show_gs == 0 or (cfg.gps_internal == 0 and cfg.gps_external == 0) then
        -- no GPS fields (GPS Data Fields hidden, or no GPS configured)
    elseif st.valid.gps then
        frame_box(0, 0, 70, 20)
        G.rstr(fs7, "GS", 4, 5, C.white)
        G.rstr(fs13, tostring(U.round(Pfd.gs_value(D.gs))), 56, 4, C.magenta, G.JR)
        if Pfd.gs_unit() == 0 then Pfd.stacked("k", "t", 61, 4, C.magenta, 4) end
    else
        G.fail_flag("GS", 1, 1, 69, 19, 8)
    end
    bearing_source_boxes(D, st, H.brg_name)
    -- top-left stack: battery status, GPSS, wind (Installation Manual
    -- figure 6-5, Pilot's Guide figure 4-4)
    local top = 240
    if Pfd.battery_shown(st) then
        Pfd.battery_box(st, 231.5)
        top = 222
    end
    if Pfd.gpss_shown(D, H.gfc) then
        Pfd.gpss_box(D, st, top - 7.5)
        top = top - 16
    end
    if cfg.show_wind ~= 0 and cfg.show_oat ~= 0 then wind_box(D, st, top) end
    -- message icon: flashes until the message list has been viewed
    if st.has_msg and (not st.msg_unseen or U.blink(st.clock)) then
        G.pic("Has_message_Icon", 9.5, 79.5)
    end
end

-- Heading source (g5_fail.lua, Pilot's Guide 1.4.1.2): magnetic heading;
-- without it GPS ground track ("TRK", magenta value and bug, track-up card,
-- red-X "HDG" flag when an installed magnetometer failed); with neither the
-- compass card loses its labels and the pointers, figure 1-10.
local hdg_flag_bg, trk_label_col
function H.draw(D, st)
    local mode = st.valid.hdg_mode
    local trk = mode == "trk"
    local hdg = Pfd.dir_value(D, st)
    G.pic("HSI_BG", 159.5, 119.5)
    corner_info(D, st)

    if mode == "fail" then
        G.pic("HSI_Round_Marks", CX, CY)
        G.pic("HSI_Fixed_NoRing", CX, CY)
        G.pic("HSI_AC_Icon", CX, CY)
        -- "HDG" flag: the heading box on a dark-red fill, red X (figure 1-10)
        hdg_flag_bg = hdg_flag_bg or G.hex("4A1010")
        G.rect(136.5, 223, 180.5, 239, hdg_flag_bg)
        G.pic("HSI_HDG_Box_O", 158.5, 215.5)
        G.rstr_c(G.rfont("bold", 11), "HDG", 158.5, 226, C.yellow)
        G.line(138, 224, 179, 238, C.red, 2)
        G.line(138, 238, 179, 224, C.red, 2)
        G.pic("HSI_HDG_Bug_Box", 276.5, 10.5)
        G.led("cyan_lr", Pfd.fmt_hdg(D.hdg_bug), 285, 10)
        return
    end

    rose(hdg)
    -- the white ring only separates the bearing pointers from the CDI when a
    -- pointer is selected (Pilot's Guide 2.2.1.1)
    G.pic((st.brg[1] ~= 0 or st.brg[2] ~= 0) and "HSI_Fixed" or "HSI_Fixed_NoRing", CX, CY)
    -- source left and CDI scale right of the aircraft symbol (figure 2-15)
    local fs10 = G.rfont("bold", 10)
    G.rstr_c(fs10, Pfd.nav_label(D), CX - 31, CY + 22.5, Pfd.nav_color(D))
    if D.hsi_src == 2 then
        G.rstr_c(fs10, CDI_SCALE[D.gps_cdi] or "ENR", CX + 32, CY + 22.5, C.magenta)
    end
    for i = 2, 1, -1 do
        if st.brg[i] ~= 0 then
            local b = bearing_for(st.brg[i], D)
            if b then bearing_pointer(b - hdg, i) end
        end
    end
    if not trk and st.valid.gps and D.gs > 5 then track_marker(D.track - hdg) end
    course_and_cdi(D, hdg)
    heading_bug(D.hdg_bug - hdg, Pfd.bug_kind(D, st))
    vdi(D)
    G.pic("HSI_AC_Icon", CX, CY)

    -- heading box "087°" with the orange lubber line; in track mode one wide
    -- box "TRK 358°M" with the red-X "HDG" inside (figures 2-15, 1-8)
    if trk then
        trk_label_col = trk_label_col or G.hex("B8B8B8")
        G.pic("HSI_TRK_Box", 158.5, 215.5)
        G.rstr_c(G.rfont("bold", 9), "TRK", 120, 226, trk_label_col)
        G.led("magenta_lr", Pfd.fmt_hdg(hdg), 150, 231, 1.05)
        Pfd.stacked("°", "M", 170, 226, C.magenta, 5)
        if st.valid.hdg_flag then
            G.rstr_c(G.rfont("bold", 9), "HDG", 190, 226, C.yellow)
            G.line(177, 224, 203, 238, C.red, 2)
            G.line(177, 238, 203, 224, C.red, 2)
        end
    else
        G.pic("HSI_HDG_Box_O", 158.5, 215.5)
        G.led("white_lr", Pfd.fmt_hdg(hdg), 156, 231, 1.05)
        G.rstr(G.rfont("bold", 12), "°", 173, 225, C.white)
    end
    G.pic("HSI_HDG_Bug_Box", 276.5, 10.5)
    G.led(trk and "magenta_lr" or "cyan_lr", Pfd.fmt_hdg(D.hdg_bug), 285, 10)
end

return H
