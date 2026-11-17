-- ZoneGlow: draws two 8x8 px squares in the top-left corner of the screen:
--   [MARKER (magenta)][ZONE COLOR]
-- An external script reads the color of the second square and sends it to OpenRGB.
-- The marker tells the script that the squares are on screen
-- (no color is sent on loading screens or outside the game).

local ADDON_NAME = ...

---------------------------------------------------------------------------
-- Zone type colors (R, G, B in the 0-1 range)
---------------------------------------------------------------------------
local PALETTE = {
    snow    = { 0.00, 0.78, 1.00 },  -- icy blue (00C8FF)
    forest  = { 0.30, 0.60, 0.06 },  -- grass green (4D990F), like the Elwynn map
    fel     = { 0.00, 1.00, 0.25 },  -- toxic green (00FF40), Felwood
    plains  = { 1.00, 0.75, 0.00 },  -- gold
    desert  = { 1.00, 0.40, 0.00 },  -- orange
    alliance = { 0.00, 0.44, 0.87 }, -- alliance blue (0070DE), Alliance cities
    horde   = { 0.80, 0.00, 0.00 },  -- horde red (CC0000), Horde cities
    ironforge = { 0.70, 0.35, 0.05 }, -- forge bronze (B3590D), Ironforge
    steppes = { 0.90, 0.27, 0.06 },  -- ember sky (E6450F), Burning Steppes
    default = { 0.00, 0.25, 1.00 },  -- dark blue (unknown zone)
}

---------------------------------------------------------------------------
-- Zone -> type (enUS client names, exactly as returned by GetRealZoneText)
---------------------------------------------------------------------------
local ZONES = {
    -- Alliance cities
    ["Stormwind City"]      = "alliance",
    ["Ironforge"]           = "ironforge",
    ["Darnassus"]           = "alliance",

    -- Horde cities
    ["Orgrimmar"]           = "horde",
    ["Thunder Bluff"]       = "horde",
    ["Undercity"]           = "horde",

    -- Snow
    ["Dun Morogh"]          = "snow",
    ["Winterspring"]        = "snow",
    ["Alterac Mountains"]   = "snow",
    ["Alterac Valley"]      = "snow",

    -- Forest / jungle / swamp
    ["Elwynn Forest"]       = "forest",
    ["Duskwood"]            = "forest",
    ["Tirisfal Glades"]     = "forest",
    ["Silverpine Forest"]   = "forest",
    ["The Hinterlands"]     = "forest",
    ["Stranglethorn Vale"]  = "forest",
    ["Swamp of Sorrows"]    = "forest",
    ["Teldrassil"]          = "forest",
    ["Darkshore"]           = "forest",
    ["Ashenvale"]           = "forest",
    ["Felwood"]             = "fel",
    ["Moonglade"]           = "forest",
    ["Azshara"]             = "forest",
    ["Feralas"]             = "forest",
    ["Un'Goro Crater"]      = "forest",
    ["Dustwallow Marsh"]    = "forest",
    ["Stonetalon Mountains"] = "forest",

    -- Plains / grassland / hills
    ["Westfall"]            = "plains",
    ["Redridge Mountains"]  = "plains",
    ["Loch Modan"]          = "plains",
    ["Wetlands"]            = "plains",
    ["Hillsbrad Foothills"] = "plains",
    ["Arathi Highlands"]    = "plains",
    ["Arathi Basin"]        = "plains",
    ["Western Plaguelands"] = "plains",
    ["Eastern Plaguelands"] = "plains",
    ["Deadwind Pass"]       = "plains",
    ["Mulgore"]             = "plains",
    ["The Barrens"]         = "plains",
    ["Warsong Gulch"]       = "plains",

    -- Desert / scorched land
    ["Durotar"]             = "desert",
    ["Badlands"]            = "desert",
    ["Searing Gorge"]       = "desert",
    ["Burning Steppes"]     = "steppes",
    ["Blasted Lands"]       = "desert",
    ["Thousand Needles"]    = "desert",
    ["Desolace"]            = "desert",
    ["Tanaris"]             = "desert",
    ["Silithus"]            = "desert",
}

---------------------------------------------------------------------------
-- Translations
-- Czech is written without diacritics on purpose: the default game fonts
-- do not contain characters such as e-caron or r-caron.
---------------------------------------------------------------------------
local LOCALES = {
    en = {
        language     = "English",
        unknown_zone = "unknown zone: |cffffff00%s|r",
        status       = "%s -> %s",
        lang_set     = "language set to %s",
        lang_usage   = "usage: /zoneglow lang en|cs",
        help_status  = "/zoneglow - show the current zone and its type",
        help_lang    = "/zoneglow lang en|cs - set the language",
        types = {
            snow = "snow", forest = "forest", fel = "fel", plains = "plains",
            desert = "desert", alliance = "Alliance city", horde = "Horde city",
            ironforge = "Ironforge", steppes = "Burning Steppes",
            default = "default",
        },
    },
    cs = {
        language     = "cestina",
        unknown_zone = "neznama zona: |cffffff00%s|r",
        status       = "%s -> %s",
        lang_set     = "jazyk nastaven: %s",
        lang_usage   = "pouziti: /zoneglow lang en|cs",
        help_status  = "/zoneglow - vypise aktualni zonu a jeji typ",
        help_lang    = "/zoneglow lang en|cs - nastavi jazyk",
        types = {
            snow = "snih", forest = "les", fel = "zkazeny les", plains = "plane",
            desert = "poust", alliance = "mesto Aliance", horde = "mesto Hordy",
            ironforge = "Ironforge", steppes = "horici stepi",
            default = "vychozi",
        },
    },
}
local DEFAULT_LANG = "en"

local function L()
    local lang = ZoneGlowDB and ZoneGlowDB.lang
    return LOCALES[lang] or LOCALES[DEFAULT_LANG]
end

local function Print(key, ...)
    print("|cff00c8ffZoneGlow|r: " .. string.format(L()[key], ...))
end

---------------------------------------------------------------------------
-- Squares
---------------------------------------------------------------------------
local SIZE = 8  -- size of one square in pixels

-- No parent (nil), so Alt+Z (hide UI) does not hide them
local frame = CreateFrame("Frame", "ZoneGlowFrame", nil)
frame:SetFrameStrata("TOOLTIP")
frame:SetPoint("TOPLEFT", WorldFrame, "TOPLEFT", 0, 0)
frame:SetSize(SIZE * 2, SIZE)

local marker = frame:CreateTexture(nil, "OVERLAY")
marker:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
marker:SetSize(SIZE, SIZE)
marker:SetColorTexture(1, 0, 1, 1)  -- magenta = marker

local swatch = frame:CreateTexture(nil, "OVERLAY")
swatch:SetPoint("TOPLEFT", marker, "TOPRIGHT", 0, 0)
swatch:SetSize(SIZE, SIZE)

-- 1 UI unit = 1 physical pixel (independent of UI scale and resolution)
local function FixScale()
    local _, physH = GetPhysicalScreenSize()
    if physH and physH > 0 then
        frame:SetScale(768 / physH)
    end
end

---------------------------------------------------------------------------
-- Logic
---------------------------------------------------------------------------
local currentZone, currentType, lastUnknown = "", "default", nil

local function Update()
    local zone = GetRealZoneText() or ""
    local zoneType = ZONES[zone]

    if not zoneType then
        zoneType = "default"
        if zone ~= "" and zone ~= lastUnknown then
            lastUnknown = zone
            Print("unknown_zone", zone)
        end
    end

    local c = PALETTE[zoneType] or PALETTE.default
    swatch:SetColorTexture(c[1], c[2], c[3], 1)
    currentZone, currentType = zone, zoneType
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
frame:RegisterEvent("UI_SCALE_CHANGED")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            ZoneGlowDB = ZoneGlowDB or {}
            if not LOCALES[ZoneGlowDB.lang] then
                ZoneGlowDB.lang = DEFAULT_LANG
            end
            frame:UnregisterEvent("ADDON_LOADED")
        end
        return
    end

    if event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        FixScale()
    end
    Update()
    -- Right after a zone change GetRealZoneText may still return the old zone, so check again
    C_Timer.After(1, Update)
end)

---------------------------------------------------------------------------
-- Slash commands
--   /zoneglow            - print the current zone and its type
--   /zoneglow lang en|cs - set the language
--   /zoneglow help       - list the commands
---------------------------------------------------------------------------
SLASH_ZONEGLOW1 = "/zoneglow"
SlashCmdList["ZONEGLOW"] = function(msg)
    local cmd, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)

    if cmd == "lang" then
        if arg and LOCALES[arg] then
            ZoneGlowDB.lang = arg
            Print("lang_set", L().language)
        else
            Print("lang_usage")
        end
    elseif cmd == "help" then
        Print("help_status")
        Print("help_lang")
    else
        Update()
        Print("status", currentZone, L().types[currentType] or currentType)
    end
end
