-- g5_gfx.lua: thin vector layer over XPLMPanelGraphics.
--
-- All callers work in G5 design units: 320 x 240, origin bottom-left, y up
-- (the physical G5 is a 320x240 QVGA panel). The device framebuffer is S times
-- larger; every coordinate, line width and font size is multiplied by S here,
-- so text is rasterised at full device resolution instead of being upscaled.
-- Transforms (rotate/translate) are issued in device pixels for the same reason.
-- Scissor rectangles are only ever set at identity transform.

local G = {}

G.W = 320
G.H = 240
G.S = 1

local S = 1

function G.set_scale(s)
    S = s
    G.S = s
end

-----------------------------------------------------------------------------
-- Colours (packed once at start; XPLMMakeColor is a C call)
-----------------------------------------------------------------------------

G.C = {}

local function hex(h, a)
    local r = tonumber(string.sub(h, 1, 2), 16) / 255
    local g = tonumber(string.sub(h, 3, 4), 16) / 255
    local b = tonumber(string.sub(h, 5, 6), 16) / 255
    return XPLMMakeColor(r, g, b, a or 1)
end
G.hex = hex

function G.rgba(r, g, b, a)
    return XPLMMakeColor(r, g, b, a or 1)
end

-- Palette sampled from the 2024-2025 G5 PNG artwork (cockpit_3d/generic/G5).
function G.init_colors()
    local C = G.C
    C.black      = hex("000000")
    C.white      = hex("FFFFFF")
    C.offwhite   = hex("E8E8E8")
    C.grey       = hex("B0B0B0")
    C.dkgrey     = hex("2F2F2F")
    C.tile       = hex("1C1C1C")
    C.tile_hi    = hex("3A3A3A")
    C.shade      = hex("000000", 0.35)   -- tape backgrounds (Shades_Main alpha 89)
    C.shade_hdg  = hex("000000", 0.45)
    C.cyan       = hex("40D8F0")
    C.cyan_box   = hex("7FC8D8")
    C.magenta    = hex("D040D0")
    C.magenta_dk = hex("B040B0")
    C.green      = hex("70C040")
    C.green_nav  = hex("30E030")
    C.yellow     = hex("F0E000")
    C.yellow_dk  = hex("7A7000")
    C.red        = hex("F01000")
    C.amber      = hex("F0A000")
    C.sky_top    = hex("1C44C0")
    C.sky_hor    = hex("3A6AE8")
    C.gnd_hor    = hex("9A6624")
    C.gnd_bot    = hex("6E4614")
    C.sky        = hex("2050D0")
    C.ground     = hex("906020")
    C.blue_logo  = hex("1A7AD0")
    C.fade = {}
    for i = 0, 20 do C.fade[i] = XPLMMakeColor(0, 0, 0, i / 20) end
end

-- alpha-scaled black, cached in 1/20 steps
function G.black_alpha(a)
    local i = math.floor(a * 20 + 0.5)
    if i < 0 then i = 0 elseif i > 20 then i = 20 end
    return G.C.fade[i]
end

-----------------------------------------------------------------------------
-- Fonts (TTF placeholders, see README "Fonts")
-----------------------------------------------------------------------------

G.font = nil      -- bold, numbers and labels
G.font_cond = nil -- condensed, small labels

local JL, JC, JR
function G.init_fonts(bold_path, cond_path)
    JL = XPLMJustification_t.xplm_JustLeft
    JC = XPLMJustification_t.xplm_JustCenter
    JR = XPLMJustification_t.xplm_JustRight
    G.JL, G.JC, G.JR = JL, JC, JR
    G.font = XPLMCreateFont(XPLMCharSet_t.xplm_CharSetUnicode)
    XPLMFontAddFace(G.font, bold_path)
    G.font_cond = XPLMCreateFont(XPLMCharSet_t.xplm_CharSetUnicode)
    XPLMFontAddFace(G.font_cond, cond_path)
    XPLMFontAddFace(G.font_cond, bold_path)
end

function G.destroy_fonts()
    if G.font then XPLMDestroyFont(G.font) G.font = nil end
    if G.font_cond then XPLMDestroyFont(G.font_cond) G.font_cond = nil end
end

-- Cap height ratio used to centre text vertically (Roboto ~0.71). `size` is
-- a TTF em size; the raster fonts are picked by cap height = size * CAP.
local CAP = 0.71

-----------------------------------------------------------------------------
-- Raster fonts (g5_rfont_data.lua, baked by tools/make_raster_fonts.py):
-- GM SansSerif pre-rasterised per pixel size on the 320x240 screen grid.
-- A size is the cap ("H") height in screen px. Glyph cells are drawn 1:1 at
-- whole screen pixels, so text is exactly as coarse as the LCD at every size.
-- G.text* use them (bold = G.font, regular = G.font_cond) and fall back to
-- the TTF placeholders only when the data is missing.
-----------------------------------------------------------------------------

G.rf = nil        -- face -> size -> {base, cw, ch, ox, oy, g, size}
local rf_sizes = {} -- face -> sorted sizes
local rf_warned = {}

local function rf_pick(face, px)
    local sizes = rf_sizes[face]
    if sizes == nil then return nil end
    local want = math.floor(px + 0.5)
    local best, bd = nil, math.huge
    for _, sz in ipairs(sizes) do
        local d = math.abs(sz - want)
        if d < bd then best, bd = sz, d end
    end
    if bd > 0 and not rf_warned[face .. want] then
        rf_warned[face .. want] = true
        print(string.format("[G5 XLua2] raster font %s %d px not baked, using %d px", face, want, best))
    end
    return G.rf[face][best]
end
G.rf_pick = rf_pick

-- UTF-8 -> codepoints (1-3 byte sequences are enough for the font)
local cps = {}
local function codepoints(str)
    local n, i, len = 0, 1, #str
    while i <= len do
        local c = string.byte(str, i)
        if c >= 0xE0 and i + 2 <= len then
            c = (c - 0xE0) * 4096 + (string.byte(str, i + 1) - 0x80) * 64 + (string.byte(str, i + 2) - 0x80)
            i = i + 3
        elseif c >= 0xC0 and i + 1 <= len then
            c = (c - 0xC0) * 64 + (string.byte(str, i + 1) - 0x80)
            i = i + 2
        else
            i = i + 1
        end
        n = n + 1
        cps[n] = c
    end
    return n
end

-- one glyph with its origin at screen pixel column px (snapped), baseline row base
local function rf_glyph(fs, gl, px, base, col)
    local l = (math.floor(px + 0.5) - fs.ox) * S
    local b = (base - fs.oy) * S
    XPLMTextureAtlasDrawIn(G.atlas, fs.base + gl[1], col, l, b + fs.ch * S, l + fs.cw * S, b)
end
G.rf_glyph = rf_glyph

local function rf_width(fs, n)
    local w = 0
    for k = 1, n do
        local gl = fs.g[cps[k]]
        if gl then w = w + gl[2] end
    end
    return w
end

-- raster text, y = baseline (bottom of the capitals), whole screen pixels
local function rf_text(fs, str, x, y, col, just)
    local n = codepoints(str)
    local pen = x
    if just == JC then pen = x - rf_width(fs, n) / 2
    elseif just == JR then pen = x - rf_width(fs, n) end
    local base = math.floor(y + 0.5)
    for k = 1, n do
        local gl = fs.g[cps[k]]
        if gl then
            rf_glyph(fs, gl, pen, base, col)
            pen = pen + gl[2]
        end
    end
end

-- raster face at a pixel size, for direct drawing (nil without raster fonts)
function G.rfont(face, px)
    return G.rf and rf_pick(face, px)
end

-- string in a raster face, y = baseline
function G.rstr(fs, str, x, y, col, just)
    rf_text(fs, str, x, y, col, just or JL)
end

-- string with its ink (first glyph's left edge .. last glyph's right edge)
-- centred on cx, y = baseline; replaces centred label images
function G.rstr_c(fs, str, cx, y, col)
    local n = codepoints(str)
    local first, last
    for k = 1, n do
        if fs.g[cps[k]] then
            first = first or fs.g[cps[k]]
            last = fs.g[cps[k]]
        end
    end
    if first == nil then return end
    local w = rf_width(fs, n) - last[2] + last[4] - first[3]
    rf_text(fs, str, cx - w / 2 - first[3], y, col, JL)
end

-- one character with its ink centred on cx, y = baseline
function G.glyph_c(fs, ch, cx, y, col)
    local gl = fs.g[string.byte(ch)]
    if gl then rf_glyph(fs, gl, cx - (gl[4] - gl[3]) / 2 - gl[3], math.floor(y + 0.5), col) end
end

-- rolling digit drum (replaces the old 0..9 strip images): digit d has its
-- baseline at base0 + (d - v) * pitch, so higher digits sit above and the
-- drum moves down as v grows; v wraps every 10. blank0: 0 is not drawn
-- (leading digit). Clip to the digit window before calling.
local DIGIT = { [0] = "0", "1", "2", "3", "4", "5", "6", "7", "8", "9" }
function G.roll(fs, cx, base0, v, pitch, col, blank0)
    local k0 = math.floor(v)
    for k = k0 - 2, k0 + 2 do
        local d = k % 10
        if not (blank0 and d == 0) then
            G.glyph_c(fs, DIGIT[d], cx, base0 + (k - v) * pitch, col)
        end
    end
end

local function face_of(font)
    return (font ~= nil and font == G.font_cond) and "regular" or "bold"
end

-- y = baseline
function G.text(str, x, y, size, col, just, font)
    local fs = G.rf and rf_pick(face_of(font), size * CAP)
    if fs then return rf_text(fs, str, x, y, col, just or JL) end
    XPLMFontDrawString(font or G.font, col, size * S, x * S, y * S, str, just or JL)
end

-- y = vertical centre of the capitals
function G.textc(str, x, y, size, col, just, font)
    local fs = G.rf and rf_pick(face_of(font), size * CAP)
    if fs then return rf_text(fs, str, x, y - fs.size / 2, col, just or JC) end
    XPLMFontDrawString(font or G.font, col, size * S, x * S, (y - size * CAP * 0.5) * S, str, just or JC)
end

-- rotated about the anchor (x, y) on the baseline, degrees counter-clockwise
function G.text_rot(str, x, y, size, col, angle, just, font)
    local fs = G.rf and rf_pick(face_of(font), size * CAP)
    if fs == nil then
        XPLMFontDrawStringRotated(font or G.font, col, size * S, x * S, y * S, str, angle, just or JC)
        return
    end
    just = just or JC
    local n = codepoints(str)
    local pen = 0
    if just == JC then pen = -rf_width(fs, n) / 2
    elseif just == JR then pen = -rf_width(fs, n) end
    local a = math.rad(angle)
    local ca, sa = math.cos(a), math.sin(a)
    for k = 1, n do
        local gl = fs.g[cps[k]]
        if gl then
            -- glyph origin rotated about the anchor; pivot = origin inside the cell
            XPLMTextureAtlasDrawScaled(G.atlas, fs.base + gl[1], col, (x + pen * ca) * S, (y + pen * sa) * S,
                fs.ox, fs.oy, S, S, -angle)
            pen = pen + gl[2]
        end
    end
end

function G.text_w(str, size, font)
    local fs = G.rf and rf_pick(face_of(font), size * CAP)
    if fs then return rf_width(fs, codepoints(str)) end
    return XPLMFontMeasureString(font or G.font, size * S, str) / S
end

-----------------------------------------------------------------------------
-- Primitives. Point lists are flat {x1, y1, x2, y2, ...} in design units.
-----------------------------------------------------------------------------

local vbuf = {}
local function verts(flat)
    local n = #flat / 2
    for i = 1, n do
        local v = vbuf[i]
        if v == nil then
            v = {}
            vbuf[i] = v
        end
        v.x = flat[2 * i - 1] * S
        v.y = flat[2 * i] * S
    end
    for i = n + 1, #vbuf do vbuf[i] = nil end
    return vbuf, n
end

function G.rect(x0, y0, x1, y1, col)
    local v = vbuf
    for i = 5, #v do v[i] = nil end
    for i = 1, 4 do if v[i] == nil then v[i] = {} end end
    v[1].x, v[1].y = x0 * S, y0 * S
    v[2].x, v[2].y = x0 * S, y1 * S
    v[3].x, v[3].y = x1 * S, y1 * S
    v[4].x, v[4].y = x1 * S, y0 * S
    XPLMPolygon(col, v, 4)
end

function G.box(x0, y0, x1, y1, col, w)
    local v, n = verts({ x0, y0, x0, y1, x1, y1, x1, y0 })
    XPLMLineLoopWithWidth(col, (w or 1) * S, v, n)
end

-- filled box with an outline
function G.panel(x0, y0, x1, y1, fill, edge, w)
    G.rect(x0, y0, x1, y1, fill)
    if edge then G.box(x0, y0, x1, y1, edge, w or 1) end
end

-- convex polygon only
function G.poly(col, flat)
    local v, n = verts(flat)
    XPLMPolygon(col, v, n)
end

-- {x, y, color, x, y, color, ...}
local cbuf = {}
function G.polyc(list)
    local n = #list / 3
    for i = 1, n do
        local v = cbuf[i]
        if v == nil then
            v = {}
            cbuf[i] = v
        end
        v.x = list[3 * i - 2] * S
        v.y = list[3 * i - 1] * S
        v.color = list[3 * i]
    end
    for i = n + 1, #cbuf do cbuf[i] = nil end
    XPLMPolygonc(cbuf, n)
end

function G.line(x0, y0, x1, y1, col, w)
    local v, n = verts({ x0, y0, x1, y1 })
    XPLMLinesWithWidth(col, (w or 1) * S, v, n)
end

-- disconnected segments
function G.lines(col, w, flat)
    local v, n = verts(flat)
    XPLMLinesWithWidth(col, (w or 1) * S, v, n)
end

function G.strip(col, w, flat)
    local v, n = verts(flat)
    XPLMLineStripWithWidth(col, (w or 1) * S, v, n)
end

function G.loop(col, w, flat)
    local v, n = verts(flat)
    XPLMLineLoopWithWidth(col, (w or 1) * S, v, n)
end

function G.dashed(x0, y0, x1, y1, col, dash, w)
    local v, n = verts({ x0, y0, x1, y1 })
    XPLMLinesStipple(col, v, n, (dash or 4) * S, (w or 1) * S)
end

local function circle_pts(cx, cy, r, seg, a0, a1)
    local t = {}
    seg = seg or 48
    a0 = a0 or 0
    a1 = a1 or (2 * math.pi)
    for i = 0, seg do
        local a = a0 + (a1 - a0) * i / seg
        t[#t + 1] = cx + r * math.cos(a)
        t[#t + 1] = cy + r * math.sin(a)
    end
    return t
end

function G.circle(cx, cy, r, col, w, seg)
    local t = circle_pts(cx, cy, r, seg or 48)
    t[#t] = nil
    t[#t] = nil
    G.loop(col, w or 1, t)
end

function G.disc(cx, cy, r, col, seg)
    local t = circle_pts(cx, cy, r, seg or 24)
    t[#t] = nil
    t[#t] = nil
    G.poly(col, t)
end

-- arc in compass degrees (0 = up, clockwise positive)
function G.arc(cx, cy, r, deg0, deg1, col, w, seg)
    local a0 = math.rad(90 - deg0)
    local a1 = math.rad(90 - deg1)
    G.strip(col, w or 1, circle_pts(cx, cy, r, seg or 24, a0, a1))
end

-- point at radius r, compass bearing deg (0 = up, clockwise)
function G.polar(cx, cy, r, deg)
    local a = math.rad(deg)
    return cx + r * math.sin(a), cy + r * math.cos(a)
end

-----------------------------------------------------------------------------
-- Failure annunciations (Pilot's Guide figures 1-2 .. 1-10): red X corner to
-- corner, yellow labels
-----------------------------------------------------------------------------

function G.red_x(x0, y0, x1, y1, w)
    G.line(x0, y0, x1, y1, G.C.red, w or 3)
    G.line(x0, y1, x1, y0, G.C.red, w or 3)
end

-- letters stacked top to bottom, centred on cx, centred vertically on cy
function G.vtext(fs, str, cx, cy, pitch, col)
    local n = #str
    local top = cy + (n - 1) * pitch / 2
    for i = 1, n do
        G.rstr_c(fs, str:sub(i, i), cx, top - (i - 1) * pitch - fs.size / 2, col)
    end
end

-- small black box with a yellow label and a red X (HDG, GS, OAT, TAS fields)
function G.fail_flag(label, x0, y0, x1, y1, px, fill)
    G.rect(x0, y0, x1, y1, fill or G.C.black)
    G.rstr_c(G.rfont("bold", px or 8), label, (x0 + x1) / 2, (y0 + y1) / 2 - (px or 8) / 2, G.C.yellow)
    G.red_x(x0 + 1, y0 + 1, x1 - 1, y1 - 1, 2)
end

-----------------------------------------------------------------------------
-- Transforms / clipping
-----------------------------------------------------------------------------

-- The current translation (device px) is tracked here because X-Plane applies
-- the transform to scissor rectangles too (verified in the sim 2026-10-08):
-- G.clip takes local coordinates, and the tracked offset is only used to
-- intersect nested clips. Clips are never set inside a rotation.
local tstack, tx, ty = {}, 0, 0
function G.push()
    tstack[#tstack + 1] = { tx, ty }
    XPLMTransformPush()
end
function G.pop()
    local t = tstack[#tstack]
    if t then tx, ty = t[1], t[2] tstack[#tstack] = nil end
    XPLMTransformPop()
end

function G.translate(dx, dy)
    tx, ty = tx + dx * S, ty + dy * S
    XPLMTransformTranslate(dx * S, dy * S)
end

-- angle in degrees, positive counter-clockwise (XPLM convention)
function G.rotate(cx, cy, deg)
    XPLMTransformRotate(cx * S, cy * S, deg)
end

-- XLua 2 runtime >= 2026-08-25 (12.4.4 b2+): XPLMScissorSet(left, top, right, bottom).
-- The July 2026 pnl builds used (top, left, bottom, right) and need the older core.
-- XPLMScissorSet replaces the scissor, so nested clips are intersected here
-- (in device px, using the tracked translation) and passed back in local px.
G.ox, G.oy = 0, 0
function G.set_origin(ox, oy)
    G.ox, G.oy = ox, oy
end

local clip_stack = {}
function G.clip(x0, y0, x1, y1)
    local l, b, r, t = x0 * S + tx, y0 * S + ty, x1 * S + tx, y1 * S + ty
    local top = clip_stack[#clip_stack]
    if top then
        l, b = math.max(l, top[1]), math.max(b, top[2])
        r, t = math.min(r, top[3]), math.min(t, top[4])
        if r < l then r = l end
        if t < b then t = b end
    end
    clip_stack[#clip_stack + 1] = { l, b, r, t }
    XPLMScissorPush()
    XPLMScissorSet(math.floor(l - tx), math.floor(t - ty), math.floor(r - tx), math.floor(b - ty))
end

function G.unclip()
    clip_stack[#clip_stack] = nil
    XPLMScissorPop()
end

-- after a draw error: pop what the failed frame left on the XPLM stacks
function G.unwind()
    for i = #clip_stack, 1, -1 do
        clip_stack[i] = nil
        XPLMScissorPop()
    end
    for i = #tstack, 1, -1 do
        tstack[i] = nil
        XPLMTransformPop()
    end
    tx, ty = 0, 0
end

-- after a draw error the stacks may be unbalanced; start every frame clean
function G.reset_clip()
    for i = #clip_stack, 1, -1 do clip_stack[i] = nil end
    for i = #tstack, 1, -1 do tstack[i] = nil end
    tx, ty = 0, 0
end

-----------------------------------------------------------------------------
-- Images (texture atlas). All artwork is drawn 1:1 (true-to-pixel) at its
-- native size; positions are image centres in screen pixels.
-----------------------------------------------------------------------------

G.atlas = nil
G.img = {}      -- key -> atlas index (first cell for sheets)
G.size = {}     -- key -> {w, h} of one cell
G.sheet = {}    -- key -> cells_x
G.fonts = {}    -- name -> {base, w, h}  (display cell size)

function G.load_images(asset_rel_dir, assets, log)
    G.atlas = XPLMCreateTextureAtlas()
    local function add(key, rel, cx, cy)
        local path = asset_rel_dir .. "/Textures/" .. rel .. ".png"
        local ok, idx
        if cx then
            ok, idx = pcall(XPLMTextureAtlasAddImageFileSet, G.atlas, path, cx, cy)
        else
            ok, idx = pcall(XPLMTextureAtlasAddImageFile, G.atlas, path)
        end
        if ok and idx ~= nil and idx >= 0 then
            return idx
        end
        log("image failed to load: " .. path)
        return nil
    end
    for _, key in ipairs(assets.IMAGES) do
        local sh = assets.SHEETS[key]
        local idx = add(key, key, sh and sh[1], sh and sh[2])
        if idx then
            G.img[key] = idx
            if sh then G.sheet[key] = sh[1] end
        end
    end
    -- raster fonts: one cell set per face and pixel size
    local rf = {}
    if assets.RFONT then
        for face, sizes in pairs(assets.RFONT.faces) do
            rf[face] = {}
            rf_sizes[face] = {}
            for size, d in pairs(sizes) do
                local idx = add("rfont:" .. d.file, d.file, d.cols, d.rows)
                if idx then
                    rf[face][size] = { base = idx, cw = d.cw, ch = d.ch, ox = d.ox, oy = d.oy, g = d.g, size = size }
                    table.insert(rf_sizes[face], size)
                end
            end
            table.sort(rf_sizes[face])
            if #rf_sizes[face] == 0 then rf[face], rf_sizes[face] = nil, nil end
        end
        if next(rf) then G.rf = rf end
    end
    XPLMTextureAtlasBake(G.atlas)
    for key, idx in pairs(G.img) do
        G.size[key] = { XPLMTextureAtlasGetImageWidth(G.atlas, idx), XPLMTextureAtlasGetImageHeight(G.atlas, idx) }
    end
    for name, f in pairs(assets.FONTS) do
        G.fonts[name] = { face = f.face, scale = f.scale, w = f.cell[1], h = f.cell[2], ink = f.ink,
            col = hex(f.color) }
    end
end

function G.destroy_images()
    if G.atlas then XPLMDestroyTextureAtlas(G.atlas) end
    G.atlas = nil
    G.img, G.size, G.sheet, G.fonts = {}, {}, {}, {}
    G.rf, rf_sizes = nil, {}
end

function G.image_size(key)
    local s = G.size[key]
    if s == nil then return 0, 0 end
    return s[1], s[2]
end

local WHITE
local function white()
    if WHITE == nil then WHITE = XPLMMakeColor(1, 1, 1, 1) end
    return WHITE
end

-- untinted image at alpha a (image tint), cached in 1/20 steps
local WHITE_A = {}
function G.white_alpha(a)
    local i = math.floor(a * 20 + 0.5)
    if i < 0 then i = 0 elseif i > 20 then i = 20 end
    if WHITE_A[i] == nil then WHITE_A[i] = XPLMMakeColor(1, 1, 1, i / 20) end
    return WHITE_A[i]
end

-- stretched into a box (x0,y0 bottom-left .. x1,y1 top-right)
function G.image(key, x0, y0, x1, y1, tint, frame)
    local i = G.img[key]
    if i == nil then return false end
    XPLMTextureAtlasDrawIn(G.atlas, i + (frame or 0), tint or white(), x0 * S, y1 * S, x1 * S, y0 * S)
    return true
end

-- native size, centred on (cx, cy)
function G.image_c(key, cx, cy, tint, frame)
    local s = G.size[key]
    if s == nil then return false end
    local w, h = s[1] / 2, s[2] / 2
    return G.image(key, cx - w, cy - h, cx + w, cy + h, tint, frame)
end
G.pic = G.image_c

-- native size, rotated clockwise by deg about its centre placed at (cx, cy)
function G.pic_rot(key, cx, cy, deg_cw, tint, frame)
    local i = G.img[key]
    if i == nil then return false end
    local s = G.size[key]
    XPLMTextureAtlasDrawScaled(G.atlas, i + (frame or 0), tint or white(), cx * S, cy * S, s[1] / 2, s[2] / 2, S, S, deg_cw)
    return true
end

-- LED string from a digit font, centred on (cx, cy) like Plane Maker's gen_LED.
-- size = gen_LED SIZE (scale of the old atlas cell px; nil = the font's default):
-- a digit slot is cell w x size wide, the digits are size x ink px tall and come
-- from the raster font of that pixel height. Every glyph is centred in its
-- slot. ' ' = blank slot, '.' = period: it advances period_w px (default: half
-- a slot) and its dot is centred in that gap.
function G.led(font, str, cx, cy, size, period_w)
    local f = G.fonts[font]
    if f == nil or G.rf == nil then return end
    local s = size or f.scale
    local fs = rf_pick(f.face, f.ink * s)
    if fs == nil then return end
    local cw = f.w * s
    period_w = period_w or cw * 0.5
    local n = 0
    for k = 1, #str do
        n = n + ((string.sub(str, k, k) == ".") and period_w or cw)
    end
    local x = cx - n / 2
    local base = math.floor(cy - fs.size / 2 + 0.5)
    for k = 1, #str do
        local b = string.byte(str, k)
        local adv = (b == 46) and period_w or cw
        local gl = (b ~= 32) and fs.g[b]
        if gl then
            rf_glyph(fs, gl, x + (adv - (gl[4] - gl[3])) / 2 - gl[3], base, f.col)
        end
        x = x + adv
    end
end

-- right-aligned LED of `digits` cells (Plane Maker gen_LED with leading blanks)
function G.led_field(font, value_str, digits, cx, cy, size, period_w)
    local pad = digits - #value_str:gsub("%.", "")
    if pad > 0 then value_str = string.rep(" ", pad) .. value_str end
    G.led(font, value_str, cx, cy, size, period_w)
end

-- width of an LED string (same layout as G.led)
function G.led_w(font, str, size, period_w)
    local f = G.fonts[font]
    if f == nil then return 0 end
    local cw = f.w * (size or f.scale)
    period_w = period_w or cw * 0.5
    local n = 0
    for k = 1, #str do
        n = n + ((string.sub(str, k, k) == ".") and period_w or cw)
    end
    return n
end

return G
