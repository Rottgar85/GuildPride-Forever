-- GuildPride v0.1.0
-- Meilenstein-Ansagen + Gilden-Logo im Chat
local ADDON, ns = ...
local L = ns.L

---------------------------------------------------------------------
-- Eigene Schriften (DejaVu, siehe Media/Fonts/LICENSE-DejaVu.txt)
---------------------------------------------------------------------
do
    local F = "Interface\\AddOns\\GuildPrideForever\\Media\\Fonts\\"
    local function Make(name, file, size, r, g, b)
        local f = CreateFont(name)
        f:SetFont(F .. file, size, "")
        f:SetTextColor(r, g, b)
        f:SetShadowColor(0, 0, 0, 0.9)
        f:SetShadowOffset(1, -1)
        f:SetJustifyH("LEFT")
        return f
    end
    --        Name                 Datei           Größe  Farbe
    Make("GPFont_Huge",        "Heading.ttf",   20, 0.94, 0.78, 0.55)
    Make("GPFont_Large",       "Heading.ttf",   15, 0.94, 0.78, 0.55)
    Make("GPFont_Normal",      "Heading.ttf",   12, 0.94, 0.78, 0.55)
    Make("GPFont_Button",      "Heading.ttf",   12, 1.00, 0.82, 0.55)
    Make("GPFont_ButtonOff",   "Heading.ttf",   12, 0.50, 0.45, 0.42)
    Make("GPFont_ButtonActive", "Heading.ttf",  12, 0.94, 0.78, 0.55)   -- aktiver Umschalter
    Make("GPFont_Ribbon",      "Heading.ttf",   11, 0.97, 0.92, 0.82)   -- Register-Reiter im Gildenbuch
    Make("GPFont_Text",        "Text.ttf",      12, 0.92, 0.90, 0.88)
    Make("GPFont_TextBold",    "TextBold.ttf",  12, 0.94, 0.78, 0.55)
    Make("GPFont_TextSmall",   "Text.ttf",      11, 0.92, 0.90, 0.88)
    Make("GPFont_Muted",       "Text.ttf",      12, 0.51, 0.47, 0.45)
    Make("GPFont_MutedSmall",  "Text.ttf",       9, 0.51, 0.47, 0.45)
    Make("GPFont_Red",         "Text.ttf",      11, 1.00, 0.30, 0.25)
    Make("GPFont_Chat",        "Text.ttf",      12, 0.92, 0.90, 0.88)   -- Größe einstellbar
    ns.FONT_TEXT = F .. "Text.ttf"
end

-- Retail (mit Mythisch+)? WoW Forever hat Interface 16001 und kein M+.
ns.IS_RETAIL = (select(4, GetBuildInfo()) or 0) >= 100000 and C_MythicPlus ~= nil
-- Classic-Clients (Era 115xx, Anniversary, Wrath, Cata, MoP) haben keine Communities.
-- WoW Forever (160xx) schon, obwohl die Interface-Nummer auch unter 100000 liegt.
local toc = select(4, GetBuildInfo()) or 0
ns.IS_CLASSIC = toc < 100000 and not (toc >= 16000 and toc < 20000)
ns.HAS_COMMUNITIES = not ns.IS_CLASSIC
-- Kennung der Spielversion für die serverweite Gruppensuche: jede Version hat
-- einen eigenen Kanal und nimmt nur Nachrichten mit der eigenen Kennung an.
-- R = Retail (über alle Erweiterungen), F = Forever, C1 … C5 = Classic Era bis MoP
if ns.IS_RETAIL then ns.CLIENT_TAG = "R"
elseif toc >= 16000 and toc < 20000 then ns.CLIENT_TAG = "F"
else ns.CLIENT_TAG = "C" .. math.floor(toc / 10000) end
ns.IS_FOREVER = ns.CLIENT_TAG == "F"
-- Serverweite Gruppensuche: in WoW Forever per Addon-Nachricht im offenen Kanal.
-- Classic sperrt Addon-Nachrichten in Chatkanälen (seit 1.13.3): dort geht der
-- eigene Eintrag als normale Chatnachricht in den Kanal (erlaubt Blizzard nur
-- direkt bei einem Klick), Antworten auf Abfragen kommen per Flüstern.
-- Nicht in Retail: Blizzard trennt Kanäle und Flüstern nach Fraktion, und dafür
-- gibt es dort den Gruppenfinder.
ns.HAS_PUBLIC_LFG = JoinTemporaryChannel ~= nil and not ns.IS_RETAIL
ns.PUBLIC_VIA_CHAT = ns.IS_CLASSIC
-- Serverweite Gruppensuche eingeschaltet und in dieser Spielversion möglich?
function ns.PublicLFGOn()
    return ns.HAS_PUBLIC_LFG and GuildPrideDB and GuildPrideDB.publicLFG and true or false
end
-- Classic-Clients haben außerdem nicht alle Events:
-- unbekannte Events werfen beim Registrieren einen Fehler, daher abgesichert.
function ns.RegisterEvents(frame, ...)
    for i = 1, select("#", ...) do pcall(frame.RegisterEvent, frame, (select(i, ...))) end
end

-- Beginn der laufenden Woche (Blizzard-Wochenreset, sonst die letzten 7 Tage)
function ns.WeekStart()
    local now = GetServerTime()
    local left = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and C_DateAndTime.GetSecondsUntilWeeklyReset()
    if left and not (issecretvalue and issecretvalue(left)) then return now + left - 7 * 86400 end
    return now - 7 * 86400
end
local PREFIX = "GuildPride"          -- max. 16 Zeichen
local MILESTONES = { [10]=true, [20]=true, [30]=true, [40]=true, [50]=true,
                     [60]=true, [70]=true, [80]=true, [90]=true }

-- Eigenes Logo: Interface\AddOns\GuildPrideForever\logo.tga (64x64, 32-bit TGA)
-- Fallback, solange du noch kein Logo hast:
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_Tournaments_banner_Human"

local defaults = { sound = true, popup = true, useCustomLogo = false,
                   replaceGuildFrame = true, memberAlerts = true, helpAlerts = true, shareMilestones = true,
                   minimap = true, chatFont = 12, scale = 1, alpha = 1, welcome = false,
                   publicLFG = true, publicAlerts = false, lfgPublic = false, lfgScope = "all",
                   mapShow = true, mapShare = true, ausweisAuto = true, groupAlts = true, compactMenu = true }

-- Weitere Meilensteine neben LEVEL (Wert ist Text bzw. ID)
local EXTRA_KINDS = { ACH = true, BOSS = true, MPLUS = true, MOUNT = true }
ns.EXTRA_KINDS = EXTRA_KINDS
local guildMembers = {}   -- ["Name-Realm"] = true

-- Modul-Nachrichten: ns.On("KIND", function(payload, sender) ... end)
ns.Handlers = {}
function ns.On(kind, fn)
    ns.Handlers[kind] = ns.Handlers[kind] or {}
    table.insert(ns.Handlers[kind], fn)
end
ns.SEP = "\031"
-- WoW Forever: Vor- plus Nachname ist regionsweit eindeutig, ein Realm gehört
-- nicht dazu. Das Spiel liefert den Nachnamen teils dort, wo sonst der Realm
-- steht („Reon-Strobek“). Einheitliche Form hier: „Reon Strobek“.
local function ForeverName(name)
    local first, rest = name:match("^([^%-]+)%-(.+)$")
    if not first then return name end
    if first:find(" ", 1, true) or rest == GetNormalizedRealmName() or rest == GetRealmName() then return first end
    local surname = rest:match("^[^%-]+")
    return surname and (first .. " " .. surname) or first
end

local function Normalize(name)
    if not name then return nil end
    if ns.IS_FOREVER then return ForeverName(name) end
    if not name:find("-") then
        name = name .. "-" .. (GetNormalizedRealmName() or "")
    end
    return name
end
ns.Normalize = Normalize

function ns.Me()
    if ns.IS_FOREVER and UnitFullName then
        local name, surname = UnitFullName("player")
        if name then return Normalize((surname and surname ~= "") and (name .. "-" .. surname) or name) end
    end
    return Normalize(UnitName("player"))
end

-- Gildeninfo und Nachricht des Tages sind in manchen Zuständen für Addons
-- gesperrt: Schon das Lesen löst dann ADDON_ACTION_BLOCKED aus (kein Lua-Fehler,
-- pcall hilft nicht). Darum vorher prüfen und den letzten Stand weiterzeigen.
local RESTRICTIONS = { "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map" }
function ns.GuildTextLocked()
    if InCombatLockdown() then return true end
    local R, T = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
    if not (R and R.IsAddOnRestrictionActive and T) then return false end
    for _, key in ipairs(RESTRICTIONS) do
        if T[key] and R.IsAddOnRestrictionActive(T[key]) then return true end
    end
    return false
end

local lastMotd = ""
function ns.GuildMOTD()
    if not GetGuildRosterMOTD or ns.GuildTextLocked() then return lastMotd end
    local text = GetGuildRosterMOTD()
    if issecretvalue and issecretvalue(text) then return lastMotd end
    lastMotd = text or ""
    return lastMotd
end

-- Blizzard-Befehl für sichere Makros (/gpromote, /gremove …): bevorzugt einen
-- Namen ohne Umlaute – im deutschen Client lief /gbefördern im Makro ins Leere,
-- /gentfernen dagegen schon. Sonst der englische Name.
function ns.SlashCmd(key, english)
    for i = 1, 9 do
        local cmd = _G["SLASH_" .. key .. i]
        if type(cmd) == "string" and not cmd:find("[\128-\255]") then return cmd end
    end
    return english
end
function ns.IsOfficer()
    return CanEditMOTD and CanEditMOTD()
end

-- Die letzten Meldungen merken: ein Klick auf [GuildPride] im Chat öffnet
-- genau diese Zeile zum Kopieren (siehe GuildPrideCopy.lua). Blizzards
-- "addon:"-Links lösen dabei nur ein Ereignis aus, nichts Geschütztes.
local printLog, printId, PRINT_KEEP = {}, 0, 200
ns.printLog = printLog
local function Print(msg)
    printId = printId + 1
    printLog[printId] = msg
    printLog[printId - PRINT_KEEP] = nil
    print(("|cffff7d0a|Haddon:GuildPride:copy:%d|h[GuildPride]|h|r "):format(printId) .. msg)
end

local function IconString(size)
    local path = "Interface\\AddOns\\GuildPrideForever\\Media\\logo_small"
    return ("|T%s:%d|t"):format(path, size or 14)
end

-- Fremde Eingaben entschärfen: Steuerzeichen und "|" (Farb-, Link- und
-- Bildcodes) entfernen, Länge begrenzen
local function Clean(s, max) return (tostring(s or ""):gsub("[%c|]", "")):sub(1, max) end
ns.Clean = Clean
-- Zahl aus einer fremden Nachricht: nil bei Unsinn, sonst ganzzahlig auf [lo, hi]
function ns.Num(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= v then return nil end
    return math.min(math.max(math.floor(v), lo), hi)
end
-- Zeit- und Versionsstempel aus fremden Nachrichten nicht weit in die Zukunft
-- lassen: ein manipulierter Riesenwert würde sonst alle späteren echten
-- Änderungen für immer überstimmen
function ns.Stamp(v) return ns.Num(v, 0, GetServerTime() + 300) or 0 end

---------------------------------------------------------------------
-- Gildenliste
---------------------------------------------------------------------
local rosterAt = 0
local function RefreshRoster()
    rosterAt = GetTime()
    wipe(guildMembers)
    if not IsInGuild() then return end
    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        -- Wert = Rang + 1 (immer wahr), für die Empfangsstatistik je Rang
        if name then guildMembers[Normalize(name)] = (rankIndex or 0) + 1 end
    end
end

-- Gehört der Name zur Gilde? Bei Unbekannten die Liste neu lesen (höchstens
-- alle 5 s, damit fremde Absender das nicht in einer Schleife auslösen)
local function IsMember(name)
    if guildMembers[name] then return true end
    if GetTime() - rosterAt > 5 then RefreshRoster() end
    return guildMembers[name] ~= nil
end
function ns.IsGuildMember(name) return name ~= nil and IsMember(Normalize(name)) end
---------------------------------------------------------------------
-- Vertrauen bei Addon-Nachrichten
-- Ein manipuliertes Addon kann beliebige Nachrichten schicken. Die Regeln:
-- * Offiziere = Ränge, die die Gildennachricht ändern dürfen (sonst Rang 0 und 1).
-- * Weitergeleitete Nachrichten (FWD) sind nie "direkt vom Urheber": wer
--   weiterleitet, könnte den Absender erfunden haben. ns.Forwarded ist dann
--   der Name des Weiterleiters.
-- * Daten über andere (Abgleich) von Nicht-Offizieren zählen erst, wenn zwei
--   verschiedene Mitglieder genau dasselbe melden (ns.Confirmed).
---------------------------------------------------------------------
ns.OFFICER_MAX_RANK = 1
ns.Forwarded = nil
-- Kommt die Nachricht wirklich direkt von "name"?
function ns.IsDirect(sender, name) return not ns.Forwarded and sender == name end

local confirms, confirmCount = {}, 0
function ns.Confirmed(key, sender)
    local who = ns.Forwarded or sender
    local set = confirms[key]
    if not set then
        if confirmCount >= 20000 then wipe(confirms); confirmCount = 0 end
        set = {}
        confirms[key] = set
        confirmCount = confirmCount + 1
    end
    set[who] = true
    local n = 0
    for _ in pairs(set) do n = n + 1; if n >= 2 then return true end end
    return false
end

-- Rangnummer eines Gildenmitglieds (0 = Gildenleitung), nil wenn unbekannt
function ns.RankIndexOf(name)
    if not name or not IsMember(Normalize(name)) then return nil end
    return guildMembers[Normalize(name)] - 1
end
-- Welche Ränge sind "Offiziere"? Wer die Gildennachricht ändern darf (Rangrecht 9,
-- "Set MOTD") – dasselbe Recht, das GuildPride für DKP und Verwaltung verlangt.
-- Liefert das Spiel die Rechte nicht (gesperrt oder fehlt), gelten Rang 0 und 1.
local officerRanks, officerRanksAt = nil, 0
local function OfficerRanks()
    if officerRanks and GetTime() - officerRanksAt < 60 then return officerRanks end
    officerRanksAt = GetTime()
    local get = C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags
    local num = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
    if not get or num == 0 then officerRanks = nil return nil end
    local set = { [0] = true }   -- Gildenleitung immer
    for r = 1, num - 1 do
        local ok, flags = pcall(get, r + 1)
        if not ok or type(flags) ~= "table" then officerRanks = nil return nil end
        if flags[9] == true then set[r] = true end
    end
    officerRanks = set
    return set
end
function ns.IsOfficerRank(r)
    if r == nil then return false end
    local set = OfficerRanks()
    if set then return set[r] == true end
    return r <= ns.OFFICER_MAX_RANK
end
-- Offizier oder Gildenleitung? Weitergeleitet zählt nie als Offizier.
function ns.IsOfficerName(name)
    if ns.Forwarded then return false end
    return ns.IsOfficerRank(ns.RankIndexOf(name))
end

ns.IconString = IconString
ns.Print = Print

-- Kennung der aktuellen Gilde ("Gilde@Realm"), nil ohne Gilde
function ns.GuildId()
    local guild, _, _, realm = GetGuildInfo("player")
    if not guild then return nil end
    return guild .. "@" .. (realm or GetNormalizedRealmName() or "")
end

-- Gespeicherte Daten einer Gilde (Verlauf, Events, Umfragen, Chat …) liegen je
-- Gilde getrennt in GuildPrideDB.guilds["Gilde@Realm"][feld]: ein Account kann
-- Charaktere in mehreren Gilden haben. Ohne Gilde: leere Wegwerf-Tabelle.
function ns.GuildTable(field)
    local id = ns.GuildId()
    if not id or not GuildPrideDB then return {} end
    GuildPrideDB.guilds = GuildPrideDB.guilds or {}
    local g = GuildPrideDB.guilds[id] or {}
    GuildPrideDB.guilds[id] = g
    g[field] = g[field] or {}
    return g[field]
end

-- Meilensteine über den abgesicherten Kanal (ohne Kanal-Schlüssel über die
-- Gilde). Der eigene kommt sofort in den Verlauf: ob der Kanal die eigene
-- Nachricht zurückliefert, ist nicht sicher; ein Echo wird ohnehin aussortiert.
local ShowMilestone
local function Broadcast(kind, value)
    if not IsInGuild() or not ns.Queue then return end
    ns.Queue(kind, "@CHANNEL", value)
    if ShowMilestone then ShowMilestone(ns.Me(), kind, value) end
    -- Wichtige Meilensteine zusätzlich nach Discord (Erfolge/Reittiere wären zu viele)
    if ns.Discord and ns.DescribeMilestone and (kind == "LEVEL" or kind == "BOSS" or kind == "MPLUS") then
        ns.Discord.Post(((ns.IS_GERMAN and "Meilenstein" or "Milestone") .. ": %s %s"):format(Ambiguate(ns.Me(), "guild"), ns.DescribeMilestone(kind, value)))
    end
end

local function DescribeMilestone(kind, value)
    if kind == "LEVEL" then
        return (L["hat Level %s erreicht!"]):format(value)
    elseif kind == "ACH" then
        local id = tonumber(value)
        local name = id and GetAchievementInfo and select(2, GetAchievementInfo(id))
        return (L["hat den Erfolg „%s“ errungen!"]):format(name or tostring(value))
    elseif kind == "BOSS" then
        -- Wert: "Schwierigkeit,Bossname"
        local diff, boss = tostring(value):match("^(%d+),(.+)$")
        local dname = diff and GetDifficultyInfo and GetDifficultyInfo(tonumber(diff))
        return (L["hat %s besiegt!"]):format((boss or tostring(value)) .. (dname and (" (" .. dname .. ")") or ""))
    elseif kind == "MPLUS" then
        return (L["hat einen +%s-Schlüssel geschafft!"]):format(value)
    elseif kind == "MOUNT" then
        local id = tonumber(value)
        local name = id and C_MountJournal and C_MountJournal.GetMountInfoByID and C_MountJournal.GetMountInfoByID(id)
        return (L["hat ein neues Reittier: %s!"]):format(name or tostring(value))
    end
    return (L["hat einen Meilenstein erreicht (%s %s)"]):format(kind, value)
end
ns.DescribeMilestone = DescribeMilestone

-- Meilenstein-Wert aus einer fremden Nachricht prüfen (nil = unbrauchbar):
-- BOSS ist Text ("Schwierigkeit,Bossname"), alle anderen sind Zahlen
local function SafeMilestoneValue(kind, value)
    if kind == "BOSS" then
        local v = Clean(value, 80)
        return v ~= "" and v or nil
    end
    return ns.Num(value, 1, 99999999)
end

---------------------------------------------------------------------
-- Verlauf (Meilensteine, Beitritte, Austritte)
-- Jeder Eintrag hat einen Schlüssel (Art + Name + Wert). So kommt er nur einmal
-- in den Verlauf, egal ob er live, über die Gildenliste oder über den Abgleich
-- mit anderen Spielern ankommt.
---------------------------------------------------------------------
local LOG_MAX = 100
local DAY = 86400

function ns.LogText(e)
    if e.kind == "LEVEL" or EXTRA_KINDS[e.kind] then return DescribeMilestone(e.kind, e.value) end
    if e.kind == "JOIN" then return L["ist der Gilde beigetreten"] end
    if e.kind == "LEAVE" then return L["hat die Gilde verlassen"] end
    if e.kind == "KICK" then return L["wurde aus der Gilde entfernt."] end
    return e.text or ""
end

local function LogKey(e)
    -- Beitritt/Austritt: ein Eintrag pro Tag und Person
    local v = (e.kind == "LEVEL" or EXTRA_KINDS[e.kind]) and e.value or math.floor((e.t or 0) / DAY)
    return (e.kind or "?") .. ":" .. tostring(e.who) .. ":" .. tostring(v)
end

local function Log() return ns.GuildTable("log") end
ns.GuildLog = Log

-- Neuen Eintrag aufnehmen; true, wenn er neu war
function ns.AddLog(kind, who, value, t)
    local e = { kind = kind, who = who, value = value, t = t or GetServerTime() }
    local key = LogKey(e)
    for _, old in ipairs(Log()) do
        if LogKey(old) == key then
            -- Schon bekannt: den früheren (genaueren) Zeitpunkt behalten
            if e.t < (old.t or e.t) then
                old.t = e.t
                table.sort(Log(), function(a, b) return (a.t or 0) > (b.t or 0) end)
                if ns.RefreshUI then ns.RefreshUI() end
            end
            return false
        end
    end
    table.insert(Log(), e)
    table.sort(Log(), function(a, b) return (a.t or 0) > (b.t or 0) end)
    while #Log() > LOG_MAX do table.remove(Log()) end
    if ns.RefreshUI then ns.RefreshUI() end
    return true
end

-- Meilenstein anzeigen (Popup + Chat), aber nur beim ersten Mal
function ShowMilestone(sender, kind, value, silent)
    local who = Ambiguate(sender, "guild")
    if not ns.AddLog(kind, who, tonumber(value) or value) or silent then return end
    local text = DescribeMilestone(kind, value)
    local line = ("%s |cff00ff00%s|r %s"):format(IconString(20), who, text)
    if ns.PlayMilestoneSound then ns.PlayMilestoneSound() end
    if GuildPrideDB.popup then
        if ns.ShowMilestonePopup then
            ns.ShowMilestonePopup(who, text, kind, value)
        else
            RaidNotice_AddMessage(RaidWarningFrame, line, ChatTypeInfo["GUILD"])
        end
    end
    Print(line)
end

-- Level-Aufstiege aus der Gildenliste erkennen – funktioniert auch für
-- Mitglieder ohne GuildPride. Aufstiege, die während man offline war passiert
-- sind, kommen nach dem Login nur still in den Verlauf (kein Popup-Schwall).
local rosterSeen = false
local function CheckRosterLevels()
    if not IsInGuild() or not ns.GuildId() or GetNumGuildMembers() == 0 then return end
    local known = ns.GuildTable("levels")
    local silent = not rosterSeen
    for i = 1, GetNumGuildMembers() do
        local name, _, _, level = GetGuildRosterInfo(i)
        if name and level and level > 0 then
            local full = Normalize(name)
            local before = known[full]
            if before and level > before then
                for lv = before + 1, level do
                    if MILESTONES[lv] then ShowMilestone(full, "LEVEL", lv, silent) end
                end
            end
            known[full] = level
        end
    end
    rosterSeen = true
end

-- Abgleich: beim Login fragt man nach Einträgen, die neuer sind als der eigene
-- neueste. Ein zufälliger anderer Spieler antwortet für alle sichtbar; wer die
-- Antwort sieht, schickt keine zweite.
local answered = {}

-- Abgleich ab 1.12.4: MHQ (Anfrage) / MHL (Eintrag), über den abgesicherten
-- Kanal. Ältere Versionen fragen mit MSQ und bekommen weiter MSL; deren MSL
-- werden aber nicht übernommen – ihr Verlauf mischt noch alle Gilden des Accounts.
-- whisper: Anfragender kann den Gildenchat nicht lesen -> Antwort per Flüstern
local function SendHistory(requester, since, whisper, kind)
    local list = {}
    for _, e in ipairs(Log()) do
        if e.kind and e.t and e.t > since then list[#list + 1] = e end
        if #list >= 25 then break end
    end
    local target = whisper and requester or (kind == "MHL" and "@CHANNEL" or nil)
    for i = #list, 1, -1 do
        local e = list[i]
        ns.Queue(kind, target, requester, e.t, e.who, e.kind, e.value or "")
    end
end

local function OnHistoryQuery(payload, sender, reply)
    if sender == ns.Me() then return end
    local sinceStr, listen = strsplit(ns.SEP, payload)
    local since = ns.Stamp(sinceStr)
    if listen == "0" then
        -- Antworten anderer sieht er nicht; jeder antwortet direkt, aber versetzt
        C_Timer.After(math.random() * 5, function() SendHistory(sender, since, true, reply) end)
        return
    end
    local newest = Log()[1]
    if not newest or (newest.t or 0) <= since then return end
    answered[sender] = nil
    C_Timer.After(1 + math.random() * 5, function()
        if not answered[sender] then
            answered[sender] = true
            SendHistory(sender, since, false, reply)
        end
    end)
end
ns.On("MSQ", function(payload, sender) OnHistoryQuery(payload, sender, "MSL") end)
ns.On("MHQ", function(payload, sender) OnHistoryQuery(payload, sender, "MHL") end)

ns.On("MSL", function(payload)
    local requester = strsplit(ns.SEP, payload)
    if requester then answered[requester] = true end
end)

ns.On("MHL", function(payload, sender)
    local requester, t, who, kind, value = strsplit(ns.SEP, payload)
    if requester then answered[requester] = true end
    if sender == ns.Me() then return end
    if kind ~= "LEVEL" and kind ~= "JOIN" and kind ~= "LEAVE" and kind ~= "KICK" and not EXTRA_KINDS[kind] then return end
    t, who = ns.Stamp(t), Clean(who, 60)
    if t == 0 or who == "" then return end
    if kind == "LEVEL" or EXTRA_KINDS[kind] then
        value = SafeMilestoneValue(kind, value)
        if not value then return end
    else
        value = nil   -- Beitritt/Austritt haben keinen Wert
    end
    -- Meilensteine und Beitritte nur von aktuellen Mitgliedern dieser Gilde
    if kind ~= "LEAVE" and kind ~= "KICK" and not ns.IsGuildMember(who) then return end
    ns.AddLog(kind, who, value, t)
end)

local function RequestHistory()
    local newest = Log()[1]
    -- Wer im Kanal ist, hört die Antworten dort, auch ohne Leserecht im Gildenchat
    local inChannel = ns.DataChannelId and ns.DataChannelId()
    local listen = (inChannel or not ns.CanListenGuild or ns.CanListenGuild()) and 1 or 0
    if ns.Queue then ns.Queue("MHQ", "@CHANNEL", newest and newest.t or 0, listen) end
end
ns.RequestHistory = RequestHistory

---------------------------------------------------------------------
-- Chat-Filter: Logo vor Nachrichten von Gildenmitgliedern
---------------------------------------------------------------------
-- Wer hat GuildPride? (jeder, von dem wir eine Addon-Nachricht bekommen haben)
ns.AddonUsers = {}

local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end

---------------------------------------------------------------------
-- Addon-Nachrichten verteilen; mehrteilige ("MP") erst zusammensetzen
---------------------------------------------------------------------
local multipart = {}   -- ["Sender:id"] = { n, got, parts, t }
-- Arten, die Rechte voraussetzen oder Identität beweisen: nie per Weiterleitung
local NO_RELAY = { DKP = true, DRW = true, ALT = true, AUS = true, AUSX = true, AUSL = true,
                   AUC = true, AUH = true, AUE = true, CKY = true, DEL = true, JHL = true, LAY = true, RCP = true, APK = true,
                   CRF = true, CRR = true, GOL = true, BRD = true, LFJ = true, LFJA = true }
local recent, recentSweep = {}, 0   -- zuletzt empfangene Nachrichten (gegen Doppelte)
local forwarded = {}   -- ["Name:id"] = Zeit, gegen doppelte Weiterleitungen
local MP_MAX = 100

-- Anfragen, auf die alle antworten: pro Absender höchstens eine alle 10 s,
-- sonst könnte einer mit Dauer-Anfragen die Addon-Nachrichten der Gilde lahmlegen
local ASKS = { REQ = true, EVQ = true, PLQ = true, LFGQ = true, KEYQ = true, MSQ = true, MHQ = true, CKQ = true, AUSQ = true, JHQ = true, RCPQ = true,
               CRQ = true, CRRQ = true, GOQ = true, BRQ = true }
local askedAt, askSweep = {}, 0
local function TooManyAsks(kind, sender)
    local now, key = GetTime(), kind .. ":" .. sender
    if askedAt[key] and now - askedAt[key] < 10 then return true end
    askedAt[key] = now
    if now - askSweep > 60 then
        askSweep = now
        for k, t in pairs(askedAt) do if now - t >= 10 then askedAt[k] = nil end end
    end
    return false
end

local function Dispatch(message, sender)
    local kind, value = message:match("^(%u+):(.+)$")
    if not kind then return end
    -- auch zusammengesetzte (MP) weitergeleitete Nachrichten prüfen
    if ns.Forwarded and NO_RELAY[kind] then return end
    if ASKS[kind] and TooManyAsks(kind, sender) then return end
    if kind == "RLY" then
        -- Ein Mitglied ohne Gildenchat-Recht bittet uns, an die Gilde weiterzugeben
        local id, msg = value:match("^([^\031]+)\031(.+)$")
        -- Kanal-Schlüssel nie weiterleiten: die Weiterleitung ginge auch in den Kanal
        if id and not msg:match("^CKY:") and guildMembers[Normalize(sender)] and ns.Queue
           and (not ns.CanSpeakGuild or ns.CanSpeakGuild()) then
            ns.Queue("FWD", nil, Normalize(sender), id, msg)
        end
        return
    end
    if kind == "FWD" then
        local origin, id, msg = value:match("^([^\031]+)\031([^\031]+)\031(.+)$")
        if not origin or not guildMembers[origin] or msg:match("^FWD:") or msg:match("^RLY:") then return end
        -- Offiziere dürfen im Gildenchat schreiben und brauchen keine Weiterleitung:
        -- eine angebliche Weiterleitung von ihnen ist gefälscht
        if ns.IsOfficerRank(guildMembers[origin] - 1) then return end
        -- Nachrichten, die Rechte voraussetzen, nie weitergeleitet annehmen
        local inner = msg:match("^(%u+):")
        if inner and NO_RELAY[inner] then return end
        local now, key = GetTime(), origin .. ":" .. id
        for k, t in pairs(forwarded) do if now - t > 120 then forwarded[k] = nil end end
        if forwarded[key] then return end
        forwarded[key] = now
        ns.AddonUsers[origin] = true
        local outer = ns.Forwarded
        ns.Forwarded = Normalize(sender)
        local ok, err = pcall(Dispatch, msg, origin)
        ns.Forwarded = outer
        if not ok then geterrorhandler()(err) end
        return
    end
    if kind == "MP" then
        local id, i, n, part = value:match("^([^\031]+)\031(%d+)\031(%d+)\031(.*)$")
        i, n = tonumber(i), tonumber(n)
        if not id or not i or not n or n < 1 or n > 20 or i < 1 or i > n then return end
        local now = GetTime()
        local count = 0
        for k, b in pairs(multipart) do
            if now - b.t > 60 then multipart[k] = nil else count = count + 1 end
        end
        -- weitergeleitete Teile getrennt halten: kein Mischen mit echten Teilen
        local key = (ns.Forwarded and ("F>" .. ns.Forwarded .. ">") or "") .. sender .. ":" .. id
        local buf = multipart[key]
        if not buf then
            -- Gegen Speicherfluten: nur begrenzt viele halbfertige Nachrichten
            if count >= MP_MAX then return end
            buf = { n = n, got = 0, parts = {}, t = now }
            multipart[key] = buf
        end
        if n ~= buf.n then return end
        if not buf.parts[i] then buf.parts[i] = part; buf.got = buf.got + 1 end
        if buf.got < buf.n then return end
        multipart[key] = nil
        local full = table.concat(buf.parts)
        if not full:match("^MP:") then Dispatch(full, sender) end
        return
    end
    if ns.Handlers[kind] then
        for _, fn in ipairs(ns.Handlers[kind]) do fn(value, sender) end
    elseif kind == "LEVEL" or EXTRA_KINDS[kind] then
        value = SafeMilestoneValue(kind, value)
        if value then ShowMilestone(sender, kind, value) end
    end
end

---------------------------------------------------------------------
-- Events
---------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("CHAT_MSG_ADDON")
ns.RegisterEvents(f, "ACHIEVEMENT_EARNED", "ENCOUNTER_END", "CHALLENGE_MODE_COMPLETED", "NEW_MOUNT_ADDED")

-- Eigene weitere Meilensteine melden (abschaltbar in den Einstellungen)
local function Share(kind, value)
    if GuildPrideDB.shareMilestones == false then return end
    Broadcast(kind, value)
end

local function OnExtraMilestone(event, ...)
    for i = 1, select("#", ...) do if IsSecret((select(i, ...))) then return end end
    if event == "ACHIEVEMENT_EARNED" then
        local id, already = ...
        -- Nur persönliche Erfolge, keine Gildenerfolge
        local isGuild = id and select(12, GetAchievementInfo(id))
        if id and not already and not isGuild then Share("ACH", id) end
    elseif event == "ENCOUNTER_END" then
        local _, name, diff, size, success = ...
        if success ~= 1 or not IsInRaid() or (size or 0) < 10 or not name then return end
        GuildPrideDB.bossKills = GuildPrideDB.bossKills or {}
        local key = diff .. "," .. name
        if GuildPrideDB.bossKills[key] then return end   -- nur der erste Sieg je Schwierigkeit
        GuildPrideDB.bossKills[key] = true
        Share("BOSS", key)
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        if not C_ChallengeMode then return end
        local info = C_ChallengeMode.GetChallengeCompletionInfo and C_ChallengeMode.GetChallengeCompletionInfo()
        local level = info and info.level
        if not level then level = select(2, C_ChallengeMode.GetCompletionInfo()) end
        if not level or level < 10 or (info and info.onTime == false) then return end
        if level <= (GuildPrideDB.mplusBest or 0) then return end   -- nur neue Bestwerte
        GuildPrideDB.mplusBest = level
        Share("MPLUS", level)
    elseif event == "NEW_MOUNT_ADDED" then
        local id = ...
        if id then Share("MOUNT", id) end
    end
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" and ... == ADDON then
        GuildPrideDB = GuildPrideDB or {}
        for k, v in pairs(defaults) do
            if GuildPrideDB[k] == nil then GuildPrideDB[k] = v end
        end
        GuildPrideDB.cleanStart = nil   -- alte Einmal-Bereinigung, nicht mehr nötig
        -- Bis 1.12.3 lagen Verlauf, Events, Umfragen, Anwesenheit, Chat und der
        -- Gildeninfo-Stand einmal für den ganzen Account vor, Gilden gemischt.
        -- Das wird verworfen: jede Gilde beginnt leer (GuildPrideDB.guilds) und
        -- holt sich ihre Daten über den abgesicherten Kanal von den Mitgliedern.
        GuildPrideDB.log, GuildPrideDB.levels, GuildPrideDB.events, GuildPrideDB.polls = nil, nil, nil, nil
        GuildPrideDB.attendance, GuildPrideDB.chat, GuildPrideDB.infoSeen = nil, nil, nil
        GuildPrideDB.logs, GuildPrideDB.guildLevels = nil, nil
        -- Eigene Regeln wurden durch die Blizzard-Gildeninfo ersetzt
        GuildPrideDB.rules, GuildPrideDB.rulesSeen = nil, nil
        -- BattleTag-Funktion wurde entfernt: alte gespeicherte Daten löschen
        GuildPrideDB.btagQueue, GuildPrideDB.btagAuto = nil, nil
        GuildPrideDB.btagAsked, GuildPrideDB.btagSent, GuildPrideDB.btagDone = nil, nil, nil
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        ns.AddonUsers[ns.Me()] = true

    elseif event == "PLAYER_LOGIN" then
        if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
        Print(L["geladen. /gp für Befehle"])
        -- Alle /gp-Befehle (aus allen Dateien) gegen Fehler absichern: ein Fehler
        -- würde sonst Blizzards Chat-Eingabe offen lassen und den Befehl drin stehen
        local slash = SlashCmdList.GUILDPRIDE
        SlashCmdList.GUILDPRIDE = function(arg)
            local ok, err = pcall(slash, arg)
            if not ok then Print("|cffff4040" .. (IsSecret(err) and "?" or tostring(err)) .. "|r") end
        end
        -- verpasste Meilensteine von anderen holen (nach dem Kanalbeitritt nach 15 s)
        C_Timer.After(22, RequestHistory)

    elseif event == "GUILD_ROSTER_UPDATE" then
        RefreshRoster()
        CheckRosterLevels()
        if ns.RefreshUI then ns.RefreshUI() end

    elseif event == "PLAYER_LEVEL_UP" then
        local level = ...
        if MILESTONES[level] then Broadcast("LEVEL", level) end

    elseif event == "ACHIEVEMENT_EARNED" or event == "ENCOUNTER_END"
        or event == "CHALLENGE_MODE_COMPLETED" or event == "NEW_MOUNT_ADDED" then
        OnExtraMilestone(event, ...)

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        -- Geschützte Werte zuerst prüfen: schon ein Vergleich damit wirft einen Fehler
        if IsSecret(prefix) or prefix ~= PREFIX then return end
        if IsSecret(message) or IsSecret(sender) or IsSecret(channel) then return end
        if channel ~= "GUILD" and channel ~= "WHISPER" and channel ~= "OFFICER" and channel ~= "CHANNEL" then return end
        if type(message) ~= "string" or type(sender) ~= "string" then return end
        -- Absender immer als "Name-Realm": manchmal kommt er ohne Realm an, dann
        -- wurden eigene Nachrichten für fremde gehalten (z. B. doppelte Hinweise)
        sender = Normalize(sender)
        -- Serverweite Gruppensuche: offener Kanal, in dem jeder schreiben kann.
        -- Nur die Gruppensuche bekommt diese Nachrichten (prüft Art und Kennung
        -- selbst), nie Dispatch – Weiterleitungen und Gildendaten sind so tabu.
        if channel == "CHANNEL" and ns.IsPublicChannel then
            local _, _, _, _, _, _, localID, chanName = ...
            if not IsSecret(localID) and not IsSecret(chanName) and ns.IsPublicChannel(localID, chanName) then
                if ns.OnPublicMessage then ns.OnPublicMessage(message, sender) end
                return
            end
        end
        -- Antwort auf eine serverweite Abfrage: kommt per Flüstern, auch von
        -- Fremden – ebenfalls nur an die Gruppensuche, und nur Einträge (PLFG)
        if channel == "WHISPER" and message:sub(1, 5) == "PLFG:" then
            if ns.OnPublicMessage then ns.OnPublicMessage(message, sender, true) end
            return
        end
        -- Kanal: nur unser abgesicherter Gildenkanal zählt, keine anderen Kanäle
        if channel == "CHANNEL" then
            local _, _, _, _, _, _, localID, chanName = ...
            -- Direkt aufrufen: "a and f()" gäbe nur den ersten Rückgabewert weiter
            local ourId, ourName
            if ns.DataChannelId then ourId, ourName = ns.DataChannelId() end
            if not ourId or IsSecret(localID) or IsSecret(chanName) then return end
            local nameOk = type(chanName) == "string" and chanName ~= "" and type(ourName) == "string"
                and chanName:lower():find(ourName:lower(), 1, true) ~= nil
            if not nameOk and localID ~= ourId then return end
        end
        -- Beitrittsanfrage aus der serverweiten Gruppensuche (und Antwort darauf):
        -- per Flüstern, auch von Fremden – nur an die Gruppensuche, nie Dispatch
        if channel == "WHISPER" and not IsMember(sender)
           and (message:sub(1, 4) == "LFJ:" or message:sub(1, 5) == "LFJA:") then
            if ns.OnPublicJoin then ns.OnPublicJoin(message, sender) end
            return
        end
        -- Flüstern und Kanäle kann jeder auf dem Server benutzen:
        -- nur Nachrichten von Gildenmitgliedern annehmen
        if (channel == "CHANNEL" or channel == "WHISPER") and not IsMember(sender) then return end
        -- Kanal-Schlüssel: nur über Gilde oder Flüstern, nie über den Kanal selbst
        if message:sub(1, 4) == "CKY:" then
            if channel ~= "CHANNEL" and ns.OnChannelKey then ns.OnChannelKey(message:sub(5), sender) end
            return
        end
        -- Im Kanal gehört: Antworten an ihn dürfen über den Kanal gehen
        if channel == "CHANNEL" and ns.ChannelSeen then ns.ChannelSeen(sender) end
        -- Rundsendungen kommen über Gilde UND Kanal: zweites Exemplar verwerfen
        local now, key = GetTime(), sender .. "\030" .. message
        if recent[key] and now - recent[key] < 30 then return end
        recent[key] = now
        if now - recentSweep > 60 then
            recentSweep = now
            for k, t in pairs(recent) do if now - t >= 30 then recent[k] = nil end end
        end
        ns.AddonUsers[sender] = true
        Dispatch(message, sender)
    end
end)

---------------------------------------------------------------------
-- Slash-Befehle
---------------------------------------------------------------------
SLASH_GUILDPRIDE1 = "/gp"
SLASH_GUILDPRIDE2 = "/guildpride"
SlashCmdList.GUILDPRIDE = function(arg)
    local raw = strtrim(arg or "")
    arg = raw:lower()
    local toggles = { sound = "sound", popup = "popup", logo = "useCustomLogo" }
    if toggles[arg] then
        local key = toggles[arg]
        GuildPrideDB[key] = not GuildPrideDB[key]
        Print(("%s: %s"):format(arg, GuildPrideDB[key] and L["an"] or L["aus"]))
    elseif arg == "" or arg == "show" then
        if ns.ToggleUI then ns.ToggleUI() end
    elseif arg == "blizzard" then
        GuildPrideDB.replaceGuildFrame = not GuildPrideDB.replaceGuildFrame
        Print(L["Eigenes Gildenfenster: "] .. (GuildPrideDB.replaceGuildFrame and L["an"] or L["aus"]))
    elseif arg:match("^einladen%f[%A]") or arg:match("^invite%f[%A]") then
        local name = raw:match("^%S+%s+(%S+)")
        if name and ns.InviteToGuild then ns.InviteToGuild(name) else Print(L["Bitte einen Charakternamen eingeben."]) end
    elseif arg == "fehler" or arg == "errors" then
        if ns.ErrorReport then ns.ErrorReport() end
    elseif arg == "fehler löschen" or arg == "errors clear" then
        if ns.ClearErrors then ns.ClearErrors() end
    elseif arg == "bewerbungen" or arg == "applications" then
        if ns.ToggleApps then ns.ToggleApps() end
    elseif arg == "backup" or arg == "sicherung" then
        if ns.ToggleBackupWindow then ns.ToggleBackupWindow() end
    elseif arg == "ausweis" or arg == "id" then
        if ns.AusweisCommand then ns.AusweisCommand() end
    elseif arg == "werben" or arg == "recruit" then
        if ns.PostRecruitText then ns.PostRecruitText() end
    elseif arg == "optionen" or arg == "options" then
        if ns.SettingsCategory and Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(ns.SettingsCategory:GetID())
        elseif ns.SettingsPanel and InterfaceOptionsFrame_OpenToCategory then
            InterfaceOptionsFrame_OpenToCategory(ns.SettingsPanel)
            InterfaceOptionsFrame_OpenToCategory(ns.SettingsPanel)   -- zweimal: alter Blizzard-Fehler
        end
    else
        Print(L["Befehle: /gp (Fenster) · sound · popup · blizzard · einladen <Name> · werben · optionen · badge <Level> · version · kanal · server · ausweis · sicherung · fehler · bewerbungen"])
    end
end
