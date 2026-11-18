-- GuildPride: Dungeons und Raids aus WoW Forever für Gildenevents.
-- Die Schlüssel sind dieselben wie im Discord-Bot (GameBot, src/instances.js):
-- Ein Event mit "raid=ony" wird dort als Raid für 40 Spieler angelegt.
local _, ns = ...

local DE = GetLocale() == "deDE"

-- { key, deutscher Name, englischer Name, Stufe }
-- Für die neuen Forever-Dungeons gibt es noch keine deutschen Namen.
local DUNGEONS = {
    { "rfc", "Flammenschlund", "Ragefire Chasm", "13" },
    { "thanes", "The Hall of Thanes", "The Hall of Thanes", "13–18" },
    { "lordaeron", "Ruins of Lordaeron", "Ruins of Lordaeron", "15–20" },
    { "dm", "Die Todesminen", "The Deadmines", "16" },
    { "wc", "Die Höhlen des Wehklagens", "Wailing Caverns", "17" },
    { "sfk", "Burg Schattenfang", "Shadowfang Keep", "18" },
    { "bfd", "Tiefschwarze Grotte", "Blackfathom Deeps", "22" },
    { "stocks", "Das Verlies", "The Stockade", "23" },
    { "rfk", "Kral der Klingenhauer", "Razorfen Kraul", "24" },
    { "gnomer", "Gnomeregan", "Gnomeregan", "25" },
    { "excav", "Excavation Site: Wetlands", "Excavation Site: Wetlands", "26–31" },
    { "dalaran", "City of Dalaran", "City of Dalaran", "28–33" },
    { "sm_gy", "Scharlachrotes Kloster: Friedhof", "Scarlet Monastery: Graveyard", "30" },
    { "sm_lib", "Scharlachrotes Kloster: Bibliothek", "Scarlet Monastery: Library", "30" },
    { "sm_arm", "Scharlachrotes Kloster: Waffenkammer", "Scarlet Monastery: Armory", "30" },
    { "sm_cath", "Scharlachrotes Kloster: Kathedrale", "Scarlet Monastery: Cathedral", "30" },
    { "rfd", "Hügel der Klingenhauer", "Razorfen Downs", "34" },
    { "ulda", "Uldaman", "Uldaman", "35" },
    { "drowned", "The Drowned City", "The Drowned City", "35–40" },
    { "kroldok", "Krol'dok Stronghold", "Krol'dok Stronghold", "40–45" },
    { "zf", "Zul'Farrak", "Zul'Farrak", "42" },
    { "mara", "Maraudon", "Maraudon", "42" },
    { "st", "Versunkener Tempel", "Sunken Temple", "45" },
    { "brd", "Schwarzfelstiefen", "Blackrock Depths", "48" },
    { "alcaz", "Alcaz Prison", "Alcaz Prison", "48–53" },
    { "lbrs", "Untere Schwarzfelsspitze", "Lower Blackrock Spire", "53" },
    { "dme", "Düsterbruch: Ost", "Dire Maul: East", "54" },
    { "dmw", "Düsterbruch: West", "Dire Maul: West", "54" },
    { "dmn", "Düsterbruch: Nord", "Dire Maul: North", "54" },
    { "strat", "Stratholme", "Stratholme", "55" },
    { "blackmaw", "Blackmaw Hold", "Blackmaw Hold", "55–60" },
    { "scholo", "Scholomance", "Scholomance", "57" },
    { "shaper", "Shaper's Terrace", "Shaper's Terrace", "58–60" },
}
-- { key, deutscher Name, englischer Name, Stufe, Gruppengröße }
local RAIDS = {
    { "barrow", "Barrow Deeps", "Barrow Deeps", "60", 10 },
    { "hyjal", "Hyjalgipfel", "Hyjal Summit", "60", 20 },
    { "ony", "Onyxias Hort", "Onyxia's Lair", "60", 40 },
}
-- Tanks und Heiler je Gruppengröße, der Rest Schadensklassen (wie im Bot)
local NEED = { [5] = { 1, 1 }, [10] = { 2, 3 }, [20] = { 2, 5 }, [40] = { 4, 10 } }

local Inst = { list = { dungeon = {}, raid = {} } }
local byKey = { dungeon = {}, raid = {} }
local function Add(kind, row)
    local x = { kind = kind, key = row[1], name = DE and row[2] or row[3], level = row[4],
                size = kind == "raid" and row[5] or 5 }
    table.insert(Inst.list[kind], x)
    byKey[kind][x.key] = x
end
for _, r in ipairs(DUNGEONS) do Add("dungeon", r) end
for _, r in ipairs(RAIDS) do Add("raid", r) end

-- Instanz zu Art und Schlüssel (nil bei unbekannten oder fremden Werten)
function Inst.Find(kind, key)
    return byKey[kind or ""] and byKey[kind][key or ""] or nil
end

-- Benötigte Rollen: { TANK = n, HEALER = n, DAMAGER = n }
function Inst.Need(size)
    local n = NEED[size] or { size <= 5 and 1 or 2, math.ceil(size / 5) }
    return { TANK = n[1], HEALER = n[2], DAMAGER = math.max(size - n[1] - n[2], 0) }
end

function Inst.KindLabel(kind) return kind == "raid" and "Raid" or "Dungeon" end

ns.Instances = Inst
