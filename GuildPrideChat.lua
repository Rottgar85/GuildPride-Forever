-- GuildPride: Chat im Gildenfenster
-- Bindet Blizzards Gildenchat, Offizierschat und alle eigenen Communities
-- (inkl. Server-Verlauf über C_Club) ein.
local ADDON, ns = ...
local L = ns.L
local MAX_SAVED = 60
local HISTORY = 150
local SendChat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
local HAS_CLUB = C_Club and C_Club.GetGuildClubId and C_Club.GetStreams and C_Club.GetMessageRanges

-- Reiter "Gilde & Chat" (GuildPrideUI.lua): Kanal-Leiste oben auf der Seite,
-- Nachrichten und Eingabe im Chat-Bereich links neben der Mitgliederliste
local page = ns.CommunityPage
local pane = ns.ChatPane

-- Aktueller Kanal: { kind = "GUILD" | "OFFICER" | "CLUB", clubId, streamId, label, club }
local channel = { kind = "GUILD", label = L["Gilde"] }

---------------------------------------------------------------------
-- Kanal-Leiste
---------------------------------------------------------------------
local bGuild = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
bGuild:SetSize(90, 24); bGuild:SetPoint("TOPLEFT", 0, 0); bGuild:SetText(L["Gilde"])
local bOfficer = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
bOfficer:SetSize(90, 24); bOfficer:SetPoint("LEFT", bGuild, "RIGHT", 6, 0); bOfficer:SetText(L["Offiziere"])
local bClub = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
bClub:SetSize(180, 24); bClub:SetPoint("LEFT", bOfficer, "RIGHT", 6, 0); bClub:SetText("Communities  ▾")
-- Lange Community-Namen abschneiden statt über den Knopf hinaus
if bClub:GetFontString() then bClub:GetFontString():SetWidth(164); bClub:GetFontString():SetWordWrap(false) end

---------------------------------------------------------------------
-- Nachrichtenfeld
---------------------------------------------------------------------
local box = CreateFrame("Frame", nil, pane)
box:SetPoint("TOPLEFT", 0, 0)
box:SetPoint("BOTTOMRIGHT", 0, 40)
local boxBg = box:CreateTexture(nil, "BACKGROUND")
boxBg:SetAllPoints(); boxBg:SetColorTexture(0, 0, 0, 0.45)
local boxEdge = box:CreateTexture(nil, "BORDER")
boxEdge:SetPoint("TOPLEFT"); boxEdge:SetPoint("BOTTOMLEFT"); boxEdge:SetWidth(3)
ns.Paint(boxEdge, "ember")

local msgs = CreateFrame("ScrollingMessageFrame", nil, box)
msgs:SetPoint("TOPLEFT", 12, -8)
msgs:SetPoint("BOTTOMRIGHT", -24, 8)
msgs:SetFontObject(GPFont_Chat)

-- Chat-Schriftgröße (Einstellungen, 10–18 pt)
function ns.SetChatFont(size)
    size = math.max(10, math.min(18, size or 12))
    GuildPrideDB.chatFont = size
    GPFont_Chat:SetFont(ns.FONT_TEXT, size, "")
end
msgs:SetJustifyH("LEFT")
msgs:SetFading(false)
msgs:SetMaxLines(300)
msgs:SetSpacing(3)
msgs:SetHyperlinksEnabled(true)
msgs:SetScript("OnHyperlinkClick", function(_, link, text, button) SetItemRef(link, text, button) end)
msgs:EnableMouseWheel(true)
msgs:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then self:ScrollUp() else self:ScrollDown() end
end)

-- Scrollbalken (Blizzards schmale Leiste, bewegt sich mit Mausrad und Verlauf)
if ScrollUtil and ScrollUtil.InitScrollingMessageFrameWithScrollBar then
    local bar = CreateFrame("EventFrame", nil, box, "MinimalScrollBar")
    bar:SetPoint("TOPRIGHT", -6, -8)
    bar:SetPoint("BOTTOMRIGHT", -6, 8)
    ScrollUtil.InitScrollingMessageFrameWithScrollBar(msgs, bar)
end

---------------------------------------------------------------------
-- Eingabe
---------------------------------------------------------------------
local input = CreateFrame("EditBox", nil, pane, "InputBoxTemplate")
input:SetPoint("BOTTOMLEFT", 8, 6)
input:SetPoint("BOTTOMRIGHT", -94, 6)
input:SetHeight(24)
input:SetAutoFocus(false)
input:SetMaxLetters(255)

local send = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
send:SetSize(86, 26)
send:SetPoint("BOTTOMRIGHT", 0, 5)
send:SetText(L["Senden"])

---------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------
local function ClassHex(classID, classFile)
    local file = classFile
    if classID and C_CreatureInfo and C_CreatureInfo.GetClassInfo then
        local info = C_CreatureInfo.GetClassInfo(classID)
        file = info and info.classFile or file
    end
    local c = file and RAID_CLASS_COLORS[file]
    return c and c.colorStr and c.colorStr:sub(3) or "f0c88c"
end

local TEXT_COLOR = { GUILD = "|cffe6e0da", OFFICER = "|cff40c040", CLUB = "|cff8fd3ff" }

-- Name noch nicht geladen? (Der Server liefert ältere Nachrichten oft ohne
-- Autorennamen; Blizzard zeigt dann "Unbekannt".)
-- Geschützte Werte (Midnight) zuerst prüfen: schon ein Vergleich wirft einen Fehler
local function Secret(v) return issecretvalue and issecretvalue(v) or false end

-- Kommt mein Name im Text vor (nicht in eigenen Nachrichten)?
local function MentionsMe(text, who)
    if Secret(text) or type(text) ~= "string" then return false end
    local me = UnitName("player")
    if not me or who == me or (who and ns.Normalize(who) == ns.Me()) then return false end
    return text:lower():find(me:lower(), 1, true) ~= nil
end

local Crown   -- unten, braucht IsUnknown

-- Discord-Logo vor Nachrichten, die über Blizzards Discord-Anbindung in den
-- Gildenchat kommen. Blizzard nutzt dafür den Atlas "UI-ChatIcon-Discord";
-- fehlt er im Client, steht dort "[Discord]" in Discord-Blau.
local DISCORD_ATLAS = "UI-ChatIcon-Discord"
local discordIcon
local function DiscordIcon()
    if not discordIcon then
        local ok = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(DISCORD_ATLAS)
        discordIcon = ok and ("|A:%s:0:0|a "):format(DISCORD_ATLAS) or "|cff5865f2[Discord]|r "
    end
    return discordIcon
end

local function Line(t, who, full, hex, text, kind, guid, discord)
    local name = full and ("|Hplayer:%s|h|cff%s%s|r|h"):format(full, hex, who) or ("|cff%s%s|r"):format(hex, who)
    -- Rang-Krone nur im Gilden- und Offizierschat: in Communities sagt der Gildenrang nichts aus
    if full and (kind == "GUILD" or kind == "OFFICER") then
        name = Crown(full, guid) .. name
        -- Twink: Main klein dahinter (GuildPrideAusweis.lua)
        local main = ns.MainOf and GuildPrideDB and GuildPrideDB.groupAlts ~= false and ns.MainOf(full)
        if main and main ~= full then name = name .. ("|cff777777 (%s)|r"):format(Ambiguate(main, "guild")) end
    end
    if discord then name = DiscordIcon() .. name end
    -- Erwähnung: » davor und goldene Schrift
    if MentionsMe(text, who) then
        return ("|cff777777%s|r  |cffffd100»|r %s: |cffffd100%s|r"):format(date("%H:%M", t), name, text)
    end
    return ("|cff777777%s|r  %s: %s%s|r"):format(date("%H:%M", t), name, TEXT_COLOR[kind] or "|cffffffff", text)
end

-- Geschützter Text: Midnight-Geheimwert oder Blizzards |K…|k-Platzhalter. Der
-- Platzhalter gilt nur in der laufenden Sitzung; gespeichert wird daraus später
-- "Unbekannt" (und jedes Mal ein neuer Eintrag, weil die Nummer wechselt).
local function IsProtected(text)
    if Secret(text) then return true end
    return type(text) == "string" and text:find("|K", 1, true) ~= nil
end

local function IsUnknown(name)
    if Secret(name) or type(name) ~= "string" then return true end
    return name == "" or name == "?" or name == UNKNOWNOBJECT or name == UNKNOWN
end

---------------------------------------------------------------------
-- Rang-Kronen: gefüllt für den Gildenmeister, leer (nur Umriss) für Offiziere
---------------------------------------------------------------------
-- Gildenmeister ist immer Rangindex 0. Einen festen Rang "Offizier" kennt WoW
-- nicht, darum gilt Rangindex 1, der höchste Rang unter dem Gildenmeister. Das
-- Recht "Offizierschat lesen" taugt nicht als Regel: Die Rechte ANDERER Ränge
-- kann nur die Gildenleitung lesen (siehe ns.CanSpeakGuild), normale Mitglieder
-- sähen also keine oder andere Kronen als die Offiziere. Der Rangindex steht für
-- alle gleich in der Gildenliste, und der Rangname wäre in jeder Gilde anders.
local CROWN_FILE = { [0] = "crown_gm", [1] = "crown_officer" }
-- Style "Schmiede" zeigt Grafiken in Originalfarben: dort Gold, sonst die
-- Überschriftenfarbe des Styles (die Grafiken selbst sind farblos)
local CROWN_GOLD = { 1.00, 0.82, 0.30 }

local crownByGuid, crownByName, crownByBare = {}, {}, {}
local crownsDirty = true

-- Liest die Gildenliste; true, wenn sich an den Kronen etwas geändert hat
local function LoadCrowns()
    crownsDirty = false
    local guids, names, bare = {}, {}, {}
    local inGuild = IsInGuild()
    -- Manche Clients liefern Offline-Mitglieder nur, wenn das eingeschaltet ist:
    -- bekannte Kronen dann behalten, sonst verlöre der Verlauf sie beim Ausloggen
    if inGuild and GetGuildRosterShowOffline and not GetGuildRosterShowOffline() then
        for k, v in pairs(crownByGuid) do guids[k] = v end
        for k, v in pairs(crownByName) do names[k] = v end
    end
    for i = 1, inGuild and GetNumGuildMembers() or 0 do
        local n, _, rank, _, _, _, _, _, _, _, _, _, _, _, _, _, g = GetGuildRosterInfo(i)
        if not IsUnknown(n) then
            -- Geschützte Werte (Midnight) nie als Schlüssel benutzen oder vergleichen
            local file = not Secret(rank) and CROWN_FILE[rank] or nil
            local key = ns.Normalize(n)
            names[key] = file
            if not Secret(g) and type(g) == "string" then guids[g] = file end
            -- Name ohne Realm bzw. Nachname; bei zwei Treffern false = nicht eindeutig
            local base = key:match("^[^%- ]+")
            if base then
                if bare[base] == nil then bare[base] = file or false else bare[base] = false end
            end
        end
    end
    local changed = false
    for k, v in pairs(names) do
        if crownByName[k] ~= v then changed = true end
    end
    for k in pairs(crownByName) do
        if names[k] == nil then changed = true end
    end
    crownByGuid, crownByName, crownByBare = guids, names, bare
    return changed
end

local function CrownMarkup(file)
    local theme = ns.Theme()
    local c = theme.tint and theme.heading or CROWN_GOLD
    -- Höhe 0 = so hoch wie die Schrift, wächst also mit der Chat-Schriftgröße mit
    return ("|T%s%s:0:0:0:0:64:64:0:64:0:64:%d:%d:%d|t "):format(ns.MEDIA, file,
        math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

-- Krone zum Absender, "" für alle anderen und für Absender außerhalb der Liste.
-- Reihenfolge: GUID (eindeutig), Name mit Realm bzw. Forever-Nachname (ns.Normalize),
-- zuletzt ein nackter Name, falls er in der Gilde nur einmal vorkommt.
function Crown(full, guid)
    if crownsDirty then LoadCrowns() end
    local file = not Secret(guid) and type(guid) == "string" and crownByGuid[guid] or nil
    if not file and not IsUnknown(full) then
        file = crownByName[ns.Normalize(full)]
        if not file and not full:find("[%- ]") then file = crownByBare[full] end
    end
    return file and CrownMarkup(file) or ""
end

-- Krone zum Rangindex, für die Mitgliederlisten (dort ist der Rang schon bekannt)
function ns.RankCrown(rankIndex)
    local file = not Secret(rankIndex) and CROWN_FILE[rankIndex] or nil
    return file and CrownMarkup(file) or ""
end

-- GUID -> Name aus der Gildenliste (für Gilden- und Offizierschat).
-- Neu einlesen, wenn die Liste leer ist oder eine GUID fehlt (höchstens alle 5 s),
-- sonst bleiben Namen direkt nach dem Login lange "Unbekannt".
local rosterByGuid, rosterAt, rosterCount = {}, -999, 0
local function RosterName(guid)
    if Secret(guid) or type(guid) ~= "string" or not IsInGuild() then return end
    if not rosterByGuid[guid] and (rosterCount == 0 or GetTime() - rosterAt > 5) then
        rosterAt = GetTime()
        wipe(rosterByGuid)
        rosterCount = 0
        for i = 1, GetNumGuildMembers() do
            local n, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, g = GetGuildRosterInfo(i)
            if not IsUnknown(n) and type(g) == "string" and not Secret(g) then
                rosterByGuid[g] = n
                rosterCount = rosterCount + 1
            end
        end
    end
    return rosterByGuid[guid]
end

-- Mitglieds-ID -> Name über die komplette Mitgliederliste des Clubs
-- (einzelnes GetMemberInfo liefert für ältere Nachrichten oft nichts)
local memberNames, memberAt = {}, {}
function ns.ClubMemberName(clubId, memberId)
    local map = memberNames[clubId]
    if (not map or not map[memberId]) and GetTime() - (memberAt[clubId] or -999) > 5
       and C_Club.GetClubMembers and C_Club.GetMemberInfo then
        memberAt[clubId] = GetTime()
        map = {}
        memberNames[clubId] = map
        for _, id in ipairs(C_Club.GetClubMembers(clubId) or {}) do
            local ok, info = pcall(C_Club.GetMemberInfo, clubId, id)
            if ok and info and not IsUnknown(info.name) then map[id] = info.name end
        end
    end
    return map and map[memberId]
end

-- Autorennamen nachschlagen: eigene Nachricht, Gildenliste, Mitgliederliste
-- des Clubs, sonst über die GUID
local function AuthorName(clubId, a)
    local name = a.name
    if IsUnknown(name) then name = nil end
    if not name and a.isSelf == true then
        name = ns.Me()
    end
    local guid = (not Secret(a.guid) and type(a.guid) == "string" and a.guid ~= "") and a.guid or nil
    if not name and guid then name = RosterName(guid) end
    if not name and clubId and a.memberId and not Secret(a.memberId) and C_Club.GetMemberInfo then
        local ok, info = pcall(C_Club.GetMemberInfo, clubId, a.memberId)
        if ok and info and not IsUnknown(info.name) then
            name = info.name
            if not Secret(info.classID) then a.classID = a.classID or info.classID end
        end
    end
    if not name and clubId and a.memberId and not Secret(a.memberId) then
        name = ns.ClubMemberName and ns.ClubMemberName(clubId, a.memberId)
    end
    if not name and guid and GetPlayerInfoByGUID then
        local ok, _, _, _, _, _, n, realm = pcall(GetPlayerInfoByGUID, guid)
        if ok and not IsUnknown(n) then
            name = (type(realm) == "string" and not Secret(realm) and realm ~= "") and (n .. "-" .. realm) or n
        end
    end
    return name
end

-- Discord-Absender: Blizzards discordInfo -> Anzeigename, Charakter-Link, Farbe.
-- Je nach Einstellung des Schreibers sein zuletzt gespielter Charakter
-- (mit Klassenfarbe und Link) oder sein Discord-Name (ohne Link, Discord-Farbe).
local DISCORD_NAME_HEX = "e0e3ff"
local function DiscordAuthor(d)
    if type(d) ~= "table" or Secret(d.fromDiscord) or d.fromDiscord ~= true then return nil end
    local globalType = Enum and Enum.DiscordDisplayNameType and Enum.DiscordDisplayNameType.GlobalName or 2
    local useGlobal = Secret(d.type) or d.type == globalType
    local char = d.lastOnlineName
    if not useGlobal and not IsUnknown(char) then
        local guid = d.lastOnlineGUID
        local class
        if not Secret(guid) and type(guid) == "string" and guid ~= "" and GetPlayerInfoByGUID then
            local ok, _, c = pcall(GetPlayerInfoByGUID, guid)
            if ok and not Secret(c) then class = c end
        end
        return Ambiguate(char, "guild"), char, ClassHex(nil, class)
    end
    local g = d.globalName
    -- Discord-Namen sind frei wählbar: keine Farb- oder Link-Codes durchlassen
    g = not IsUnknown(g) and g:gsub("|", ""):sub(1, 40) or ""
    if g == "" then g = "Discord" end
    return g, nil, DISCORD_NAME_HEX
end

-- Server-Nachricht -> gespeicherter Eintrag { t, who, full, hex, text, memberId, guid, discord }
-- allowSecret: geschützter Text (Midnight, z. B. im Schlachtfeld) nur zum
-- Anzeigen – nicht vergleichen, nicht speichern
local function ClubEntry(clubId, m, kind, allowSecret)
    if not m or m.destroyed or not m.content then return end
    if Secret(m.content) and not allowSecret then return end
    if ns.HideBridgeLine and ns.HideBridgeLine(m.content) then return end
    local a = m.author or {}
    local full = AuthorName(clubId, a)
    local epoch = m.messageId and m.messageId.epoch
    local t = GetServerTime()
    if type(epoch) == "number" and not Secret(epoch) then
        -- Retail liefert Mikrosekunden, Classic-Clients teils Milli- oder ganze Sekunden
        if epoch > 1e14 then t = epoch / 1000000
        elseif epoch > 1e11 then t = epoch / 1000
        elseif epoch > 1e8 then t = epoch end
    end
    -- Battle.net-Communities: kein Charaktername -> kein Player-Link
    local link = full and (kind ~= "CLUB" or a.clubType ~= Enum.ClubType.BattleNet) and full or nil
    local dWho, dFull, dHex = DiscordAuthor(a.discordInfo)
    if dWho then
        return { t = t, who = dWho, full = dFull, hex = dHex, text = m.content, memberId = a.memberId,
                 isSelf = a.isSelf, discord = true }
    end
    return { t = t, who = full and Ambiguate(full, "guild") or nil, full = link, hex = ClassHex(not Secret(a.classID) and a.classID or nil),
             text = m.content, memberId = a.memberId, guid = a.guid, isSelf = a.isSelf }
end

local function EntryLine(e, kind)
    -- Ohne Namen: Blizzard liefert keine Namen für Leute, die nicht mehr im Club sind
    if not e.who then return Line(e.t, L["Ehemaliges Mitglied"], nil, "888888", e.text, kind, nil, e.discord) end
    return Line(e.t, e.who, e.full, e.hex, e.text, kind, e.guid, e.discord)
end

-- Verlauf je Kanal lokal merken: der Server liefert nach dem Login oft nur
-- einen Teil, so bleibt das bisher Gesagte trotzdem sichtbar.
local CACHE_MAX = 200

local cleaned = {}
local function Cache(clubId, streamId)
    GuildPrideDB.clubCache = GuildPrideDB.clubCache or {}
    local key = tostring(clubId) .. ":" .. tostring(streamId)
    local cache = GuildPrideDB.clubCache[key]
    if not cache then
        cache = {}
        GuildPrideDB.clubCache[key] = cache
        cleaned[key] = true
    end
    -- Alte gespeicherte Platzhalter (siehe IsProtected) einmal pro Sitzung entfernen
    if not cleaned[key] then
        cleaned[key] = true
        for i = #cache, 1, -1 do
            -- t < 1e9: Zeitstempel in falscher Einheit gespeichert (frühe Classic-Tests)
            if IsProtected(cache[i].text) or (cache[i].t or 0) < 1e9 then table.remove(cache, i) end
        end
    end
    return cache
end

-- Dieselbe Nachricht? Gleicher Text und zeitlich nah beieinander (Chat-Ereignis
-- und Server-Verlauf haben andere Zeitstempel). Fehlt einer Seite der Name,
-- großzügiger vergleichen – sonst taucht sie doppelt als "Unbekannt" auf.
-- Namen ohne Realm vergleichen: Server-Verlauf und Chat-Ereignis liefern den
-- Realm in Classic nicht immer gleich ("Name" gegenüber "Name-Realm").
local function BaseName(n) return (n:gsub("%-.*$", "")) end
-- Text ohne Farbcodes und überzählige Leerzeichen: Chat-Ereignis und Server-Verlauf
-- liefern denselben Text in Classic teils unterschiedlich (z. B. Leerzeichen am Ende)
local function NormText(s)
    if type(s) ~= "string" or Secret(s) then return s end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s+", " ")
    return strtrim(s)
end
local function Same(a, b)
    if a.text ~= b.text and NormText(a.text) ~= NormText(b.text) then return false end
    local dt = math.abs((a.t or 0) - (b.t or 0))
    if a.who and b.who then return BaseName(a.who) == BaseName(b.who) and dt < 120 end
    return dt < 900
end

-- Einträge in den Speicher übernehmen: ohne Doppelte, fehlende Namen ergänzen
local function Remember(cache, entries)
    local changed = false
    for _, e in ipairs(entries) do
        local found
        for i = #cache, 1, -1 do
            if Same(cache[i], e) then found = cache[i]; break end
        end
        if found then
            if e.discord and not found.discord then
                found.who, found.full, found.hex, found.discord = e.who, e.full, e.hex, true
                changed = true
            end
            if not found.who and e.who then
                found.who, found.full, found.hex = e.who, e.full, e.hex
                changed = true
            end
            found.memberId, found.guid = found.memberId or e.memberId, found.guid or e.guid
        else
            cache[#cache + 1] = e
            changed = true
        end
    end
    if changed then
        table.sort(cache, function(a, b) return a.t < b.t end)
        while #cache > CACHE_MAX do table.remove(cache, 1) end
    end
end

-- Alte Einträge ohne Namen beim Anzeigen erneut nachschlagen; was dann noch
-- namenlos ist, aber als Eintrag mit Namen schon existiert, fliegt raus
local function FixNames(clubId, cache)
    for _, e in ipairs(cache) do
        if not e.who or IsUnknown(e.who) then
            local full = AuthorName(clubId, { memberId = e.memberId, guid = e.guid, isSelf = e.isSelf })
            if full then e.who, e.full = Ambiguate(full, "guild"), full end
            if IsUnknown(e.who) then e.who = nil end
        end
    end
    for i = #cache, 1, -1 do
        local e = cache[i]
        if not e.who then
            for j = 1, #cache do
                if j ~= i and cache[j].who and Same(cache[j], e) then table.remove(cache, i); break end
            end
        end
    end
    -- Schon gespeicherte Doppelte (älterer Classic-Vergleich) entfernen; die Liste
    -- ist nach Zeit sortiert, daher nur die nahen Vorgänger prüfen
    for i = #cache, 2, -1 do
        local e = cache[i]
        for j = i - 1, 1, -1 do
            if (e.t or 0) - (cache[j].t or 0) > 900 then break end
            if Same(cache[j], e) then table.remove(cache, i); break end
        end
    end
end

-- Welcher Club/Stream gehört zum aktuellen Kanal?
local function Resolve(ch)
    if not HAS_CLUB then return end
    if ch.kind == "CLUB" then return ch.clubId, ch.streamId end
    local clubId = C_Club.GetGuildClubId()
    if not clubId then return end
    local want = ch.kind == "OFFICER" and Enum.ClubStreamType.Officer or Enum.ClubStreamType.Guild
    for _, st in ipairs(C_Club.GetStreams(clubId) or {}) do
        if not Secret(st.streamType) and st.streamType == want then return clubId, st.streamId end
    end
end

-- Lokaler Fallback (Clients ohne C_Club)
local function Store()
    local s = ns.GuildTable("chat")   -- je Gilde getrennt
    s.GUILD, s.OFFICER = s.GUILD or {}, s.OFFICER or {}
    return s
end

---------------------------------------------------------------------
-- Ungelesen: Zähler je Kanal ("GUILD", "OFFICER", "clubId:streamId")
---------------------------------------------------------------------
local unread = {}

local function ChannelKey(ch)
    if ch.kind == "CLUB" then return tostring(ch.clubId) .. ":" .. tostring(ch.streamId) end
    return ch.kind
end

-- Gilden-Streams auf "GUILD"/"OFFICER" abbilden, alles andere "clubId:streamId"
local function StreamKey(clubId, streamId)
    for _, kind in ipairs({ "GUILD", "OFFICER" }) do
        local c, s = Resolve({ kind = kind })
        if c and c == clubId and s == streamId then return kind end
    end
    return tostring(clubId) .. ":" .. tostring(streamId)
end

local function Count(text, n)
    return n and n > 0 and (text .. "  |cffff8c40(" .. n .. ")|r") or text
end

local function ClubUnread(clubId)
    local n, prefix = 0, tostring(clubId) .. ":"
    for k, v in pairs(unread) do
        if k:sub(1, #prefix) == prefix then n = n + v end
    end
    return n
end

local UpdateBadges   -- unten, braucht die Kanal-Knöpfe

local function MarkUnread(key)
    if pane:IsVisible() and ChannelKey(channel) == key then return end
    unread[key] = (unread[key] or 0) + 1
    UpdateBadges()
end

---------------------------------------------------------------------
-- Anzeigen
---------------------------------------------------------------------
local requested = {}
local focused

local function Redraw()
    msgs:Clear()
    if HAS_CLUB then
        local clubId, streamId = Resolve(channel)
        if not clubId then
            msgs:AddMessage(L["|cff888888Chat wird geladen …|r"])
            return
        end
        -- Stream "fokussieren", damit der Server den Verlauf schickt
        if C_Club.FocusStream then
            if focused and C_Club.UnfocusStream and (focused[1] ~= clubId or focused[2] ~= streamId) then
                C_Club.UnfocusStream(focused[1], focused[2])
            end
            C_Club.FocusStream(clubId, streamId)
            focused = { clubId, streamId }
        end
        -- ALLE geladenen Bereiche lesen (früher nur den letzten -> älterer Verlauf fehlte)
        local ranges = C_Club.GetMessageRanges(clubId, streamId) or {}
        local server, oldest = {}, nil
        for _, rg in ipairs(ranges) do
            local o = rg.oldestMessageId
            if o and not Secret(o.epoch) and (not oldest or (o.epoch or 0) < (oldest.epoch or 0)) then oldest = o end
            for _, m in ipairs(C_Club.GetMessagesInRange(clubId, streamId, rg.oldestMessageId, rg.newestMessageId) or {}) do
                -- Eine kaputte Nachricht darf nicht den ganzen Verlauf verhindern
                local ok, e = pcall(ClubEntry, clubId, m, channel.kind, true)
                if ok and e then server[#server + 1] = e end
            end
        end
        -- Geschützter Text (|K…|k bzw. Midnight-Geheimwert) gilt nur in dieser
        -- Sitzung: nie speichern, sondern jedes Mal frisch vom Server anzeigen
        local plain, protected = {}, {}
        for _, e in ipairs(server) do
            if IsProtected(e.text) then protected[#protected + 1] = e else plain[#plain + 1] = e end
        end
        local cache = Cache(clubId, streamId)
        Remember(cache, plain)
        FixNames(clubId, cache)
        local show, claimed = {}, {}
        for _, e in ipairs(cache) do show[#show + 1] = e end
        -- Classic liefert den Server-Verlauf der Gilde komplett geschützt, dieselbe
        -- Nachricht steht aber schon im Klartext (Chat-Ereignis) im Speicher. Da sich
        -- der Text nicht vergleichen lässt: gleicher Autor zur gleichen Zeit = doppelt.
        for _, e in ipairs(protected) do
            local dup = false
            if e.who then
                for i, c in ipairs(cache) do
                    if not claimed[i] and c.who and BaseName(c.who) == BaseName(e.who)
                       and math.abs((c.t or 0) - (e.t or 0)) < 120 then
                        claimed[i] = true; dup = true; break
                    end
                end
            end
            if not dup then show[#show + 1] = e end
        end
        for i, e in ipairs(show) do e.order = i end
        table.sort(show, function(a, b)
            if a.t ~= b.t then return a.t < b.t end
            return a.order < b.order
        end)
        if #show == 0 then
            msgs:AddMessage(L["|cff888888Noch keine Nachrichten.|r"])
        end
        for i = math.max(1, #show - HISTORY + 1), #show do
            msgs:AddMessage(EntryLine(show[i], channel.kind))
        end
        -- Mehr Verlauf vom Server holen (höchstens alle 30 Sekunden je Kanal)
        local key = clubId .. ":" .. streamId
        if #server < HISTORY and C_Club.RequestMoreMessagesBefore and GetTime() - (requested[key] or -999) > 30 then
            requested[key] = GetTime()
            C_Club.RequestMoreMessagesBefore(clubId, streamId, oldest, HISTORY)
        end
    else
        if channel.kind == "CLUB" then return end
        for _, e in ipairs(Store()[channel.kind] or {}) do
            msgs:AddMessage(Line(e.t, e.who, e.full, (e.discord and not e.full) and DISCORD_NAME_HEX or ClassHex(nil, e.class), e.text, e.ch, nil, e.discord))
        end
    end
    msgs:ScrollToBottom()
end

local function Highlight()
    local function set(btn, on)
        if btn.gpBg then btn.gpBg:SetTexture(ns.MEDIA .. (on and "nav_active" or "nav")) end
    end
    set(bGuild, channel.kind == "GUILD")
    set(bOfficer, channel.kind == "OFFICER")
    set(bClub, channel.kind == "CLUB")
    UpdateBadges()
end

-- Kanal-Knöpfe mit Zählern beschriften, Summe am Reiter "Gilde & Chat"
function UpdateBadges()
    bGuild:SetText(Count(L["Gilde"], unread.GUILD))
    bOfficer:SetText(Count(L["Offiziere"], bOfficer:IsShown() and unread.OFFICER or 0))
    local clubs = 0
    for k, v in pairs(unread) do
        if k ~= "GUILD" and k ~= "OFFICER" then clubs = clubs + v end
    end
    -- Gewählte Community steht im Knopf
    local label = channel.kind == "CLUB" and not Secret(channel.label) and channel.label or nil
    bClub:SetText(Count(label and (label .. "  ▾") or "Communities  ▾", clubs))
    local total = (unread.GUILD or 0) + (bOfficer:IsShown() and unread.OFFICER or 0) + clubs
    if ns.SetTabBadge then ns.SetTabBadge(page, total > 0 and ("(" .. total .. ")") or nil) end
end

-- Im Schlachtfeld liefert der Server teils geschützte Werte; ein Fehler beim
-- Anzeigen darf den Kanalwechsel nicht blockieren
local function SafeRedraw()
    local ok = pcall(Redraw)
    if not ok then
        msgs:Clear()
        msgs:AddMessage(L["|cff888888Verlauf hier gerade nicht verfügbar (Blizzard-Schutz in Instanzen).|r"])
    end
end

local function SetChannel(ch)
    channel = ch
    if pane:IsVisible() then unread[ChannelKey(ch)] = nil end
    Highlight()
    -- Mitgliederliste daneben zeigt dieselbe Gilde bzw. Community
    if ns.SetMemberSource then ns.SetMemberSource(ch.kind == "CLUB" and ch.club or nil) end
    SafeRedraw()
end

bGuild:SetScript("OnClick", function() SetChannel({ kind = "GUILD", label = L["Gilde"] }) end)
bOfficer:SetScript("OnClick", function() SetChannel({ kind = "OFFICER", label = L["Offiziere"] }) end)

---------------------------------------------------------------------
-- Community-Auswahl (alle Blizzard-Communities, außer der Gilde)
---------------------------------------------------------------------
local function Communities()
    local out = {}
    if not (HAS_CLUB and ns.HAS_COMMUNITIES and C_Club.GetSubscribedClubs) then return out end
    for _, club in ipairs(C_Club.GetSubscribedClubs() or {}) do
        -- Geschützte Werte (Schlachtfeld) nicht vergleichen
        if not Secret(club.clubType) and not Secret(club.clubId) and club.clubType ~= Enum.ClubType.Guild then
            local streams = {}
            for _, st in ipairs(C_Club.GetStreams(club.clubId) or {}) do
                local n = st.name
                if Secret(n) or type(n) ~= "string" or n == "" then n = L["Allgemein"] end
                if not Secret(st.streamId) then streams[#streams + 1] = { id = st.streamId, name = n } end
            end
            local name = club.name
            if Secret(name) or type(name) ~= "string" then name = "Community " .. tostring(club.clubId) end
            out[#out + 1] = { id = club.clubId, name = name, bnet = club.clubType == Enum.ClubType.BattleNet, streams = streams }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

local function Pick(club, st)
    local label = #club.streams > 1 and (club.name .. " · " .. st.name) or club.name
    SetChannel({ kind = "CLUB", clubId = club.id, streamId = st.id, label = label,
                 club = { id = club.id, name = club.name, bnet = club.bnet } })
end

bClub:SetScript("OnClick", function(self)
    local list = Communities()
    if #list == 0 then
        ns.Print(L["Du bist in keiner Blizzard-Community."])
        return
    end
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle("Communities")
            for _, club in ipairs(list) do
                local label = Count(club.name .. (club.bnet and " |cff82c5ff(Battle.net)|r" or ""), ClubUnread(club.id))
                if #club.streams <= 1 then
                    local st = club.streams[1]
                    if st then root:CreateButton(label, function() Pick(club, st) end) end
                else
                    local sub = root:CreateButton(label)
                    for _, st in ipairs(club.streams) do
                        local n = unread[tostring(club.id) .. ":" .. tostring(st.id)]
                        sub:CreateButton(Count(st.name, n), function() Pick(club, st) end)
                    end
                end
            end
        end)
    else
        -- Fallback: der Reihe nach durchschalten
        local flat = {}
        for _, c in ipairs(list) do for _, st in ipairs(c.streams) do flat[#flat + 1] = { c, st } end end
        local idx = 1
        for i, p in ipairs(flat) do
            if channel.kind == "CLUB" and p[1].id == channel.clubId and p[2].id == channel.streamId then idx = i % #flat + 1 end
        end
        Pick(flat[idx][1], flat[idx][2])
    end
end)

---------------------------------------------------------------------
-- Senden
---------------------------------------------------------------------
local function Send()
    local text = strtrim(input:GetText() or "")
    if text == "" then input:ClearFocus(); return end
    -- Befehle nicht in den Chat schicken: /gp selbst ausführen, alles andere
    -- an die normale Chat-Eingabe weiterreichen (dort mit Enter bestätigen)
    if text:sub(1, 1) == "/" then
        input:SetText("")
        local cmd, rest = text:match("^/(%S+)%s*(.*)$")
        cmd = (cmd or ""):lower()
        if (cmd == "gp" or cmd == "guildpride") and SlashCmdList.GUILDPRIDE then
            SlashCmdList.GUILDPRIDE(rest or "")
        elseif ChatFrame_OpenChat then
            ChatFrame_OpenChat(text)
        end
        return
    end
    if channel.kind == "CLUB" then
        local ok, err = pcall(C_Club.SendMessage, channel.clubId, channel.streamId, text)
        if not ok then
            ns.Print(L["|cffff4040Nachricht konnte nicht gesendet werden:|r "] .. (Secret(err) and "?" or tostring(err)))
            return
        end
    else
        SendChat(text, channel.kind)
    end
    input:SetText("")
end
send:SetScript("OnClick", Send)
input:SetScript("OnEnterPressed", Send)
input:SetScript("OnEscapePressed", input.ClearFocus)

-- Aufgerufen von "Gilde & Chat" (GuildPrideUI.lua) beim Anzeigen/Aktualisieren
function ns.ChatRefresh()
    local canOfficer = (C_GuildInfo and C_GuildInfo.CanViewOfficerNote and C_GuildInfo.CanViewOfficerNote())
        or (CanViewOfficerNote and CanViewOfficerNote())
    bOfficer:SetShown(canOfficer and true or false)
    bClub:ClearAllPoints()
    bClub:SetPoint("LEFT", canOfficer and bOfficer or bGuild, "RIGHT", 6, 0)
    -- Communities gibt es in den Classic-Clients nicht
    bClub:SetShown(HAS_CLUB and ns.HAS_COMMUNITIES and C_Club.GetSubscribedClubs and true or false)
    if not canOfficer and channel.kind == "OFFICER" then channel = { kind = "GUILD", label = L["Gilde"] } end
    SetChannel(channel)
end

-- Chat ausgeblendet (anderer Reiter oder große Mitgliederliste): Stream freigeben
pane:SetScript("OnHide", function()
    if focused and C_Club and C_Club.UnfocusStream then
        C_Club.UnfocusStream(focused[1], focused[2])
        focused = nil
    end
end)
pane:SetScript("OnShow", function()
    unread[ChannelKey(channel)] = nil
    UpdateBadges()
    SafeRedraw()
end)

---------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------
local f = CreateFrame("Frame")
if HAS_CLUB then
    local pendingRedraw
    local function RedrawSoon()
        if pendingRedraw then return end
        pendingRedraw = C_Timer.NewTimer(0.5, function() pendingRedraw = nil; if pane:IsVisible() then SafeRedraw() end end)
    end
    local recent = {}   -- zuletzt live gezeigte Nachrichten (gegen doppelte Ereignisse)
    -- CLUB_MEMBER(S)_UPDATED: Autorennamen kommen oft erst später
    ns.RegisterEvents(f, "CLUB_MESSAGE_ADDED", "CLUB_MESSAGE_HISTORY_RECEIVED", "CLUB_STREAMS_LOADED",
        "CLUB_MESSAGE_UPDATED", "CLUB_MEMBER_UPDATED", "CLUB_MEMBERS_UPDATED")
    f:SetScript("OnEvent", function(_, event, clubId, streamId, messageId)
        if event == "CLUB_MESSAGE_ADDED" then
            -- Auch bei geschlossenem Fenster merken, damit der Verlauf vollständig bleibt
            local kind = channel.kind == "CLUB" and "CLUB" or "GUILD"
            local ok, e = pcall(ClubEntry, clubId, C_Club.GetMessageInfo(clubId, streamId, messageId), kind, true)
            if not ok or not e or not GuildPrideDB then return end
            -- Geschützt: nicht speichern (der Server liefert sie beim nächsten Anzeigen neu)
            if not IsProtected(e.text) then
                Remember(Cache(clubId, streamId), { e })
            end
            -- Classic meldet neue Nachrichten teils zweimal: dieselbe nur einmal zeigen/zählen
            local key = StreamKey(clubId, streamId)
            if not IsProtected(e.text) then
                for _, s in ipairs(recent) do
                    if s.key == key and Same(s.e, e) then return end
                end
                table.insert(recent, { key = key, e = e })
                if #recent > 20 then table.remove(recent, 1) end
            end
            -- Ungelesen zählen (eigene Nachrichten nicht)
            if e.isSelf ~= true and not (e.full and e.full == ns.Me()) then
                MarkUnread(key)
            end
            local myClub, myStream = Resolve(channel)
            if pane:IsVisible() and clubId == myClub and streamId == myStream then
                msgs:AddMessage(EntryLine(e, channel.kind))
            end
            return
        end
        if not pane:IsVisible() then return end
        local myClub = Resolve(channel)
        if clubId == myClub then RedrawSoon() end
    end)

    -- Gilden- und Offizierschat zusätzlich über die normalen Chat-Ereignisse merken:
    -- dort ist der Name immer bekannt (auch wenn der Server-Verlauf ihn nicht liefert)
    local gc = CreateFrame("Frame")
    gc:RegisterEvent("CHAT_MSG_GUILD")
    gc:RegisterEvent("CHAT_MSG_OFFICER")
    gc:SetScript("OnEvent", function(_, event, text, author, _, _, _, flags, _, _, _, _, _, guid, ...)
        if issecretvalue and (issecretvalue(text) or issecretvalue(author) or issecretvalue(guid)) then return end
        if not GuildPrideDB or type(text) ~= "string" or type(author) ~= "string" or author == "" then return end
        if ns.HideBridgeLine and ns.HideBridgeLine(text) then return end
        local clubId, streamId = Resolve({ kind = event == "CHAT_MSG_OFFICER" and "OFFICER" or "GUILD" })
        if not clubId then return end
        -- Discord: Kennzeichen "DISCORD" (6.) bzw. discordInfo (18. Wert)
        local dWho, dFull, dHex = DiscordAuthor((select(6, ...)))
        if not dWho and not Secret(flags) and flags == "DISCORD" then
            dWho, dFull, dHex = (Ambiguate(author, "guild"):gsub("|", "")), nil, DISCORD_NAME_HEX
        end
        if dWho then
            Remember(Cache(clubId, streamId), { { t = GetServerTime(), who = dWho, full = dFull, hex = dHex,
                text = text, discord = true } })
            return
        end
        local _, class = nil, nil
        if guid and guid ~= "" and GetPlayerInfoByGUID then _, class = GetPlayerInfoByGUID(guid) end
        Remember(Cache(clubId, streamId), { { t = GetServerTime(), who = Ambiguate(author, "guild"), full = author,
            hex = ClassHex(nil, class), text = text, guid = guid } })
    end)
else
    f:RegisterEvent("CHAT_MSG_GUILD")
    f:RegisterEvent("CHAT_MSG_OFFICER")
    f:SetScript("OnEvent", function(_, event, text, author, _, _, _, flags, _, _, _, _, _, guid, ...)
        if issecretvalue and (issecretvalue(text) or issecretvalue(author)) then return end
        if not GuildPrideDB then return end
        if ns.HideBridgeLine and ns.HideBridgeLine(text) then return end
        local ch = event == "CHAT_MSG_OFFICER" and "OFFICER" or "GUILD"
        local list = Store()[ch]
        local _, class = (guid and guid ~= "" and GetPlayerInfoByGUID) and GetPlayerInfoByGUID(guid)
        local e = { t = time(), ch = ch, who = Ambiguate(author, "guild"), full = author, text = text, class = class }
        local dWho, dFull = DiscordAuthor((select(6, ...)))
        if dWho or (not Secret(flags) and flags == "DISCORD") then
            e.who, e.full, e.discord = dWho or (e.who:gsub("|", "")), dFull, true
        end
        table.insert(list, e)
        while #list > MAX_SAVED do table.remove(list, 1) end
        if ns.Normalize(author) ~= ns.Me() and Ambiguate(author, "guild") ~= UnitName("player") then MarkUnread(ch) end
        if pane:IsVisible() and channel.kind == ch then
            msgs:AddMessage(Line(e.t, e.who, e.full, (e.discord and not e.full) and DISCORD_NAME_HEX or ClassHex(nil, e.class), e.text, ch, nil, e.discord))
        end
    end)
end

-- Kronen aktuell halten: Die Gildenliste kommt nach dem Öffnen oft erst später an,
-- und Ränge ändern sich. Neu zeichnen nur bei echter Änderung, denn das springt
-- im Verlauf nach unten und die Liste meldet sich sehr oft.
local crownWatch = CreateFrame("Frame")
crownWatch:RegisterEvent("GUILD_ROSTER_UPDATE")
crownWatch:RegisterEvent("GUILD_RANKS_UPDATE")
crownWatch:SetScript("OnEvent", function()
    if not pane:IsVisible() or channel.kind == "CLUB" then
        crownsDirty = true
    elseif LoadCrowns() then
        SafeRedraw()
    end
end)
-- Style gewechselt: Kronen in der neuen Farbe zeigen
ns.OnThemeChanged(function()
    if pane:IsVisible() then SafeRedraw() end
end)

-- Gespeicherte Chat-Schriftgröße nach dem Login anwenden
local lf = CreateFrame("Frame")
lf:RegisterEvent("PLAYER_LOGIN")
lf:SetScript("OnEvent", function() ns.SetChatFont(GuildPrideDB.chatFont) end)
