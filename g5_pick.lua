--[[
G5 plugin-side click picking ("compatibility mode").

X-Plane only picks OBJ manipulators from the aircraft's ONE cockpit object
(OBJ8 spec: "Only triangles in the cockpit object can be in the manipulation
plane"). G5.obj is attached as an ordinary object so that any aircraft can
take it without giving up its own cockpit object; its manipulators are
therefore ignored by X-Plane, and this module emulates them:

  * G5.obj is read at start-up: every ATTR_manip_* batch (type, cursor,
    commands, triangles with the static part of their animation).
  * The .acf is read for the slot(s) that attach G5.obj: offset, rotation,
    hide dataref. Plugin picking switches itself off for a slot that X-Plane
    can already pick natively (the slot IS the cockpit object, or the host
    cockpit object already carries the G5 click regions), so nothing ever
    fires twice.
  * Every frame the manipulator groups (knob, power button) are projected with
    the 3D-cockpit camera; one small, invisible, undecorated window is laid
    tightly over each group. Nothing of the host aircraft outside those
    rectangles is ever covered.
  * Inside a window, the mouse ray is intersected with the manipulator
    triangles: a hit fires the command (Begin on mouse down, End on mouse up,
    like X-Plane's own manipulators) and sets the cursor. Mouse wheel turns
    the knob.

Limits: 3D cockpit view only (no VR controllers, no external views); host
geometry in front of the G5 does not block it; only ANIM_trans offsets are
applied (rotations are ignored, fine for round knobs).
--]]

local P = {}

local U, log, config
local FT = 0.3048

local slots = {}        -- attached G5.obj instances: base offset (m, CG frame), rotation, hide dataref
local groups = {}       -- manipulator groups: { batches = {...}, verts = {...}, win = window }
local active = nil      -- { cmd = ref } command held by the current click
local dr = {}
local enabled = false
local status = "off"

-----------------------------------------------------------------------------
-- small vector helpers (tables {x, y, z})
-----------------------------------------------------------------------------

local sin, cos, rad, tan = math.sin, math.cos, math.rad, math.tan

local function rot_x(v, a) local c, s = cos(a), sin(a); return { v[1], v[2] * c - v[3] * s, v[2] * s + v[3] * c } end
local function rot_y(v, a) local c, s = cos(a), sin(a); return { v[1] * c + v[3] * s, v[2], -v[1] * s + v[3] * c } end
local function rot_z(v, a) local c, s = cos(a), sin(a); return { v[1] * c - v[2] * s, v[1] * s + v[2] * c, v[3] } end

-- X-Plane heading/pitch/roll (deg) -> rotation of a vector from the rotated
-- frame into the parent frame; inverse undoes it. Same convention for the
-- pilot's head and for attached objects (heading CW, pitch up, roll right).
local function to_parent(v, psi, the, phi) return rot_y(rot_x(rot_z(v, -rad(phi)), rad(the)), -rad(psi)) end
local function to_child(v, psi, the, phi) return rot_z(rot_x(rot_y(v, rad(psi)), -rad(the)), rad(phi)) end

local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end

-- Moller-Trumbore, both faces; returns distance along the ray or nil
local function ray_tri(o, d, a, b, c)
    local e1, e2 = sub(b, a), sub(c, a)
    local p = cross(d, e2)
    local det = dot(e1, p)
    if math.abs(det) < 1e-12 then return nil end
    local inv = 1 / det
    local t = sub(o, a)
    local u = dot(t, p) * inv
    if u < 0 or u > 1 then return nil end
    local q = cross(t, e1)
    local v = dot(d, q) * inv
    if v < 0 or u + v > 1 then return nil end
    local dist = dot(e2, q) * inv
    if dist <= 0 then return nil end
    return dist
end

-----------------------------------------------------------------------------
-- Files
-----------------------------------------------------------------------------

local function norm_path(p)
    p = (p or ""):gsub("\\", "/")
    local out = {}
    for part in p:gmatch("[^/]+") do
        if part == ".." and #out > 0 and out[#out] ~= ".." then
            out[#out] = nil
        elseif part ~= "." then
            out[#out + 1] = part
        end
    end
    local lead = p:match("^/") and "/" or ""
    return lead .. table.concat(out, "/")
end

local CURSORS = {
    four_arrows = "xplm_CursorFourArrows", hand = "xplm_CursorHandle", button = "xplm_CursorButton",
    rotate_small = "xplm_CursorRotateSmall", rotate_small_left = "xplm_CursorRotateSmallLeft",
    rotate_small_right = "xplm_CursorRotateSmallRight", rotate_medium = "xplm_CursorRotateMedium",
    rotate_medium_left = "xplm_CursorRotateMediumLeft", rotate_medium_right = "xplm_CursorRotateMediumRight",
    rotate_large = "xplm_CursorRotateLarge", rotate_large_left = "xplm_CursorRotateLargeLeft",
    rotate_large_right = "xplm_CursorRotateLargeRight", up_down = "xplm_CursorUpDown", down = "xplm_CursorDown",
    up = "xplm_CursorUp", left_right = "xplm_CursorLeftRight", left = "xplm_CursorLeft", right = "xplm_CursorRight",
    arrow = "xplm_CursorArrow",
}

local function cursor_id(name)
    local key = CURSORS[name or ""] or "xplm_CursorHandle"
    return (XPLMCursorStatus and XPLMCursorStatus[key]) or 0
end

-- manipulator line -> { kind = "hold" | "pair", axis = "x" | "y", cursor, cmds = { name... } }
local function parse_manip(p)
    local k = p[1]
    if k == "ATTR_manip_command" or k == "ATTR_manip_command_knob2" then
        return { kind = "hold", cursor = p[2], cmds = { p[3] } }
    elseif k == "ATTR_manip_command_switch_left_right" or k == "ATTR_manip_command_switch_left_right2"
        or k == "ATTR_manip_command_knob" then
        return { kind = "pair", axis = "x", cursor = p[2], cmds = { p[3], p[4] } }
    elseif k == "ATTR_manip_command_switch_up_down" or k == "ATTR_manip_command_switch_up_down2" then
        return { kind = "pair", axis = "y", cursor = p[2], cmds = { p[3], p[4] } }
    end
    return nil
end

-- G5.obj manipulator batches, vertices in OBJ-local metres incl. static ANIM_trans
local function read_obj(path)
    local f = io.open(path, "r")
    if not f then return nil, "cannot open " .. path end
    local vt, idx, batches = {}, {}, {}
    local stack = { { 0, 0, 0 } }
    local manip, top_group, group_seq = nil, 0, 0
    for line in f:lines() do
        local p = {}
        for w in line:gmatch("%S+") do p[#p + 1] = w end
        local k = p[1]
        if k == "VT" then
            vt[#vt + 1] = { tonumber(p[2]), tonumber(p[3]), tonumber(p[4]) }
        elseif k == "IDX" or k == "IDX10" then
            for i = 2, #p do idx[#idx + 1] = tonumber(p[i]) end
        elseif k == "ANIM_begin" then
            if #stack == 1 then group_seq = group_seq + 1; top_group = group_seq end
            local t = stack[#stack]
            stack[#stack + 1] = { t[1], t[2], t[3] }
        elseif k == "ANIM_end" then
            stack[#stack] = nil
            if #stack == 1 then top_group = 0 end
        elseif k == "ANIM_trans" then
            local t = stack[#stack]
            t[1], t[2], t[3] = t[1] + tonumber(p[2]), t[2] + tonumber(p[3]), t[3] + tonumber(p[4])
        elseif k and k:sub(1, 11) == "ATTR_manip_" then
            manip = (k ~= "ATTR_manip_none") and parse_manip(p) or nil
            if k ~= "ATTR_manip_none" and not manip then log("pick: unsupported manipulator ignored: " .. k) end
        elseif k == "TRIS" and manip then
            local first, count = tonumber(p[2]), tonumber(p[3])
            local off = stack[#stack]
            local tris = {}
            for i = first, first + count - 1, 3 do
                local tri = {}
                for j = 0, 2 do
                    local v = vt[idx[i + j + 1] + 1]
                    tri[j + 1] = { v[1] + off[1], v[2] + off[2], v[3] + off[3] }
                end
                tris[#tris + 1] = tri
            end
            batches[#batches + 1] = {
                kind = manip.kind, axis = manip.axis, cursor = manip.cursor, cmd_names = manip.cmds,
                tris = tris,
                -- batches outside any animation are their own group
                group = (top_group ~= 0) and top_group or (1000 + #batches),
            }
        end
    end
    f:close()
    return batches
end

local function read_acf(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local obja = {}
    local root = {}
    for line in f:lines() do
        local n, key, val = line:match("^P _obja/(%d+)/(%S+) (.*)$")
        if n then
            n = tonumber(n)
            obja[n] = obja[n] or {}
            obja[n][key] = val:gsub("%s+$", "")
        else
            local k2, v2 = line:match("^P acf/(%S+) (.*)$")
            if k2 == "_cgY" or k2 == "_cgZ" then root[k2] = tonumber(v2) end
        end
    end
    f:close()
    return obja, root
end

local function file_contains(path, needle)
    local f = io.open(path, "r")
    if not f then return false end
    local s = f:read("*a")
    f:close()
    return s:find(needle, 1, true) ~= nil
end

-----------------------------------------------------------------------------
-- Datarefs
-----------------------------------------------------------------------------

local function find(name)
    local h = XPLMFindDataRef(name)
    if h == nil then log("pick: dataref not found: " .. name) end
    return h
end

local scratch = {}

-- "path[3]" or "path" -> number, any type
local function read_any(h, index)
    if h == nil then return 0 end
    local t = XPLMGetDataRefTypes(h)
    if index then
        if t % 16 >= 8 then -- float array bit
            if XPLMGetDatavf(h, scratch, index, 1) == 1 then return scratch[1] or 0 end
        elseif t % 32 >= 16 then
            if XPLMGetDatavi(h, scratch, index, 1) == 1 then return scratch[1] or 0 end
        end
        return 0
    end
    if t % 4 >= 2 then return XPLMGetDataf(h) end
    if t % 2 >= 1 then return XPLMGetDatai(h) end
    if t % 8 >= 4 then return XPLMGetDatad(h) end
    return 0
end

local function hide_ref(spec)
    if not spec or spec == "" or spec == "none" then return nil end
    local name, index = spec:match("^(.-)%[(%d+)%]$")
    name = name or spec
    local h = XPLMFindDataRef(name)
    if h == nil then return nil end
    return { h = h, index = index and tonumber(index) or nil }
end

-----------------------------------------------------------------------------
-- Camera
-----------------------------------------------------------------------------

local cam = { ok = false }
local proj_m = {}

local function bounds()
    local b = XPLMGetScreenBoundsGlobal()
    local function num(x) return tonumber(tostring(x)) or 0 end
    if type(b) == "table" then
        return num(b.outLeft or b[1]), num(b.outTop or b[2]), num(b.outRight or b[3]), num(b.outBottom or b[4])
    end
    return 0, 0, 0, 0
end

local function update_camera()
    cam.ok = false
    if XPLMGetDatai(dr.view_type) ~= 1026 then return end          -- 3D cockpit only
    if dr.vr and XPLMGetDatai(dr.vr) ~= 0 then return end
    local l, t, r, b = bounds()
    if r - l < 10 or t - b < 10 then return end
    local ww, wh = XPLMGetDatai(dr.win_w), XPLMGetDatai(dr.win_h)
    local aspect = (ww > 0 and wh > 0) and (ww / wh) or ((r - l) / (t - b))
    cam.l, cam.t, cam.r, cam.b = l, t, r, b
    -- The projection X-Plane really used for the last 3D frame. It includes the
    -- mouse-wheel zoom, which field_of_view_deg does not (zoomed 72.5 deg showed
    -- as 38 deg). OpenGL column-major: m[0] = 1/tan_h, m[5] = 1/tan_v, m[8]/m[9]
    -- = frustum shift.
    local m = proj_m
    local ok = dr.proj and XPLMGetDatavf(dr.proj, m, 0, 16) == 16
        and m[1] and m[6] and m[1] > 0.05 and m[6] > 0.05 and m[11] and m[11] < 0
    if ok then
        cam.tan_h, cam.tan_v = 1 / m[1], 1 / m[6]
        cam.shift_x, cam.shift_y = -m[9], -m[10]
    else
        cam.tan_h = tan(rad(XPLMGetDataf(dr.fov) * 0.5))
        cam.tan_v = cam.tan_h / aspect
        cam.shift_x = XPLMGetDataf(dr.fov_hr) * 2      -- frustum shift, 1 = one screen width
        cam.shift_y = XPLMGetDataf(dr.fov_vr) * 2
    end
    -- position: the pilot's head in the aircraft frame (exact; the world-space
    -- view_x/y/z floats lose millimetres far from the local origin)
    cam.pos = { XPLMGetDataf(dr.hx), XPLMGetDataf(dr.hy), XPLMGetDataf(dr.hz) }
    -- orientation: the camera X-Plane really rendered (world view angles, which
    -- include the aircraft attitude), brought into the aircraft frame. The head
    -- angles alone were off by ~25 px at large head yaw with the aircraft pitched.
    local vh, vp, vr = XPLMGetDataf(dr.vhdg), XPLMGetDataf(dr.vpitch), XPLMGetDataf(dr.vroll)
    local ah, ap, ar = XPLMGetDataf(dr.apsi), XPLMGetDataf(dr.athe), XPLMGetDataf(dr.aphi)
    local function axis(v) return to_child(to_parent(v, vh, vp, vr), ah, ap, ar) end
    cam.ax_r, cam.ax_u, cam.ax_b = axis({ 1, 0, 0 }), axis({ 0, 1, 0 }), axis({ 0, 0, 1 })
    cam.ok = true
end

-- CG-frame vector -> camera frame (x right, y up, z toward the viewer)
local function cam_local(v)
    return { dot(v, cam.ax_r), dot(v, cam.ax_u), dot(v, cam.ax_b) }
end

-- CG-frame point -> global boxels, or nil if behind the camera
local function project(p)
    local c = cam_local(sub(p, cam.pos))
    if c[3] > -1e-4 then return nil end
    local nx = (c[1] / -c[3]) / cam.tan_h + cam.shift_x
    local ny = (c[2] / -c[3]) / cam.tan_v + cam.shift_y
    return cam.l + (nx * 0.5 + 0.5) * (cam.r - cam.l), cam.b + (ny * 0.5 + 0.5) * (cam.t - cam.b)
end

-- global boxels -> ray (origin, dir) in the CG frame
local function mouse_ray(x, y)
    local nx = ((x - cam.l) / (cam.r - cam.l)) * 2 - 1 - cam.shift_x
    local ny = ((y - cam.b) / (cam.t - cam.b)) * 2 - 1 - cam.shift_y
    local a, b = nx * cam.tan_h, ny * cam.tan_v
    local d = {
        a * cam.ax_r[1] + b * cam.ax_u[1] - cam.ax_b[1],
        a * cam.ax_r[2] + b * cam.ax_u[2] - cam.ax_b[2],
        a * cam.ax_r[3] + b * cam.ax_u[3] - cam.ax_b[3],
    }
    return cam.pos, d
end

local function slot_visible(s)
    if not s.hide then return true end
    return read_any(s.hide.h, s.hide.index) == 0
end

local function to_cg(s, v) return add(to_parent(v, s.psi, s.the, s.phi), s.base) end

-----------------------------------------------------------------------------
-- Hit test
-----------------------------------------------------------------------------

-- nearest manipulator hit for a group: batch, slot, hit point (CG frame)
local function hit_group(g, x, y)
    if not cam.ok then return nil end
    local o, d = mouse_ray(x, y)
    local best, bb, bs = nil, nil, nil
    for _, s in ipairs(slots) do
        if s.on and slot_visible(s) then
            -- ray into the object's frame
            local lo = to_child(sub(o, s.base), s.psi, s.the, s.phi)
            local ld = to_child(d, s.psi, s.the, s.phi)
            for _, b in ipairs(g.batches) do
                for _, tri in ipairs(b.tris) do
                    local dist = ray_tri(lo, ld, tri[1], tri[2], tri[3])
                    if dist and (not best or dist < best) then best, bb, bs = dist, b, s end
                end
            end
        end
    end
    return bb, bs
end

-- which command of a "pair" batch: screen side of the batch centre
local function pair_index(b, s, x, y)
    local cx, cy = project(to_cg(s, b.center))
    if not cx then return 1 end
    if b.axis == "y" then return (y >= cy) and 1 or 2 end
    return (x >= cx) and 1 or 2
end

-- a "pair" batch in the same group, for the mouse wheel
local function wheel_batch(g, b)
    if b.kind == "pair" then return b end
    for _, o in ipairs(g.batches) do
        if o.kind == "pair" then return o end
    end
    return nil
end

-----------------------------------------------------------------------------
-- Window callbacks
-----------------------------------------------------------------------------

local function end_active()
    if active then
        XPLMCommandEnd(active.cmd)
        active = nil
    end
end

local function on_draw(win, g)
    -- invisible: the window only catches the mouse over the G5 controls
end

local function on_click(win, x, y, mouse, g)
    local ok, ret = pcall(function()
        if mouse == XPLMMouseStatus.xplm_MouseDown then
            end_active()
            local b, s = hit_group(g, x, y)
            if not b then return config.pick_pass_misses ~= 0 and 0 or 1 end
            local i = (b.kind == "pair") and pair_index(b, s, x, y) or 1
            local c = b.cmds[i]
            if c then
                XPLMCommandBegin(c)
                active = { cmd = c }
            end
            if config.pick_debug ~= 0 then log("pick: " .. tostring(b.cmd_names[i])) end
            return 1
        elseif mouse == XPLMMouseStatus.xplm_MouseUp then
            end_active()
        end
        return 1
    end)
    if not ok then
        log("pick: click error " .. tostring(ret))
        end_active()
        return 1
    end
    return ret
end

local function on_cursor(win, x, y, g)
    local ok, ret = pcall(function()
        local b, s = hit_group(g, x, y)
        if not b then return XPLMCursorStatus.xplm_CursorDefault end
        local name = b.cursor or "hand"
        if b.kind == "pair" and name:match("^rotate_%a+$") and b.axis == "x" then
            name = name .. ((pair_index(b, s, x, y) == 1) and "_right" or "_left")
        end
        return cursor_id(name)
    end)
    if not ok then return 0 end
    return ret
end

local function on_wheel(win, x, y, wheel, clicks, g)
    local ok, ret = pcall(function()
        local b = hit_group(g, x, y)
        if not b then return false end
        local w = wheel_batch(g, b)
        if w and wheel == 0 and clicks ~= 0 then
            local c = (clicks > 0) and w.cmds[1] or w.cmds[2]
            for _ = 1, math.min(math.abs(clicks), 10) do XPLMCommandOnce(c) end
        end
        return true     -- consume over the G5 controls
    end)
    if not ok then return true end
    return ret
end

-----------------------------------------------------------------------------
-- Public
-----------------------------------------------------------------------------

function P.init(util, cfg)
    U, config = util, cfg
    log = U.log
end

-- obj_path: this package's G5.obj; acf_path: the user aircraft
function P.load(obj_path, acf_path)
    slots, groups = {}, {}
    status = "off"
    if config.pick_mode == 0 then
        status = "disabled in config.ini"
        log("pick: " .. status)
        return
    end
    local obja, root = read_acf(acf_path)
    if not obja then
        status = "cannot read " .. acf_path
        log("pick: " .. status)
        return
    end
    local acf_dir = norm_path(acf_path):match("^(.*)/[^/]*$") or ""
    local cg = { 0, (root._cgY or 0) * FT, (root._cgZ or 0) * FT }
    local function resolve(file) return norm_path(acf_dir .. "/objects/" .. file) end

    -- which slots attach G5.obj: this package's file, else any file named G5.obj
    local want = string.lower(norm_path(obj_path))
    local matches, cockpit_file = {}, nil
    for n, o in pairs(obja) do
        local file = o._v10_att_file_stl
        local flags = tonumber(o._obj_flags or "0") or 0
        if file and (flags % 4096) >= 2048 then cockpit_file = resolve(file) end
        if file and string.lower(resolve(file)) == want then matches[#matches + 1] = n end
    end
    if #matches == 0 then
        for n, o in pairs(obja) do
            local file = o._v10_att_file_stl
            if file and string.lower(resolve(file)):match("/g5%.obj$") then
                matches[#matches + 1] = n
                obj_path = resolve(file)
            end
        end
    end
    if #matches == 0 then
        status = "G5.obj is not attached in " .. acf_path
        log("pick: " .. status)
        return
    end

    local batches, err = read_obj(obj_path)
    if not batches then
        status = err
        log("pick: " .. err)
        return
    end
    local injected = cockpit_file and file_contains(cockpit_file, "G5 2026 click regions") or false
    table.sort(matches)
    for _, n in ipairs(matches) do
        local o = obja[n]
        local flags = tonumber(o._obj_flags or "0") or 0
        local s = {
            n = n,
            base = {
                (tonumber(o._v10_att_x_acf_prt_ref) or 0) * FT - cg[1],
                (tonumber(o._v10_att_y_acf_prt_ref) or 0) * FT - cg[2],
                (tonumber(o._v10_att_z_acf_prt_ref) or 0) * FT - cg[3],
            },
            psi = tonumber(o._v10_att_psi_ref) or 0,
            the = tonumber(o._v10_att_the_ref) or 0,
            phi = tonumber(o._v10_att_phi_ref) or 0,
            hide = hide_ref(o._obj_hide_dataref),
            on = true,
        }
        if (flags % 4096) >= 2048 then
            s.on, s.why = false, "slot is the cockpit object (native clicks)"
        elseif injected and config.pick_mode ~= 2 then
            s.on, s.why = false, "cockpit object already has the G5 click regions"
        end
        slots[#slots + 1] = s
        log(string.format("pick: %s slot %d at (%.3f, %.3f, %.3f) m from CG: %s", obj_path, n,
            s.base[1], s.base[2], s.base[3], s.on and "plugin picking" or s.why))
    end

    -- group the batches, resolve commands, cache vertices for the window rects
    local by_id = {}
    for _, b in ipairs(batches) do
        b.cmds = {}
        for i, name in ipairs(b.cmd_names) do b.cmds[i] = XPLMFindCommand(name) end
        local sx, sy, sz, n = 0, 0, 0, 0
        for _, tri in ipairs(b.tris) do
            for j = 1, 3 do sx, sy, sz, n = sx + tri[j][1], sy + tri[j][2], sz + tri[j][3], n + 1 end
        end
        b.center = { sx / n, sy / n, sz / n }
        local g = by_id[b.group]
        if not g then
            g = { batches = {}, verts = {}, rect = { 0, 0, 0, 0 } }
            by_id[b.group] = g
            groups[#groups + 1] = g
        end
        g.batches[#g.batches + 1] = b
        for _, tri in ipairs(b.tris) do
            for j = 1, 3 do g.verts[#g.verts + 1] = tri[j] end
        end
    end
    status = string.format("%d manipulator group(s), %d batch(es)", #groups, #batches)
    log("pick: " .. status)
end

function P.enable()
    if #groups == 0 then return end
    local any = false
    for _, s in ipairs(slots) do any = any or s.on end
    if not any then return end
    dr.view_type = find("sim/graphics/view/view_type")
    dr.vr = XPLMFindDataRef("sim/graphics/VR/enabled")
    dr.win_w = find("sim/graphics/view/window_width")
    dr.win_h = find("sim/graphics/view/window_height")
    dr.fov = find("sim/graphics/view/field_of_view_deg")
    dr.fov_hr = find("sim/graphics/view/field_of_view_horizontal_ratio")
    dr.fov_vr = find("sim/graphics/view/field_of_view_vertical_ratio")
    dr.proj = find("sim/graphics/view/projection_matrix_3d")
    dr.vhdg = find("sim/graphics/view/view_heading")
    dr.vpitch = find("sim/graphics/view/view_pitch")
    dr.vroll = find("sim/graphics/view/view_roll")
    dr.apsi = find("sim/flightmodel/position/psi")
    dr.athe = find("sim/flightmodel/position/theta")
    dr.aphi = find("sim/flightmodel/position/phi")
    dr.hx = find("sim/graphics/view/pilots_head_x")
    dr.hy = find("sim/graphics/view/pilots_head_y")
    dr.hz = find("sim/graphics/view/pilots_head_z")
    dr.hpsi = find("sim/graphics/view/pilots_head_psi")
    dr.hthe = find("sim/graphics/view/pilots_head_the")
    dr.hphi = find("sim/graphics/view/pilots_head_phi")
    for _, g in ipairs(groups) do
        g.win = XPLMCreateWindowEx({
            left = 0, top = 1, right = 1, bottom = 0,
            visible = false,
            drawWindowFunc = on_draw,
            handleMouseClickFunc = on_click,
            handleCursorFunc = on_cursor,
            handleMouseWheelFunc = on_wheel,
            refcon = g,
            decorateAsFloatingWindow = XPLMWindowDecoration.xplm_WindowDecorationNone,
            layer = XPLMWindowLayer.xplm_WindowLayerFlightOverlay,
        })
        g.shown = false
    end
    enabled = true
end

local function hide(g)
    if g.shown then
        XPLMSetWindowIsVisible(g.win, false)
        g.shown = false
    end
end

-- per frame: lay each window over its group's projected bounding box
function P.update()
    if not enabled then return end
    update_camera()
    for _, g in ipairs(groups) do
        local l, t, r, b = nil, nil, nil, nil
        if cam.ok and not active then
            for _, s in ipairs(slots) do
                if s.on and slot_visible(s) then
                    for _, v in ipairs(g.verts) do
                        local x, y = project(to_cg(s, v))
                        if not x then l = nil; break end
                        l = l and math.min(l, x) or x
                        r = r and math.max(r, x) or x
                        b = b and math.min(b, y) or y
                        t = t and math.max(t, y) or y
                    end
                end
            end
        end
        if active then
            -- keep the window still while a click is held
        elseif l and r > cam.l and l < cam.r and t > cam.b and b < cam.t and (r - l) < (cam.r - cam.l) * 0.5 then
            l, b = math.floor(l) - 1, math.floor(b) - 1
            r, t = math.ceil(r) + 1, math.ceil(t) + 1
            g.rect = { l, t, r, b }
            XPLMSetWindowGeometry(g.win, l, t, r, b)
            if config.pick_debug ~= 0 then
                g.dbg = (g.dbg or 0) + 1
                if g.dbg % 60 == 1 then
                    log(string.format("pick: window %s  l %d t %d r %d b %d  (screen %d %d %d %d)",
                        tostring(g.batches[1].cmd_names[1]), l, t, r, b, cam.l, cam.t, cam.r, cam.b))
                    -- self-test: the projected centre of each batch must pick that batch
                    for _, bt in ipairs(g.batches) do
                        local s1 = slots[1]
                        local pt = bt.center
                        if bt.kind == "pair" then
                            -- rim: a point 90 % of the way to its outermost vertex (right side)
                            local far = pt
                            for _, tri in ipairs(bt.tris) do
                                for j = 1, 3 do if tri[j][1] > far[1] then far = tri[j] end end
                            end
                            pt = { pt[1] + (far[1] - pt[1]) * 0.9, pt[2], far[3] }
                        end
                        local px, py = project(to_cg(s1, pt))
                        local hb, hs = hit_group(g, px, py)
                        local side = (hb and hb.kind == "pair") and pair_index(hb, hs, px, py) or 1
                        log(string.format("pick: self-test %s at %.1f,%.1f -> %s", tostring(bt.cmd_names[1]),
                            px or -1, py or -1, hb and tostring(hb.cmd_names[side]) or "MISS"))
                    end
                end
            end
            if not g.shown then
                XPLMSetWindowIsVisible(g.win, true)
                g.shown = true
            end
        else
            hide(g)
        end
    end
end

function P.disable()
    end_active()
    for _, g in ipairs(groups) do
        if g.win then
            XPLMDestroyWindow(g.win)
            g.win = nil
        end
    end
    enabled = false
end

function P.status() return status end

return P
