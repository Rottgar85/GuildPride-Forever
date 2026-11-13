-- Minimale Nachbildung der WoW-API für die Tests (lua5.1).
-- Unbekannte Globale liefern ein "Alles-Objekt", das jeden Aufruf und jeden
-- Zugriff schluckt; was die Tests brauchen, ist hier ausdrücklich nachgebaut.
local W = {}

local magic
local mmt = {}
mmt.__index = function() return magic end
mmt.__call = function() return magic end
mmt.__newindex = function() end
magic = setmetatable({}, mmt)
W.magic = magic

-- Uhr
W.now = 1000
W.server = 1800000000
function GetTime() return W.now end
function GetServerTime() return W.server end
function W.Advance(sec) W.now = W.now + sec; W.server = W.server + sec end

-- Lua-Helfer aus WoW
function strsplit(sep, s)
    local out, from = {}, 1
    while true do
        local a, b = s:find(sep, from, true)
        if not a then out[#out + 1] = s:sub(from); break end
        out[#out + 1] = s:sub(from, a - 1)
        from = b + 1
    end
    return unpack(out)
end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
function Ambiguate(name) return name end
function geterrorhandler() return function(e) error(e, 0) end end

-- Frames: Skripte und Events merken, alles andere schlucken
W.frames = {}
local function NewFrame()
    local f = { scripts = {}, events = {} }
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:GetScript(k) return self.scripts[k] end
    function f:RegisterEvent(e) self.events[e] = true end
    function f:UnregisterEvent(e) self.events[e] = nil end
    setmetatable(f, { __index = function() return magic end })
    W.frames[#W.frames + 1] = f
    return f
end
function CreateFrame() return NewFrame() end
function CreateFont() return magic end
function W.Fire(event, ...)
    for _, f in ipairs(W.frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end

-- Timer: sofort ausführen (Reihenfolge reicht für die Tests)
C_Timer = {
    After = function(_, fn) fn() end,
    NewTimer = function() return magic end,
    NewTicker = function() return magic end,
}

-- Spieler, Gilde, Battle.net
W.me = "Tester"
W.battletag = "Tester#1234"
W.myRank = 3
W.canMotd = false
W.roster = {}   -- { { name, rankIndex, level, online } }
function GetBuildInfo() return "1.16.0", "1", "Nov 1 2026", 16001 end
function UnitFullName() return W.me, "" end
function UnitName() return W.me end
function GetNormalizedRealmName() return "Realm" end
function GetRealmName() return "Realm" end
function IsInGuild() return true end
function GetGuildInfo() return "Testgilde", "Rang", W.myRank, "Realm" end
function GetNumGuildMembers() return #W.roster, #W.roster end
function GetGuildRosterInfo(i)
    local m = W.roster[i]
    if not m then return nil end
    return m[1], "Rang" .. m[2], m[2], m[3] or 60, "Krieger", "Zone", "", "", m[4] ~= false,
        0, "WARRIOR", 0, 0, false, false, 0, "Player-" .. i
end
function GetGuildRosterShowOffline() return true end
function GuildControlGetNumRanks() return 5 end
function GuildControlGetRankName(i) return "Rang" .. (i - 1) end
function CanEditMOTD() return W.canMotd end
function BNGetInfo() return 1, W.battletag end
C_GuildInfo = {
    GuildRoster = function() end,
    -- Rang 0 und 1 (rankOrder 1 und 2) dürfen die Gildennachricht ändern
    GuildControlGetRankFlags = function(rankOrder) return { [9] = rankOrder <= 2 } end,
}
C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
SlashCmdList = {}
UISpecialFrames = {}
StaticPopupDialogs = {}

function InCombatLockdown() return false end
function IsInRaid() return false end
function IsInGroup() return false end
function UnitExists() return false end
function time() return W.server end
date = os.date

-- Diese Globalen gibt es im Test nicht (nil statt Alles-Objekt): sonst wären
-- z. B. alle Werte "geheim" oder Tabellen würden für Zahlen gehalten
local NILS = { GuildPrideDB = true, GuildPrideBackupDB = true, issecretvalue = true,
    C_RestrictedActions = true, GetNumGuildEvents = true, GetGuildEventInfo = true,
    QueryGuildEventLog = true, C_DateAndTime = true, Settings = true, C_MythicPlus = true,
    JoinTemporaryChannel = true, C_Club = true, C_ChallengeMode = true }

-- Rest: Alles-Objekt
setmetatable(_G, { __index = function(_, k) if NILS[k] then return nil end return magic end })

-- Addon laden: wie WoW mit (Name, Namensraum)
W.ns = { L = setmetatable({}, { __index = function(_, k) return k end }) }
W.sent = {}
function W.Load(file)
    local chunk = assert(loadfile(file))
    chunk("GuildPrideForever", W.ns)
end
function W.Start()
    W.ns.Queue = function(kind, target, ...)
        local parts = { ... }
        for i = 1, select("#", ...) do parts[i] = tostring(parts[i] == nil and "" or parts[i]) end
        W.sent[#W.sent + 1] = { kind = kind, target = target, msg = kind .. ":" .. table.concat(parts, "\031") }
    end
    W.ns.SendAddonMsg = function() return 0 end
    W.Fire("ADDON_LOADED", "GuildPrideForever")
    W.Fire("GUILD_ROSTER_UPDATE")
end

-- Nachricht eines anderen Spielers empfangen
function W.Receive(sender, message, channel)
    W.Advance(31)   -- Doppelte-Filter umgehen
    W.Fire("CHAT_MSG_ADDON", "GuildPride", message, channel or "GUILD", sender)
end

return W
