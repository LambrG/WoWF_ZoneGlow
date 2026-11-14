-- luacheck config for the WoW Forever addon (Lua 5.1)
std = "lua51"
max_line_length = 120

-- Globals the addon defines
globals = {
    "ZoneGlowDB",
    "SLASH_ZONEGLOW1",
    "SlashCmdList",
}

-- WoW API used by the addon
read_globals = {
    "CreateFrame",
    "WorldFrame",
    "GetPhysicalScreenSize",
    "GetRealZoneText",
    "C_Timer",
    "strsplit",
    "strtrim",
}
