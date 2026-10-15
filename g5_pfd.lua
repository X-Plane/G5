-- g5_pfd.lua: PFD page, drawn with the 2024-2025 G5 artwork at 1:1.
--
-- Positions are the Plane Maker POS values of the old 3D-panel G5 converted
-- to screen pixels (screen = panel - (7, 1150)); images are centred on them.
-- Animation constants (px per kt / ft / deg, strip key frames) are the old
-- KEY_FRAME values. Vector drawing only where no artwork exists.

local U, G, Sys, cfg
local C
local dual_ylw, gpss_frame

local P = {}

local CX, CY = 160, 120     -- attitude centre (gen_needle POS 167,1270)
local PPD = 3.6             -- px per pitch degree (ArtHori_Words: 36 px / 10 deg)
local PPK = 4               -- px per knot (60 kt on 240 px)
local PPF = 0.6             -- px per foot (400 ft on 240 px)

function P.init(util, gfx, sys, config)
    U, G, Sys, cfg = util, gfx, sys, config
    C = G.C
    PPD = cfg.pitch_px_per_deg
end

local yoff = 0 -- whole-PFD displacement when the autopilot is engaged (old: -14 px)

-- local coordinates: the scissor follows the current translation (see g5_gfx)
local function clip(x0, y0, x1, y1)
    G.clip(x0, y0, x1, y1)
end

local function nav_color(D)
    if D.hsi_src == 2 then return C.magenta end
    return C.green_nav
end
P.nav_color = nav_color

local function nav_type(D)
    return (D.hsi_src == 1) and D.nav2_type or D.nav1_type
end

-- a localizer is tuned: the receiver reports a LOC / ILS station, or (no
-- station received) the frequency is 108.10-111.95 MHz with an odd tenth.
-- Source label, AFCS word and "NO LOC" all use this.
local function loc_tuned(D)
    local t = nav_type(D)
    if t == 4 or t == 5 then return true end
    local f = (D.hsi_src == 1) and D.nav2_freq or D.nav1_freq
    return f >= 10810 and f <= 11195 and math.floor(f / 10) % 2 == 1
end
P.loc_tuned = loc_tuned

-- Source names (Pilot's Guide table 2-1): GPS / VOR / LOC, with the
-- navigator number only when two navigators are configured (nav_count).
local function nav_label(D)
    local two = cfg.nav_count >= 2
    if D.hsi_src == 2 then return two and "GPS1" or "GPS" end
    local n = two and ((D.hsi_src == 1) and "2" or "1") or ""
    if loc_tuned(D) then return "LOC" .. n end
    return "VOR" .. n
end
P.nav_label = nav_label

local function fmt_hdg(v)
    local h = U.round(v) % 360
    if h == 0 then h = 360 end
    return string.format("%03d", h)
end
P.fmt_hdg = fmt_hdg

-----------------------------------------------------------------------------
-- Attitude (ArtHori_BG / _Gradients / _Words / Red_Arrows are gen_needles
-- whose artwork is drawn rotated 90 deg: sky on the left of the bitmap)
-----------------------------------------------------------------------------

-- Pitch ladder: one ArtHori_Ladder cell per 2.5 deg line (k = -36..36, line
-- pitch -2.5 k, cell centre 9 k - 1 px below the horizon on the bitmap). Like
-- the real unit, only lines near the current pitch show: full within
-- LADDER_FULL deg, fading to nothing over the next LADDER_FADE deg. The
-- horizon line (k = 0) always shows.
local LADDER_FULL, LADDER_FADE = 15, 5

local function ladder(pitch)
    local y0 = CY - pitch * PPD
    local k0 = math.max(-36, math.ceil(-(pitch + LADDER_FULL + LADDER_FADE) / 2.5))
    local k1 = math.min(36, math.floor(-(pitch - LADDER_FULL - LADDER_FADE) / 2.5))
    if k0 > 0 then k0 = 0 end
    if k1 < 0 then k1 = 0 end
    for k = k0, k1 do
        local a = 1
        if k ~= 0 then
            local d = math.abs(-2.5 * k - pitch)
            a = U.clamp((LADDER_FULL + LADDER_FADE - d) / LADDER_FADE, 0, 1)
        end
        if a > 0 then
            G.pic_rot("ArtHori_Ladder", CX, y0 - (9 * k - 1), 90, G.white_alpha(a), k + 36)
        end
    end
end

-- Roll_Arc = rows 0..48 of Roll_Indicator (arc and ticks only); its centre on
-- screen and the lowest row of the arc, below which Roll_Indicator only holds
-- the aircraft symbol
local ROLL_ARC_CY, ROLL_ARC_BOTTOM = 188, 163
-- the arc line is a circle of radius ~84.4 around (159, 121)
local ARC_X, ARC_Y, ARC_R = 159, 121, 84.4

-- Standard-turn roll reference (Figure 2-1 #26, 3-4): green triangles just outside
-- the arc at the bank angle of a 3 deg/s turn at the current TAS, pointing in
-- at the arc like the zero mark. `rot` = rotation of the scale (ground pointer).
local STD_RATE = math.rad(3)
local function std_turn_ref(D, rot)
    if cfg.std_turn_ref == 0 or D.tas < 30 then return end
    local b = math.deg(math.atan(D.tas * 0.514444 * STD_RATE / 9.80665))
    G.push()
    G.rotate(CX, CY, rot)
    for s = -1, 1, 2 do
        local a = s * b
        local tx, ty = G.polar(ARC_X, ARC_Y, ARC_R + 2, a)
        local lx, ly = G.polar(ARC_X, ARC_Y, ARC_R + 10, a - 3.4)
        local rx, ry = G.polar(ARC_X, ARC_Y, ARC_R + 10, a + 3.4)
        G.poly(C.green, { tx, ty, rx, ry, lx, ly })
    end
    G.pop()
end

-- "ALIGNING" on its dark-blue backing (figure 1-4), ~53 px above the horizon
local align_bg
local function aligning_label(y)
    align_bg = align_bg or G.hex("1C2F7A", 0.9)
    G.rect(118, y - 8, 201, y + 8, align_bg)
    G.pic("ALIGNING", 159.5, y)
end

-- the aircraft symbol alone (the symbol rows of Roll_Indicator)
local function aircraft_symbol()
    G.pic("Aimer_1", 159, 111)
    clip(0, 0, 320, ROLL_ARC_BOTTOM)
    G.pic("Roll_Indicator", 159, 154)
    G.unclip()
end

-- No attitude (Pilot's Guide figures 1-5, 1-6): black, the aircraft symbol,
-- and either "ATTITUDE FAIL" on a red X or "ALIGNING / KEEP WINGS LEVEL".
-- No command bars, roll scale, slip or turn rate.
local att_fail_bg
local function no_attitude(st)
    if st.att_state == "fail" then
        att_fail_bg = att_fail_bg or G.hex("3C1410")
        G.rect(88, 40, 230, 200, att_fail_bg)
        G.red_x(90, 42, 228, 198, 5)
        local fs = G.rfont("bold", 14)
        G.rstr_c(fs, "ATTITUDE", 159, 178, C.yellow)
        G.rstr_c(fs, "FAIL", 159, 160, C.yellow)
        aircraft_symbol()
    else
        aircraft_symbol()
        aligning_label(168)
        G.rstr_c(G.rfont("bold", 8), "KEEP WINGS LEVEL", 159.5, 148, C.yellow)
    end
end

local function attitude(D, st)
    if st.att_state == "fail" or st.att_state == "kwl" then
        no_attitude(st)
        return
    end
    local pitch, roll = D.pitch, D.roll
    -- keep a sliver of sky / ground at extreme pitch (old AH_Gradient masks)
    local bg = U.clamp(pitch * PPD, -(CY - 14), CY - 14)

    G.push()
    G.rotate(CX, CY, roll)
    G.pic_rot("ArtHori_BG", CX, CY - bg, 90)
    G.pic_rot("ArtHori_Gradients", CX, CY - bg, 90)
    ladder(pitch)
    G.pic_rot("Red_Arrows", CX, CY - pitch * PPD, 90)
    G.pop()

    G.pic("Shades_Main", 160, 120)

    -- flight director: commands limited to pitch -15..+20, roll 30 (3.3.3)
    local dual = cfg.fd_cue == "dual"
    if D.ap_mode >= 1 then
        local fp = U.clamp(D.fd_pitch, -15, 20)
        local fr = U.clamp(D.fd_roll, -30, 30)
        if dual then
            -- dual cue (figures 2-6, 3-7): magenta cross, horizontal bar = pitch
            -- command, vertical bar = roll command
            local mag = C.magenta
            local by = CY + U.clamp((fp - pitch) * PPD, -60, 60)
            local bx = CX + U.clamp((fr - roll) * 1.5, -60, 60)
            G.rect(CX - 52, by - 1.5, CX + 52, by + 1.5, mag)
            G.rect(bx - 1.5, CY - 52, bx + 1.5, CY + 52, mag)
        else
            -- single cue (FD_Aimer: FD only, AP_Aimer: AP engaged)
            G.push()
            G.rotate(CX, CY, roll)
            G.translate(0, (fp - pitch) * PPD)
            G.rotate(CX, CY, -fr)
            G.pic(D.ap_mode >= 2 and "AP_Aimer" or "FD_Aimer", 158.5, 108.5)
            G.pop()
        end
    end

    if not dual then G.pic("Aimer_1", 159, 111) end

    -- Roll scale (Pilot's Guide 2.1.2.1). OUT_Turn_Tri is the inverted zero
    -- mark, INN_Turn_Tri the roll pointer. Ground pointer (default): arc and
    -- zero mark turn with the horizon, the pointer stays at the top. Sky
    -- pointer: arc fixed, the pointer turns with the horizon. Roll_Indicator
    -- also holds the aircraft symbol, so in ground mode only its symbol rows
    -- are drawn level and the arc comes from Roll_Arc (tools/make_roll_arc.py).
    if dual then
        dual_ylw = dual_ylw or G.hex("F0D000")
        local ylw, edge = dual_ylw, C.black
        for sgn = -1, 1, 2 do
            local x0, x1 = CX + sgn * 28, CX + sgn * 68
            G.rect(math.min(x0, x1) - 1, CY - 2, math.max(x0, x1) + 1, CY + 3, edge)
            G.rect(math.min(x0, x1), CY - 1, math.max(x0, x1), CY + 2, ylw)
            G.rect(x0 - 2, CY - 9, x0 + 2, CY + 3, edge)
            G.rect(x0 - 1, CY - 8, x0 + 1, CY + 2, ylw)
        end
        G.rect(CX - 3, CY - 2, CX + 3, CY + 4, edge)
        G.rect(CX - 2, CY - 1, CX + 2, CY + 3, ylw)
    end
    if cfg.roll_pointer == "sky" then
        if dual then
            G.pic("Roll_Arc", 159, ROLL_ARC_CY)
        else
            G.pic("Roll_Indicator", 159, 154)
        end
        G.pic("OUT_Turn_Tri", 158.5, 210.5)
        std_turn_ref(D, 0)
        G.push()
        G.rotate(CX, CY, roll)
        G.pic("INN_Turn_Tri", 158.5, 200.5)
        G.pop()
    else
        if not dual then
            clip(0, 0, 320, ROLL_ARC_BOTTOM)
            G.pic("Roll_Indicator", 159, 154)
            G.unclip()
        end
        G.push()
        G.rotate(CX, CY, roll)
        G.pic("Roll_Arc", 159, ROLL_ARC_CY)
        G.pic("OUT_Turn_Tri", 158.5, 210.5)
        G.pop()
        std_turn_ref(D, roll)
        G.pic("INN_Turn_Tri", 158.5, 200.5)
    end
    -- valid but not yet within the accuracy limits: attitude stays usable
    if st.att_state == "aligning" then aligning_label(173) end
end

-----------------------------------------------------------------------------
-- Vertical speed (VS_30config: +/-3000 fpm, VS_15config: +/-1500 fpm)
-----------------------------------------------------------------------------

local function vsi(D)
    local dir = (cfg.vsi_scale == 15) and "VS_15config/" or "VS_30config/"
    local range = cfg.vsi_scale * 100
    G.pic(dir .. "VS_Stripe_Full", 311, 121)
    local k = 107 / range
    local vy = U.clamp(D.vs, -range, range) * k
    if math.abs(vy) > 0.5 then
        G.image(dir .. "VS_Stripe", 315.5, 121 + math.min(0, vy), 319.5, 121 + math.max(0, vy))
    end
    if D.alt_mode == 4 then
        G.pic("VS-Bug", 317.5, 120.5 + U.clamp(D.vs_bug, -range, range) * k)
    end
    G.pic(dir .. "VS_Arrow", 315.5, 120.5 + U.clamp(D.vs, -range, range) * 107.5 / range)
end

-----------------------------------------------------------------------------
-- Heading tape: ticks from HDG_Ticks (5 px per degree, KEY_FRAME 0 -> 898,
-- 360 -> -902), labels every 10 deg in the raster font where the old
-- HDG_Nums art had them: 7 px off-white, ink centre x 159 + 5 * (V - hdg),
-- baseline y 231
-----------------------------------------------------------------------------

local HDG_LABEL_PX, HDG_LABEL_BASE = 7, 231
local hdg_label_col

-- Heading source (g5_fail.lua): magnetic heading, or GPS ground track without
-- it (Pilot's Guide 1.4.1.2): "TRK" label, magenta value and track bug, and a
-- red-X "HDG" flag when an installed magnetometer has failed.
function P.dir_value(D, st)
    if st.valid.hdg_mode == "trk" then return D.track end
    return D.hdg
end

-- Heading tape failure banner (figure 1-9, AFMS 3-1) on a dark-red backing:
-- HEADING FAIL with a magnetometer installed, GPS FAIL on a track-only unit.
local banner_bg
local function heading_banner(magnetometer)
    banner_bg = banner_bg or G.hex("5A1010", 0.8)
    G.rect(67, 216, 232, 239, banner_bg)
    if magnetometer then
        G.pic("Heading_Fail", 149.5, 227.5)
    else
        G.line(69, 218, 230, 237, C.red, 3)
        G.line(69, 237, 230, 218, C.red, 3)
        G.rstr_c(G.rfont("bold", 13), "GPS FAIL", 149.5, 221, C.yellow)
    end
end

-- small stacked unit glyphs ("kt", "°M"): `top` above `bottom`, ink centred on x
local function stacked(top, bottom, x, base, col, px)
    px = px or 4
    local fs = G.rfont("bold", px)
    G.rstr_c(fs, top, x, base + px + 1.5, col)
    G.rstr_c(fs, bottom, x, base, col)
end
P.stacked = stacked

local trk_label_col
local function heading_tape(D, st)
    local mode = st.valid.hdg_mode
    if mode == "fail" then
        heading_banner(cfg.magnetometer ~= 0)
        return
    end
    local trk = mode == "trk"
    local hdg = P.dir_value(D, st)
    G.pic("HDG_Shade", 149.5, 228.5)
    clip(65, 216, 234, 241)
    G.pic("HDG_Ticks", 149.5 + 898 - hdg * 5, 228.5)
    hdg_label_col = hdg_label_col or G.hex("BFBFBF")
    local fs = G.rfont("bold", HDG_LABEL_PX)
    local v0 = math.floor((hdg - 20) / 10) * 10
    for v = v0, v0 + 40, 10 do
        G.rstr_c(fs, string.format("%03d", v % 360), 159 + 5 * (v - hdg), HDG_LABEL_BASE, hdg_label_col)
    end
    -- bug: hollow while GPSS steers (figure 4-3); magenta selected track in
    -- track mode or with the GFC 500 in TRK (figure 2-13)
    local r = U.clamp((U.angdiff(D.hdg_bug, hdg) + 18) / 34, 0, 1)
    local bug = P.bug_kind(D, st)
    G.pic(bug == "hollow" and "Bug_HDG_Hollow" or (bug == "trk" and "Bug_TRK" or "Bug_HDG"), 64.5 + r * 169, 220.5)
    -- selected course / DTK: small arrow in the source colour (figure 2-1)
    if D.hsi_show_h ~= 0 then
        local cx = 159 + 5 * U.angdiff(D.hsi_obs, hdg)
        if cx > 64 and cx < 235 then
            local col = nav_color(D)
            G.rect(cx - 1, 216, cx + 1, 220, col)
            G.poly(col, { cx - 3.5, 219.5, cx, 224.5, cx + 3.5, 219.5 })
        end
    end
    -- current ground track: magenta triangle on the tick line (Figure 2-12),
    -- shown while GPS ground speed makes the track meaningful
    if not trk and st.valid.gps and D.gs > 5 then
        local tx = 159 + 5 * U.angdiff(D.track, hdg)
        if tx > 62 and tx < 237 then
            G.poly(C.magenta, { tx - 4, 217, tx, 222, tx + 4, 217 })
        end
    end
    G.unclip()
    -- value box: "087°" (figure 2-1); in track mode one wider box holding
    -- grey "TRK", the magenta track, a stacked "°M" and the red-X "HDG"
    -- (figure 1-7). Digits: ~8 px advance, ~11 px glyphs (real unit).
    if trk then
        trk_label_col = trk_label_col or G.hex("B8B8B8")
        G.pic("TRK_Num_Box", 159, 231)
        G.rstr_c(G.rfont("bold", 8), "TRK", 122, 228, trk_label_col)
        G.led("magenta", fmt_hdg(hdg), 149, 233, 0.45)
        stacked("°", "M", 166, 228, C.magenta, 5)
        if st.valid.hdg_flag then
            G.rstr_c(G.rfont("bold", 8), "HDG", 185, 228, C.yellow)
            G.line(172, 226, 198, 237, C.red, 2)
            G.line(172, 237, 198, 226, C.red, 2)
        end
    else
        G.pic("HDG_Num_Box_W", 159, 231)
        G.led("white", fmt_hdg(hdg), 155.5, 233, 0.45)
        G.rstr(G.rfont("bold", 10), "°", 169.5, 228, C.white)
    end
end

-----------------------------------------------------------------------------
-- Battery status (Pilot's Guide 2.1.7, AFMS 3-4 / 4-2): top-left corner,
-- "99%" then the icon; H:MM once on battery for about a minute; lightning
-- bolt while charging, a hollow dashed bolt when it cannot charge; BATT
-- (battery fault) / NO BATT (not detected) flags. Shown always or only on
-- battery (show_battery); nothing when no battery is configured.
-----------------------------------------------------------------------------

local function batt_frame(pct)
    return U.clamp(math.floor(pct / 20.001), 0, 4)
end
P.batt_frame = batt_frame

function P.battery_shown(st)
    if st.mode < Sys.PFD then return false end
    if st.fail.no_batt or (st.fail.battery and st.batt_present) then return true end
    if not st.batt_present then return false end
    if cfg.show_battery == "always" then return true end
    return not st.ext_power or st.cannot_charge
end

local batt_flag_bg
function P.battery_box(st, y)
    if st.fail.no_batt or (st.fail.battery and st.batt_present) then
        batt_flag_bg = batt_flag_bg or G.hex("7A1010")
        G.fail_flag(st.fail.no_batt and "NO BATT" or "BATT", 1, y - 8.5, 64, y + 8.5, 8, batt_flag_bg)
        return
    end
    G.pic("BATT_PFD_Box", 32.5, y)
    local fs = G.rfont("bold", 9)
    local base = y - 4.5
    if not st.ext_power and st.on_batt_t >= 60 then
        -- remaining time; the box art carries the colon
        local m = math.max(0, math.floor(Sys.battery_minutes()))
        local h = math.min(9, math.floor(m / 60))
        G.rstr(fs, tostring(h), 9.5, base, C.white, G.JR)
        G.rstr(fs, string.format("%02d", math.min(59, m - h * 60)), 13.5, base, C.white)
    else
        G.rect(10, y - 4, 12, y + 2, C.black)
        G.rstr(fs, tostring(U.round(st.batt_pct)) .. "%", 3, base, C.white)
    end
    G.pic("BATT_Icon_25", 46, y, nil, batt_frame(st.batt_pct))
    if st.charging then
        G.pic("BATT_Charging_Icon", 45.5, y - 0.5)
    elseif st.cannot_charge then
        G.pic("BATT_NoCharge_Icon", 45.5, y - 0.5)
    end
end

-- GPSS selected (Pilot's Guide 4.1, figures 4-3 / 4-4, AFMS 4-3): a box
-- with a crossed-out heading bug and "GPSS"; amber when the GPSS data is
-- invalid (no GPS source, no GPS, no lateral guidance). Only with an analog
-- autopilot interface (gpss_menu), not with a GFC 500.
function P.gpss_shown(D, gfc)
    return cfg.gpss_menu ~= 0 and not gfc and (D.hdg_is_gpss ~= 0 or D.gpss_status ~= 0)
end

function P.gpss_box(D, st, y)
    local ok = D.hsi_src == 2 and st.valid.gps and D.hsi_show_h ~= 0
    local col = ok and C.white or C.amber
    G.rect(0, y - 7, 56, y + 7, C.black)
    gpss_frame = gpss_frame or G.hex("808080")
    G.box(0.5, y - 6.5, 55.5, y + 6.5, gpss_frame, 1)
    G.pic("Bug_HDG", 12, y)
    G.line(4, y - 5, 20, y + 5, C.white, 1.5)
    G.line(4, y + 5, 20, y - 5, C.white, 1.5)
    G.rstr(G.rfont("bold", 8), "GPSS", 25, y - 4, col)
end

-- which heading bug to draw: "hollow" (GPSS), "trk" (magenta selected
-- track) or "hdg"
function P.bug_kind(D, st)
    if D.hdg_is_gpss ~= 0 or D.gpss_status == 2 then return "hollow" end
    if st.valid.hdg_mode == "trk" or D.hdg_mode == 18 then return "trk" end
    return "hdg"
end

-----------------------------------------------------------------------------
-- Airspeed tape
-----------------------------------------------------------------------------

-- knots -> display unit (settings.ini: kt / mph / km/h). The whole airspeed
-- display (tape, limits, V-speeds, bug, readout, boxes) is in that unit, like
-- the real unit; speed_tape_min stays in display units.
local KT_TO = { [0] = 1, [1] = 1.15078, [2] = 1.852 }
local function speed_value(kt)
    return kt * (KT_TO[cfg.speed_unit] or 1)
end
P.speed_value = speed_value
local SPEED_LABEL = { [0] = "KT", [1] = "MPH", [2] = "KMH" }
function P.speed_label()
    return SPEED_LABEL[cfg.speed_unit] or "KT"
end

-- ground speed has its own unit (configuration mode Units page); -1 = the
-- airspeed unit
function P.gs_unit()
    local u = cfg.gs_unit or -1
    if u < 0 then return cfg.speed_unit end
    return u
end
function P.gs_value(kt)
    return kt * (KT_TO[P.gs_unit()] or 1)
end

-- band limits: configuration mode value (knots) or, at 0, the aircraft's
function P.vlimit(D, key)
    local v = cfg[key] or 0
    if v > 0 then return v end
    return D[key] or 0
end

local function strip(key, lo, hi, spd, x0, x1)
    if hi <= lo then return end
    local y0 = CY + 1 + (lo - spd) * PPK
    local y1 = CY + 1 + (hi - spd) * PPK
    if y1 < -2 or y0 > 242 then return end
    G.image(key, x0, math.max(y0, -2), x1, math.min(y1, 242))
end

-- { config key, marker art, letter drawn on the blank flag }
local VREFS = { { "vx", "vx_marker" }, { "vy", "vy_marker" }, { "va", "va_marker" }, { "vg", "vg_marker" },
    { "vr", "vflag_blank", "R" } }

local vyse_col, vletter_col
local function vline(kt, col, spd)
    local v = speed_value(kt or 0)
    if v <= 0 then return end
    vyse_col = vyse_col or G.hex("2F8CFF")
    local y = CY + 1 + (v - spd) * PPK
    G.rect(58, y - 1, 65, y + 1, col or vyse_col)
end

local function vmarker(ref, y)
    G.pic(ref[2], 71.5, y)
    -- letter cell of the art: x 6..12, rows 2..8 (baseline 4 px below the centre)
    if ref[3] then
        vletter_col = vletter_col or G.hex("80CBDC")
        G.glyph_c(G.rfont("bold", 9), ref[3], 73.5, y - 4, vletter_col)
    end
end

-- top edge of the GS / OAT boxes in the lower-left corner (screen y, not
-- displaced by the AP bar); see boxes_bottom
local function bottom_boxes_top()
    local top = 0
    if cfg.show_oat ~= 0 then top = 13.5 end
    if cfg.show_gs ~= 0 and (cfg.gps_internal ~= 0 or cfg.gps_external ~= 0) then top = top + 19 end
    return top
end

local vref_list = {}
local function vref_desc(a, b) return a[1] > b[1] end

-- Airspeed indication starts at speed_tape_min (Pilot's Guide 2.1.1: 30 kt).
-- Below it the readout shows dashes and the V-speeds are listed at the bottom
-- (2.1.1.1); all of them switch together, with speed_alive_hyst of hysteresis
-- so taxi-speed noise around the threshold does not make them flicker.
local spd_alive = false
local function update_speed_alive(D)
    local ias = speed_value(D.ias)
    if spd_alive then
        if ias < cfg.speed_tape_min - cfg.speed_alive_hyst then spd_alive = false end
    elseif ias >= cfg.speed_tape_min then
        spd_alive = true
    end
end

local function speed_tape(D, st, gfc)
    local vmin = cfg.speed_tape_min
    local ias = speed_value(D.ias)
    local vso, vs1, vno = speed_value(P.vlimit(D, "vso")), speed_value(P.vlimit(D, "vs1")), speed_value(P.vlimit(D, "vno"))
    local vne, vfe = speed_value(P.vlimit(D, "vne")), speed_value(P.vlimit(D, "vfe"))
    local spd = math.max(ias, vmin)
    -- the tape ends at its minimum speed: nothing is drawn below it (at low
    -- speed the red strip, ticks and labels stop at the pointer)
    local floor_y = math.max(0, CY + 1 + (vmin - spd) * PPK)

    -- colour strips (SPD_Strip_*, x 58..65; white line x 62..65)
    clip(58, floor_y, 65, 240)
    if vso > 0 then strip("SPD_Strip_Red", 0, vso, spd, 58, 65) end
    if vso > 0 and vs1 > vso then strip("SPD_Strip_White", vso, vs1, spd, 58, 65) end
    if vs1 > 0 and vno > vs1 then strip("SPD_Strip_Green", vs1, vno, spd, 58, 65) end
    if vno > 0 and vne > vno then strip("SPD_Strip_Yellow", vno, vne, spd, 58, 65) end
    if vso > 0 and vfe > vso then strip("SPD_Strip_White_Line", vso, vfe, spd, 62, 65) end
    if vne > 0 then
        local y = CY + 1 + (vne - spd) * PPK
        while y < 242 do
            G.image("SPD_Strip_Barber", 58, y, 65, y + 240)
            y = y + 240
        end
    end
    -- multi-engine: red line at VMC, blue line at VYSE (configuration mode)
    vline(cfg.vmc, C.red, spd)
    vline(cfg.vyse, vyse_col, spd)
    G.unclip()

    -- tick tape (30 kt cycle = 120 px; stops at the bottom below 50 kt)
    local r
    if ias < vmin then r = -1
    elseif ias < vmin + 30 then r = -(1 - (ias - vmin) / 30)
    else r = (ias % 30) / 30 end
    local off = (r < 0) and (60.5 + (-r) * 120.5) or (60.5 - 120 * r)
    clip(0, floor_y, 65, 240)
    G.pic("SPD_Tape", 57.5, 120 + off)
    -- labels every 10 kt (gen_LED, Num_OffWhite_Bold, centre x 21)
    local v = math.floor((spd - 40) / 10) * 10
    while v <= spd + 40 do
        if v >= vmin then
            G.led_field("offwhite", tostring(v), 3, 21, CY + 1 + (v - spd) * PPK, 0.58)
        end
        v = v + 10
    end
    G.unclip()

    -- trend vector (magenta, right of the strips)
    local trend = speed_value(D.ias_accel) * cfg.speed_trend_s * PPK
    if spd_alive and math.abs(trend) > 1 then
        local y = U.clamp(CY + 1 + trend, floor_y, 240)
        G.image("VS_15config/VS_Stripe", 65.5, math.min(CY + 1, y), 69.5, math.max(CY + 1, y))
    end

    -- V-speed references. Below the tape minimum they are listed in speed
    -- order (highest on top) like the real unit, stacked on top of the GS /
    -- OAT boxes: the boxes keep their place, the list moves up.
    local n = 0
    for _, ref in ipairs(VREFS) do
        local val = cfg[ref[1]]   -- knots in config.ini
        if val then val = speed_value(val) end
        if val and val > 0 then
            if not spd_alive then
                n = n + 1
                local e = vref_list[n] or {}
                e[1], e[2] = val, ref
                vref_list[n] = e
            else
                local y = CY + 1 + (val - spd) * PPK
                if y > 4 and y < 236 then vmarker(ref, y) end
            end
        end
    end
    for i = #vref_list, n + 1, -1 do vref_list[i] = nil end
    if n > 0 then
        table.sort(vref_list, vref_desc)
        -- real unit: 15 px pitch, first entry ~8.5 px above the box edge
        local base = bottom_boxes_top() + 8.5 - yoff
        for i = 1, n do
            local y = base + (n - i) * 15
            vmarker(vref_list[i][2], y)
            G.led_field("cyan_lr", tostring(U.round(vref_list[i][1])), 3, 48, y + 1, 0.9)
        end
    end

    -- airspeed reference bug: GFC 500 IAS mode only (Pilot's Guide 3.3.4.5)
    if gfc and D.alt_mode == 5 then
        local rb = U.clamp((speed_value(D.spd_bug) - (spd - 30)) / 60, 0, 1)
        G.pic("Bug_SPD", 59.5, 0.5 + rb * 240)
    end
end

-----------------------------------------------------------------------------
-- Altimeter tape
-----------------------------------------------------------------------------

-- old gen_LEDs (x = POS - 7): "Large xx000" SIZE 0.6 at 250 (+dt), below
-- 10000 ft "Small 00xxx" 0.49 at 262 (+ind +dt); above, "Single Digit" 0.49
-- at 257 and "Smaller 000xx" 0.36 at 268 (+ind +dt)
-- The old panel positions sat ~8 px left of the real unit's labels and ran
-- into the major ticks (Pilot's Guide figure 2-9: "2700" spans x 251..288);
-- five-digit labels move only 4 px so they stay clear of the VSI scale.
local function alt_label(a, y, font)
    local aa = math.abs(a)
    local large = math.floor(aa / 1000)
    local small = aa % 1000
    local dt = ((large >= 10) and 12 or 0) + ((aa >= 10000) and 4 or 8)
    local ind = (large > 0) and 12 or 0
    local sign = (a < 0) and "-" or ""
    if large > 0 then
        G.led_field(font, sign .. tostring(large), 2, 243 + dt, y, 0.6)
        if aa >= 10000 then
            G.led_field(font, tostring(math.floor(small / 100)), 1, 250 + ind + dt, y, 0.49)
            G.led_field(font, string.format("%02d", small % 100), 2, 261 + ind + dt, y, 0.36)
        else
            G.led_field(font, string.format("%03d", small), 3, 255 + ind + dt, y, 0.49)
        end
    else
        G.led_field(font, sign .. tostring(small), 3, 255 + dt, y, 0.49)
    end
end

local function altitude_tape(D, st)
    local alt = D.alt
    clip(234, 0, 296, 240)
    local r = (alt % 400) / 400
    G.pic("ALT_Tape", 241.5, 120 + 121 - 240 * r)
    -- the selected altitude's label is cyan whenever it is on the tape
    -- (figures 2-9, 2-14), autopilot or not
    local hl = true
    local hl_val = U.round(D.alt_bug / 100) * 100
    local a = math.floor((alt - 260) / 100) * 100
    while a <= alt + 260 do
        local font = (hl and a == hl_val) and "cyan" or "offwhite"
        alt_label(a, CY + 1 + (a - alt) * PPF, font)
        a = a + 100
    end
    local rb = U.clamp((D.alt_bug - (alt - 200)) / 400, 0, 1)
    G.pic("Bug_ALT", 239.5, 0.5 + rb * 240)
    G.unclip()
end

-----------------------------------------------------------------------------
-- Rolling readouts (SPD_ALT_Box + digit strips + SPD_ALT_Shade)
-----------------------------------------------------------------------------

-- Digit drums in raster fonts (G.roll), placed like the old 0..9 strip images:
-- large digits are 16 px with a 25 px pitch, the altitude tens 12 px labels
-- every 20 ft at 19.75 px. base = baseline of digit 0 at value 0. The
-- altitude hundreds digit is large like the thousands (real unit); the three
-- large altitude lanes sit at a 13 px pitch, hundreds flush with the box edge.
local BIG, SMALL = 16, 12
local P_BIG = 25
local SPD_BASE, ALT_BASE = 112.5, 113.5
local ALT10_BASE, ALT10_PITCH = 115, 9.875 -- per 10 ft

-- Airspeed pointer colours (Pilot's Guide 2.1.1): the pointer turns red at
-- VNE; the digits turn yellow while the 6 s trend vector crosses VNE.
-- Interior of the speed pointer in SPD_ALT_Box (drawn at 159, 121): body
-- x 6..54 y 109..133, drum window x 40..55 y 94..148, arrow tip at x 58.
local spd_red_col
local function speed_pointer_fill(col)
    G.rect(6, 109, 54, 133, col)
    G.rect(40, 94, 55, 148, col)
    G.poly(col, { 54, 127, 58, 121, 54, 115 })
end

local function speed_alert(D)
    local vne = P.vlimit(D, "vne")
    if vne <= 0 then return nil end
    if D.ias >= vne then return "red" end
    if D.ias + D.ias_accel * cfg.speed_trend_s >= vne then return "yellow" end
    return nil
end

local function readouts(D, st)
    G.pic("SPD_ALT_Box", 159, 121)
    do
        -- airspeed
        local spd = speed_value(D.ias)
        local alert = speed_alert(D)
        if alert == "red" then
            spd_red_col = spd_red_col or G.hex("E02010")
            speed_pointer_fill(spd_red_col)
        end
        local dcol = (alert == "yellow") and C.yellow or C.white
        if not spd_alive then
            -- one dash under each digit lane: tens lane centre x 30.5, ones
            -- window x 39..54 (centre 46.5). No_SPD holds both dashes
            -- (columns 0..6, centre 3.5, and 16..23, ink centre 20).
            clip(6, 110, 38, 133)
            G.pic("No_SPD", 30.5 - 3.5 + 12, 121)
            G.unclip()
            clip(38, 95, 54, 148)
            G.pic("No_SPD", 46.5 - 20 + 12, 121)
            G.unclip()
        else
            local fs = G.rfont("bold", BIG)
            local ones = spd % 10
            local f10 = (ones > 9) and (ones - 9) or 0
            local f100 = (spd % 100 > 99) and (spd % 100 - 99) or 0
            clip(6, 110, 38, 133)
            G.roll(fs, 14.5, SPD_BASE, math.floor(spd / 100) % 10 + f100, P_BIG, dcol, true)
            G.roll(fs, 30.5, SPD_BASE, math.floor(spd / 10) % 10 + f10, P_BIG, dcol)
            G.unclip()
            clip(38, 95, 53, 148)
            G.roll(fs, 46.5, SPD_BASE, ones, P_BIG, dcol)
            G.unclip()
        end

        -- altitude
        local a = math.max(D.alt, 0)
        local last2 = a % 100
        local h = math.floor(a / 100) % 10
        local th = math.floor(a / 1000) % 10
        local tth = math.floor(a / 10000) % 10
        local fh = (last2 > 80) and (last2 - 80) / 20 or 0
        local fth = (h == 9) and fh or 0
        local ftth = (th == 9) and fth or 0
        -- tens: "00".."80" labels, higher values above
        clip(286, 97, 311, 146)
        local fs = G.rfont("bold", SMALL)
        local t10 = math.floor(a / 10) % 10 + (a % 10) / 10
        local k0 = math.floor(t10 / 2) * 2
        for k = k0 - 4, k0 + 6, 2 do
            G.rstr(fs, string.format("%02d", (k * 10) % 100), 299.5, ALT10_BASE + (k - t10) * ALT10_PITCH, C.white, G.JC)
        end
        G.unclip()
        -- body interior x 247..286 (column 286 is the box edge)
        clip(247, 108, 286, 135)
        fs = G.rfont("bold", BIG)
        if a > 80 then G.roll(fs, 280, ALT_BASE, h + fh, P_BIG, C.white) end
        G.roll(fs, 267, ALT_BASE, th + fth, P_BIG, C.white, a < 9980)
        if a > 9980 then G.roll(fs, 254, ALT_BASE, tth + ftth, P_BIG, C.white, true) end
        G.unclip()
    end
    G.pic("SPD_ALT_Shade", 166 - 7, 121)
end

-----------------------------------------------------------------------------
-- Slip / turn rate / CDI / VDI / message icon (not displaced by the AP bar)
-----------------------------------------------------------------------------

local turn_rate = 0
local last_hdg = nil

function P.update(dt, D)
    update_speed_alive(D)
    local st = Sys.st
    if st.mode == Sys.PFD then
        P.track_afcs(D, st)
    else
        P.fl.reseed = true
    end
    -- turn rate from the AHRS heading (deg/s), lightly smoothed
    if last_hdg ~= nil and dt > 0 then
        local r = U.angdiff(D.hdg, last_hdg) / dt
        -- a new flight / position jump is not a turn
        if math.abs(r) > 100 then r = 0 end
        turn_rate = turn_rate + (r - turn_rate) * math.min(1, dt * 4)
    end
    last_hdg = D.hdg
end

local function slip_turn(D)
    G.pic("Turn_Rate_Indicator", 159, 5)
    -- trend vector: the 8 px wide Turn_Rate_Tape (tip at its top) laid on
    -- its side along the bottom edge, stretched to the rate (figure 2-11)
    local px = U.clamp(turn_rate / 3 * 41.5, -62, 62)
    if math.abs(px) > 0.5 then
        G.push()
        G.rotate(159, 4.5, px > 0 and -90 or 90)
        G.image("Turn_Rate_Tape", 155, 4.5, 163, 4.5 + math.abs(px))
        G.pop()
    end
    G.pic("Slip_Indicator_Box", 159, 24)
    G.pic("Slip_Ball", 159 - U.clamp(D.slip, -7, 7) * 27 / 7, 23)
end


-- Lateral deviation (Horizontal_GS: 112 x 15 box at the old dev-mode POS,
-- centre line on the aircraft symbol x 159, dots every 21.5 px). NAV source
-- with a localizer tuned but no signal: "NO LOC" in place of the inner dots
-- and centre line, as on the real unit. Half-pixel y keeps the edges on pixels.
local CDI_X, CDI_Y, CDI_DOT = 159, 45.5, 21.5

local function cdi_pfd(D)
    local nav = D.hsi_src ~= 2
    if D.hsi_show_h ~= 0 then
        local col = nav_color(D)
        G.pic("Horizontal_GS", CDI_X, CDI_Y)
        -- pointer: magenta triangle for GPS, green diamond for VOR / LOC
        -- (figures 2-1, 2-21); no source label on the PFD
        local x = CDI_X + U.clamp(D.hsi_hdef, -2.3, 2.3) * CDI_DOT
        if D.hsi_src == 2 then
            G.poly(col, { x - 6, CDI_Y - 5, x, CDI_Y + 6, x + 6, CDI_Y - 5 })
        else
            G.poly(col, { x, CDI_Y + 6, x + 5, CDI_Y, x, CDI_Y - 6, x - 5, CDI_Y })
        end
    elseif nav and loc_tuned(D) then
        local x0, x1, y0, y1 = CDI_X - 56, CDI_X + 56, CDI_Y - 7.5, CDI_Y + 7.5
        local m = 33   -- between the outer (+-43) and inner (+-22) dots
        clip(x0, y0, CDI_X - m, y1) G.pic("Horizontal_GS", CDI_X, CDI_Y) G.unclip()
        clip(CDI_X + m, y0, x1, y1) G.pic("Horizontal_GS", CDI_X, CDI_Y) G.unclip()
        clip(CDI_X - m, y0, CDI_X + m, y0 + 1) G.pic("Horizontal_GS", CDI_X, CDI_Y) G.unclip()
        clip(CDI_X - m, y1 - 1, CDI_X + m, y1) G.pic("Horizontal_GS", CDI_X, CDI_Y) G.unclip()
        G.rect(CDI_X - m, y0 + 1, CDI_X + m, y1 - 1, G.black_alpha(0.65))
        G.textc("NO LOC", CDI_X, CDI_Y, 9, C.white, G.JC, G.font)
    end
end

-- Vertical deviation (Vert_GS_Box 13 x 113 at the old POS: a label cell on
-- top, centre line on the altitude pointer y 121.5, dots every ~18.75 px).
-- Localizer tuned without a glideslope: "NO GS" between the outer dots.
local VDI_X, VDI_Y, VDI_DOT = 226.5, 128, 18.75
local VDI_C = VDI_Y - 6.5

local function vdi(D)
    local x = VDI_X
    if D.hsi_show_v ~= 0 then
        local col = nav_color(D)
        G.pic("Vert_GS_Box", x, VDI_Y)
        local y = VDI_C + U.clamp(D.hsi_vdef, -2.4, 2.4) * VDI_DOT
        G.poly(col, { x, y + 6, x + 5, y, x, y - 6, x - 5, y })
        -- label cell: magenta "G" for a GPS glidepath, empty for an ILS
        -- glideslope (figures 2-23, 2-25)
        if D.hsi_src == 2 then G.rstr_c(G.rfont("bold", 8), "G", x, VDI_Y + 45, C.magenta) end
    elseif D.hsi_src ~= 2 and loc_tuned(D) then
        local x0, x1, y0, y1 = x - 6.5, x + 6.5, VDI_C - 28, VDI_C + 28
        clip(x0, VDI_Y - 56.5, x1, y0) G.pic("Vert_GS_Box", x, VDI_Y) G.unclip()
        clip(x0, y1, x1, VDI_Y + 56.5) G.pic("Vert_GS_Box", x, VDI_Y) G.unclip()
        clip(x0, y0, x0 + 1, y1) G.pic("Vert_GS_Box", x, VDI_Y) G.unclip()
        clip(x1 - 1, y0, x1, y1) G.pic("Vert_GS_Box", x, VDI_Y) G.unclip()
        G.rect(x0 + 1, y0, x1 - 1, y1, G.black_alpha(0.65))
        G.textc("N", x, VDI_C + 15, 9, C.white, G.JC, G.font)
        G.textc("O", x, VDI_C + 4, 9, C.white, G.JC, G.font)
        G.textc("G", x, VDI_C - 11, 9, C.white, G.JC, G.font)
        G.textc("S", x, VDI_C - 22, 9, C.white, G.JC, G.font)
    end
end

-----------------------------------------------------------------------------
-- Air data failure (Pilot's Guide figure 1-2): both tapes, the readouts, the
-- VSI and the selected altitude give way to dark panels with a red X and
-- "AIRSPEED FAIL" / "ALTITUDE FAIL" in stacked yellow letters. Drawn in the
-- displaced (AP bar) frame; the bottom boxes are not displaced.
-----------------------------------------------------------------------------

local air_fail_bg
local function air_fail()
    air_fail_bg = air_fail_bg or G.hex("3C1410")
    local fs = G.rfont("bold", 12)
    local x0, y0, x1, y1 = 1, bottom_boxes_top() + 1 - yoff, 64, 240
    G.rect(x0, y0, x1, y1, air_fail_bg)
    G.red_x(x0 + 2, y0 + 2, x1 - 2, y1 - 2, 5)
    local cy = (y0 + y1) / 2
    G.vtext(fs, "AIRSPEED", 19, cy, 18, C.yellow)
    G.vtext(fs, "FAIL", 46, cy, 18, C.yellow)
    x0, y0, x1, y1 = 235, 20 - yoff, 319, 240
    G.rect(x0, y0, x1, y1, air_fail_bg)
    G.red_x(x0 + 2, y0 + 2, x1 - 2, y1 - 2, 5)
    cy = (y0 + y1) / 2
    G.vtext(fs, "ALTITUDE", 262, cy, 18, C.yellow)
    G.vtext(fs, "FAIL", 292, cy, 18, C.yellow)
end

-----------------------------------------------------------------------------
-- Data boxes
-----------------------------------------------------------------------------


local function boxes_bottom(D, st)
    -- baro (Baro_Box, inHg 2 decimals or hPa)
    -- inHg as on the real unit: "29.92" then a stacked "in" (Baro_Unit_in,
    -- tools/make_unit_sprites.py); the period takes a 5 px gap
    G.pic("Baro_Box", 276.5, 9.5)
    if cfg.baro_unit == 1 then
        G.led_field("cyan_lr", tostring(U.round(D.baro * 33.8639)), 4, 275, 9, 0.95)
    else
        G.led("cyan_lr", string.format("%.2f", D.baro), 275, 9, 0.95, 5)
        G.pic("Baro_Unit_in", 303.5, 9.5)
    end
    -- VS target (VS mode)
    local da_y0 = 19
    if D.alt_mode == 4 and st.valid.air then
        -- "+500" / "-500" (figure 3-11)
        local v = U.round(D.vs_bug / 10) * 10
        G.pic("VS_Box", 276.5, 26.5)
        G.led_field("cyan_lr", ((v < 0) and "-" or "+") .. tostring(math.abs(v)), 5, 271, 27, 0.93)
        da_y0 = 36
    end
    -- density altitude above the baro box, with an OAT probe, while there is
    -- no airspeed (on the ground: Installation Manual figure 6-4; the in-flight
    -- figures with a GAD 13 have none)
    if cfg.show_density_alt ~= 0 and cfg.show_oat ~= 0 and st.valid.oat and st.valid.air
        and not spd_alive then
        local pa = D.alt + (29.92 - D.baro) * 1000
        local da = pa + 118.8 * (D.oat_c - (15 - 1.98 * pa / 1000))
        G.rect(234, da_y0, 319, da_y0 + 24, C.black)
        G.box(234.5, da_y0 + 0.5, 318.5, da_y0 + 23.5, C.white, 1)
        G.rstr_c(G.rfont("bold", 6), "DENSITY ALT", 276.5, da_y0 + 15, C.white)
        G.rstr_c(G.rfont("bold", 9), tostring(U.round(da / 100) * 100), 276.5, da_y0 + 3, C.white)
    end
    -- OAT and GS (GS moves up 13 px when OAT is shown). Digit sizes are the
    -- old gen_LED SIZEs: OAT digits match the small "F" (real unit).
    local up = 0
    if cfg.show_oat ~= 0 then
        local t = (cfg.temp_unit == 1) and D.oat_c or (D.oat_c * 9 / 5 + 32)
        if st.valid.oat then
            G.pic("OAT_Box", 32.5, 6.5)
            G.led_field("white_lr", tostring(U.round(t)), 3, 42.5, 7, 0.63)
            G.pic(cfg.temp_unit == 1 and "OAT_C" or "OAT_F", 57.5, 6.5)
        else
            G.fail_flag("OAT", 1, 0, 64, 13, 7)   -- AFMS 3-3
        end
        up = 13
    end
    -- no GPS configured at all: no ground speed (Maintenance Manual 8);
    -- configured but lost: red X
    if cfg.show_gs ~= 0 and (cfg.gps_internal ~= 0 or cfg.gps_external ~= 0) then
        if st.valid.gps then
            G.pic("GS_Box", 32.5, 9.5 + up)
            G.led_field("magenta_lr", tostring(U.round(P.gs_value(D.gs))), 3, 39, 10 + up, 0.99)
            if P.gs_unit() == 0 then stacked("k", "t", 58.5, 5 + up, C.magenta) end
        else
            G.fail_flag("GS", 1, up + 1, 64, up + 18, 8)
        end
    end
    -- [!]: flashes until the message list has been viewed (Pilot's Guide 1.6)
    if st.has_msg and (not st.msg_unseen or U.blink(st.clock)) then
        G.pic("Has_message_Icon", 96.5, 21.5)
    end
end

local function boxes_top(D, st, gfc)
    local air = st.valid.air
    -- with failed air data the AIRSPEED / ALTITUDE FAIL panels take the corners
    local tas_shown = cfg.show_tas ~= 0 and air
    -- top-left stack (figure 2-1): battery status, TAS, IAS reference
    local top = 231.5
    if P.battery_shown(st) then
        P.battery_box(st, top)
        top = top - 18
    end
    if P.gpss_shown(D, gfc) then
        P.gpss_box(D, st, top + 1.5)
        top = top - 15
    end
    if gfc and D.alt_mode == 5 and air then
        local dn = tas_shown and -17 or 0
        G.pic("SPD_Bug_Box", 32.5, top - 1 + dn)
        G.led_field("cyan_lr", tostring(U.round(speed_value(D.spd_bug))), 5, 21, top - 0.5 + dn)
    end
    if tas_shown then
        if st.valid.tas then
            G.pic("TAS_Box", 32.5, top)
            if spd_alive then
                G.led_field("white_lr", tostring(U.round(speed_value(D.tas))), 3, 41, top + 1.5, 0.83)
            else
                -- no airspeed: "TAS ___" (Installation Manual figure 6-4)
                for i = -1, 1 do G.rect(41 + i * 8.5 - 3, top - 5.5, 41 + i * 8.5 + 3, top - 4.5, C.white) end
            end
            if cfg.speed_unit == 0 then stacked("k", "t", 58.5, top - 4.5, C.white) end
        else
            G.fail_flag("TAS", 1, top - 8.5, 64, top + 8.5, 8)
        end
    end
    if not air then return end
    -- selected altitude (alerting: flash / yellow, Pilot's Guide 2.1.3.2)
    -- deviation alert: digits and bug yellow (figure 2-10); five-digit values
    -- have no room for the "ft" (figures 2-10, 2-14)
    local alert = st.alt_alert_phase == 3
    G.pic(alert and "ALT_Bug_Box_Alert" or "ALT_Bug_Box", 276.5, 230.5)
    local sel = tostring(U.round(D.alt_bug))
    if #sel >= 5 then G.rect(304, 224, 311, 237, C.black) end
    local blink_off = st.alt_alert_t > 0 and (math.floor(st.alt_alert_t * 2.5) % 2 == 1)
    if not blink_off then
        G.led_field(alert and "yellow_xb" or "cyan_lr", sel, 5, #sel >= 5 and 282 or 278, 231)
    end
    if cfg.show_hdg_box ~= 0 then
        G.pic("HDG_Bug_Box", 99.5, 203.5)
        G.led_field("cyan_lr", fmt_hdg(D.hdg_bug), 5, 99, 204, 0.9)
    end
end

-----------------------------------------------------------------------------
-- GFC 500 annunciator bar (AP/*.png words)
-----------------------------------------------------------------------------

-- Words without artwork in the style of AP/*.png: bold, 10 px cap height,
-- ink 228.5..238.5 (the art is centred on y 233.5), active green 74C14C,
-- armed white.
local ap_green
local function ap_text(str, x, col)
    ap_green = ap_green or G.hex("74C14C")
    G.rstr_c(G.rfont("bold", 10), str, x, 228.5, col or ap_green)
end

local function word(key, x, fallback, col)
    if not G.pic(key, x, 233.5) and fallback then
        ap_text(fallback, x, col)
    end
end

-- Mode decoding (pure: D -> modes), from X-Plane's per-mode status datarefs
-- (0 off / 1 armed / 2 active) with the mode enums as a fallback. Words as
-- annunciated by the G5 (Pilot's Guide tables 3-4 .. 3-9).
function P.afcs_modes(D)
    local m = {}
    local gps = D.hsi_src == 2
    local t = nav_type(D)
    local loc = loc_tuned(D)
    local function navword() return gps and "GPS" or (loc and "LOC" or "VOR") end
    local ground = (D.on_ground or 0) ~= 0

    -- lateral
    if D.toga_lat_status == 2 or D.hdg_mode == 10 then m.lat = ground and "TO" or "GA"
    elseif D.bc_status == 2 then m.lat = "BC"
    elseif D.gpss_status == 2 or D.hdg_mode == 13 then m.lat = "GPS"
    elseif D.nav_status == 2 or D.apr_status == 2 then m.lat = navword()
    elseif D.track_status == 2 or D.hdg_mode == 18 then m.lat = "TRK"
    elseif D.hdg_status == 2 or D.hdg_hold_status == 2 or D.hdg_mode == 1 or D.hdg_mode == 14 then m.lat = "HDG"
    else m.lat = "ROL" end
    if D.bc_status == 1 then m.lat_armed = "BC"
    elseif D.gpss_status == 1 then m.lat_armed = "GPS"
    elseif D.nav_status == 1 or D.apr_status == 1 then m.lat_armed = navword() end
    if m.lat_armed == m.lat then m.lat_armed = nil end

    -- vertical, with its reference
    if D.toga_status == 2 or D.alt_mode == 10 then m.vert = ground and "TO" or "GA"
    elseif D.gs_status == 2 or D.alt_mode == 8 then m.vert = gps and "GP" or "GS"
    elseif D.vnav_status == 2 or D.alt_mode == 9 then m.vert = "VNV"
    elseif D.alt_hold_status == 2 or D.alt_mode == 6 then
        m.vert = "ALT"
        m.ref = tostring(U.round(D.alt_hold / 10) * 10)   -- the held altitude, not the bug
        m.ref_unit = "ft"
    elseif D.vvi_status == 2 or D.alt_mode == 4 then
        m.vert = "VS"
        local v = U.round(D.vs_bug / 10) * 10
        m.ref = ((v < 0) and "-" or "+") .. tostring(math.abs(v))
    elseif D.speed_status == 2 or D.alt_mode == 5 then
        m.vert = "IAS"
        m.ref = tostring(U.round(speed_value(D.spd_bug)))  -- no unit (figure 3-13)
    elseif D.fpa_status == 2 or D.alt_mode == 19 then
        m.vert = "FPA"
        m.ref = string.format("%+.1f", D.fpa)
    else m.vert = "PIT" end
    -- one armed vertical field: approach first, then VNAV, then altitude capture
    if D.gs_status == 1 then m.vert_armed = gps and "GP" or "GS"
    elseif D.altv_armed ~= 0 then m.vert_armed = "ALTV"       -- VNAV target altitude (figure 3-14)
    elseif D.vnav_status == 1 then m.vert_armed = "VNAV"
    elseif D.alt_armed ~= 0 or D.alt_hold_status == 1 then m.vert_armed = "ALTS" end
    -- TO / GA are coupled pitch and roll modes: both fields
    if m.vert == "TO" or m.vert == "GA" then m.lat = m.vert end
    if m.lat == "TO" or m.lat == "GA" then m.vert = m.lat end
    m.ap = D.servos_on ~= 0
    m.yd = D.yd_on ~= 0
    return m
end

-- field centres measured on the real unit (figures 2-1, 3-4): lateral armed /
-- active, AP, YD, vertical active, its reference, vertical armed
local X_LAT_ARMED, X_LAT, X_AP, X_YD, X_VERT, X_REF, X_ARMED = 29, 73, 118.5, 144.5, 190, 240, 289
local ART_G = { ROL = "AP/ROL_G", HDG = "AP/HDG_G", TRK = "AP/TRK_G", GPS = "AP/GPS_G", LOC = "AP/LOC_G",
    PIT = "AP/PIT_G", ALT = "AP/ALT_G", VS = "AP/VS_G", IAS = "AP/IAS_G", GS = "AP/GS_G", GP = "AP/GP_G",
    AP = "AP/AP_G", YD = "AP/YD_G" }
local ART_W = { GPS = "AP/GPS", ALTS = "AP/ALTS", VNAV = "AP/VNAV" }

local afcs_col
local function afcs_colors()
    if afcs_col then return afcs_col end
    afcs_col = {
        green = G.hex("74C14C"), dark = G.hex("101010"), red = G.hex("E01010"),
        yellow = G.hex("F0E000"), white = C.white, black = C.black,
    }
    return afcs_col
end

-- one annunciation word. style: "active" (green), "armed" (white),
-- "reverse" (green box, dark text: automatic transition), "caution" (yellow
-- text: mode lost), "box" (fg on a bg box: AFCS / AP / PFT / PTRIM)
local function afcs_word(w, x, style, fg, bg)
    local c = afcs_colors()
    local half = #w * 3.6 + 3
    if style == "active" then
        if not (ART_G[w] and G.pic(ART_G[w], x, 233.5)) then ap_text(w, x, c.green) end
    elseif style == "armed" then
        if not (ART_W[w] and G.pic(ART_W[w], x, 233.5)) then ap_text(w, x, c.white) end
    elseif style == "reverse" then
        G.rect(x - half, 227, x + half, 240, c.green)
        ap_text(w, x, c.dark)
    elseif style == "caution" then
        ap_text(w, x, c.yellow)
    elseif style == "box" then
        G.rect(x - half, 227, x + half, 240, bg)
        ap_text(w, x, fg)
    end
end

-- transition / reversion flashes and the disconnect alert (Pilot's Guide
-- 3.3.2.2, 3.3.3.2): timers on the unit's clock (simulator time)
local fl = { lat = nil, lat_armed = nil, vert = nil, vert_armed = nil, ap = false,
    lat_until = 0, lat_style = nil, vert_until = 0, vert_style = nil, disc_until = 0, disc_abnormal = false }
local NAV_LAT = { GPS = true, VOR = true, LOC = true, BC = true }
local NAV_VERT = { GS = true, GP = true, VNV = true }

local function track_flashes(m, D, st)
    local now = st.clock or 0
    -- the unit was not on the PFD page (other page, off, configuration
    -- mode) or the clock restarted (new flight): start from the current
    -- modes, no alerts. (Not time based: a long frame, e.g. a screenshot,
    -- must not cancel a running alert.)
    if fl.seen == nil or now < fl.seen or fl.reseed then
        fl.reseed = false
        fl.lat, fl.vert, fl.ap = nil, nil, m.ap
        fl.lat_until, fl.vert_until, fl.disc_until = 0, 0, 0
    end
    fl.seen = now
    if fl.lat ~= nil and m.lat ~= fl.lat then
        if m.lat == fl.lat_armed then
            fl.lat_until, fl.lat_style = now + 10, "reverse"
        elseif m.lat == "ROL" and NAV_LAT[fl.lat] and D.hsi_show_h == 0 then
            fl.lat_until, fl.lat_style = now + 10, "caution"
        else
            fl.lat_until = 0
        end
    end
    if fl.vert ~= nil and m.vert ~= fl.vert then
        if m.vert == fl.vert_armed or (m.vert == "ALT" and fl.vert_armed == "ALTS")
            or (m.vert == "VNV" and fl.vert_armed == "VNAV") then
            fl.vert_until, fl.vert_style = now + 10, "reverse"
        elseif m.vert == "PIT" and NAV_VERT[fl.vert] and D.hsi_show_v == 0 then
            fl.vert_until, fl.vert_style = now + 10, "caution"
        else
            fl.vert_until = 0
        end
    end
    if fl.ap and not m.ap then
        -- autopilot off: normal (pilot) or abnormal (failure / no power)
        fl.disc_abnormal = D.otto_fail_warn ~= 0 or D.otto_failed or D.servos_failed or D.ap_has_power == 0
        fl.disc_until = now + (fl.disc_abnormal and 10 or 5)
    elseif m.ap then
        fl.disc_until = 0
    end
    fl.lat, fl.lat_armed, fl.vert, fl.vert_armed, fl.ap = m.lat, m.lat_armed, m.vert, m.vert_armed, m.ap
end

P.fl = fl   -- flash state (tests)

-- autopilot disconnect alert: 0 none, 1 normal (yellow), 2 abnormal (red)
function P.disc_alert(st)
    if (st.clock or 0) >= fl.disc_until then return 0 end
    return fl.disc_abnormal and 2 or 1
end

function P.track_afcs(D, st)
    track_flashes(P.afcs_modes(D), D, st)
end

local function flashing(until_t, st)
    local now = st.clock or 0
    return now < until_t, U.blink(now, 1)
end

local function ap_bar(D, st, gfc, show_modes, m)
    G.pic("AP/AP_Bar", 159.5, 233.5)
    local c = afcs_colors()

    if show_modes then
        if m.lat_armed then afcs_word(m.lat_armed, X_LAT_ARMED, "armed") end
        local on, phase = flashing(fl.lat_until, st)
        if on and fl.lat_style == "reverse" then
            afcs_word(m.lat, X_LAT, phase and "reverse" or "active")
        elseif on and fl.lat_style == "caution" then
            if phase then afcs_word(m.lat, X_LAT, "caution") end
        else
            afcs_word(m.lat, X_LAT, "active")
        end
        on, phase = flashing(fl.vert_until, st)
        if on and fl.vert_style == "reverse" then
            afcs_word(m.vert, X_VERT, phase and "reverse" or "active")
        elseif on and fl.vert_style == "caution" then
            if phase then afcs_word(m.vert, X_VERT, "caution") end
        else
            afcs_word(m.vert, X_VERT, "active")
        end
        if m.ref then
            local fs = G.rfont("bold", 10)
            G.rstr_c(fs, m.ref, X_REF, 228.5, c.green)
            if m.ref_unit then stacked("f", "t", X_REF + #m.ref * 3.8 + 4, 228.5, c.green, 4) end
        end
        -- the armed word takes the reference's place when there is none
        -- ("PIT ALTS", figure 3-9) and the far field otherwise ("VS +500 ALTS")
        if m.vert_armed then afcs_word(m.vert_armed, m.ref and X_ARMED or X_REF, "armed") end
    end

    -- AP field (Pilot's Guide table 3-12): failures, preflight test, disconnect, engaged
    local up = st.up_t or 99
    if D.otto_failed then
        afcs_word("AFCS", X_AP, "box", c.white, c.red)
    elseif D.servos_failed then
        afcs_word("AP", X_AP, "caution")
        G.line(X_AP - 9, 228, X_AP + 9, 239, c.red, 2)
        G.line(X_AP - 9, 239, X_AP + 9, 228, c.red, 2)
    elseif gfc and up < cfg.afcs_pft_s then
        afcs_word("PFT", X_AP, "box", c.black, c.white)
    else
        local on, phase = flashing(fl.disc_until, st)
        if on then
            if phase then
                if fl.disc_abnormal then
                    afcs_word("AP", X_AP, "box", c.red, c.black)
                else
                    afcs_word("AP", X_AP, "box", c.black, c.yellow)
                end
            end
        elseif m.ap then
            afcs_word("AP", X_AP, "active")
        end
    end
    if D.trim_fail ~= 0 then
        afcs_word("PTRIM", X_YD + 9, "box", c.white, c.red)
    elseif m.yd then
        afcs_word("YD", X_YD, "active")
    end
end

-- TRIM UP / TRIM DOWN (Pilot's Guide 3.4.1, figures 3-21 / 3-22): black on
-- yellow, centred below the aircraft symbol
local function trim_alert(D)
    if D.trim_up == 0 and D.trim_down == 0 then return end
    local c = afcs_colors()
    G.rect(109, 62, 209, 79, c.yellow)
    G.rstr_c(G.rfont("bold", 10), (D.trim_up ~= 0) and "TRIM UP" or "TRIM DOWN", 159, 65.5, c.black)
end

-----------------------------------------------------------------------------

function P.draw(D, st, gfc)
    -- everything above the bottom row moves down 14 px once the flight
    -- director is on, and the AFCS status box shows the FD modes; the AP
    -- field only fills when the autopilot is engaged (Pilot's Guide 3.2.6)
    -- With a GFC 500 the status box stays as an empty bar when AP and FD are
    -- off (figure 3-25, AFMS 7-1); with another autopilot it shows while the
    -- flight director is on. No FD modes without a valid attitude (3.3.3.2).
    local fd_on = D.ap_mode > 0 and st.valid.att
    -- mode changes are tracked in P.update (sim time, every frame on the PFD
    -- page), so a disconnect that also turns the flight director off still
    -- gets its AP alert: the bar stays up for it
    local modes = P.afcs_modes(D)
    local alert = (st.clock or 0) < fl.disc_until
    local disp = cfg.show_ap_bar ~= 0 and (fd_on or alert or (gfc and cfg.ap_bar_reserved ~= 0))
    yoff = disp and -14 or 0

    local air = st.valid.air
    G.push()
    G.translate(0, yoff)
    attitude(D, st)
    if air then vsi(D) end
    heading_tape(D, st)
    if air then
        speed_tape(D, st, gfc)
        altitude_tape(D, st)
        readouts(D, st)
    else
        air_fail()
    end
    vdi(D)
    boxes_top(D, st, gfc)
    if st.valid.att then trim_alert(D) end
    G.pop()
    yoff = 0

    -- rate of turn and slip come from the AHRS (AFMS: not available with
    -- an attitude failure)
    if st.valid.att then slip_turn(D) end
    cdi_pfd(D)
    boxes_bottom(D, st)
    if disp then ap_bar(D, st, gfc, fd_on, modes) end
end

return P
