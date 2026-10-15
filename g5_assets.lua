-- g5_assets.lua: every PNG in Textures/ (imported 1:1 from the 2024-2025 G5
-- artwork by tools/import_assets.py). key = path without ".png".
-- Sprite sheets list their cell grid {cx, cy}. Text and LED digits come from
-- the raster fonts in Textures/RFont (g5_rfont_data.lua).

local A = {}

A.IMAGES = {
    "321", "ALIGNING", "ALT_Bug_Box", "ALT_Tape", "AP_Aimer", "Aimer_1",
    "ArtHori_BG", "ArtHori_Gradients", "ArtHori_Words", "ArtHori_Ladder", "BATT_Charging_Icon", "BATT_NoCharge_Icon", "BATT_Icon", "BATT_Icon_25", "BATT_PFD_Box",
    "Baro_Box", "Baro_Unit_in", "Brightness_Auto_Pressed", "Brightness_Panel_Auto", "Brightness_Panel_Main",
    "Brightness_Pusher", "Brightness_Slider_Mask", "Bug_ALT", "Bug_HDG", "Bug_SPD",
    "Ext_Power_Lost_UI", "FD_Aimer", "G5_Garmin_Logo", "GPSS_ON_Bar", "GS_Box",
    "HDG_Bug_Box", "HDG_Num_Box", "HDG_Ticks", "HDG_Shade", "HSI_AC_Icon", "HSI_BG", "Bug_TRK", "HSI_TRK_Bug",
    -- batch G (tools/make_batch_g_art.py)
    "HDG_Num_Box_W", "TRK_Num_Box", "HSI_HDG_Box_O", "HSI_TRK_Box", "Bug_HDG_Hollow",
    "HSI_HDG_Bug_Hollow", "HSI_Fixed_NoRing", "ALT_Bug_Box_Alert", "Pops_Menu_Blank",
    "Cyan_Bars_3_dashes", "Cyan_Bars_5_dashes",
    -- batch E (tools/make_batch_e_art.py)
    "Tile_Back", "Tile_Message", "Tile_GPSS", "Tile_HSI", "Tile_PFD", "Tile_Blank", "Pops_Title_Bar",
    "HSI_Circles_Rot", "HSI_Fixed", "HSI_HDG_Box", "HSI_HDG_Bug", "HSI_HDG_Bug_Box", "HSI_MSG",
    "HSI_Options_5", "HSI_Options_6", "HSI_Round_Marks", "Has_message_Icon", "Heading_Fail",
    "Horizontal_GS", "INN_Turn_Tri", "Menu_Altitude_Units", "Menu_Horizontal_Bar",
    "Menu_Option_Base", "No_SPD", "OAT_Box", "OAT_C", "OAT_F", "OUT_Turn_Tri",
    "PFD_Menu_Selected", "PFD_Options_5", "PFD_Options_6", "Pops_Menu_Altitude",
    "Pops_Menu_Course", "Pops_Menu_Heading", "Pops_Menu_OBS", "Pops_Menu_VOR",
    "Pops_Msg_Type_1", "Pops_Msg_Type_2", "Pops_Msg_Type_3", "Red_Arrows", "Roll_Indicator", "Roll_Arc",
    "SPD_ALT_Box", "SPD_ALT_Shade", "SPD_Bug_Box", "SPD_Strip_Barber", "SPD_Strip_Green",
    "SPD_Strip_Red", "SPD_Strip_White", "SPD_Strip_White_Line", "SPD_Strip_Yellow",
    "SPD_Tape", "SPD_Unit",
    "Shades_Main", "Shut_Ongoing", "Slip_Ball", "Slip_Indicator_Box", "TAS_Box",
    "Turn_Rate_Indicator", "Turn_Rate_Tape", "VS-Bug", "VS_Box", "VS_Symbol",
    "Vert_GS_Box", "va_marker", "vg_marker", "vx_marker", "vy_marker", "vflag_blank",
    "AP/AP_Bar", "AP/ALTS", "AP/ALT_G", "AP/AP_G", "AP/GPS", "AP/GPS_G", "AP/GP_G", "AP/GS_G",
    "AP/HDG_G", "AP/IAS_G", "AP/LOC_G", "AP/PIT_G", "AP/ROL_G", "AP/TRK_G", "AP/VNAV",
    "AP/VS_G", "AP/YD_G",
    "VS_15config/VS_Stripe", "VS_15config/VS_Stripe_Full", "VS_15config/VS_Arrow",
    "VS_30config/VS_Stripe", "VS_30config/VS_Stripe_Full", "VS_30config/VS_Arrow",
}

-- sprite sheets: {cells_x, cells_y}; frame i (0-based) = left to right, top to bottom
A.SHEETS = {
    ["321"] = { 4, 1 },            -- blank, 3, 2, 1
    ["BATT_Icon"] = { 5, 1 },      -- empty (red) .. full (green)
    ["BATT_Icon_25"] = { 5, 1 },   -- the same, 25 px frames (tools/make_batch_c_art.py)
    ["VS_Symbol"] = { 2, 1 },      -- up, down
    ["Menu_Altitude_Units"] = { 2, 1 }, -- stacked "ft", "m"
    ["SPD_Unit"] = { 1, 2 },       -- KT, MPH
    ["ArtHori_Ladder"] = { 73, 1 }, -- one pitch-ladder line per cell (tools/make_ladder_sheet.py)
}

-- LED digit fonts, drawn from the raster fonts (A.RFONT, g5_gfx G.led). They
-- keep the geometry of the 2024-2025 PNG atlases they replace, so gen_LED
-- SIZEs in the callers stay valid: `cell` = atlas cell px {w, h}, `ink` =
-- digit height in atlas px, `scale` = default size. On screen a digit slot is
-- cell w x size px wide and the digits are ink x size px tall (rounded to whole
-- pixels, one raster font per height). `color` = the old atlas colour.
local FULL = { 20, 48 }
local LOW = { 10, 24 }
A.FONTS = {
    white      = { face = "bold", cell = FULL, ink = 22, scale = 0.5, color = "FFFFFF" },
    offwhite   = { face = "bold", cell = FULL, ink = 22, scale = 0.5, color = "BFBFBF" },
    cyan       = { face = "bold", cell = FULL, ink = 22, scale = 0.5, color = "95CFDC" },
    green      = { face = "bold", cell = FULL, ink = 22, scale = 0.5, color = "6AD974" },
    magenta    = { face = "bold", cell = FULL, ink = 22, scale = 0.5, color = "AD66AF" },
    cyan_xb    = { face = "xbold", cell = FULL, ink = 23, scale = 0.5, color = "95CFDC" },
    yellow_xb  = { face = "xbold", cell = FULL, ink = 23, scale = 0.5, color = "E4E137" },
    white_lr   = { face = "bold", cell = LOW, ink = 12, scale = 1, color = "FFFFFF" },
    cyan_lr    = { face = "bold", cell = LOW, ink = 12, scale = 1, color = "95CFDC" },
    magenta_lr = { face = "bold", cell = LOW, ink = 12, scale = 1, color = "AD66AF" },
    ap         = { face = "bold", cell = LOW, ink = 12, scale = 1, color = "74C14C" },
}

return A
