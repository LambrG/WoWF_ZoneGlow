-- ZoneGlow: vykresli v levem hornim rohu obrazovky dva ctverecky 8x8 px:
--   [MARKER (magenta)][BARVA ZONY]
-- Python skript cte barvu druheho ctverecku a posila ji do OpenRGB.
-- Marker slouzi skriptu jako kontrola, ze ctverecky jsou na obrazovce
-- (pri nacitaci obrazovce nebo mimo hru se barva neposle).

---------------------------------------------------------------------------
-- Barvy pro typy zon (R, G, B v rozsahu 0-1)
---------------------------------------------------------------------------
local PALETTE = {
    snow    = { 0.00, 0.78, 1.00 },  -- ledove modra (00C8FF)
    forest  = { 0.00, 1.00, 0.25 },  -- zelena
    plains  = { 1.00, 0.75, 0.00 },  -- zlatozluta
    desert  = { 1.00, 0.40, 0.00 },  -- oranzova
    city    = { 0.63, 0.25, 1.00 },  -- fialova
    default = { 0.00, 0.25, 1.00 },  -- tmave modra (neznama zona)
}

---------------------------------------------------------------------------
-- Zona -> typ (nazvy pro enUS klienta, presne jak je vraci GetRealZoneText)
---------------------------------------------------------------------------
local ZONES = {
    -- Mesta
    ["Stormwind City"]      = "city",
    ["Ironforge"]           = "city",
    ["Darnassus"]           = "city",
    ["Orgrimmar"]           = "city",
    ["Thunder Bluff"]       = "city",
    ["Undercity"]           = "city",

    -- Snih
    ["Dun Morogh"]          = "snow",
    ["Winterspring"]        = "snow",
    ["Alterac Mountains"]   = "snow",
    ["Alterac Valley"]      = "snow",

    -- Les / dzungle / bazina
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
    ["Felwood"]             = "forest",
    ["Moonglade"]           = "forest",
    ["Azshara"]             = "forest",
    ["Feralas"]             = "forest",
    ["Un'Goro Crater"]      = "forest",
    ["Dustwallow Marsh"]    = "forest",
    ["Stonetalon Mountains"] = "forest",

    -- Plane / pastviny / kopce
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

    -- Poust / vyprahla zeme
    ["Durotar"]             = "desert",
    ["Badlands"]            = "desert",
    ["Searing Gorge"]       = "desert",
    ["Burning Steppes"]     = "desert",
    ["Blasted Lands"]       = "desert",
    ["Thousand Needles"]    = "desert",
    ["Desolace"]            = "desert",
    ["Tanaris"]             = "desert",
    ["Silithus"]            = "desert",
}

---------------------------------------------------------------------------
-- Ctverecky
---------------------------------------------------------------------------
local SIZE = 8  -- velikost jednoho ctverecku v pixelech

-- Bez rodice (nil), aby je neschovalo Alt+Z (skryti UI)
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

-- 1 jednotka UI = 1 fyzicky pixel (nezavisle na UI scale a rozliseni)
local function FixScale()
    local _, physH = GetPhysicalScreenSize()
    if physH and physH > 0 then
        frame:SetScale(768 / physH)
    end
end

---------------------------------------------------------------------------
-- Logika
---------------------------------------------------------------------------
local currentZone, currentType, lastUnknown = "", "default", nil

local function Update()
    local zone = GetRealZoneText() or ""
    local zoneType = ZONES[zone]

    if not zoneType then
        zoneType = "default"
        if zone ~= "" and zone ~= lastUnknown then
            lastUnknown = zone
            print("|cff00c8ffZoneGlow|r: neznama zona: |cffffff00" .. zone .. "|r")
        end
    end

    local c = PALETTE[zoneType] or PALETTE.default
    swatch:SetColorTexture(c[1], c[2], c[3], 1)
    currentZone, currentType = zone, zoneType
end

frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
frame:RegisterEvent("UI_SCALE_CHANGED")

frame:SetScript("OnEvent", function(_, event)
    if event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        FixScale()
    end
    Update()
    -- Pri zmene zony muze GetRealZoneText chvili vracet starou zonu, proto jeste jednou
    C_Timer.After(1, Update)
end)

---------------------------------------------------------------------------
-- /zoneglow - vypise aktualni zonu a jeji typ
---------------------------------------------------------------------------
SLASH_ZONEGLOW1 = "/zoneglow"
SlashCmdList["ZONEGLOW"] = function()
    Update()
    print(string.format("|cff00c8ffZoneGlow|r: %s -> %s", currentZone, currentType))
end
