-- GuildPride: Gruppensuche / Quest-Hilfe
-- Man trägt sich ein, die anderen sehen wer sucht, wie voll die Gruppe ist
-- und welche Rollen noch fehlen – und melden sich selbst.
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP
local EXPIRE = 30 * 60   -- Einträge verfallen nach 30 Minuten
local RESEND = 4 * 60    -- eigenen Eintrag regelmäßig neu senden (falls Nachrichten verloren gingen)
local STALE = 10 * 60    -- fremde Einträge ohne Lebenszeichen ausblenden

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
local ROLES = {
    { key = "T", label = "Tank",        color = "|cff6fa8ff", spec = "TANK" },
    { key = "H", label = L["Heiler"],   color = "|cff40ff40", spec = "HEALER" },
    { key = "D", label = L["DD"],       color = "|cffff6060", spec = "DAMAGER" },
}
local ROLE_BY_SPEC = { TANK = "T", HEALER = "H", DAMAGER = "D" }
-- Farben der Rollen als Zahlen (für die Füllstand-Punkte)
local ROLE_RGB = { T = { 0.44, 0.66, 1 }, H = { 0.25, 1, 0.25 }, D = { 1, 0.38, 0.38 } }

-- Flüsterzeile an einen Spieler öffnen (neuere Spielversionen: ChatFrameUtil)
local function SendTell(name)
    local f = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
    if f then f(name) end
end

local entries = {}   -- [Name-Realm] = { kind, note, level, zone, size, max, needs, role, class, t, seen }
local publicEntries = {}   -- dasselbe vom ganzen Server (offener Kanal), getrennt von der Gilde
local mine           -- eigener Eintrag (mine.public: auch serverweit)
local needs = {}     -- eigene Auswahl: { T = true, H = true }
local picked         -- gewählte Quest aus dem Questlog: { id, level, name }
local pickedDungeon  -- gewählter Dungeon: { name, min, max, diff, keyLevel }
local lastSent = 0
-- Versionsnummer des eigenen Zustands (eingetragen/ausgetragen/Art). Sie steigt
-- bei jeder Änderung; Empfänger ignorieren ältere Stände. Sonst konnte eine
-- verspätete Nachricht (Drosselung, Antwort auf eine Anfrage) einen neueren
-- Eintrag überschreiben und der Eintrag sprang zwischen zwei Arten hin und her.
local stateVer = 0
local function BumpVer() stateVer = math.max(stateVer + 1, GetServerTime()) end
local verBy = {}     -- [Name-Realm] = zuletzt gesehene Version
local alertedAt = {} -- [Name-Realm] = Zeit des letzten Chat-Hinweises
local ALERT_GAP = 60

local function Clean(s, max) return (tostring(s or ""):gsub("[%c|]", "")):sub(1, max) end

local function GroupSize()
    if IsInGroup and IsInGroup() then
        return GetNumGroupMembers(), (IsInRaid() and 40 or 5)
    end
    return 1, 5
end

local function MyRoleKey()
    local r = GuildPrideDB.role
    if not r and GetSpecialization and GetSpecializationRole then
        local spec = GetSpecialization()
        r = spec and GetSpecializationRole(spec)
    end
    return ROLE_BY_SPEC[r or ""] or "D"
end

local function NeedsString(s)
    local out = {}
    for _, r in ipairs(ROLES) do
        if s and s:find(r.key, 1, true) then out[#out + 1] = r.color .. r.label .. "|r" end
    end
    return table.concat(out, ", ")
end

local function RoleLabel(key)
    for _, r in ipairs(ROLES) do if r.key == key then return r.color .. r.label .. "|r" end end
    return ""
end

-- "Sucht Gruppe" allein, "Sucht Mitspieler" wenn man schon eine Gruppe hat
local function KindLabel(kind, size)
    if kind == "group" and (size or 1) > 1 then return L["Sucht Mitspieler"] end
    return TYPES[kind].label
end

---------------------------------------------------------------------
-- Senden / Empfangen
---------------------------------------------------------------------
-- Angebotener Schlüssel aktuell halten (Stufe ändert sich nach einem Lauf)
local function UpdateMyKey()
    if mine and mine.kind == "key" and ns.MyKey then
        local map, level = ns.MyKey()
        if map then mine.map, mine.keyLevel = map, level end
    end
end

---------------------------------------------------------------------
-- Serverweit: offener Kanal je Spielversion (GuildPrideEvents.lua), eigene
-- Nachrichten PLFG/PLFGQ. Erste Felder: Spielversion + Protokoll – passt das
-- nicht, wird verworfen. Kein Gildenname und keine Gildendaten, nur was die
-- Suche braucht; immer einteilig (unter 255 Byte).
---------------------------------------------------------------------
local PROTO = "1"
local PUBLIC_MAX = 300
-- Classic: der Eintrag wird nicht regelmäßig neu gesendet (nur beim Klicken),
-- daher dort erst nach Ablauf (EXPIRE) ausblenden statt nach STALE
local function PublicStale() return ns.PUBLIC_VIA_CHAT and EXPIRE or STALE end
local FACTION = { Alliance = "A", Horde = "H" }
local publicLive = false   -- steht gerade ein eigener Eintrag im offenen Kanal?
local lastPublicSent = 0
local pubVerBy = {}        -- wie verBy, nur für den offenen Kanal
local publicAt = {}        -- ["Name-Realm:Art"] = letzte angenommene Nachricht

-- Auf Bytes kürzen, ohne ein Umlaut-Zeichen (UTF-8) zu zerschneiden
local function Short(s, max)
    s = Clean(s, max)
    if #s == max then s = s:gsub("[\192-\255][\128-\191]*$", "") end
    return s
end

local function MyFaction() return FACTION[UnitFactionGroup("player") or ""] or "" end

local function PublicNone()
    return ns.CLIENT_TAG, PROTO, "none", "", 0, "", 0, 0, "", "", "", stateVer
end

local function PublicFields()
    local size, max = GroupSize()
    local _, class = UnitClass("player")
    local q, d = mine.quest, mine.dungeon
    return ns.CLIENT_TAG, PROTO, mine.kind, Short(mine.note, 48), UnitLevel("player"),
        Short(GetZoneText(), 24), size, max, mine.needs or "", MyRoleKey(), class or "", stateVer,
        mine.map or 0, mine.keyLevel or 0, q and q.id or 0, q and q.level or 0, q and Short(q.name, 36) or "",
        d and Short(d.name, 36) or "", d and d.min or 0, d and d.max or 0, d and d.diff or "", d and d.keyLevel or 0,
        MyFaction()
end

-- Classic: in den offenen Kanal darf nur direkt aus einem Klick geschrieben
-- werden (normale Chatnachricht). Klick-Handler laufen deshalb über ByClick.
local userClick = false
local function ByClick(fn, ...)
    userClick = true
    local ok, err = pcall(fn, ...)
    userClick = false
    if not ok then geterrorhandler()(err) end
end

-- target: Antwort auf eine Abfrage per Flüstern; sonst Rundsendung in den Kanal
local function SendPublic(target)
    if not ns.PublicLFGOn() then return end
    if target then
        if mine and mine.public then ns.QueuePublicTo(target, "PLFG", PublicFields()) end
        return
    end
    if ns.PUBLIC_VIA_CHAT and not userClick then return end
    local function Send(...)
        if ns.PUBLIC_VIA_CHAT then ns.SendPublicChat("PLFG", ...) else ns.Queue("PLFG", "@PUBLIC", ...) end
    end
    if mine and mine.public then
        Send(PublicFields())
        publicLive, lastPublicSent = true, GetServerTime()
    elseif publicLive then
        Send(PublicNone())
        publicLive = false
    end
end

-- Abfrage an alle im offenen Kanal (beim Öffnen, Klick auf Server/Alle)
local lastPublicAsk = 0
local function AskPublic()
    if not (ns.PublicChannelId and ns.PublicChannelId()) or GetTime() - lastPublicAsk < 30 then return end
    if ns.PUBLIC_VIA_CHAT and not userClick then return end
    lastPublicAsk = GetTime()
    if ns.PUBLIC_VIA_CHAT then ns.SendPublicChat("PLFGQ", ns.CLIENT_TAG, PROTO)
    else ns.Queue("PLFGQ", "@PUBLIC", ns.CLIENT_TAG, PROTO) end
end

local function SendMine(target)
    if mine then
        UpdateMyKey()
        local size, max = GroupSize()
        local _, class = UnitClass("player")
        -- Felder 11/12: Schlüssel (ältere Versionen ignorieren sie und kennen "key" nicht)
        -- Felder 13–15: verlinkte Quest (ID, Stufe, Name)
        -- Felder 16–20: Dungeon (Name, Levelbereich, Schwierigkeit N/H/M/K, M+-Stufe)
        local q, d = mine.quest, mine.dungeon
        ns.Queue("LFG", target, mine.kind, mine.note, UnitLevel("player"), GetZoneText() or "",
            size, max, mine.needs or "", MyRoleKey(), class or "", stateVer, mine.map or 0, mine.keyLevel or 0,
            q and q.id or 0, q and q.level or 0, q and Clean(q.name, 50) or "",
            d and Clean(d.name, 40) or "", d and d.min or 0, d and d.max or 0, d and d.diff or "", d and d.keyLevel or 0)
        if not target then lastSent = GetServerTime() end
    elseif not target then
        ns.Queue("LFG", nil, "none", "", 0, "", 0, 0, "", "", "", stateVer)
    end
    if not target then SendPublic() end
    -- Rundsendung zusätzlich an die Gildenleitung flüstern (Rangrechte)
    if not target and ns.TellLeaders then ns.TellLeaders(SendMine) end
end

-- Eigener Eintrag als Listenzeile (wird nicht über das Netz empfangen)
local function MyEntry()
    local size, max = GroupSize()
    local _, class = UnitClass("player")
    return { kind = mine.kind, note = mine.note, level = UnitLevel("player"), zone = GetZoneText() or "",
             size = size, max = max, needs = mine.needs or "", role = MyRoleKey(), class = class or "",
             map = mine.map, keyLevel = mine.keyLevel, t = mine.t, self = true,
             questId = mine.quest and mine.quest.id or 0, questLevel = mine.quest and mine.quest.level or 0,
             questName = mine.quest and mine.quest.name or "", dungeon = mine.dungeon }
end

-- Eintrag aus einer fremden Nachricht (Gilde oder offener Kanal). Zweiter
-- Rückgabewert: Chat-Hinweis fällig (neu, höchstens einer pro Spieler und Minute)
local function BuildEntry(old, sender, kind, note, level, zone, size, max, need, role, class,
                          map, keyLevel, questId, questLevel, questName, dName, dMin, dMax, dDiff, dKey)
    local isNew = not old or old.kind ~= kind
    local now = GetServerTime()
    local alert = isNew and now - (alertedAt[sender] or 0) >= ALERT_GAP
    if alert then alertedAt[sender] = now end
    -- Zahlen begrenzen (fremde Nachricht: keine Riesenwerte oder Kommazahlen)
    local N = ns.Num
    local e = { kind = kind, note = Clean(note, 60), level = N(level, 0, 999) or 0, zone = Clean(zone, 40),
                size = N(size, 1, 40) or 1, max = N(max, 1, 40) or 5, needs = Clean(need, 3),
                role = Clean(role, 1), class = Clean(class, 20), t = old and old.t or now,
                map = N(map, 0, 99999) or 0, keyLevel = N(keyLevel, 0, 999) or 0, seen = now,
                questId = N(questId, 0, 9999999) or 0, questLevel = N(questLevel, 0, 999) or 0,
                questName = Clean(questName, 50) }
    dName = Clean(dName, 40)
    if dName ~= "" then
        e.dungeon = { name = dName, min = N(dMin, 0, 999) or 0, max = N(dMax, 0, 999) or 0,
                      diff = Clean(dDiff, 1), keyLevel = N(dKey, 0, 999) or 0 }
    end
    if isNew then e.t = now end
    return e, alert
end

local function Alert(sender, e)
    local extra = (" · " .. L["Gruppe %d/%d"]):format(e.size, e.max)
    if e.kind == "key" then extra = " · " .. KeyLabel(e.map, e.keyLevel) .. extra end
    if e.questId > 0 then extra = " · " .. QuestLink(e.questId, e.questLevel, e.questName) .. extra end
    if e.dungeon then extra = " · |cff66ccff" .. DungeonText(e.dungeon) .. "|r" .. extra end
    if e.needs ~= "" then extra = extra .. " · " .. (L["Sucht noch: %s"]):format(NeedsString(e.needs)) end
    local who = e.public and (Ambiguate(sender, "none") .. " |cff8fb3ff[" .. L["Server"] .. "]|r") or Ambiguate(sender, "guild")
    ns.Print(("%s%s|r: |cffffd100%s|r (Lvl %d, %s)%s%s"):format(TYPES[e.kind].color, KindLabel(e.kind, e.size),
        who, e.level, e.zone, extra, e.note ~= "" and (" – " .. e.note) or ""))
    if GuildPrideDB.sound then PlaySound(SOUNDKIT.TELL_MESSAGE) end
end

ns.On("LFG", function(payload, sender)
    if sender == ns.Me() then return end
    local kind, note, level, zone, size, max, need, role, class, ver, map, keyLevel, questId, questLevel, questName,
          dName, dMin, dMax, dDiff, dKey = strsplit(SEP, payload)
    -- Älteren Stand als den schon bekannten ignorieren (ältere Versionen senden keine Nummer)
    ver = ns.Stamp(ver)   -- nicht in der Zukunft, sonst wären spätere Einträge gesperrt
    if ver > 0 then
        if verBy[sender] and ver < verBy[sender] then return end
        verBy[sender] = ver
    end
    if kind == "none" or not TYPES[kind] then
        entries[sender] = nil
    else
        local e, alert = BuildEntry(entries[sender], sender, kind, note, level, zone, size, max, need, role, class,
            map, keyLevel, questId, questLevel, questName, dName, dMin, dMax, dDiff, dKey)
        entries[sender] = e
        if alert and GuildPrideDB.helpAlerts ~= false then Alert(sender, e) end
    end
    if ns.RefreshUI then ns.RefreshUI() end
end)

-- Offener Kanal: nur PLFG/PLFGQ mit eigener Spielversion; Ignorierte und
-- selbst Gesperrte bleiben draußen; pro Absender begrenzt
local function TooSoon(key, gap)
    local now = GetTime()
    if publicAt[key] and now - publicAt[key] < gap then return true end
    publicAt[key] = now
    return false
end

local function Blocked(name)
    if GuildPrideDB.lfgBlocked and GuildPrideDB.lfgBlocked[name] then return true end
    local short = Ambiguate(name, "none")
    if C_FriendList and C_FriendList.IsIgnored then return C_FriendList.IsIgnored(short) and true or false end
    return IsIgnored and IsIgnored(short) and true or false
end

-- Kein Platz mehr: der am längsten stumme Eintrag fliegt raus
local function MakeRoom()
    local n, oldest, oldestT = 0, nil, math.huge
    for name, e in pairs(publicEntries) do
        n = n + 1
        if e.seen < oldestT then oldest, oldestT = name, e.seen end
    end
    if n >= PUBLIC_MAX and oldest then publicEntries[oldest] = nil end
end

local function OnPublicEntry(payload, sender)
    local kind, note, level, zone, size, max, need, role, class, ver, map, keyLevel, questId, questLevel, questName,
          dName, dMin, dMax, dDiff, dKey, faction = strsplit(SEP, payload)
    ver = ns.Stamp(ver)
    if ver > 0 then
        if pubVerBy[sender] and ver < pubVerBy[sender] then return end
        pubVerBy[sender] = ver
    end
    faction = Clean(faction, 1)
    -- Die andere Fraktion kann man weder einladen noch anfragen
    if kind == "none" or not TYPES[kind] or (faction ~= "" and faction ~= MyFaction()) then
        publicEntries[sender] = nil
    else
        if TooSoon(sender .. ":E", 3) then return end
        local old = publicEntries[sender]
        if not old then MakeRoom() end
        local e, alert = BuildEntry(old, sender, kind, note, level, zone, size, max, need, role, class,
            map, keyLevel, questId, questLevel, questName, dName, dMin, dMax, dDiff, dKey)
        e.public, e.faction = true, faction
        publicEntries[sender] = e
        -- Gildenmitglieder melden sich schon über die Gilde
        if alert and GuildPrideDB.publicAlerts and not entries[sender] then Alert(sender, e) end
    end
    if ns.RefreshUI then ns.RefreshUI() end
end

-- whisper: kam per Flüstern (Antwort auf unsere Abfrage) – dann nur Einträge
function ns.OnPublicMessage(message, sender, whisper)
    if not ns.PublicLFGOn() then return end
    -- Eigene Nachrichten kommen aus dem Kanal zurück: zeigt, dass der Kanal sie durchreicht
    if sender == ns.Me() then
        if not whisper then ns.publicStats.echo = ns.publicStats.echo + 1 end
        return
    end
    ns.publicStats.received = ns.publicStats.received + 1
    local kind, value = message:match("^(%u+):(.*)$")
    if kind ~= "PLFG" and (kind ~= "PLFGQ" or whisper) then return end
    local tag, proto, rest = value:match("^([^\031]*)\031([^\031]*)\031?(.*)$")
    if tag ~= ns.CLIENT_TAG or proto ~= PROTO or Blocked(sender) then return end
    if kind == "PLFG" then return OnPublicEntry(rest, sender) end
    -- Abfrage: nur wer selbst serverweit eingetragen ist, antwortet – mit
    -- Zufallsverzögerung. Classic: per Flüstern an den Fragenden (in den Kanal
    -- ginge nur beim Klicken); sonst in den Kanal, außer der Eintrag ging gerade erst raus
    if TooSoon(sender .. ":Q", 30) or not (mine and mine.public) then return end
    C_Timer.After(1 + math.random() * 7, function()
        if not (mine and mine.public) then return end
        if ns.PUBLIC_VIA_CHAT then SendPublic(sender)
        elseif GetServerTime() - lastPublicSent >= 60 then SendPublic() end
    end)
end

-- Option an/aus (Einstellungen, /gp server)
function ns.PublicLFGChanged()
    if ns.PublicLFGOn() then
        ns.UpdatePublicChannel()
        -- nach dem Beitritt den eigenen Eintrag nachliefern
        if mine and mine.public then C_Timer.After(8, SendPublic) end
    else
        -- Eintrag bei den anderen zurückziehen, dann den Kanal verlassen
        local farewell
        if publicLive and (userClick or not ns.PUBLIC_VIA_CHAT) then
            local parts = { PublicNone() }
            for i = 1, #parts do parts[i] = tostring(parts[i]) end
            farewell = "PLFG:" .. table.concat(parts, SEP)
        end
        publicLive = false
        wipe(publicEntries)
        ns.UpdatePublicChannel(farewell)
    end
    if ns.RefreshUI then ns.RefreshUI() end
end

-- REQ: Login-Abgleich aller Module · LFGQ: jemand hat die Gruppensuche geöffnet
for _, k in ipairs({ "REQ", "LFGQ" }) do
    ns.On(k, function(_, sender)
        if sender ~= ns.Me() then SendMine(sender) end
    end)
end

-- Eigenen Eintrag regelmäßig erneuern bzw. nach Ablauf austragen
C_Timer.NewTicker(60, function()
    local now = GetServerTime()
    -- Einträge vom Server ohne Lebenszeichen und alte Zähler wegräumen
    for name, e in pairs(publicEntries) do
        if now - e.t > EXPIRE or now - e.seen > PublicStale() then publicEntries[name] = nil end
    end
    for k, t in pairs(publicAt) do if GetTime() - t > 60 then publicAt[k] = nil end end
    if not mine then return end
    if now - mine.t > EXPIRE then
        mine = nil
        BumpVer()
        SendMine()
        ns.Print(L["Dein Eintrag in der Gruppensuche ist abgelaufen."])
        if ns.RefreshUI then ns.RefreshUI() end
    elseif now - lastSent >= RESEND then
        SendMine()
    end
end)

-- Gruppengröße ändert sich -> Eintrag automatisch aktualisieren
local pendingUpdate
local grp = CreateFrame("Frame")
grp:RegisterEvent("GROUP_ROSTER_UPDATE")
grp:RegisterEvent("ZONE_CHANGED_NEW_AREA")
grp:SetScript("OnEvent", function()
    if not mine or pendingUpdate then return end
    pendingUpdate = C_Timer.NewTimer(2, function()
        pendingUpdate = nil
        if not mine then return end
        -- Gruppe voll -> Eintrag löschen
        local n, max = GroupSize()
        if n >= max then
            mine = nil
            BumpVer()
            ns.Print(L["Deine Gruppe ist voll – du bist abgemeldet."])
        end
        SendMine()
        if ns.RefreshUI then ns.RefreshUI() end
    end)
end)

---------------------------------------------------------------------
-- UI-Reiter
---------------------------------------------------------------------
local page = ns.AddTab(L["Gruppensuche"], 40)

local hint = page:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
hint:SetPoint("TOPLEFT", 2, -2)
hint:SetText(L["Quest oder Dungeon und fehlende Rollen wählen, dann anmelden."])
hint:SetWidth(520); hint:SetJustifyH("LEFT"); hint:SetWordWrap(false)

-- Eigenen Eintrag auch serverweit zeigen (nur wenn die Option an ist)
local pubCheck = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
pubCheck:SetSize(22, 22)
pubCheck:SetPoint("TOPRIGHT", -78, 4)
local pubLabel = page:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
pubLabel:SetPoint("LEFT", pubCheck, "RIGHT", 2, 0)
pubLabel:SetText(L["Serverweit"])
pubCheck:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L["Serverweit"], 1, 1, 1)
    GameTooltip:AddLine(L["Eintrag auch allen mit GuildPride auf dem Server zeigen (gleiche Spielversion, ohne Gildenname)."],
        0.8, 0.8, 0.8, true)
    if ns.PUBLIC_VIA_CHAT then
        GameTooltip:AddLine(L["Classic: Dein Eintrag geht beim Eintragen in den Kanal; wer die Gruppensuche öffnet, bekommt ihn per Flüstern."],
            0.6, 0.8, 1, true)
    end
    GameTooltip:Show()
end)
pubCheck:HookScript("OnLeave", function() GameTooltip:Hide() end)
pubCheck:SetScript("OnClick", function(self)
    GuildPrideDB.lfgPublic = self:GetChecked() and true or false
    if mine then
        mine.public = GuildPrideDB.lfgPublic
        BumpVer()
        ByClick(SendMine)
    end
    ns.RefreshUI()
end)

-- Auswahlknöpfe: Quest aus dem Questlog, Dungeon aus der Dungeonliste
local function PickButton(anchor, width, text, tipTitle, tipText)
    local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    if anchor then b:SetPoint("LEFT", anchor, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 8, -22) end
    b:SetText(text)
    b:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(tipTitle, 1, 1, 1)
        GameTooltip:AddLine(tipText, 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end
local bQuestPick = PickButton(nil, 66, L["Quest"], L["Quest verlinken"], L["Quest aus deinem Questlog wählen"])
local bDungeonPick = PickButton(bQuestPick, 74, L["Dungeon"], L["Dungeon wählen"],
    L["Dungeon, Schwierigkeit und Stufe für deinen Eintrag"])

-- Auswahlliste unter einem Knopf (eigene Liste, gleich in allen Spielversionen);
-- top: Platz für eine Kopfzeile (z. B. Suchfeld)
local PICK_H, PICK_W = 20, 290
local function MakePicker(anchor, top)
    local p = CreateFrame("Frame", nil, page)
    p:SetFrameStrata("DIALOG")
    p:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    p:SetWidth(PICK_W + 30)
    p:EnableMouse(true)
    p:Hide()
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.04, 0.04, 0.97)
    local edge = p:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT"); edge:SetPoint("TOPRIGHT"); edge:SetHeight(2)
    ns.Paint(edge, "accent")
    local scroll = ns.NewScroll(p)
    scroll:SetPoint("TOPLEFT", 4, -6 - top)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(PICK_W, 1)
    scroll:SetScrollChild(child)
    local rows = {}
    -- items: { text, onClick }
    function p:Fill(items)
        for i, it in ipairs(items) do
            local b = rows[i]
            if not b then
                b = CreateFrame("Button", nil, child)
                b:SetSize(PICK_W, PICK_H)
                b:SetPoint("TOPLEFT", 0, -(i - 1) * PICK_H)
                b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                b.text = b:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
                b.text:SetPoint("LEFT", 6, 0); b.text:SetPoint("RIGHT", -4, 0)
                b.text:SetJustifyH("LEFT"); b.text:SetWordWrap(false)
                rows[i] = b
            end
            b.text:SetText(it.text)
            local onClick = it.onClick
            b:SetScript("OnClick", onClick and function(...) ByClick(onClick, ...) end)
            b:Show()
        end
        for i = #items + 1, #rows do rows[i]:Hide() end
        child:SetHeight(math.max(1, #items * PICK_H))
        p:SetHeight(top + math.max(1, math.min(#items, 14)) * PICK_H + 10)
        scroll:SetVerticalScroll(0)
    end
    -- Platz oberhalb der Liste ändern (z. B. wenn Knöpfe ausgeblendet sind)
    function p:SetTop(t)
        top = t
        scroll:SetPoint("TOPLEFT", 4, -6 - top)
    end
    page:HookScript("OnHide", function() p:Hide() end)
    return p
end

-- Nach einer Auswahl: schon eingetragen -> Eintrag gleich erneuern
local function ApplyPicks()
    if mine then
        mine.quest, mine.dungeon = picked, pickedDungeon
        BumpVer()
        SendMine()
    end
    ns.RefreshUI()
end

-- Quest
local questPicker = MakePicker(bQuestPick, 0)
local function OpenQuestPicker()
    local list = QuestLogList()
    if #list == 0 then
        ns.Print(L["Dein Questlog ist leer."])
        return
    end
    local function Pick(q) picked = q; questPicker:Hide(); ApplyPicks() end
    local items = { { text = "|cff999999" .. L["Keine Quest"] .. "|r", onClick = function() Pick(nil) end } }
    for _, q in ipairs(list) do
        items[#items + 1] = { text = ("|cff999999[%d]|r |cffffd100%s|r"):format(q.level, q.name),
                              onClick = function() Pick(q) end }
    end
    questPicker:Fill(items)
    questPicker:Show()
end

-- Dungeon: Suchfeld, darunter Schwierigkeit
local hasDiff = #DIFFS > 1
local dungeonPicker = MakePicker(bDungeonPick, hasDiff and 56 or 30)
local search = CreateFrame("EditBox", nil, dungeonPicker, "InputBoxTemplate")
search:SetSize(200, 20)
search:SetPoint("TOPLEFT", 12, -8)
search:SetAutoFocus(false)
local searchHint = search:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
searchHint:SetPoint("LEFT", 2, 0)
searchHint:SetText(L["Suchen …"])

local diffSel = hasDiff and DIFFS[1].key or "N"
local diffBtns = {}
local FillDungeons
local function UpdateDiffButtons()
    for key, b in pairs(diffBtns) do
        if b.gpBg then b.gpBg:SetTexture(ns.MEDIA .. (key == diffSel and "nav_active" or "nav")) end
        if key == diffSel then b:LockHighlight() else b:UnlockHighlight() end
    end
end
if hasDiff then
    for _, d in ipairs(DIFFS) do
        local b = CreateFrame("Button", nil, dungeonPicker, "UIPanelButtonTemplate")
        b:SetSize(64, 20)
        b:SetText(d.label)
        b:SetScript("OnClick", function() diffSel = d.key; UpdateDiffButtons(); FillDungeons() end)
        diffBtns[d.key] = b
    end
end

-- Nur Schwierigkeiten anbieten, die der Charakter gerade laufen kann: Der
-- Gruppenbrowser liefert nur Dungeons passend zur Stufe (heroisch erst ab
-- Höchststufe). Bleibt nur eine übrig, entfallen die Knöpfe ganz.
local function LayoutDiffButtons()
    if not hasDiff then return end
    local have = {}
    for _, d in ipairs(DungeonList()) do
        for key in pairs(d.diffs) do have[key] = true end
    end
    local avail = {}
    for _, d in ipairs(DIFFS) do
        if have[d.key] then avail[#avail + 1] = d.key end
    end
    local show = #avail > 1
    for _, b in pairs(diffBtns) do b:Hide() end
    if show then
        for i, key in ipairs(avail) do
            local b = diffBtns[key]
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 8 + (i - 1) * 68, -32)
            b:Show()
        end
    end
    dungeonPicker:SetTop(show and 56 or 30)
    if not have[diffSel] then diffSel = avail[1] or "N" end
    UpdateDiffButtons()
end

function FillDungeons()
    local filter = search:GetText():lower()
    local function Pick(d)
        local v = d and d.diffs[diffSel]
        pickedDungeon = v and { name = d.name, min = v.min, max = v.max, diff = hasDiff and diffSel or "", keyLevel = 0 } or nil
        dungeonPicker:Hide()
        ApplyPicks()
    end
    local items = { { text = "|cff999999" .. L["Kein Dungeon"] .. "|r", onClick = function() Pick(nil) end } }
    -- Nur Dungeons, die es in der gewählten Schwierigkeit gibt
    local any
    for _, d in ipairs(DungeonList()) do
        local v = d.diffs[diffSel]
        if v then
            any = true
            if filter == "" or d.name:lower():find(filter, 1, true) then
                local lv = LevelRange(v.min, v.max)
                items[#items + 1] = { text = (lv ~= "" and ("|cff999999[%s]|r "):format(lv) or "") .. "|cff66ccff" .. d.name .. "|r",
                                      onClick = function() Pick(d) end }
            end
        end
    end
    if not any then
        items[#items + 1] = { text = "|cff888888" .. L["Für deine Stufe gibt es keine Dungeons in dieser Schwierigkeit."] .. "|r",
                              onClick = function() end }
    end
    dungeonPicker:Fill(items)
end
search:SetScript("OnTextChanged", function(self)
    searchHint:SetShown(self:GetText() == "")
    if dungeonPicker:IsShown() then FillDungeons() end
end)
search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local function OpenDungeonPicker()
    if #DungeonList() == 0 then
        ns.Print(L["Keine Dungeonliste verfügbar."])
        return
    end
    dungeonPicker:Show()
    search:SetText("")
    LayoutDiffButtons()
    FillDungeons()
end

bQuestPick:SetScript("OnClick", function()
    dungeonPicker:Hide()
    if questPicker:IsShown() then questPicker:Hide() else OpenQuestPicker() end
end)
bDungeonPick:SetScript("OnClick", function()
    questPicker:Hide()
    if dungeonPicker:IsShown() then dungeonPicker:Hide() else OpenDungeonPicker() end
end)
-- Retail: ohne Dungeon-Knopf
if not HAS_DUNGEON_PICK then bDungeonPick:Hide() end

local needLabel = page:CreateFontString(nil, "OVERLAY", "GPFont_Text")
needLabel:SetPoint("LEFT", HAS_DUNGEON_PICK and bDungeonPick or bQuestPick, "RIGHT", 16, 0)
needLabel:SetText(L["Fehlt noch:"])

local needBtns = {}
local function UpdateNeedButtons()
    for _, r in ipairs(ROLES) do
        local b = needBtns[r.key]
        if b.gpBg then b.gpBg:SetTexture(ns.MEDIA .. (needs[r.key] and "nav_active" or "nav")) end
        if needs[r.key] then b:LockHighlight() else b:UnlockHighlight() end
    end
end
local function NeedsCode()
    local s = ""
    for _, r in ipairs(ROLES) do if needs[r.key] then s = s .. r.key end end
    return s
end

local prev = needLabel
for _, r in ipairs(ROLES) do
    local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    b:SetSize(74, 22)
    b:SetPoint("LEFT", prev, "RIGHT", prev == needLabel and 8 or 4, 0)
    b:SetText(r.label)
    b:SetScript("OnClick", function()
        needs[r.key] = not needs[r.key] or nil
        UpdateNeedButtons()
        -- schon angemeldet: gesuchte Rollen sofort im Eintrag aktualisieren
        if mine then
            mine.needs = NeedsCode()
            BumpVer()
            SendMine()
            ns.RefreshUI()
        end
    end)
    needBtns[r.key] = b
    prev = b
end

local function Set(kind)
    if kind == "key" and not (ns.MyKey and ns.MyKey()) then
        ns.Print(L["Du hast gerade keinen Schlüsselstein."])
        return
    end
    if kind then
        mine = { kind = kind, note = "", needs = NeedsCode(), quest = picked, dungeon = pickedDungeon,
                 t = GetServerTime(), public = ns.PublicLFGOn() and GuildPrideDB.lfgPublic or false }
        UpdateMyKey()
        ns.Print(L["Du bist eingetragen: "] .. KindLabel(kind, (GroupSize())))
    else
        mine = nil
        ns.Print(L["Du bist ausgetragen."])
    end
    BumpVer()
    SendMine()
    ns.RefreshUI()
end

-- Knopfleiste: links eintragen / austragen, rechts die Schlüssel-Ansicht (Retail)
-- Anmelden: mit gewählter Quest (ohne Dungeon) als Quest-Hilfe, sonst als Gruppensuche
local bSignUp = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
bSignUp:SetSize(108, 24); bSignUp:SetPoint("TOPLEFT", 4, -52); bSignUp:SetText(L["Anmelden"])
bSignUp:SetScript("OnClick", function() ByClick(Set, (picked and not pickedDungeon) and "quest" or "group") end)
local bSignOff = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
bSignOff:SetSize(108, 24); bSignOff:SetPoint("LEFT", bSignUp, "RIGHT", 4, 0); bSignOff:SetText(L["Abmelden"])
bSignOff:SetScript("OnClick", function() ByClick(Set, nil) end)
local bOffer = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
bOffer:SetSize(132, 24); bOffer:SetPoint("LEFT", bSignOff, "RIGHT", 4, 0); bOffer:SetText(L["Schlüssel anbieten"])
bOffer:SetScript("OnClick", function() ByClick(Set, "key") end)
bOffer:SetShown(TYPES.key ~= nil)

-- Ansicht "Schlüssel der Gilde" (nur Retail, siehe GuildPrideKeys.lua)
local keysView = false
local keysHolder, keysList, keysEmpty
local bKeys = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
bKeys:SetSize(140, 24); bKeys:SetPoint("TOPRIGHT", -2, -52)
bKeys:SetShown(ns.GuildKeys ~= nil)
if ns.GuildKeys then
    keysHolder = CreateFrame("Frame", nil, page)
    keysHolder:SetPoint("TOPLEFT", 0, -96)
    keysHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    keysHolder:Hide()
    keysList = ns.CreateList(keysHolder, 24)
    keysEmpty = keysHolder:CreateFontString(nil, "OVERLAY", "GPFont_Muted")
    keysEmpty:SetPoint("TOP", 0, -76)
    keysEmpty:SetText(L["Noch keine Schlüssel bekannt (nur Mitglieder mit GuildPride)."])
    bKeys:SetScript("OnClick", function()
        keysView = not keysView
        if keysView and ns.AskKeys then ns.AskKeys() end
        page:Refresh()
    end)
end

-- Blizzards Dungeonbrowser (nur Forever): klickt den Blizzard-Knopf der Menüleiste.
-- Unser Fenster liegt höher und würde den Browser verdecken, schließt sich also.
if ns.IS_FOREVER and LFDMicroButton then
    local bBrowser = ns.SecureClickButton(page, 140, L["Dungeonbrowser"], LFDMicroButton)
    bBrowser:SetPoint("TOPRIGHT", -2, -52)
    bBrowser:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Dungeonbrowser"], 1, 1, 1)
        GameTooltip:AddLine(L["Öffnet Blizzards Dungeonbrowser. Dein Eintrag in der Gruppensuche bleibt bestehen."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    bBrowser:HookScript("OnLeave", function() GameTooltip:Hide() end)
    bBrowser:HookScript("OnClick", function()
        if not LFDMicroButton:IsEnabled() then
            local reason = LFDMicroButton.GetGroupFinderDisabledTooltip and LFDMicroButton:GetGroupFinderDisabledTooltip()
            ns.Print(type(reason) == "string" and reason ~= "" and reason or L["Der Dungeonbrowser ist gerade nicht verfügbar."])
            return
        end
        -- Kurz warten: Blizzard lädt das Fenster beim ersten Öffnen erst nach
        C_Timer.After(0.1, function()
            if LFGParentFrame and LFGParentFrame:IsShown() and not InCombatLockdown() then GuildPrideFrame:Hide() end
        end)
    end)
end

-- Eigener Status in einer eigenen Zeile unter den Knöpfen
local status = page:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
status:SetPoint("TOPLEFT", 6, -82)
status:SetJustifyH("LEFT")

-- Welche Einträge zeigen: Gilde · Server · Alle (rechts neben dem Status)
local SCOPES = { { key = "guild", label = L["Gilde"] }, { key = "server", label = L["Server"] }, { key = "all", label = L["Alle"] } }
local scopeBtns = {}
local function Scope()
    if not ns.PublicLFGOn() then return "guild" end
    return GuildPrideDB.lfgScope or "all"
end
for i, s in ipairs(SCOPES) do
    local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    b:SetSize(64, 20)
    b:SetPoint("TOPRIGHT", -2 - (#SCOPES - i) * 66, -76)
    b:SetText(s.label)
    b:SetScript("OnClick", function()
        GuildPrideDB.lfgScope = s.key
        page:Refresh()
        if s.key ~= "guild" then ByClick(AskPublic) end
    end)
    scopeBtns[s.key] = b
end
local function UpdateScopeButtons(show)
    local cur = Scope()
    for key, b in pairs(scopeBtns) do
        b:SetShown(show)
        if b.gpBg then b.gpBg:SetTexture(ns.MEDIA .. (key == cur and "nav_active" or "nav")) end
        if key == cur then b:LockHighlight() else b:UnlockHighlight() end
    end
end

-- Liste: Titel groß oben, darunter zwei Zeilen; scrollbar bei vielen Einträgen
local ROW_H, ROW_W, rows = 60, 624, {}
local listScroll = ns.NewScroll(page)
listScroll:SetPoint("TOPLEFT", 0, -98)
listScroll:SetPoint("BOTTOMRIGHT", -26, 0)
local listChild = CreateFrame("Frame", nil, listScroll)
listChild:SetSize(ROW_W, 1)
listScroll:SetScrollChild(listChild)

local function GetRow(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, listChild)
    r:SetSize(ROW_W, ROW_H - 2)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    ns.Paint(r.bg, "glow", i % 2 == 0 and 0.05 or 0.02)
    r.edge = r:CreateTexture(nil, "BORDER"); r.edge:SetPoint("TOPLEFT"); r.edge:SetPoint("BOTTOMLEFT"); r.edge:SetWidth(3)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(30, 30); r.icon:SetPoint("LEFT", 10, 0)
    -- Titel: der oben eingegebene Text, sonst die Art des Eintrags
    r.title = r:CreateFontString(nil, "OVERLAY", "GPFont_Large"); r.title:SetPoint("TOPLEFT", 50, -6)
    r.title:SetWidth(420); r.title:SetJustifyH("LEFT"); r.title:SetWordWrap(false)
    r.name = r:CreateFontString(nil, "OVERLAY", "GPFont_TextBold"); r.name:SetPoint("TOPLEFT", 50, -25)
    r.info = r:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall"); r.info:SetPoint("LEFT", r.name, "RIGHT", 10, 0)
    r.line2 = r:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall"); r.line2:SetPoint("BOTTOMLEFT", 50, 7)
    r.line2:SetWidth(420); r.line2:SetJustifyH("LEFT"); r.line2:SetWordWrap(false)
    -- Quest-Link: Maus drüber zeigt die Quest, Klick öffnet sie, Shift-Klick postet sie im Chat
    if r.SetHyperlinksEnabled then
        r:SetHyperlinksEnabled(true)
        r:SetScript("OnHyperlinkEnter", function(self, link)
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then GameTooltip:Show() else GameTooltip:Hide() end
        end)
        r:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
        r:SetScript("OnHyperlinkClick", function(_, link, text, button) pcall(SetItemRef, link, text, button) end)
    end
    -- Gruppen-Füllstand als Punkte
    r.pips = {}
    for p = 1, 5 do
        local t = r:CreateTexture(nil, "ARTWORK")
        t:SetSize(9, 9)
        t:SetPoint("RIGHT", r, "RIGHT", -112 - (5 - p) * 12, 8)
        r.pips[p] = t
    end
    r.count = r:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall"); r.count:SetPoint("TOPRIGHT", r, "TOPRIGHT", -112, -36)
    r.tell = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.tell:SetSize(96, 24); r.tell:SetPoint("RIGHT", -6, 0); r.tell:SetText(L["Beitreten"])
    -- Rechtsklick: trotzdem anflüstern
    r.tell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.tell:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if self.whisperOnly then
            GameTooltip:SetText(L["Gruppenleiter anflüstern"], 1, 1, 1)
            GameTooltip:AddLine(L["Im Dungeonbrowser fragt man per Flüstern, ob man mit darf."], 0.8, 0.8, 0.8, true)
        else
            GameTooltip:SetText(L["Linksklick: Beitritt anfragen bzw. einladen"], 1, 1, 1)
            GameTooltip:AddLine(L["Rechtsklick: anflüstern"], 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    r.tell:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- Einträge vom Server: Spieler in der Gruppensuche ausblenden
    r.block = CreateFrame("Button", nil, r)
    r.block:SetSize(14, 14); r.block:SetPoint("TOPRIGHT", -4, -2)
    r.block:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    r.block:SetHighlightTexture("Interface\\Buttons\\UI-StopButton", "ADD")
    r.block:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Ignorieren"], 1, 1, 1)
        GameTooltip:AddLine(L["Diesen Spieler in der Gruppensuche ausblenden"], 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    r.block:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end
local empty = page:CreateFontString(nil, "OVERLAY", "GPFont_Muted")
empty:SetPoint("TOP", 0, -160)
empty:SetText(L["Gerade sucht niemand Hilfe."])

-- Beitritt anfragen bzw. einladen; ohne passende Spielfunktion wird angeflüstert
local function JoinOrInvite(target, mode)
    local P = C_PartyInfo or {}
    if mode == "invite" then
        local invite = P.InviteUnit or InviteUnit
        if invite then
            invite(target)
            ns.Print((L["Einladung an |cffffd100%s|r gesendet."]):format(target))
            return
        end
    elseif P.RequestInviteFromUnit then
        local r = { tank = false, healer = false, dps = false }
        local key = MyRoleKey()
        if key == "T" then r.tank = true elseif key == "H" then r.healer = true else r.dps = true end
        P.RequestInviteFromUnit(target, r.tank, r.healer, r.dps)
        ns.Print((L["Beitrittsanfrage an |cffffd100%s|r gesendet."]):format(target))
        return
    end
    SendTell(target)
end

local function Ago(now, t)
    local m = math.floor((now - t) / 60)
    return m < 1 and L["gerade eben"] or (L["vor %d Min."]):format(m)
end

-- Ergebnisse aus Blizzards Dungeonbrowser (nur Forever). Blizzard hält nur eine
-- Ergebnisliste: Auch eine Suche im Blizzard-Fenster landet also hier.
local BROWSER = (ns.IS_FOREVER and C_LFGList and C_LFGList.Search and C_LFGList.GetSearchResultInfo) and {
    icon = "Interface\\Icons\\INV_Misc_GroupLooking",
    max = 40,
}

-- Während der Chat-Sperre sind die Werte geheim: Der Zugriff scheitert dann im pcall des Aufrufers
local function BrowserEntry(id, now)
    local G = C_LFGList
    local info = G.GetSearchResultInfo(id)
    if not info or info.isDelisted or info.hasSelf or not info.leaderName then return end
    local acts = info.activityIDs or {}
    local act = acts[1] and G.GetActivityInfoTable(acts[1])
    local leader = G.GetSearchResultLeaderInfo(id) or {}
    local title = act and act.fullName or L["Dungeonbrowser"]
    if #acts > 1 then title = title .. (" |cff999999+%d|r"):format(#acts - 1) end
    local max = act and act.maxNumPlayers or 0
    -- Rollen in der Gruppe (so zeigt es auch Blizzards Fenster)
    local counts = G.GetSearchResultMemberCounts and G.GetSearchResultMemberCounts(id)
    local roles = counts and { T = tonumber(counts.TANK) or 0, H = tonumber(counts.HEALER) or 0,
                               D = tonumber(counts.DAMAGER) or 0 }
    return ns.Normalize(info.leaderName), {
        kind = "group", browser = true, note = title, needs = "", roles = roles,
        class = leader.classFilename, level = leader.level or 0, zone = leader.areaName or "",
        t = now - (info.age or 0), size = info.numMembers or 1, max = max > 0 and max or 5,
    }
end

local function AddBrowserEntries(list, now)
    local G = C_LFGList
    local _, ids = (G.GetFilteredSearchResults or G.GetSearchResults)()
    local me, added = ns.Me(), 0
    for _, id in ipairs(ids or {}) do
        if added >= BROWSER.max then break end
        local ok, name, e = pcall(BrowserEntry, id, now)
        if ok and name and name ~= me and not entries[name] and not publicEntries[name] then
            list[#list + 1] = { name = name, e = e }
            added = added + 1
        end
    end
end

function page:Refresh()
    local now = GetServerTime()
    -- Ablauf des eigenen Eintrags erledigt der Minuten-Takt oben (inkl. Austragen bei den anderen)
    UpdateNeedButtons()
    if mine then
        local size, max = GroupSize()
        UpdateMyKey()
        status:SetText((L["Dein Status: %s%s|r"]):format(TYPES[mine.kind].color, KindLabel(mine.kind, size))
            .. (mine.kind == "key" and ("  " .. KeyLabel(mine.map, mine.keyLevel)) or "")
            .. "  |cff999999" .. (L["Gruppe %d/%d"]):format(size, max) .. "|r")
    else
        status:SetText(L["|cff888888Du bist nicht eingetragen.|r"])
    end
    if pickedDungeon then status:SetText(status:GetText() .. "  ·  |cff66ccff" .. DungeonText(pickedDungeon) .. "|r") end
    if picked then status:SetText(status:GetText() .. "  ·  " .. QuestLink(picked.id, picked.level, picked.name)) end
    if mine and mine.public and ns.PublicLFGOn() then status:SetText(status:GetText() .. "  ·  |cff8fb3ff" .. L["Serverweit"] .. "|r") end

    local publicOn = ns.PublicLFGOn()
    pubCheck:SetShown(publicOn); pubLabel:SetShown(publicOn)
    status:SetWidth(publicOn and not keysView and 420 or 620); status:SetWordWrap(false)
    pubCheck:SetChecked(GuildPrideDB.lfgPublic)
    UpdateScopeButtons(publicOn and not keysView)

    -- Schlüssel der Gilde statt der Suchliste
    bKeys:SetText(keysView and L["Gruppensuche"] or L["Schlüssel der Gilde"])
    if keysHolder then keysHolder:SetShown(keysView) end
    listScroll:SetShown(not keysView)
    if keysView then
        empty:Hide()
        local list = ns.GuildKeys()
        keysEmpty:SetShown(#list == 0)
        for i, k in ipairs(list) do
            local row = keysList:GetRow(i)
            row.left:SetText(Ambiguate(k.name, "guild") .. (k.name == ns.Me() and (" |cff999999(" .. L["du"] .. ")|r") or ""))
            row.mid:SetText(k.level > 0 and ("|cffa335ee+%d|r %s"):format(k.level, k.map or "") or ("|cff777777" .. L["kein Schlüssel"] .. "|r"))
            row.right:SetText(k.rating > 0 and ("|cffffd100" .. (L["M+-Wertung: %d"]):format(k.rating) .. "|r") or "")
        end
        keysList:Finish(#list)
        return
    end

    local list = {}
    local scope = Scope()
    if mine and (scope ~= "server" or mine.public) then list[1] = { name = ns.Me(), e = MyEntry() } end
    for name, e in pairs(entries) do
        if now - e.t > EXPIRE or now - (e.seen or e.t) > STALE then
            entries[name] = nil
        elseif scope ~= "server" then
            list[#list + 1] = { name = name, e = e }
        end
    end
    if scope ~= "guild" then
        for name, e in pairs(publicEntries) do
            if now - e.t > EXPIRE or now - e.seen > PublicStale() then
                publicEntries[name] = nil
            elseif scope == "server" or not entries[name] then   -- bei "Alle" zählt der Gildeneintrag
                list[#list + 1] = { name = name, e = e }
            end
        end
    end
    -- Dungeonbrowser: serverweite Gruppen, also bei „Server“ und „Alle“, nicht bei „Gilde“
    if BROWSER and (not publicOn or scope ~= "guild") then AddBrowserEntries(list, now) end
    -- Gilde und Server zuerst, die Gruppen aus dem Dungeonbrowser darunter
    table.sort(list, function(a, b)
        if (a.e.browser or false) ~= (b.e.browser or false) then return not a.e.browser end
        return a.e.t > b.e.t
    end)
    empty:SetShown(#list == 0)

    for i = #list + 1, #rows do rows[i]:Hide() end
    listChild:SetHeight(math.max(1, #list * ROW_H))
    for i, item in ipairs(list) do
        local r = GetRow(i)
        r:Show()
        do
            local e, t = item.e, TYPES[item.e.kind]
            local c = RAID_CLASS_COLORS[e.class]
            local hex = c and c.colorStr and c.colorStr:sub(3) or "f0c88c"
            r.icon:SetTexture(e.browser and BROWSER.icon or t.icon)
            if e.browser then r.edge:SetColorTexture(0.4, 0.8, 1, 1)
            elseif item.e.kind == "quest" then r.edge:SetColorTexture(1, 0.82, 0, 1)
            elseif item.e.kind == "key" then r.edge:SetColorTexture(0.64, 0.21, 0.93, 1)
            else r.edge:SetColorTexture(0.44, 0.66, 1, 1) end
            -- Vom Server: Realm zeigen, wenn es ein anderer ist, und Kennzeichen
            local shown, mark = Ambiguate(item.name, "guild"), ""
            if e.public then
                shown = Ambiguate(item.name, "none")
                mark = " |cff8fb3ff[" .. L["Server"] .. "]|r"
            elseif e.browser then
                mark = " |cff66ccff[" .. L["Dungeonbrowser"] .. "]|r"
            end
            r.name:SetText(("|cff%s%s|r"):format(hex, shown) .. mark
                .. (e.self and (" |cff999999(" .. L["du"] .. ")|r") or ""))
            r.block:SetShown(e.public and not e.self)
            r.block:SetScript("OnClick", function()
                GuildPrideDB.lfgBlocked = GuildPrideDB.lfgBlocked or {}
                GuildPrideDB.lfgBlocked[item.name] = true
                publicEntries[item.name] = nil
                ns.Print((L["%s wird in der Gruppensuche ausgeblendet (/gp server entsperren hebt das auf)."]):format(shown))
                page:Refresh()
            end)
            if e.browser then
                r.info:SetText((e.level > 0 and ("Lvl %d · "):format(e.level) or "") .. "|cff999999" .. e.zone .. "|r")
            else
                r.info:SetText(("Lvl %d · %s · |cff999999%s|r"):format(e.level, RoleLabel(e.role), e.zone))
            end
            -- Titel: eigener Text (ältere Versionen), sonst Dungeon mit Levelbereich,
            -- sonst die verlinkte Quest, sonst die Art des Eintrags
            local hasQuest = (e.questId or 0) > 0 and (e.questName or "") ~= ""
            local d = e.dungeon
            local lv = d and LevelRange(d.min, d.max) or ""
            local key = e.kind == "key" and KeyLabel(e.map, e.keyLevel) or ""
            r.title:SetText(e.note ~= "" and e.note
                or (key ~= "" and key)
                or (d and ("|cff66ccff" .. DungeonText(d) .. "|r" .. (lv ~= "" and (" |cff999999" .. lv .. "|r") or "")))
                or (hasQuest and ("|cffffd100" .. e.questName .. "|r"))
                or (t.color .. KindLabel(e.kind, e.size) .. "|r"))

            -- Unten nur noch Quest, gesuchte Rollen und Zeit (Art, Schlüssel und Dungeon stehen im Titel)
            local parts = {}
            if hasQuest then parts[#parts + 1] = QuestLink(e.questId, e.questLevel, e.questName) end
            if e.needs ~= "" then parts[#parts + 1] = (L["Sucht noch: %s"]):format(NeedsString(e.needs)) end
            -- Dungeonbrowser: fehlt der Gruppe noch Tank oder Heiler?
            if e.roles then
                local missing = (e.roles.T == 0 and "T" or "") .. (e.roles.H == 0 and "H" or "")
                if missing ~= "" then parts[#parts + 1] = (L["Fehlt noch: %s"]):format(NeedsString(missing)) end
            end
            parts[#parts + 1] = "|cff777777" .. Ago(now, e.t) .. "|r"
            r.line2:SetText(table.concat(parts, "  ·  "))

            -- Füllstand: bei 5er-Gruppen Punkte, bei Raids nur Zahl
            local showPips = e.max <= 5
            -- Dungeonbrowser: Punkte nach Rolle färben (Tank, Heiler, DD, dann frei)
            local pipColors = {}
            if e.roles then
                for _, rk in ipairs({ "T", "H", "D" }) do
                    for _ = 1, e.roles[rk] do pipColors[#pipColors + 1] = ROLE_RGB[rk] end
                end
            end
            for p = 1, 5 do
                local pip = r.pips[p]
                pip:SetShown(showPips)
                local c = ns.Theme().ember
                if pipColors[p] then pip:SetColorTexture(pipColors[p][1], pipColors[p][2], pipColors[p][3], 1)
                elseif p <= e.size then pip:SetColorTexture(c[1], c[2], c[3], 1)
                else pip:SetColorTexture(0.25, 0.2, 0.18, 1) end
            end
            r.count:SetText(e.size <= 1 and L["Allein"] or (L["Gruppe %d/%d"]):format(e.size, e.max))

            -- Allein + "Sucht Gruppe" -> in die eigene Gruppe einladen,
            -- sonst eine Beitrittsanfrage an seine Gruppe schicken
            local target = Ambiguate(item.name, "none")
            local inMyGroup = UnitInParty(target) or UnitInRaid(target)
            -- Schlüssel-Angebot: immer anmelden (Beitrittsanfrage an den Schlüsselhalter)
            local mode = (e.kind == "group" and e.size <= 1) and "invite" or "join"
            r.tell:SetShown(not e.self)
            r.tell.whisperOnly = e.browser
            if e.browser and not inMyGroup then
                -- Blizzards Dungeonbrowser kennt keine Anmeldung: den Gruppenleiter anflüstern
                r.tell:SetText(L["Anflüstern"]); r.tell:Enable()
            elseif inMyGroup then
                r.tell:SetText(L["In Gruppe"]); r.tell:Disable()
            elseif mode == "join" and e.size >= e.max then
                r.tell:SetText(L["Voll"]); r.tell:Disable()
            elseif e.kind == "key" then
                r.tell:SetText(L["Anmelden"]); r.tell:Enable()
            else
                r.tell:SetText(mode == "invite" and L["Einladen"] or L["Beitreten"]); r.tell:Enable()
            end
            r.tell:SetScript("OnClick", function(_, button)
                if button == "RightButton" or e.browser then SendTell(target) else JoinOrInvite(target, mode) end
            end)
        end
    end
end

-- Suche im Dungeonbrowser: Forever sperrt C_LFGList.Search für Addons („Aktion blockiert“).
-- Der Knopf klickt deshalb sicher Blizzards „Erneut suchen“ im Dungeonbrowser; das sucht
-- in der Kategorie, die dort gewählt ist. Ohne Kategorie sucht Blizzard gar nicht.
if BROWSER then
    local asked = false
    local function BlizzardSearchButton()
        local f = LFGBrowseFrame
        local cat = f and f.CategoryDropdown and f.CategoryDropdown.GetValue and f.CategoryDropdown:GetValue()
        if type(cat) == "number" and cat > 0 then return f.RefreshButton end
    end
    local bSearch = ns.SecureClickButton(page, 150, L["Browser durchsuchen"], nil)
    bSearch:SetPoint("TOPRIGHT", -146, -52)
    bSearch:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Browser durchsuchen"], 1, 1, 1)
        GameTooltip:AddLine(L["Holt Gruppen aus Blizzards Dungeonbrowser in diese Liste. Du erkennst sie an der Markierung [Dungeonbrowser]."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    bSearch:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- Vor dem sicheren Klick das Ziel setzen (außerhalb des Kampfs erlaubt)
    bSearch:SetScript("PreClick", function(self)
        if InCombatLockdown() then return end
        local target = BlizzardSearchButton()
        self:SetAttribute("clickbutton", target)
        if target then
            asked = true
        else
            ns.Print(L["Öffne einmal den Dungeonbrowser und wähle dort eine Kategorie (z. B. Dungeons). Danach sucht dieser Knopf dort neu, und die Gruppen erscheinen hier."])
        end
    end)

    local pending = false
    local function RefreshSoon()
        if pending then return end
        pending = true
        C_Timer.After(0.3, function()
            pending = false
            if page:IsShown() then page:Refresh() end
        end)
    end
    local watch = CreateFrame("Frame")
    watch:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
    watch:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
    watch:RegisterEvent("LFG_LIST_SEARCH_FAILED")
    watch:SetScript("OnEvent", function(_, event)
        if event ~= "LFG_LIST_SEARCH_RESULT_UPDATED" then
            if asked then
                asked = false
                if event == "LFG_LIST_SEARCH_FAILED" then
                    ns.Print(L["Die Suche im Dungeonbrowser ist fehlgeschlagen."])
                elseif (C_LFGList.GetFilteredSearchResults or C_LFGList.GetSearchResults)() == 0 then
                    ns.Print(L["Im Dungeonbrowser wurde gerade nichts gefunden."])
                end
            end
        end
        RefreshSoon()
    end)
end

-- Beim Öffnen die aktuellen Einträge der anderen anfragen (höchstens einmal pro Minute)
local lastAsk = 0
page:HookScript("OnShow", function()
    local now = GetServerTime()
    if now - lastAsk < 60 then return end
    lastAsk = now
    ns.Queue("LFGQ", nil, "1")
    -- Der Reiter öffnet sich nur durch Klick oder Taste (Fenster, Reiter, J, /gp)
    ByClick(AskPublic)
end)

-- /gp server: serverweite Gruppensuche an/aus · /gp server entsperren: Ausgeblendete wieder zeigen
local origSlash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd = strtrim(arg or ""):lower()
    if (cmd == "server" or cmd == "server status") and not ns.HAS_PUBLIC_LFG then
        ns.Print(ns.IS_RETAIL and L["Serverweite Gruppensuche: in Retail nicht verfügbar – nutze dafür den Gruppenfinder."]
            or L["Serverweite Gruppensuche: in dieser Spielversion nicht möglich (Blizzard sperrt Addon-Nachrichten in Chatkanälen)."])
    elseif cmd == "server" then
        GuildPrideDB.publicLFG = not GuildPrideDB.publicLFG
        ByClick(ns.PublicLFGChanged)   -- Befehl per Eingabetaste: Abmeldung darf in den Kanal
        ns.Print(L["Serverweite Gruppensuche: "] .. (GuildPrideDB.publicLFG and L["an"] or L["aus"]))
    elseif cmd == "server status" then
        -- Fehlersuche: Option, Kanal, eigener Eintrag, Gesendetes und Empfangenes
        local st, id, n = ns.publicStats, ns.PublicChannelId(), 0
        for _ in pairs(publicEntries) do n = n + 1 end
        ns.Print(L["Serverweite Gruppensuche: "] .. (ns.PublicLFGOn() and L["an"] or L["aus"])
            .. "  ·  " .. (L["Kanal %s: %s"]):format(ns.PublicChannelName(), id and ("#" .. id) or L["nicht beigetreten"])
            .. "  ·  " .. L["Eigener Eintrag serverweit: "] .. (mine and mine.public and L["ja"] or L["nein"])
            .. "  ·  " .. (ns.PUBLIC_VIA_CHAT and L["Weg: Chat beim Klicken + Flüstern"] or L["Weg: Addon-Nachrichten"]))
        ns.Print((L["Gesendet: %d (letztes Ergebnis: %s) · Empfangen: %d · Einträge vom Server: %d"]):format(
            st.sent, st.lastRes == nil and "-" or tostring(st.lastRes), st.received, n))
        ns.Print((L["Eigene Nachrichten aus dem Kanal zurück: %d"]):format(st.echo))
    elseif cmd == "server entsperren" or cmd == "server unblock" then
        GuildPrideDB.lfgBlocked = nil
        ns.Print(L["Ausgeblendete Spieler in der Gruppensuche werden wieder angezeigt."])
    else
        origSlash(arg)
    end
end

C_Timer.NewTicker(60, function() if ns.RefreshUI then ns.RefreshUI() end end)
