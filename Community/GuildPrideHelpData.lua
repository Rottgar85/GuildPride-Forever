-- GuildPride: Gruppensuche – feste Daten und kleine Helfer ohne eigenen Zustand
-- (Arten, Rollen, Schwierigkeiten, Dungeonliste, Questlog). GuildPrideHelp.lua lädt direkt danach.
local ADDON, ns = ...
local L = ns.L

local TYPES = {
    group = { label = L["Sucht Gruppe"],        color = "|cff6fa8ff", icon = "Interface\\Icons\\INV_Misc_GroupNeedMore" },
    quest = { label = L["Braucht Quest-Hilfe"], color = "|cffffd100", icon = "Interface\\Icons\\INV_Misc_Note_01" },
}
-- Schlüsselstein anbieten (nur Retail, siehe GuildPrideKeys.lua)
if ns.MyKey then
    TYPES.key = { label = L["Bietet Schlüssel an"], color = "|cffa335ee", icon = "Interface\\Icons\\INV_Relics_Hourglass" }
end

-- "+12 Nebel von Tirna Scithe"
local function KeyLabel(map, level)
    if not level or level == 0 then return "" end
    local name = ns.KeyMapName and ns.KeyMapName(map) or nil
    return ("|cffa335ee+%d %s|r"):format(level, name or "")
end

-- Quest-Link selbst bauen: GetQuestLink erwartet in Classic den Questlog-Index
local function QuestLink(id, level, name)
    if not id or id == 0 or not name or name == "" then return "" end
    return ("|cffffff00|Hquest:%d:%d|h[%s]|h|r"):format(id, level or 0, name)
end

-- Quests im eigenen Questlog: { id, level, name } (Retail/Forever: C_QuestLog, Classic: GetQuestLogTitle)
local function QuestLogList()
    local out = {}
    local Q = C_QuestLog
    local modern = Q and Q.GetInfo and Q.GetNumQuestLogEntries
    local n = (modern and Q.GetNumQuestLogEntries()) or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
    for i = 1, n do
        local title, level, isHeader, hidden, id
        if modern then
            local q = Q.GetInfo(i)
            if q then title, level, isHeader, hidden, id = q.title, q.level, q.isHeader, q.isHidden, q.questID end
        elseif GetQuestLogTitle then
            local _
            title, level, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
        end
        if title and not isHeader and not hidden and (id or 0) > 0 then
            out[#out + 1] = { id = id, level = level or 0, name = title }
        end
    end
    return out
end

ns.QuestLogList = QuestLogList   -- für GuildPrideGuildQuests.lua

-- Dungeon-Auswahl nur außerhalb von Retail (dort gibt es den Dungeonbrowser/M+)
local HAS_DUNGEON_PICK = not ns.IS_RETAIL

-- Schwierigkeiten je Spielversion: Classic Era nur normal, ab TBC heroisch, Forever auch mythisch
local DIFF_LABEL = { N = L["Normal"], H = L["Heroisch"], M = L["Mythisch"] }
local DIFFS = { { key = "N", label = DIFF_LABEL.N } }
if (select(4, GetBuildInfo()) or 0) >= 20000 or not ns.IS_CLASSIC then DIFFS[#DIFFS + 1] = { key = "H", label = DIFF_LABEL.H } end
if not ns.IS_CLASSIC then DIFFS[#DIFFS + 1] = { key = "M", label = DIFF_LABEL.M } end

-- "Lvl 18–23" bzw. "Lvl 80+"
local function LevelRange(lo, hi)
    if (lo or 0) <= 0 then return "" end
    if (hi or 0) > lo then return ("Lvl %d–%d"):format(lo, hi) end
    return ("Lvl %d+"):format(lo)
end

-- "Todesminen (Heroisch)"
local function DungeonText(d)
    local diff = DIFF_LABEL[d.diff or ""]
    return d.name .. (diff and (" (" .. diff .. ")") or "")
end

-- Schwierigkeit aus dem Namenszusatz ("Heroisch" in "… (Heroisch)"), sonst nil
local function SuffixDiff(suffix)
    suffix = suffix and suffix:lower() or ""
    if suffix == "" then return nil end
    local function Has(s) return s and s ~= "" and suffix:find(s:lower(), 1, true) end
    if Has(PLAYER_DIFFICULTY6) or Has("mythic") or Has(DIFF_LABEL.M) then return "M" end
    if Has(PLAYER_DIFFICULTY2) or Has("heroic") or Has(DIFF_LABEL.H) then return "H" end
    if Has(PLAYER_DIFFICULTY1) or Has("normal") or Has(DIFF_LABEL.N) then return "N" end
end

-- Schwierigkeit einer Aktivität aus dem Gruppenbrowser: N, H oder M
local function ActivityDiff(info, suffix)
    if info.isMythicActivity then return "M" end
    if info.isHeroicActivity then return "H" end
    if (info.difficultyID or 0) > 0 and GetDifficultyInfo then
        local _, _, isHeroic, _, displayHeroic, displayMythic = GetDifficultyInfo(info.difficultyID)
        if displayMythic then return "M" end
        if isHeroic or displayHeroic then return "H" end
    end
    -- Ältere Clients: nur der Zusatz im Namen
    return SuffixDiff(suffix) or "N"
end

-- Dungeons der jeweiligen Spielversion aus dem Gruppenbrowser:
-- { name, diffs = { N = { min, max }, H = { min, max } } }. Varianten je
-- Schwierigkeit ("… (Heroisch)") werden zu einem Eintrag zusammengefasst; in
-- diffs steht nur, was es für diesen Dungeon wirklich gibt.
local dungeonCache
local function DungeonList()
    if dungeonCache then return dungeonCache end
    local out, seen = {}, {}
    local G = C_LFGList
    if not (G and G.GetAvailableActivities and G.GetActivityInfoTable) then return out end
    local ok, acts = pcall(G.GetAvailableActivities, GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2)
    for _, aid in ipairs(ok and acts or {}) do
        local info = G.GetActivityInfoTable(aid)
        local full = info and info.fullName
        local suffix = full and full:match("%(([^%(%)]*)%)%s*$")
        -- Nur den Schwierigkeitszusatz abschneiden: "Düsterbruch (Ost)" bleibt so
        local name = full
        if SuffixDiff(suffix) then name = full:gsub("%s*%([^%(%)]*%)%s*$", "") end
        if name and name ~= "" and not info.isMythicPlusActivity then
            local diff = ActivityDiff(info, suffix)
            local lo = info.minLevelSuggestion or 0
            if lo == 0 then lo = info.minLevel or 0 end
            local hi = info.maxLevelSuggestion or 0
            local d = seen[name]
            if not d then
                d = { name = name, diffs = {} }
                seen[name] = d
                out[#out + 1] = d
            end
            local v = d.diffs[diff]
            if not v then
                d.diffs[diff] = { min = lo, max = hi }
            else
                if lo > 0 and (v.min == 0 or lo < v.min) then v.min = lo end
                if hi > v.max then v.max = hi end
            end
            -- Sortierung nach der niedrigsten Stufe über alle Schwierigkeiten
            if lo > 0 and (not d.min or lo < d.min) then d.min = lo end
        end
    end
    for _, d in ipairs(out) do d.min = d.min or 0 end
    table.sort(out, function(a, b)
        if a.min ~= b.min then return a.min < b.min end
        return a.name < b.name
    end)
    -- Leere Liste nicht merken (Daten evtl. noch nicht geladen)
    if #out > 0 then dungeonCache = out end
    return out
end
-- Mit neuer Stufe kommen neue Dungeons dazu (z. B. heroisch mit Höchststufe)
local levelWatch = CreateFrame("Frame")
levelWatch:RegisterEvent("PLAYER_LEVEL_UP")
levelWatch:SetScript("OnEvent", function() dungeonCache = nil end)
-- Rollen-Symbole aus Blizzards Gruppensuche (UI-LFG-ICON-PORTRAITROLES, 64×64)
local ROLE_TEX = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:%d:%d:%d:%d|t"
local ROLES = {
    { key = "T", label = "Tank",        color = "|cff6fa8ff", spec = "TANK",    icon = ROLE_TEX:format(0, 19, 22, 41) },
    { key = "H", label = L["Heiler"],   color = "|cff40ff40", spec = "HEALER",  icon = ROLE_TEX:format(20, 39, 1, 20) },
    { key = "D", label = L["DD"],       color = "|cffff6060", spec = "DAMAGER", icon = ROLE_TEX:format(20, 39, 22, 41) },
}
local ROLE_BY_SPEC = { TANK = "T", HEALER = "H", DAMAGER = "D" }
-- Farben der Rollen als Zahlen (für die Füllstand-Punkte)
local ROLE_RGB = { T = { 0.44, 0.66, 1 }, H = { 0.25, 1, 0.25 }, D = { 1, 0.38, 0.38 } }

-- Flüsterzeile an einen Spieler öffnen (neuere Spielversionen: ChatFrameUtil)
local function SendTell(name)
    local f = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
    if f then f(name) end
end

ns.HelpData = {
    DIFFS = DIFFS, DungeonList = DungeonList, DungeonText = DungeonText, HAS_DUNGEON_PICK = HAS_DUNGEON_PICK,
    KeyLabel = KeyLabel, LevelRange = LevelRange, QuestLink = QuestLink, QuestLogList = QuestLogList,
    ROLES = ROLES, ROLE_BY_SPEC = ROLE_BY_SPEC, ROLE_RGB = ROLE_RGB, SendTell = SendTell,
    SuffixDiff = SuffixDiff, TYPES = TYPES,
}
