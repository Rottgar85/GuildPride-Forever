-- GuildPride Handwerk: Rezept-Verzeichnis – welche Rezepte gibt es in einem Beruf?
-- Für die Rezept-Lücken der Gilde (GuildPrideCraftGaps.lua).
-- Quellen: eigene Berufsfenster (craftAll), Rezepte der Gilde, Guide-Schritte und eine Suche in den
-- Rezeptdaten des eigenen Spiels (einmal je Spielversion, in kleinen Stücken, nie im Kampf).
-- Gespeichert: GuildPrideDB.craftCatalog = { build, lines = { [Skill-Line-ID] = { Rezept-IDs } } }
local ADDON, ns = ...
local G = ns.CraftGuides

local K = {}
ns.CraftCatalog = K

-- Rang-Zauber (Lehrling, Geselle, Experte, Fachmann): keine Rezepte, stehen in Berufs-Links
K.RANK_SPELLS = {
    [164] = { 2018, 3100, 3538, 9785 }, [165] = { 2108, 3104, 3811, 10662 }, [171] = { 2259, 3101, 3464, 11611 },
    [197] = { 3908, 3909, 3910, 12180 }, [202] = { 4036, 4037, 4038, 12656 }, [333] = { 7411, 7412, 7413, 13920 },
    [185] = { 2550, 3102, 3413, 18260 }, [129] = { 3273, 3274, 7924, 10846 }, [186] = { 2575, 2576, 3564, 10248 },
}
-- Bereiche der Rezept-IDs: Classic und Forever
local RANGES = { { 2000, 30000 }, { 1225000, 1330000 } }
local CHUNK, MAX_PER_LINE = 1500, 1500

local function Saved()
    local c = type(GuildPrideDB) == "table" and GuildPrideDB.craftCatalog
    return type(c) == "table" and type(c.lines) == "table" and c or nil
end

local function LineOf(link) return tonumber(tostring(link or ""):match("^trade:.*:(%d+)$")) end

---------------------------------------------------------------------
-- Alle bekannten Rezepte eines Berufs: { Rezept-IDs }
---------------------------------------------------------------------
function K.Ids(line)
    line = tonumber(line)
    if not line then return {} end
    local out, seen = {}, {}
    for _, id in ipairs(K.RANK_SPELLS[line] or {}) do seen[id] = true end
    local function Add(id)
        if type(id) == "number" and not seen[id] then seen[id] = true; out[#out + 1] = id end
    end
    local all = type(GuildPrideDB) == "table" and type(GuildPrideDB.craftAll) == "table" and GuildPrideDB.craftAll[line]
    for id in pairs(type(all) == "table" and all or {}) do Add(id) end
    local c = Saved()
    for _, id in ipairs(c and c.lines[line] or {}) do Add(id) end
    for _, s in ipairs(G.STEPS[line] or {}) do Add(s[3]) end
    local name = G.NAMES[line]
    for _, e in pairs(ns.GuildTable("crafts")) do
        for prof, ids in pairs(e.rec or {}) do
            local ln = LineOf(e.links and e.links[prof])
            if ln == line or (not ln and name and (prof == name.de or prof == name.en)) then
                for _, id in ipairs(ids) do Add(id) end
            end
        end
    end
    return out
end

---------------------------------------------------------------------
-- Suche in den Rezeptdaten des Spiels
---------------------------------------------------------------------
local function Build()
    local v, b = GetBuildInfo()
    return tostring(v) .. "." .. tostring(b)
end

local running = false
function K.Running() return running end
-- onMore() wird gerufen, wenn die Suche fertig ist
function K.Scan(onMore)
    local T = C_TradeSkillUI
    local ask = T and T.GetProfessionInfoByRecipeID
    if running or not ask or type(GuildPrideDB) ~= "table" then return false end
    local c = Saved()
    if c and c.build == Build() then return false end
    running = true
    local lines, n, bad = {}, {}, {}
    local r, id = 1, RANGES[1][1]
    local function Step()
        if InCombatLockdown and InCombatLockdown() then C_Timer.After(3, Step) return end
        for _ = 1, CHUNK do
            local ok, info = pcall(ask, id)
            local line = ok and type(info) == "table" and info
            if line then
                local p, own = tonumber(line.parentProfessionID), tonumber(line.professionID)
                line = (p and G.NAMES[p] and p) or (own and G.NAMES[own] and own) or nil
            end
            if line and not bad[line] then
                n[line] = (n[line] or 0) + 1
                -- so viele Rezepte hat kein Beruf: Antwort des Spiels unbrauchbar
                if n[line] > MAX_PER_LINE then bad[line], lines[line] = true, nil
                else
                    lines[line] = lines[line] or {}
                    lines[line][n[line]] = id
                end
            end
            id = id + 1
            if id > RANGES[r][2] then
                r = r + 1
                if not RANGES[r] then
                    running = false
                    GuildPrideDB.craftCatalog = { build = Build(), lines = lines }
                    if onMore then ns.Try(onMore) end
                    return
                end
                id = RANGES[r][1]
            end
        end
        C_Timer.After(0.02, Step)
    end
    C_Timer.After(0.02, Step)
    return true
end
