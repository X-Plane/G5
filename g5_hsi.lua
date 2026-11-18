-- g5_hsi.lua: HSI page (Pilot's Guide 2.2 / 2.3) on the 2024-2025 artwork:
-- HSI_BG, HSI_Round_Marks (rotating rose), HSI_Fixed (lubber ticks
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
local R_LABEL = 74            -- rose label radius
local R_BUG = 107             -- HSI_HDG_Bug radius
local RING = 60               -- HSI_Fixed inner ring
-- heading box (with its lubber needle) moved down so the box's tip meets the
-- outer outline of the rose ticks (y 213.5): on the real unit no lubber shows
-- above the ticks and it reaches further in. The art has
-- the tip at 217.
local HDG_DY = -4
local DOT = 25                -- HSI_Circles_Rot dot spacing

local LABELS = { "N", "3", "6", "E", "12", "15", "S", "21", "24", "W", "30", "33" }

-- HSI Size "Expanded" (real unit, 2026-07-20 video 1:19, measured on the
-- rectified frame): the compass group 1.28 x larger about a centre pushed
-- down to y 80, so the top of the rose stays just under the heading box (the
-- box stands free of the dial) and the top corners are clear for the bearing
-- source boxes; the rose runs off the bottom and sides. Drawn with a scale
-- transform; text is drawn unscaled at mapped positions (map()). The rose
-- labels sit further out than the scale alone gives (EXP_LABEL_K).
local EXP_X, EXP_Y, EXP_K = CX, 80, 1.28
local EXP_LABEL_K = 1.39
local big = false
local function map(x, y)
    if not big then return x, y end
    return EXP_X + EXP_K * (x - CX), EXP_Y + EXP_K * (y - CY)
end
local function compass_begin()
    if not big then return end
    G.push()
    G.translate(EXP_X, EXP_Y)
    G.scale(EXP_K)
    G.translate(-CX, -CY)
end
local function compass_end()
    if big then G.pop() end
end

-- X-Plane gps_cdi_sensitivity -> the G5's CDI scale words (Pilot's Guide
-- table 2-1 has no DPRT / MAPR / RNPAR / GLS: departure and missed approach
-- scale as TERM, RNP AR and GLS as APR). "VFR" comes from the interface
-- state instead (st.gps_vfr, g5_fail.lua).
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
-- 12 px tall number images were centred
local function rose_marks(hdg)
    G.pic_rot("HSI_Round_Marks", CX, CY, -hdg)
end

local function rose_labels(hdg)
    local fs = G.rfont("xbold", 12)
    -- the labels ride on the turning rose: keep their fractional positions,
    -- or they step a whole pixel at a time against the smoothly turning marks
    G.subpixel(true, true)
    for k = 0, 11 do
        local x, y
        if big then
            x, y = G.polar(EXP_X, EXP_Y, R_LABEL * EXP_LABEL_K, k * 30 - hdg)
        else
            x, y = G.polar(CX, CY, R_LABEL, k * 30 - hdg)
        end
        G.rstr_c(fs, LABELS[k + 1], x, y - 6, C.white)
    end
    G.subpixel(false, false)
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
        if D.nav1_sta then return D.nav1_brg end
    elseif src == 3 then
        if D.nav2_sta then return D.nav2_brg end
    end
    return nil
end

local track_line_col
local function track_marker(rel)
    rotated(rel)
    G.pic("HSI_Track_Mark", CX, CY + R - 6.5, C.magenta)
    -- the line is grey; only the marker on the rim is magenta (figure 2-16)
    track_line_col = track_line_col or G.hex("B0B0B0")
    G.dashed(CX, CY + 18, CX, CY + R - 11, track_line_col, 4, 1.5)
    G.pop()
end

local function course_and_cdi(D, hdg)
    -- GPS source with no GPS data reaching the unit (G5.lua: gps_removed)
    if D.gps_removed and D.hsi_src == 2 then return end
    local col = Pfd.nav_color(D)
    rotated(D.crs - hdg)
    do
        -- pre-rendered antialiased sprites, tinted
        G.pic("HSI_CRS_Needle", CX, CY, col)
        G.pic("HSI_Circles_Rot", CX, CY)
        if D.hsi_show_h ~= 0 then
            local x = CX + U.clamp(D.hsi_hdef, -2.4, 2.4) * DOT
            G.pic("HSI_CDI_Bar", x, CY, col)
            if D.hsi_fromto == 1 then
                G.pic("HSI_ToFrom", CX, CY + 29, col)
            elseif D.hsi_fromto == 2 then
                G.pic_rot("HSI_ToFrom", CX, CY - 29, 180, col)
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

local function vdi(D, st)
    local x = 296
    local vn = Pfd.vnav(D, st)
    if vn then
        -- VNAV path (Pfd.vnav): "V" in the label cell, the chevron's apex on
        -- the box's left inner edge (x 290.5), clipped below the label cell
        G.pic("Vert_GS_Box", x, CY)
        G.rstr_c(G.rfont("bold", 8), "V", x, CY + 46, C.magenta)
        Pfd.vnav_chevron(x - 5.5, CY, 22, vn, CY - 55.5, CY + 41.5)
    elseif D.hsi_show_v ~= 0 then
        local col = Pfd.nav_color(D)
        G.pic("Vert_GS_Box", x, CY)
        -- hsi_vdef > 0 = aircraft above the path (X-Plane, KLAF ILS 10, 2026-10-29:
        -- +1.80 at 325 ft above, -0.86 at 152 ft below): diamond below centre
        local y = CY - U.clamp(D.hsi_vdef, -2.4, 2.4) * 22
        G.pic("Nav_Diamond", x, y, col)
        -- label inside the box's top cell: magenta "G" for a GPS glidepath,
        -- empty for an ILS glideslope (figures 2-24, 2-26)
        if D.hsi_src == 2 then G.rstr_c(G.rfont("bold", 8), "G", x, CY + 46, C.magenta) end
    elseif D.hsi_src == 2 and D.no_gp then
        -- the GPS approach lost its glidepath (g5_sim Sim.update_no_gp): no
        -- figure in the manual, drawn like NO GS (our rule)
        G.textc("NO GP", x, CY, 8, C.amber, G.JC, G.font_cond)
    elseif D.hsi_src ~= 2 and D.hsi_show_h ~= 0 then
        -- a localizer without a glideslope (g5_sim Sim.nav_flags)
        local loc, gs = D.nav1_loc, D.nav1_gs
        if D.hsi_src == 1 then loc, gs = D.nav2_loc, D.nav2_gs end
        if loc and not gs then
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
-- Wind Vector (HSI Setup): off | speed_dir (arrow, speed over direction) |
-- head_xwind (head / tail and cross components). Wind needs a valid airspeed
-- too: on the ground (TAS dashed) the real unit shows NO WIND DATA.
local function wind_box(D, st, top)
    local mode = cfg.wind_vector or "speed_dir"
    if mode == "off" then return end
    local y0 = top - 31
    frame_box(0, y0, 70, top)
    local fs = G.rfont("bold", 8)
    local ok = st.valid.oat and st.valid.air and st.valid.gps and st.valid.hdg_mode ~= "fail"
        and Pfd.speed_alive()
    if not ok then
        G.rstr_c(fs, "NO WIND", 35, y0 + 17, C.white)
        G.rstr_c(fs, "DATA", 35, y0 + 6, C.white)
        return
    end
    if mode == "head_xwind" then
        -- wind from (relative to the nose): headwind + / tailwind -, crosswind
        -- from the right + / left -; arrows the way the components blow
        local a = math.rad(D.wind_dir - Pfd.dir_value(D, st))
        local spd = Pfd.speed_value(D.wind_spd)
        local head, cross = spd * math.cos(a), spd * math.sin(a)
        local ux = (head >= 0) and -1 or 1          -- headwind blows down the screen
        G.line(12, y0 + 22 + 5 * ux, 12, y0 + 22 - 5 * ux, C.white, 2)
        G.poly(C.white, { 12, y0 + 22 + 7 * ux, 8, y0 + 22 + 2 * ux, 16, y0 + 22 + 2 * ux })
        G.rstr(fs, tostring(U.round(math.abs(head))), 24, y0 + 18, C.white)
        local sx = (cross >= 0) and -1 or 1         -- from the right blows left
        G.line(12 - 5 * sx, y0 + 8, 12 + 5 * sx, y0 + 8, C.white, 2)
        G.poly(C.white, { 12 + 7 * sx, y0 + 8, 12 + 2 * sx, y0 + 12, 12 + 2 * sx, y0 + 4 })
        G.rstr(fs, tostring(U.round(math.abs(cross))) .. " " .. Pfd.speed_label(), 24, y0 + 4, C.white)
        return
    end
    local rel = D.wind_dir + 180 - Pfd.dir_value(D, st)
    -- within 4 deg of straight up / down / across, draw it straight: a 2 px
    -- shaft tilted a few degrees straddles two pixel columns and looks
    -- doubled (seen with a 360 deg wind on heading 183); the tip
    -- moves less than a pixel
    local q = U.round(rel / 90) * 90
    if math.abs(U.angdiff(rel, q)) < 4 then rel = q end
    local cx, cy = 14, y0 + 15.5
    -- shaft as a 2 px quad up to the head's base, head as a triangle: no
    -- overlapping line ends, so a vertical arrow lands on whole pixels
    -- (a vertical arrow looked doubled)
    local tx, ty = G.polar(cx, cy, 7, rel)
    local hx, hy = G.polar(cx, cy, 2, rel)
    local b1x, b1y = G.polar(cx, cy, 7, rel + 180)
    local ax, ay = G.polar(0, 0, 1, rel + 90)
    G.poly(C.white, { b1x - ax, b1y - ay, hx - ax, hy - ay, hx + ax, hy + ay, b1x + ax, b1y + ay })
    local lx, ly = G.polar(tx, ty, 6, rel + 150)
    local rx, ry = G.polar(tx, ty, 6, rel - 150)
    G.poly(C.white, { tx, ty, lx, ly, rx, ry })
    G.rstr(fs, tostring(U.round(Pfd.speed_value(D.wind_spd))) .. " " .. Pfd.speed_label(), 28, y0 + 18, C.white)
    G.rstr(fs, Pfd.fmt_hdg(D.wind_dir) .. "°", 28, y0 + 6, C.white)
end

-- bearing pointer source boxes (figures 2-15 .. 2-17; real unit 2026-07-20):
-- pointer 1 single line arrow "->", pointer 2 double line arrow "<=", the
-- source as GPS / LOC / VOR (VLOC named by what is tuned). Normal HSI: above
-- the bottom corner boxes, cut corner towards the rose (top inner corner).
-- Expanded: top corners under the wind box, label on top, cut corner at the
-- bottom inner corner.
local function brg_label(v, D)
    if v == 1 then return "GPS" end
    local w = ((v == 3) and D.nav2_loc or (v ~= 3 and D.nav1_loc)) and "LOC" or "VOR"
    if cfg.nav_count >= 2 then w = w .. ((v == 3) and "2" or "1") end
    return w
end

-- source icons, miniatures of the needles (real unit, 2026-07-20 video,
-- zoomed): a filled chevron head part way along and the shaft running on
-- past it to a point. Pointer 1 points right on a single shaft, pointer 2
-- points left on a double shaft. x = icon centre.
local function arrow1(x, y)
    G.rect(x - 11, y - 1, x + 8, y + 1, C.cyan)
    G.poly(C.cyan, { x + 8, y + 1, x + 11, y, x + 8, y - 1 })
    G.poly(C.cyan, { x - 3, y + 4.5, x - 0.5, y + 4.5, x + 4, y, x + 1, y })
    G.poly(C.cyan, { x - 3, y - 4.5, x + 1, y, x + 4, y, x - 0.5, y - 4.5 })
end

local function arrow2(x, y)
    G.rect(x - 1, y + 1, x + 9, y + 2.5, C.cyan)
    G.rect(x - 1, y - 2.5, x + 9, y - 1, C.cyan)
    G.rect(x - 6, y - 0.75, x - 2, y + 0.75, C.cyan)
    G.poly(C.cyan, { x - 6, y + 0.75, x - 9, y, x - 6, y - 0.75 })
    G.poly(C.cyan, { x + 2, y + 4.5, x + 4.5, y + 4.5, x, y, x - 2.5, y })
    G.poly(C.cyan, { x + 2, y - 4.5, x - 2.5, y, x, y, x + 4.5, y - 4.5 })
end

local function brg_box(pts, col)
    G.poly(C.black, pts)
    local o = {}
    for i = 1, #pts, 2 do
        -- frame on the inner half pixel
        o[i] = pts[i] + ((pts[i] < 160) and 0.5 or -0.5)
        o[i + 1] = pts[i + 1] + 0.5
    end
    G.loop(col, 1, o)
end

-- Bearing pointer source boxes, measured on the real unit (2026-07-20 video).
-- Normal HSI: stacked on the CRS / DTK box (pointer 1, bottom left) and on the
-- heading-bug box (pointer 2, bottom right), the same width, ~33 px tall,
-- with a large cut on the corner towards the dial (top inner corner).
-- Expanded HSI: in the top corners under the wind box, wide at the top and
-- slanted on the dial side; label on top, icon below; the right one ~13 px
-- lower than the left (clear of the distance box). Labels in the size of the
-- CRS digits.
local function bearing_source_boxes(D, st, expanded, up)
    up = up or 0
    frame_col = frame_col or G.hex("808080")
    local fs = G.rfont("bold", 13)
    if expanded then
        if st.brg[1] ~= 0 then
            local y0, y1 = 161, 194
            brg_box({ 0, y0, 0, y1, 67, y1, 39, y0 }, frame_col)
            G.rstr(fs, brg_label(st.brg[1], D), 4, y1 - 14, C.cyan)
            arrow1(20, y0 + 9)
        end
        if st.brg[2] ~= 0 then
            local y0, y1 = 148, 181
            brg_box({ 320, y0, 281, y0, 253, y1, 320, y1 }, frame_col)
            G.rstr(fs, brg_label(st.brg[2], D), 316, y1 - 14, C.cyan, G.JR)
            arrow2(301, y0 + 9)
        end
        return
    end
    if st.brg[1] ~= 0 then
        -- on the CRS / DTK box (x 0..70, top y 20; + up over the OAT box)
        brg_box({ 0, 20 + up, 0, 53 + up, 55, 53 + up, 70, 31 + up, 70, 20 + up }, frame_col)
        arrow1(20, 44 + up)
        G.rstr(fs, brg_label(st.brg[1], D), 4, 23 + up, C.cyan)
    end
    if st.brg[2] ~= 0 then
        -- on the heading-bug box (HSI_HDG_Bug_Box, x 233..320, top y 22)
        brg_box({ 320, 22, 233, 22, 233, 33, 252, 55, 320, 55 }, frame_col)
        arrow2(302, 47)
        G.rstr(fs, brg_label(st.brg[2], D), 316, 25, C.cyan, G.JR)
    end
end

-- OAT in the bottom-left corner on an HSI-only installation (Installation
-- Manual 6.3.9 step 3c: "If only a G5 HSI is installed, verify the OAT is
-- shown and valid in the bottom left hand corner of the G5 HSI"): no other
-- G5 is installed (sole_unit, set by G5.lua), this unit is installed as the
-- HSI (Power Up Page HSI with the HSI page enabled, as in the IM HSI
-- configuration tables) and the OAT sensor is configured. An attitude unit
-- with an HSI page, and the HSI unit of a dual installation, show none. No
-- figure shows it: the PFD's OAT box at the bottom, with the DTK / CRS / GS
-- box and the bearing pointer 1 box moved up over it, is our layout.
H.sole_unit = nil
function H.oat_shown()
    return cfg.show_oat ~= 0 and cfg.startup_page == 2 and cfg.hsi_page ~= 0
        and H.sole_unit ~= nil and H.sole_unit()
end

local function corner_info(D, st)
    local col = Pfd.nav_color(D)
    local fs7, fs13 = G.rfont("bold", 7), G.rfont("bold", 13)
    local up = 0
    if H.oat_shown() then
        Pfd.oat_box(D, st)
        up = 13
    end
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
    if D.hsi_src == 2 and st.valid.gps and not D.gps_removed then
        frame_box(0, up, 70, 20 + up)
        G.rstr(fs7, "DTK", 4, 5 + up, C.white)
        G.rstr(fs13, Pfd.fmt_hdg(D.crs) .. "°", 24, 4 + up, C.magenta)
    elseif D.hsi_src ~= 2 and (D.hsi_show_h ~= 0 or Pfd.nav_tuned(D)) then
        -- VOR / LOC source: the selected course, "CRS 172°" in the source
        -- colour (real unit, 2026-07-20 photos)
        frame_box(0, up, 70, 20 + up)
        G.rstr(fs7, "CRS", 4, 5 + up, C.white)
        G.rstr(fs13, Pfd.fmt_hdg(D.hsi_obs) .. "°", 24, 4 + up, col)
    elseif cfg.show_gs == 0 or (cfg.gps_internal == 0 and cfg.gps_external == 0) then
        -- no GPS fields (GPS Data Fields hidden, or no GPS configured)
    elseif st.valid.gps then
        frame_box(0, up, 70, 20 + up)
        G.rstr(fs7, "GS", 4, 5 + up, C.white)
        G.rstr(fs13, tostring(U.round(Pfd.gs_value(D.gs))), 56, 4 + up, C.magenta, G.JR)
        if Pfd.gs_unit() == 0 then Pfd.stacked("k", "t", 61, 4 + up, C.magenta, 4) end
    else
        G.fail_flag("GS", 1, 1 + up, 69, 19 + up, 8)
    end
    bearing_source_boxes(D, st, big, up)
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
    -- messages: "MSG" inside the ring, lower left (real unit), flashing until
    -- the message list has been viewed. Yellow, as the 2026-07 real-unit
    -- photos show. AFMS 7-1 says a white indication; the real unit
    -- wins, as with the 3 s AP disconnect flash: yellow on purpose, the
    -- photos are the stronger evidence
    if st.has_msg and (not st.msg_unseen or U.blink(st.clock)) then
        local x, y = map(CX - 34, CY - 31)
        G.rstr_c(G.rfont("bold", 10), "MSG", x, y, C.yellow)
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
    big = cfg.hsi_size == "expanded" and mode ~= "fail"

    if mode == "fail" then
        corner_info(D, st)
        G.pic("HSI_Round_Marks", CX, CY)
        G.pic("HSI_Fixed_NoRing", CX, CY)
        G.pic("HSI_AC_Icon", CX, CY)
        -- "HDG" flag: the heading box on a dark-red fill, red X (figure 1-10)
        hdg_flag_bg = hdg_flag_bg or G.hex("4A1010")
        G.rect(136.5, 223 + HDG_DY, 180.5, 239 + HDG_DY, hdg_flag_bg)
        G.pic("HSI_HDG_Box_O", 158.5, 215.5 + HDG_DY)
        G.rstr_c(G.rfont("bold", 11), "HDG", 158.5, 226 + HDG_DY, C.yellow)
        G.line(138, 224 + HDG_DY, 179, 238 + HDG_DY, C.red, 2)
        G.line(138, 238 + HDG_DY, 179, 224 + HDG_DY, C.red, 2)
        -- no heading reference, so no selected heading either: three
        -- dashes on the digits' baseline before the box's small degree sign
        -- (AFMS 3-1). The "unset bug" case of AFMS 3-4 / PG figure 1-18
        -- (valid heading) is not done: its trigger is unknown.
        G.pic("HSI_HDG_Bug_Box", 276.5, 10.5)
        G.pic("Cyan_Bars_3_dashes", 282, 5)
        return
    end

    compass_begin()
    rose_marks(hdg)
    -- the white ring only separates the bearing pointers from the CDI when a
    -- pointer is selected (Pilot's Guide 2.2.1.1)
    G.pic((st.brg[1] ~= 0 or st.brg[2] ~= 0) and "HSI_Fixed" or "HSI_Fixed_NoRing", CX, CY)
    for i = 2, 1, -1 do
        if st.brg[i] ~= 0 then
            local b = bearing_for(st.brg[i], D)
            if b then bearing_pointer(b - hdg, i) end
        end
    end
    if not trk and st.valid.gps and D.gs > 5 then track_marker(D.track - hdg) end
    course_and_cdi(D, hdg)
    heading_bug(D.hdg_bug - hdg, Pfd.bug_kind(D, st))
    G.pic("HSI_AC_Icon", CX, CY)
    compass_end()
    rose_labels(hdg)
    -- source left and CDI scale right of the aircraft symbol (figure 2-15)
    local fs10 = G.rfont("bold", 10)
    local lx, ly = map(CX - 31, CY + 22.5)
    G.rstr_c(fs10, Pfd.nav_label(D), lx, ly, Pfd.nav_color(D))
    -- "INT" in cyan, centred under the GPS source label (Pilot's Guide figures
    -- 1-14 / 1-16: same type size, its top row 17 px below the label's, cyan).
    -- The text never says what it means: our rule is that the G5's own GPS
    -- receiver is the GPS in use (enabled, not failed, fix after gps_init_s),
    -- so it is not drawn while only the navigator's data is being used (the
    -- "Using external GPS data" message) or with no internal receiver
    if D.hsi_src == 2 and st.gps_int_ok then
        local ix, iy = map(CX - 31, CY + 22.5 - 17)
        G.rstr_c(fs10, "INT", ix, iy, C.cyan)
    end
    if D.hsi_src == 2 then
        lx, ly = map(CX + 32, CY + 22.5)
        if st.gps_vfr then
            -- no ARINC 429 GPS data (Pilot's Guide p.26 note): "VFR", magenta
            -- on an RS-232 only installation (figure 1-16), yellow when the
            -- GAD 29 has failed (1.4.1.2, AFMS 3-3). The deflection arrives
            -- on the VFR scale (0.25 / 1.25 / 5.00 nm, G5.lua vfr_dots).
            G.rstr_c(fs10, "VFR", lx, ly, (cfg.nav_interface == "rs232") and C.magenta or C.yellow)
        else
            G.rstr_c(fs10, CDI_SCALE[D.gps_cdi] or "ENR", lx, ly, C.magenta)
        end
    end
    vdi(D, st)
    corner_info(D, st)

    -- heading box "087°" with the orange lubber line; in track mode one wide
    -- box "TRK 358°M" with the red-X "HDG" inside (figures 2-15, 1-8)
    if trk then
        trk_label_col = trk_label_col or G.hex("B8B8B8")
        G.pic("HSI_TRK_Box", 158.5, 215.5 + HDG_DY)
        G.rstr_c(G.rfont("bold", 9), "TRK", 120, 226 + HDG_DY, trk_label_col)
        G.led("magenta_lr", Pfd.fmt_hdg(hdg), 150, 231 + HDG_DY, 1.05)
        Pfd.stacked("°", "M", 170, 226 + HDG_DY, C.magenta, 5)
        if st.valid.hdg_flag then
            G.rstr_c(G.rfont("bold", 9), "HDG", 190, 226 + HDG_DY, C.yellow)
            G.line(177, 224 + HDG_DY, 203, 238 + HDG_DY, C.red, 2)
            G.line(177, 238 + HDG_DY, 203, 224 + HDG_DY, C.red, 2)
        end
    else
        -- "HDG 200°" (real unit): widened box on black (the expanded rose
        -- runs under it), small grey HDG label, the heading, a degree sign
        G.rect(125, 224 + HDG_DY, 192, 240 + HDG_DY, C.black)
        G.pic("HSI_HDG_Box_L", 158.5, 215.5 + HDG_DY)
        -- digits and degree sign yellow while the magnetic heading may be
        -- outside its accuracy limits (Pilot's Guide 1.4.1.2)
        local deg = st.valid.hdg_degraded
        trk_label_col = trk_label_col or G.hex("B8B8B8")
        G.rstr(G.rfont("bold", 7), "HDG", 127, 227 + HDG_DY, trk_label_col)
        G.led(deg and "yellow_lr" or "white_lr", Pfd.fmt_hdg(hdg), 166.5, 231 + HDG_DY, 1.05)
        G.rstr(G.rfont("bold", 12), "°", 183.5, 225 + HDG_DY, deg and Pfd.hdg_yellow() or C.white)
    end
    G.pic("HSI_HDG_Bug_Box", 276.5, 10.5)
    -- the digits take the bug's colour: magenta for a selected track (ground
    -- track mode, or the autopilot in TRK), see Pfd.bug_kind
    G.led(Pfd.bug_kind(D, st) == "trk" and "magenta_lr" or "cyan_lr", Pfd.fmt_hdg(D.hdg_bug), 285, 10)
end

return H
