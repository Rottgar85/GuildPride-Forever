-- GuildPride: Event-Planer mit Anmeldung (synchronisiert über Addon-Nachrichten)
local ADDON, ns = ...
local L = ns.L
local PREFIX = "GuildPride"
local SEP = "\031"
local ROLES = {
    TANK   = { short = "T", label = "Tank",   color = "|cff6fa8ff" },
    HEALER = { short = "H", label = L["Heiler"], color = "|cff40ff40" },
    DAMAGER= { short = "D", label = L["DD"],     color = "|cffff6060" },
}

local STATUS = {
    yes   = { label = L["Zugesagt"],   color = "|cff40ff40" },
    maybe = { label = L["Vielleicht"], color = "|cffffd100" },
    no    = { label = L["Abgesagt"],   color = "|cffff4040" },
}

---------------------------------------------------------------------
-- Daten
---------------------------------------------------------------------
local function DB()
    return ns.GuildTable("events")   -- je Gilde getrennt
end

-- Addon-Flüstern an Spieler, die inzwischen offline sind, erzeugt sonst
-- "Momentan ist kein Spieler mit dem Namen ... online." im Chat
local whisperedAt = {}
function ns.SendAddonMsg(prefix, msg, channel, target)
    if channel == "WHISPER" and target then
        whisperedAt[target] = GetTime()
        whisperedAt[(target:match("^[^-]+")) or target] = GetTime()
    end
    return C_ChatInfo.SendAddonMessage(prefix, msg, channel, target)
end
local AddSystemFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
if AddSystemFilter and ERR_CHAT_PLAYER_NOT_FOUND_S then
    local pattern = "^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
    AddSystemFilter("CHAT_MSG_SYSTEM", function(_, _, text)
        if issecretvalue and issecretvalue(text) then return false end
        local who = text and text:match(pattern)
        if not who then return false end
        local t = whisperedAt[who] or whisperedAt[(who:match("^[^-]+")) or who]
        return t ~= nil and GetTime() - t < 10
    end)
end

local function Me()
    return ns.Me()
end

local function CanManage()
    -- Offiziere (wer die Gildennachricht ändern darf) dürfen Events anlegen/löschen
    return CanEditMOTD and CanEditMOTD()
end

local function Now() return GetServerTime() end

local function Clean(s, max)
    s = (tostring(s or ""):gsub("[%c|]", ""))
    return s:sub(1, max)
end

---------------------------------------------------------------------
-- Senden (mit Warteschlange gegen Drosselung)
---------------------------------------------------------------------
-- Der Server drosselt Addon-Nachrichten pro Prefix. Gedrosselte Nachrichten
-- gingen früher verloren; jetzt kommen sie zurück in die Warteschlange.
local queue = {}
local publicQueue = {}   -- serverweite Gruppensuche (Ziel "@PUBLIC"), eigener Takt
local pauseUntil = 0
local RESULT = Enum and Enum.SendAddonMessageResult
local function Throttled(res)
    if not RESULT then return false end
    return (RESULT.AddonMessageThrottle ~= nil and res == RESULT.AddonMessageThrottle)
        or (RESULT.ChannelThrottle ~= nil and res == RESULT.ChannelThrottle)
end

---------------------------------------------------------------------
-- Ränge ohne Gildenchat-Recht
-- Wer im Gildenchat nicht schreiben darf, kann auch keine Addon-Nachrichten an
-- die Gilde schicken. Solche Nachrichten gehen deshalb als Flüstern ("RLY") an
-- ein GuildPride-Mitglied mit Schreibrecht, das sie unter dem ursprünglichen
-- Namen an die Gilde weitergibt ("FWD", siehe GuildPride.lua).
---------------------------------------------------------------------
local function RankFlags(rankIndex)
    if not (rankIndex and C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags) then return nil end
    return C_GuildInfo.GuildControlGetRankFlags(rankIndex + 1)
end

-- Nur ein ausdrückliches "Nein" zählt. Achtung: Die Rangrechte ANDERER Ränge
-- kann nur die Gildenleitung lesen – für normale Mitglieder kommt dort "aus"
-- zurück. Darauf darf das Senden deshalb nie beruhen.
function ns.CanSpeakGuild()
    if C_GuildInfo and C_GuildInfo.CanSpeakInGuildChat then return C_GuildInfo.CanSpeakInGuildChat() ~= false end
    return true
end

function ns.CanListenGuild()
    local _, _, rankIndex = GetGuildInfo("player")
    local flags = RankFlags(rankIndex)
    if not flags or flags[1] == nil then return true end
    return flags[1] and true or false
end

-- Wer leitet weiter? Bekannte GuildPride-Nutzer zuerst (bis zu 2), sonst bis
-- zu 3 zufällige Mitglieder online (Addon-Nachrichten sind für Spieler ohne
-- GuildPride unsichtbar). Wer selbst nicht schreiben darf, leitet nicht weiter.
local function Relays()
    local known, others = {}, {}
    local me = Me()
    for i = 1, GetNumGuildMembers() do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if name and online then
            local full = ns.FullName and ns.FullName(name) or name
            if full ~= me then
                if ns.AddonUsers and ns.AddonUsers[full] then known[#known + 1] = full else others[#others + 1] = full end
            end
        end
    end
    local list = #known > 0 and known or others
    local pick, max = {}, #known > 0 and 2 or 3
    while #list > 0 and #pick < max do pick[#pick + 1] = table.remove(list, math.random(#list)) end
    return pick
end

local function Failed(res)
    if type(res) ~= "number" then return res == false end
    local ok = RESULT and RESULT.Success or 0
    return res ~= ok
end

local relayId = 0
local function Relay(msg)
    relayId = relayId % 9999 + 1
    local id = math.random(10, 99) .. relayId
    local res
    for _, r in ipairs(Relays()) do
        res = ns.SendAddonMsg(PREFIX, "RLY:" .. id .. SEP .. msg, "WHISPER", r)
    end
    return res
end

-- Immer zuerst direkt an die Gilde. Nur wenn das scheitert oder der eigene
-- Rang ausdrücklich nicht schreiben darf, zusätzlich über andere weiterleiten.
local function SendToGuild(msg)
    local res = ns.SendAddonMsg(PREFIX, msg, "GUILD")
    if Throttled(res) then return res end
    if Failed(res) or not ns.CanSpeakGuild() then
        Relay(msg)
        return nil
    end
    return res
end

---------------------------------------------------------------------
-- Abgesicherter Kanal der Gilde
-- Rundsendungen gehen zusätzlich über einen eigenen Chat-Kanal, damit sie nicht
-- von Rangrechten im Gildenkanal abhängen; auch der Abgleich (Antworten auf
-- Anfragen) läuft darüber, sobald der Empfänger im Kanal ist.
-- Name und Passwort kommen aus einem geheimen Zufallsschlüssel, den die
-- Gildenleitung erzeugt. Er wird NIE über den Kanal selbst verschickt, nur über
-- den Gildenkanal (Server liefert nur an Mitglieder) oder per Flüstern an
-- Gildenmitglieder ("CKY", Empfang in GuildPride.lua). Wer ihn nicht hat, fragt
-- nach ("CKQ"). Verlässt jemand die Gilde, erzeugt die Gildenleitung einen neuen.
-- Nachrichten zählen zusätzlich nur von Gildenmitgliedern (GuildPride.lua).
-- Der Kanal wird nicht in Chatfenster eingetragen (Addon-Nachrichten sind dort
-- ohnehin unsichtbar) – Blizzards Chatcode wird nicht angefasst.
---------------------------------------------------------------------
local function Hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return h
end

local function GuildKey()
    local guild = GetGuildInfo("player")
    if not guild then return end
    local realm = select(4, GetGuildInfo("player")) or GetNormalizedRealmName() or ""
    return guild, realm
end

-- Alter Kanal (bis 1.12.2): aus dem Gildennamen berechnet, also für jeden
-- mit dem Addon-Code ausrechenbar. Wird nur noch verlassen.
local function LegacyChannel()
    local guild, realm = GuildKey()
    if not guild then return end
    return ("GPd%x"):format(Hash(guild .. "@" .. realm))
end

local function KeyStore()
    local guild, realm = GuildKey()
    if not guild or not GuildPrideDB then return end
    GuildPrideDB.chanKeys = GuildPrideDB.chanKeys or {}
    local id = guild .. "@" .. realm
    GuildPrideDB.chanKeys[id] = GuildPrideDB.chanKeys[id] or {}
    return GuildPrideDB.chanKeys[id]
end

local function DataChannel()
    local s = KeyStore()
    local k = s and s.k
    if not k then return end
    return ("GPs%x%x"):format(Hash(k), Hash(k:reverse())), ("%x%x"):format(Hash("pw" .. k), Hash(k .. "pw"))
end

function ns.DataChannelId()
    local name = DataChannel()
    if not name then return end
    local id = GetChannelName(name)
    return id and id > 0 and id or nil, name
end
function ns.DataChannelName() return (DataChannel()) end

-- Wer wurde zuletzt im Kanal gehört? Dorthin gehen Antworten über den Kanal
local chanSeen = {}
function ns.ChannelSeen(who) chanSeen[who] = GetTime() end
local function InChannel(who) return chanSeen[who] and GetTime() - chanSeen[who] < 300 end
ns.HeardInChannel = InChannel

local joinReady, joinedName = false, nil
local function JoinDataChannel()
    if not joinReady then return end
    local legacy = LegacyChannel()
    if legacy and LeaveChannelByName and GetChannelName(legacy) > 0 then LeaveChannelByName(legacy) end
    local name, pw = DataChannel()
    if joinedName and joinedName ~= name and LeaveChannelByName then LeaveChannelByName(joinedName) end
    joinedName = name
    if not name or ns.DataChannelId() then return end
    if JoinTemporaryChannel then JoinTemporaryChannel(name, pw) end
end

---------------------------------------------------------------------
-- Serverweite Gruppensuche: offener Kanal je Spielversion ("GPLFGR",
-- "GPLFGC1" …). Darin kann jeder schreiben – angenommen werden dort nur
-- Gruppensuche-Einträge mit passender Kennung (GuildPrideHelp.lua).
---------------------------------------------------------------------
local function PublicChannel() return "GPLFG" .. (ns.CLIENT_TAG or "X") end
ns.PublicChannelName = PublicChannel
local SendChat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
-- Für /gp server status: gesendet, letztes Sende-Ergebnis, empfangen
ns.publicStats = { sent = 0, received = 0, echo = 0 }

function ns.PublicChannelId()
    if not ns.PublicLFGOn() then return end
    local id = GetChannelName(PublicChannel())
    return id and id > 0 and id or nil
end

function ns.IsPublicChannel(localID, chanName)
    local id = ns.PublicChannelId()
    if not id then return false end
    if localID == id then return true end
    local name = PublicChannel():lower()
    return type(chanName) == "string" and (chanName:lower() == name or chanName:lower():match("^%d+%.%s*(.+)$") == name)
end

-- farewell: beim Verlassen noch direkt gesendet (eigenen Eintrag zurückziehen)
local publicWarned = false
function ns.UpdatePublicChannel(farewell)
    if not joinReady then return end
    local name = PublicChannel()
    local joined = GetChannelName(name) > 0
    if ns.PublicLFGOn() and not joined then
        if JoinTemporaryChannel then JoinTemporaryChannel(name) end
        -- Kein Platz mehr (höchstens 10 eigene Kanäle)? Einmal Bescheid geben
        C_Timer.After(5, function()
            if ns.PublicLFGOn() and GetChannelName(name) == 0 and not publicWarned then
                publicWarned = true
                ns.Print(L["Serverweite Gruppensuche: Kanal konnte nicht betreten werden (zu viele Chatkanäle?)."])
            end
        end)
    elseif not ns.PublicLFGOn() and joined then
        wipe(publicQueue)
        if farewell then
            if ns.PUBLIC_VIA_CHAT then SendChat((farewell:gsub(SEP, "~")), "CHANNEL", nil, (GetChannelName(name)))
            else ns.SendAddonMsg(PREFIX, farewell, "CHANNEL", (GetChannelName(name))) end
        end
        if LeaveChannelByName then LeaveChannelByName(name) end
    end
end

-- Classic: Rundsendungen gehen als normale Chatnachricht in den offenen Kanal.
-- Das erlaubt Blizzard nur direkt bei einem Klick – Aufrufer achten darauf.
-- Das Trennzeichen ist dort nicht erlaubt und wird zu "~".
function ns.SendPublicChat(kind, ...)
    local chan = ns.PublicChannelId()
    if not chan then return end
    local parts = { ... }
    for i = 1, select("#", ...) do parts[i] = (tostring(parts[i] == nil and "" or parts[i]):gsub("~", "-")) end
    local msg = kind .. ":" .. table.concat(parts, "~")
    if #msg > 255 then return end
    SendChat(msg, "CHANNEL", nil, chan)
    local st = ns.publicStats
    st.sent, st.lastRes, st.lastAt = st.sent + 1, "chat", GetTime()
end

-- Kanalzeilen nicht im Chatfenster zeigen; der Filter kommt erst dazu, wenn
-- der Chat-Weg wirklich genutzt wird (Retail bleibt unberührt)
local chatFiltered = false
local function FilterPublicChat()
    if chatFiltered then return end
    local AddFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    if not AddFilter then return end
    chatFiltered = true
    AddFilter("CHAT_MSG_CHANNEL", function(_, _, _, _, _, chanName, _, _, _, chanIndex, chanBase)
        if not ns.PUBLIC_VIA_CHAT then return false end
        return ns.IsPublicChannel(chanIndex, chanBase) or ns.IsPublicChannel(nil, chanName)
    end)
end
if ns.PUBLIC_VIA_CHAT then FilterPublicChat() end

-- Classic: Einträge und Abfragen aus dem offenen Kanal an die Gruppensuche
local chatIn = CreateFrame("Frame")
chatIn:RegisterEvent("CHAT_MSG_CHANNEL")
chatIn:SetScript("OnEvent", function(_, _, text, sender, _, chanName, _, _, _, chanIndex, chanBase)
    if not ns.PUBLIC_VIA_CHAT or not ns.OnPublicMessage then return end
    if type(text) ~= "string" or type(sender) ~= "string" or sender == "" then return end
    if not (ns.IsPublicChannel(chanIndex, chanBase) or ns.IsPublicChannel(nil, chanName)) then return end
    ns.OnPublicMessage((text:gsub("~", SEP)), ns.Normalize(sender))
end)

local chanFrame = CreateFrame("Frame")
chanFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
chanFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
chanFrame:SetScript("OnEvent", function()
    -- spät beitreten, damit Allgemein/Handel ihre gewohnten Nummern behalten
    C_Timer.After(15, function() joinReady = true; JoinDataChannel(); ns.UpdatePublicChannel() end)
end)

-- Schlüssel: Hex-Text + Version (Zeit). Neuere Version gewinnt, bei
-- Gleichstand der größere Text – so landen alle beim selben Schlüssel.
local function NewKey()
    local t = {}
    for i = 1, 24 do t[i] = ("%x"):format(math.random(0, 15)) end
    return table.concat(t)
end

local function Newer(k, v, s)
    if not s.k then return true end
    return v > (s.v or 0) or (v == (s.v or 0) and k > s.k)
end

local function SendKey(target)
    local s = KeyStore()
    if not (s and s.k) then return end
    local msg = "CKY:" .. s.k .. SEP .. s.v
    if target then
        ns.SendAddonMsg(PREFIX, msg, "WHISPER", target)
    elseif IsInGuild() then
        ns.SendAddonMsg(PREFIX, msg, "GUILD")
    end
end

-- Empfang (nur über Gilde oder Flüstern von Mitgliedern, siehe GuildPride.lua)
function ns.OnChannelKey(payload, sender)
    local k, v = strsplit(SEP, payload)
    v = ns.Stamp(v)
    if not k or not k:match("^%x+$") or #k < 16 or #k > 64 or v == 0 then return end
    local s = KeyStore()
    if not s or not Newer(k, v, s) then return end
    s.k, s.v = k, v
    JoinDataChannel()
end

-- Neuen Schlüssel erzeugen (nur Gildenleitung), höchstens einmal pro Minute;
-- kommt eine weitere Anfrage zu früh, wird sie nach Ablauf der Minute nachgeholt
local rotatedAt, rotatePending = -999, false
function ns.RotateChannelKey(force)
    if not CanManage() or not IsInGuild() then return false end
    local wait = 60 - (GetTime() - rotatedAt)
    if not force and wait > 0 then
        if not rotatePending then
            rotatePending = true
            C_Timer.After(wait, function() rotatePending = false; ns.RotateChannelKey() end)
        end
        return false
    end
    local s = KeyStore()
    if not s then return false end
    rotatedAt = GetTime()
    s.k, s.v = NewKey(), math.max(Now(), (s.v or 0) + 1)
    SendKey()
    JoinDataChannel()
    return true
end

local keyAskedAt = -999
local function AskKey()
    local s = KeyStore()
    if not s or GetTime() - keyAskedAt < 25 then return end
    keyAskedAt = GetTime()
    ns.Queue("CKQ", nil, s.v or 0)
end

-- Anfrage: wer einen neueren Schlüssel hat, flüstert ihn zu. Damit nicht die
-- halbe Gilde antwortet, antwortet jeder nur mit einer Wahrscheinlichkeit,
-- die im Schnitt etwa drei Antworten ergibt (wer leer ausgeht, fragt erneut).
ns.On("CKQ", function(payload, sender)
    if sender == Me() then return end
    local s = KeyStore()
    if not s then return end
    local theirs = ns.Stamp(payload)
    if s.k and theirs < (s.v or 0) then
        local n = 0
        for i = 1, GetNumGuildMembers() do
            local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
            if name and online and ns.AddonUsers[ns.FullName and ns.FullName(name) or name] then n = n + 1 end
        end
        if math.random() * math.max(n, 1) < 3 then
            C_Timer.After(0.5 + math.random() * 3, function() SendKey(sender) end)
        end
    elseif theirs > (s.v or 0) then
        AskKey()   -- der andere hat einen neueren: selbst nachfragen
    end
end)

-- Nach dem Login nachfragen; ohne Schlüssel weiter fragen. Ist nach einer Weile
-- immer noch keiner da, erzeugt die Gildenleitung einen. Wer den Gildenkanal
-- nicht lesen darf, verpasst neue Schlüssel und fragt deshalb alle 10 Min.
local keyFrame = CreateFrame("Frame")
keyFrame:RegisterEvent("PLAYER_LOGIN")
keyFrame:SetScript("OnEvent", function()
    C_Timer.After(5, AskKey)
    local tries = 0
    C_Timer.NewTicker(30, function()
        if not IsInGuild() then return end
        local s = KeyStore()
        if not s then return end
        tries = tries + 1
        if not s.k then
            -- Gildenleitung erst nach zwei Nachfragen (1 Min.), damit sie keinen
            -- vorhandenen Schlüssel überschreibt, nur weil zufällig keiner antwortete
            if CanManage() and tries >= 2 then ns.RotateChannelKey(true) elseif tries <= 10 then AskKey() end
        elseif tries % 20 == 0 and ns.CanListenGuild and not ns.CanListenGuild() then
            AskKey()
        end
    end)
end)

local origSlash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd = strtrim(arg or ""):lower()
    if cmd == "kanal" or cmd == "channel" then
        local s = KeyStore()
        if s and s.k then
            ns.Print((L["Abgesicherter Kanal aktiv (Schlüssel vom %s)."]):format(ns.FormatDay(s.v, true)))
        else
            ns.Print(L["Noch kein Kanal-Schlüssel – er kommt von der Gildenleitung."])
        end
    elseif cmd == "kanal neu" or cmd == "channel new" then
        if ns.RotateChannelKey(true) then
            ns.Print(L["Neuer Kanal-Schlüssel erzeugt und an die Gilde verteilt."])
        else
            ns.Print(L["Nur die Gildenleitung kann einen neuen Kanal-Schlüssel erzeugen."])
        end
    else
        origSlash(arg)
    end
end

C_Timer.NewTicker(0.3, function()
    if GetTime() < pauseUntil then return end
    -- Während der Chat-Sperre (Bosskampf, M+, PvP) nichts senden; die Warteschlange bleibt erhalten
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
    local item = table.remove(queue, 1)
    if not item then return end
    local res
    if item.target == "@OFFICER" then
        if IsInGuild() then res = ns.SendAddonMsg(PREFIX, item.msg, "OFFICER") end
    elseif item.target == "@CHANNEL" then
        -- Nur über den abgesicherten Kanal; ohne Kanal-Schlüssel über die Gilde
        local chan = ns.DataChannelId()
        if chan then
            res = ns.SendAddonMsg(PREFIX, item.msg, "CHANNEL", chan)
        elseif IsInGuild() then
            res = SendToGuild(item.msg)
        end
    elseif item.target then
        -- Abgleich: ist der Empfänger im abgesicherten Kanal, dort senden
        -- (alle im Kanal bleiben so auf demselben Stand), sonst flüstern
        local chan = ns.DataChannelId()
        if chan and InChannel(item.target) then
            res = ns.SendAddonMsg(PREFIX, item.msg, "CHANNEL", chan)
        else
            res = ns.SendAddonMsg(PREFIX, item.msg, "WHISPER", item.target)
        end
    elseif IsInGuild() then
        res = SendToGuild(item.msg)
        local chan = ns.DataChannelId()
        if chan and not Throttled(res) then ns.SendAddonMsg(PREFIX, item.msg, "CHANNEL", chan) end
    end
    if Throttled(res) then
        item.tries = (item.tries or 0) + 1
        if item.tries <= 10 then table.insert(queue, 1, item) end
        pauseUntil = GetTime() + 1.5
    end
end)

-- Serverweite Gruppensuche: höchstens eine Nachricht alle 2 s, nur über den
-- offenen Kanal (nie ersatzweise an die Gilde), Gildennachrichten haben Vorrang
C_Timer.NewTicker(2, function()
    if #queue > 0 or GetTime() < pauseUntil then return end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
    local item = table.remove(publicQueue, 1)
    if not item then return end
    local res
    if item.to then
        -- Antwort auf eine Abfrage: direkt an den Fragenden
        res = ns.SendAddonMsg(PREFIX, item.msg, "WHISPER", item.to)
    else
        local chan = ns.PublicChannelId()
        if not chan or ns.PUBLIC_VIA_CHAT then return end
        res = ns.SendAddonMsg(PREFIX, item.msg, "CHANNEL", chan)
    end
    local st = ns.publicStats
    st.sent, st.lastRes, st.lastAt = st.sent + 1, res, GetTime()
    if not item.to and RESULT and RESULT.InvalidChatType ~= nil and res == RESULT.InvalidChatType then
        -- Diese Spielversion lässt keine Addon-Nachrichten in eigene Kanäle zu:
        -- weiter wie in Classic (Chatnachricht beim Klicken, Antworten per Flüstern)
        ns.PUBLIC_VIA_CHAT = true
        FilterPublicChat()
        for i = #publicQueue, 1, -1 do if not publicQueue[i].to then table.remove(publicQueue, i) end end
        ns.Print(L["Serverweite Gruppensuche: Diese Spielversion sperrt Addon-Nachrichten in Chatkanälen. Dein Eintrag geht jetzt beim Eintragen raus, Antworten kommen per Flüstern."])
    elseif Throttled(res) then
        item.tries = (item.tries or 0) + 1
        if item.tries <= 5 then table.insert(publicQueue, 1, item) end
        pauseUntil = GetTime() + 1.5
    end
end)

-- Addon-Nachrichten dürfen höchstens 255 Byte lang sein; längere (z. B. Events
-- mit Beschreibung und Notiz) kamen früher nie an. Sie werden jetzt als
-- "MP:id·nr·anzahl·stück" verschickt und beim Empfänger wieder zusammengesetzt
-- (siehe GuildPride.lua). Die Grenze lässt Platz für die Weiterleitung (RLY/FWD).
local MAX_LEN, PART_LEN = 195, 175
local multiId = 0

-- Serverweit: nie mehrteilig (MP wird dort nicht angenommen); pro Art und
-- Empfänger zählt nur der neueste Stand, ältere wartende werden ersetzt
local function PublicPush(kind, msg, to)
    if #msg > 255 then return end
    for i, it in ipairs(publicQueue) do
        if it.kind == kind and it.to == to then publicQueue[i] = { msg = msg, kind = kind, to = to }; return end
    end
    table.insert(publicQueue, { msg = msg, kind = kind, to = to })
end

-- Antwort auf eine serverweite Abfrage: per Flüstern an den Fragenden
function ns.QueuePublicTo(to, kind, ...)
    local parts = { ... }
    for i = 1, select("#", ...) do parts[i] = tostring(parts[i] == nil and "" or parts[i]) end
    PublicPush(kind, kind .. ":" .. table.concat(parts, SEP), to)
end

local function Queue(kind, target, ...)
    local parts = { ... }
    for i = 1, select("#", ...) do parts[i] = tostring(parts[i] == nil and "" or parts[i]) end
    local msg = kind .. ":" .. table.concat(parts, SEP)
    if target == "@PUBLIC" then
        PublicPush(kind, msg)
        return
    end
    if #msg <= MAX_LEN then
        table.insert(queue, { msg = msg, target = target })
        return
    end
    multiId = multiId % 999 + 1
    local id = math.random(100, 999) .. multiId
    local n = math.ceil(#msg / PART_LEN)
    for i = 1, n do
        table.insert(queue, { target = target,
            msg = ("MP:%s%s%d%s%d%s%s"):format(id, SEP, i, SEP, n, SEP, msg:sub((i - 1) * PART_LEN + 1, i * PART_LEN)) })
    end
end
ns.Queue = Queue
function ns.QueueLength() return #queue end
-- Nur der neueste Stand zählt (z. B. die Kartenposition): wartende ältere
-- Nachrichten derselben Art an dasselbe Ziel fliegen vorher raus
function ns.QueueLatest(kind, target, ...)
    local head = kind .. ":"
    for i = #queue, 1, -1 do
        local it = queue[i]
        if it.target == target and it.msg:sub(1, #head) == head then table.remove(queue, i) end
    end
    Queue(kind, target, ...)
end

local function SendEvent(e, target)
    -- rep: Wiederholung in Tagen (7 = jede Woche); ältere Versionen ignorieren das Feld
    Queue("EVT", target, e.id, e.t, e.title, e.desc, e.creator, e.ver, e.note or "", e.rep or 0)
end
local function SendDelete(e, target) Queue("DEL", target, e.id, e.ver) end
local function SendSign(id, name, s, target) Queue("SGN", target, id, name, s.s, s.v, s.r or "") end

-- Ist der Spieler gerade online? (Gildenliste)
local function IsOnline(full)
    for i = 1, GetNumGuildMembers() do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if name and online and (ns.FullName and ns.FullName(name) or name) == full then return true end
    end
end

-- Zusätzlich direkt an den Ersteller flüstern: Was ein Rang an die Gilde schickt,
-- kommt nicht immer bei allen an (Rangrechte), ein Flüstern schon.
function ns.TellCreator(creator, send)
    if creator and creator ~= "" and creator ~= Me() and IsOnline(creator) then send(creator) end
end

-- Kommt jemand online, ruft fn(name) auf (z. B. eigene Anmeldungen nachliefern,
-- die der Ersteller verpasst hat, weil er offline war)
local onlineBefore, onlineHooks = nil, {}
function ns.OnMemberOnline(fn) onlineHooks[#onlineHooks + 1] = fn end
local rosterWatch = CreateFrame("Frame")
rosterWatch:RegisterEvent("GUILD_ROSTER_UPDATE")
rosterWatch:SetScript("OnEvent", function()
    local now, me = {}, Me()
    for i = 1, GetNumGuildMembers() do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if name and online then now[ns.FullName and ns.FullName(name) or name] = true end
    end
    if onlineBefore then
        for full in pairs(now) do
            if not onlineBefore[full] and full ~= me then
                -- kurz warten, bis der andere sein Addon geladen hat
                C_Timer.After(20 + math.random() * 10, function()
                    for _, fn in ipairs(onlineHooks) do fn(full) end
                end)
            end
        end
    end
    onlineBefore = now
end)

-- Dasselbe für Nachrichten ohne Ersteller (z. B. Gruppensuche): an die Gildenleitung
-- (Rang 0 und 1) flüstern, die online ist. Wer selbst Rang 0/1 hat, braucht das nicht.
function ns.TellLeaders(send)
    local _, _, myRank = GetGuildInfo("player")
    if not myRank or myRank <= 1 then return end
    local me, n = Me(), 0
    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex, _, _, _, _, _, online = GetGuildRosterInfo(i)
        local full = name and (ns.FullName and ns.FullName(name) or name)
        if full and online and rankIndex and rankIndex <= 1 and full ~= me and n < 3 then
            n = n + 1
            send(full)
        end
    end
end

---------------------------------------------------------------------
-- Daten anwenden (neuere Version gewinnt)
---------------------------------------------------------------------
local STORE_MAX = 300   -- Obergrenze für gespeicherte Events (gegen Speicherfluten)

local function StoreCount()
    local n = 0
    for _ in pairs(DB()) do n = n + 1 end
    return n
end

-- Voll? Dann zuerst Einträge wegräumen, die seit 30 Tagen vorbei bzw. unverändert sind
local function GetOrStub(id)
    local e = DB()[id]
    if not e then
        if StoreCount() >= STORE_MAX then
            local old = Now() - 30 * 86400
            for k, x in pairs(DB()) do
                if (x.t or 0) < old and (x.ver or 0) < old then DB()[k] = nil end
            end
            if StoreCount() >= STORE_MAX then return nil end
        end
        e = { id = id, ver = 0, signups = {} }
        DB()[id] = e
    end
    e.signups = e.signups or {}
    return e
end

local function ApplyEvent(id, t, title, desc, creator, ver, note, fromOther, rep)
    local e = GetOrStub(id)
    if not e or ver <= e.ver then return end
    local isNew = not e.title
    -- Wiederholtes Event: hier schon weitergerückt? Dann nicht zurücksetzen
    if not (rep and rep > 0 and e.rep == rep and e.t and e.t > t) then e.t = t end
    e.title, e.desc, e.creator, e.ver, e.deleted = title, desc, creator, ver, nil
    e.note = note or ""
    e.rep = (rep and rep > 0) and rep or nil
    if isNew and fromOther then
        ns.Print((L["Neues Gildenevent: |cffffd100%s|r am %s"]):format(title, ns.FormatDate(t, "short")))
    end
end

local function ApplyDelete(id, ver)
    local e = GetOrStub(id)
    if not e or ver < e.ver then return end
    e.deleted, e.ver = true, ver
end

local function ApplySign(id, name, status, ver, role)
    if not STATUS[status] then return end
    if not ROLES[role or ""] then role = nil end
    local e = GetOrStub(id)
    if not e then return end
    local cur = e.signups[name]
    if not cur or ver > cur.v then e.signups[name] = { s = status, v = ver, r = role } end
end

---------------------------------------------------------------------
-- Empfangen
---------------------------------------------------------------------
-- Unsere bekannten Events (inkl. Anmeldungen) an jemanden schicken
local function SendAllEvents(target)
    local cutoff = Now() - 86400
    for _, e in pairs(DB()) do
        if e.deleted then
            if (e.ver or 0) > cutoff - 6 * 86400 then SendDelete(e, target) end
        elseif e.title and e.t > cutoff then
            SendEvent(e, target)
            for name, s in pairs(e.signups) do SendSign(e.id, name, s, target) end
        end
    end
end

-- Ersteller kommt online: eigene Anmeldungen zu seinen Events direkt nachliefern
ns.OnMemberOnline(function(who)
    local me, cutoff = Me(), Now() - 86400
    for _, e in pairs(DB()) do
        local s = e.signups[me]
        if s and e.creator == who and not e.deleted and e.title and e.t > cutoff then
            SendSign(e.id, me, s, who)
        end
    end
end)

local function OnEventMessage(kind, payload, sender)
    if sender == Me() then return end
    local a = { strsplit(SEP, payload) }
    -- Fremde Werte prüfen: IDs und Namen ohne Codes und begrenzt lang,
    -- Versionen nicht in der Zukunft (sonst ließe sich ein Event sperren)
    local id = Clean(a[1], 80)
    if id == "" and (kind == "EVT" or kind == "DEL" or kind == "SGN") then return end
    -- Wer darf? Ein Event gehört dem, dessen Name vorne in der ID steht.
    -- Direkt vom Urheber oder von Offizieren: sofort. Abgleich über andere
    -- Mitglieder: erst, wenn zwei verschiedene genau dasselbe melden.
    if kind == "EVT" or kind == "DEL" or kind == "SGN" then
        local author = kind == "SGN" and Clean(a[2], 60) or id:match("^(.+)%-%d+%-%d+$")
        if not author then return end
        if kind == "EVT" and Clean(a[5], 60) ~= author then return end   -- Ersteller passt nicht zur ID
        if not (ns.IsDirect(sender, author) or ns.IsOfficerName(sender))
           and not ns.Confirmed(kind .. "\030" .. payload, sender) then return end
    end
    if kind == "EVT" then
        local rep = tonumber(a[8]) or 0
        ApplyEvent(id, ns.Num(a[2], 0, 2 ^ 31) or 0, Clean(a[3], 40), Clean(a[4], 120), Clean(a[5], 60),
            ns.Stamp(a[6]), Clean(a[7], 100), true, (rep == 7) and 7 or 0)
    elseif kind == "DEL" then
        ApplyDelete(id, ns.Stamp(a[2]))
    elseif kind == "SGN" then
        local name = Clean(a[2], 60)
        if name == "" or not ns.IsGuildMember(name) then return end
        ApplySign(id, name, a[3], ns.Stamp(a[4]), a[5])
    elseif kind == "REQ" or kind == "EVQ" then
        -- Jemand hat sich eingeloggt bzw. den Reiter Events geöffnet:
        -- kurz zufällig warten, damit nicht alle gleichzeitig antworten
        C_Timer.After(math.random() * 3, function() SendAllEvents(sender) end)
        return
    end
    if ns.RefreshUI then ns.RefreshUI() end
end
for _, k in ipairs({ "EVT", "DEL", "SGN", "REQ", "EVQ" }) do
    ns.On(k, function(payload, sender) OnEventMessage(k, payload, sender) end)
end

---------------------------------------------------------------------
-- Aktionen
---------------------------------------------------------------------
local function CreateEvent(title, t, desc, rep)
    local e = GetOrStub(Me() .. "-" .. Now() .. "-" .. math.random(1000, 9999))
    if not e then return end
    ApplyEvent(e.id, t, Clean(title, 40), Clean(desc, 120), Me(), Now(), nil, nil, rep)
    SendEvent(e)
    if ns.Discord then ns.Discord.EventCreated(e) end
    ns.RefreshUI()
end

-- Wöchentliche Events: 3 Std. nach Beginn auf die nächste Woche rücken.
-- Jeder rechnet gleich; Anmeldungen von vor dem letzten Termin verfallen.
function ns.RollEvents()
    if not GuildPrideDB then return end
    local now = Now()
    for _, e in pairs(DB()) do
        if e.rep and e.rep > 0 and e.title and not e.deleted and e.t then
            local moved = false
            while e.t + 3 * 3600 < now do
                e.t = e.t + e.rep * 86400
                moved = true
            end
            if moved then
                e.reminded = nil
                local cutoff = e.t - e.rep * 86400 + 3 * 3600
                for name, s in pairs(e.signups) do
                    if (s.v or 0) < cutoff then e.signups[name] = nil end
                end
            end
        end
    end
end

local function DeleteEvent(e)
    ApplyDelete(e.id, Now())
    SendDelete(e)
    if ns.Discord then ns.Discord.EventDeleted(e) end
    ns.RefreshUI()
end

local function MyRole()
    if GuildPrideDB.role then return GuildPrideDB.role end
    local spec = GetSpecialization and GetSpecialization()
    local r = spec and GetSpecializationRole and GetSpecializationRole(spec)
    return ROLES[r or ""] and r or "DAMAGER"
end

local function SetNote(e, note)
    ApplyEvent(e.id, e.t, e.title, e.desc, e.creator, Now(), Clean(note, 100), nil, e.rep)
    SendEvent(e)
    ns.RefreshUI()
end

local function SignUp(e, status)
    ApplySign(e.id, Me(), status, Now(), status ~= "no" and MyRole() or nil)
    SendSign(e.id, Me(), e.signups[Me()])
    ns.TellCreator(e.creator, function(who) SendSign(e.id, Me(), e.signups[Me()], who) end)
    if ns.Discord then ns.Discord.SignedUp(e, e.signups[Me()]) end
    ns.RefreshUI()
end

-- Datum: "24.12.", "24.12", "24.12.26", "24.12.2026" (auch mit / oder -)
-- Rückgabe: Tag, Monat, Jahr (Jahr nil, wenn nicht angegeben)
local function ParseDay(str)
    local d, m, y = str:match("^(%d%d?)[%./%-](%d%d?)[%./%-]?(%d*)$")
    d, m = tonumber(d), tonumber(m)
    if not d or m < 1 or m > 12 or d < 1 or d > 31 then return nil end
    y = tonumber(y)
    if y and y < 100 then y = y + 2000 end
    return d, m, y
end

-- Uhrzeit: "20", "20:00", "20.00", "2000", "8:30", "20 Uhr"
local function ParseClock(str)
    str = str:lower():gsub("%s*uhr$", "")
    local H, M = str:match("^(%d%d?)[:%.](%d%d)$")
    if not H then H, M = str:match("^(%d%d)(%d%d)$") end
    if not H then H, M = str:match("^(%d%d?)$"), "0" end
    H, M = tonumber(H), tonumber(M)
    if not H or H > 23 or M > 59 then return nil end
    return H, M
end

-- Datum + Uhrzeit -> Zeitstempel; ohne Jahr gilt der nächste passende Termin
local function ParseDate(dayStr, clockStr)
    local d, m, y = ParseDay(dayStr)
    if not d then return nil, "date" end
    local H, M = ParseClock(clockStr)
    if not H then return nil, "time" end
    local function Make(year)
        local t = time({ year = year, month = m, day = d, hour = H, min = M })
        local check = date("*t", t)
        if check.day ~= d or check.month ~= m then return nil end   -- z. B. 31.02.
        return t
    end
    local t = Make(y or tonumber(date("%Y")))
    if not t then return nil, "date" end
    if not y and t < time() then t = Make(tonumber(date("%Y")) + 1) or t end
    return t
end

local function UpcomingEvents()
    ns.RollEvents()
    local list, cutoff = {}, Now() - 3 * 3600 -- 3 h nach Beginn noch sichtbar
    for _, e in pairs(DB()) do
        if e.title and not e.deleted and e.t > cutoff then list[#list + 1] = e end
    end
    table.sort(list, function(a, b) return a.t < b.t end)
    return list
end

local function CountSignups(e)
    local c = { yes = 0, maybe = 0, no = 0 }
    for _, s in pairs(e.signups) do c[s.s] = (c[s.s] or 0) + 1 end
    return c
end

---------------------------------------------------------------------
-- UI: Reiter "Events"
---------------------------------------------------------------------
local page = ns.AddTab("Events", 30)

-- Beim Öffnen die Events der anderen abfragen (höchstens alle 2 Minuten)
local lastAsk = 0
page:HookScript("OnShow", function()
    if GetTime() - lastAsk < 120 then return end
    lastAsk = GetTime()
    Queue("EVQ", nil, "1")
end)
local selected
local ROWS = 6
local rows = {}

for i = 1, ROWS do
    local b = CreateFrame("Button", nil, page)
    b:SetSize(650, 24)
    b:SetPoint("TOPLEFT", 0, -(i - 1) * 25)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.when = b:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
    b.when:SetPoint("LEFT", 6, 0)
    b.title = b:CreateFontString(nil, "OVERLAY", "GPFont_Normal")
    b.title:SetPoint("LEFT", 110, 0)
    b.info = b:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
    b.info:SetPoint("RIGHT", -6, 0)
    b:SetScript("OnClick", function(self) selected = self.event and self.event.id; page:Refresh() end)
    rows[i] = b
end

local empty = page:CreateFontString(nil, "OVERLAY", "GPFont_Muted")
empty:SetPoint("TOP", 0, -60)
empty:SetText(L["Keine anstehenden Events."])

-- Detailbereich
local detail = CreateFrame("Frame", nil, page, "BackdropTemplate")
detail:SetPoint("TOPLEFT", 0, -ROWS * 25 - 8)
detail:SetPoint("BOTTOMRIGHT", 0, 34)
detail:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
detail:SetBackdropColor(0, 0, 0, 0.35)

local dTitle = detail:CreateFontString(nil, "OVERLAY", "GPFont_Large")
dTitle:SetPoint("TOPLEFT", 8, -8)
local dWhen = detail:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
dWhen:SetPoint("TOPLEFT", dTitle, "BOTTOMLEFT", 0, -4)
local dDesc = detail:CreateFontString(nil, "OVERLAY", "GPFont_Text")
dDesc:SetPoint("TOPLEFT", dWhen, "BOTTOMLEFT", 0, -6)
dDesc:SetWidth(620); dDesc:SetJustifyH("LEFT")
local dPeople = detail:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
dPeople:SetPoint("TOPLEFT", dDesc, "BOTTOMLEFT", 0, -8)
dPeople:SetWidth(620); dPeople:SetJustifyH("LEFT"); dPeople:SetSpacing(3)

local function Btn(text, w, anchor, x, onClick)
    local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    b:SetSize(w, 24); b:SetText(text)
    b:SetPoint("BOTTOMLEFT", anchor or page, anchor and "BOTTOMRIGHT" or "BOTTOMLEFT", x or 0, 0)
    b:SetScript("OnClick", onClick)
    return b
end

local function Sel() return selected and DB()[selected] end
local bYes   = Btn(L["Zusagen"], 90, nil, 0, function() if Sel() then SignUp(Sel(), "yes") end end)
local bMaybe = Btn(L["Vielleicht"], 90, bYes, 4, function() if Sel() then SignUp(Sel(), "maybe") end end)
local bNo    = Btn(L["Absagen"], 90, bMaybe, 4, function() if Sel() then SignUp(Sel(), "no") end end)
local bDel   = Btn(L["Löschen"], 80, bNo, 20, function()
    if Sel() then StaticPopup_Show("GUILDPRIDE_DELETE_EVENT", Sel().title, nil, Sel()) end
end)
local bNew   = Btn(L["Neues Event"], 110, bDel, 8, function() ns.ShowCreateDialog() end)
local bAttend = Btn(L["Anwesenheit"], 110, bNew, 8, function() end)   -- Klick siehe unten

-- Rollenwahl (oben rechts im Detailbereich)
local roleBtns = {}
local roleLabel = detail:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
for i, key in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
    local b = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    b:SetSize(58, 20)
    b:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -8 - (3 - i) * 62, -8)
    b:SetText(ROLES[key].label)
    b:SetScript("OnClick", function()
        GuildPrideDB.role = key
        local e = Sel()
        local mine = e and e.signups[Me()]
        if mine and mine.s ~= "no" then SignUp(e, mine.s) else page:Refresh() end
    end)
    roleBtns[key] = b
end
roleLabel:SetPoint("RIGHT", roleBtns.TANK, "LEFT", -6, 0)
roleLabel:SetText(L["Meine Rolle:"])

-- Offiziers-Notiz bearbeiten
local bNote = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
bNote:SetSize(140, 22)
bNote:SetPoint("BOTTOMRIGHT", -8, 8)
bNote:SetText(L["Notiz bearbeiten"])
bNote:SetScript("OnClick", function()
    if Sel() then StaticPopup_Show("GUILDPRIDE_EVENT_NOTE", nil, nil, Sel()) end
end)

-- Alle Zugesagten einladen: erst bis zu 4 in die Gruppe, dann zum Schlachtzug
-- umwandeln und den Rest einladen (Umwandeln geht erst mit bestehender Gruppe)
local InviteToGroup = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
local ConvertToRaidFn = (C_PartyInfo and C_PartyInfo.ConvertToRaid) or ConvertToRaid

local function InviteAttendees(e)
    local names = {}
    for name, s in pairs(e.signups) do
        if s.s == "yes" and name ~= Me() and not UnitInParty(Ambiguate(name, "none")) then
            names[#names + 1] = name
        end
    end
    if #names == 0 then ns.Print(L["Keine weiteren Zusagen zum Einladen."]); return end
    table.sort(names)
    local first = IsInRaid() and #names or math.min(#names, 4)
    for i = 1, first do InviteToGroup(names[i]) end
    ns.Print((L["%d Spieler eingeladen."]):format(first))
    if first < #names then
        C_Timer.After(2, function()
            if not IsInRaid() and ConvertToRaidFn then ConvertToRaidFn() end
            C_Timer.After(1.5, function()
                for i = first + 1, #names do InviteToGroup(names[i]) end
                ns.Print((L["%d Spieler eingeladen."]):format(#names - first))
            end)
        end)
    end
end

local bInvite = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
bInvite:SetSize(170, 22)
bInvite:SetPoint("RIGHT", bNote, "LEFT", -6, 0)
bInvite:SetText(L["Alle Zugesagten einladen"])
bInvite:SetScript("OnClick", function() if Sel() then InviteAttendees(Sel()) end end)

-- Raid-Aufstellung (GuildPrideRoster.lua): Offiziere teilen ein, alle sehen sie
local bRoster = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
bRoster:SetSize(120, 22)
bRoster:SetPoint("RIGHT", bInvite, "LEFT", -6, 0)
bRoster:SetText(L["Aufstellung …"])
bRoster:SetScript("OnClick", function() if Sel() and ns.ShowRoster then ns.ShowRoster(Sel()) end end)

---------------------------------------------------------------------
-- Anwesenheit: wer zugesagt hat und wer wirklich in der Gruppe war.
-- Nur lokal gespeichert, je Gilde: ["id:t"] = { title, t, yes, present }
---------------------------------------------------------------------
local function Attendance() return ns.GuildTable("attendance") end

local function GroupNames()
    local out = {}
    local realm = GetNormalizedRealmName() or ""
    local n = GetNumGroupMembers()
    for i = 1, n do
        local unit = IsInRaid() and ("raid" .. i) or (i == n and "player" or ("party" .. i))
        -- Forever: Der zweite Wert von UnitFullName ist der Nachname
        local name, r = (ns.IS_FOREVER and UnitFullName or UnitName)(unit)
        if name and not (issecretvalue and issecretvalue(name)) then
            out[ns.Normalize(name .. "-" .. ((r and r ~= "") and r or realm))] = true
        end
    end
    out[Me()] = true
    return out
end

local function RecordAttendance(e, quiet)
    if not IsInGroup() then
        if not quiet then ns.Print(L["Du bist in keiner Gruppe – Anwesenheit kann nicht erfasst werden."]) end
        return
    end
    local rec = { title = e.title, t = e.t, yes = {}, present = {} }
    for name, s in pairs(e.signups) do
        if s.s == "yes" then rec.yes[#rec.yes + 1] = name end
    end
    for name in pairs(GroupNames()) do rec.present[#rec.present + 1] = name end
    Attendance()[e.id .. ":" .. e.t] = rec
    if not quiet then ns.Print((L["Anwesenheit für |cffffd100%s|r erfasst (%d da)."]):format(e.title, #rec.present)) end
end

-- Übersicht: je Spieler Zusagen, davon da, Quote
local function AttendanceText()
    local stats, events = {}, 0
    for _, rec in pairs(Attendance()) do
        events = events + 1
        local here = {}
        for _, n in ipairs(rec.present) do here[n] = true end
        for _, n in ipairs(rec.yes) do
            local s = stats[n] or { yes = 0, came = 0 }
            s.yes = s.yes + 1
            if here[n] then s.came = s.came + 1 end
            stats[n] = s
        end
    end
    if events == 0 then return L["|cff888888Noch nichts erfasst. Das passiert 10 Min. nach Beginn automatisch (Ersteller oder Offizier in der Gruppe).|r"] end
    local list = {}
    for n, s in pairs(stats) do list[#list + 1] = { n = n, s = s } end
    table.sort(list, function(a, b)
        local qa, qb = a.s.came / a.s.yes, b.s.came / b.s.yes
        if qa ~= qb then return qa > qb end
        return a.n < b.n
    end)
    local parts = {}
    for _, x in ipairs(list) do
        local q = math.floor(x.s.came / x.s.yes * 100 + 0.5)
        local col = q >= 75 and "|cff40ff40" or (q >= 50 and "|cffffd100" or "|cffff6060")
        parts[#parts + 1] = ("%s %s%d/%d (%d %%)|r"):format(Ambiguate(x.n, "guild"), col, x.s.came, x.s.yes, q)
    end
    return (L["Erfasste Events: %d · da / zugesagt (Quote)"]):format(events) .. "\n" .. table.concat(parts, "  ·  ")
end

local attendView = false
local bRecord = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
bRecord:SetSize(160, 22)
bRecord:SetPoint("RIGHT", bInvite, "LEFT", -6, 0)
bRecord:SetText(L["Anwesenheit erfassen"])
bRecord:SetScript("OnClick", function() if Sel() then RecordAttendance(Sel()) end end)

-- Aufstellung: bis 5 Spieler 1/1/3, sonst Schlachtzug mit 2 Tanks und
-- einem Heiler je 5 Spieler
local function Lineup(roleCount, total)
    local need
    if total <= 5 then need = { TANK = 1, HEALER = 1, DAMAGER = 3 }
    else
        local heal = math.ceil(total / 5)
        need = { TANK = 2, HEALER = heal, DAMAGER = math.max(total - 2 - heal, 0) }
    end
    local parts = {}
    for _, key in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
        local have, want = roleCount[key], need[key]
        local col = have >= want and "|cff40ff40" or "|cffff6060"
        parts[#parts + 1] = ("%s%s %s%d/%d|r"):format(ROLES[key].color, ROLES[key].label, col, have, want)
    end
    return (L["Aufstellung (%s): %s"]):format(total <= 5 and L["Gruppe"] or L["Schlachtzug"], table.concat(parts, " · "))
end

StaticPopupDialogs["GUILDPRIDE_EVENT_NOTE"] = {
    text = L["Offiziers-Notiz (z. B. Treffpunkt, benötigte Rollen):"],
    button1 = SAVE or L["Speichern"], button2 = CANCEL,
    hasEditBox = true, maxLetters = 100, editBoxWidth = 320,
    OnShow = function(self, e)
        local eb = self.editBox or self.EditBox
        eb:SetText(e.note or ""); eb:SetFocus()
    end,
    OnAccept = function(self, e)
        local eb = self.editBox or self.EditBox
        SetNote(e, strtrim(eb:GetText()))
    end,
    EditBoxOnEnterPressed = function(self)
        local p = self:GetParent()
        SetNote(p.data, strtrim(self:GetText())); p:Hide()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["GUILDPRIDE_DELETE_EVENT"] = {
    text = L["Event \"%s\" wirklich löschen?"],
    button1 = YES, button2 = NO,
    OnAccept = function(_, e) DeleteEvent(e); selected = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

bAttend:SetScript("OnClick", function() attendView = not attendView; page:Refresh() end)

function page:Refresh()
    local list = UpcomingEvents()
    empty:SetShown(#list == 0)
    for i, b in ipairs(rows) do
        local e = list[i]
        b.event = e
        b:SetShown(e ~= nil)
        if e then
            local c = CountSignups(e)
            local mine = e.signups[Me()]
            b.when:SetText(ns.FormatDate(e.t, "short"))
            b.title:SetText(e.title .. (e.rep and ("  |cff999999(" .. L["jede Woche"] .. ")|r") or ""))
            b.info:SetText(("%s%d|r / %s%d|r%s"):format(STATUS.yes.color, c.yes, STATUS.maybe.color, c.maybe,
                mine and ("  " .. STATUS[mine.s].color .. "●|r") or ""))
            b.bg:SetColorTexture(1, 0.82, 0, e.id == selected and 0.18 or (i % 2 == 0 and 0.04 or 0))
        end
    end

    local e = Sel()
    if e and (e.deleted or not e.title) then e, selected = nil, nil end
    if not CanManage() then attendView = false end
    detail:SetShown(e ~= nil or attendView)
    bYes:SetEnabled(e ~= nil); bMaybe:SetEnabled(e ~= nil); bNo:SetEnabled(e ~= nil)
    bDel:SetShown(CanManage() and e ~= nil)
    bNew:SetShown(CanManage())
    bAttend:SetShown(CanManage())
    if attendView then bAttend:LockHighlight() else bAttend:UnlockHighlight() end

    -- Anwesenheits-Übersicht im Detailbereich
    local eventOnly = not attendView
    for _, b in pairs(roleBtns) do b:SetShown(eventOnly) end
    roleLabel:SetShown(eventOnly)
    bRecord:SetShown(eventOnly and CanManage())
    if attendView then
        dTitle:SetText(L["Anwesenheit"])
        dWhen:SetText(L["Nur auf diesem Rechner gespeichert."])
        dDesc:SetText("")
        dPeople:SetText(AttendanceText())
        bNote:Hide(); bInvite:Hide()
        return
    end
    if not e then return end

    dTitle:SetText(e.title)
    dWhen:SetText((L["%s · erstellt von %s"]):format(ns.FormatDate(e.t, "long"), Ambiguate(e.creator or "?", "guild"))
        .. (e.rep and (" · " .. L["jede Woche"]) or ""))
    local descText = e.desc ~= "" and e.desc or L["|cff888888Keine Beschreibung.|r"]
    if e.note and e.note ~= "" then
        descText = descText .. L["\n|cffff7d0aOffiziers-Notiz:|r "] .. e.note
    end
    dDesc:SetText(descText)
    bNote:SetShown(CanManage())
    bInvite:SetShown(CanManage())
    bRoster:SetShown(e ~= nil and not attendView and (CanManage() or (e.layout ~= nil and next(e.layout) ~= nil)))

    local myRole = MyRole()
    for key, b in pairs(roleBtns) do
        if key == myRole then b:LockHighlight() else b:UnlockHighlight() end
    end

    local groups = { yes = {}, maybe = {}, no = {} }
    local roleCount = { TANK = 0, HEALER = 0, DAMAGER = 0 }
    for name, s in pairs(e.signups) do
        local label = Ambiguate(name, "guild")
        if s.r and ROLES[s.r] and s.s ~= "no" then
            label = ("%s %s(%s)|r"):format(label, ROLES[s.r].color, ROLES[s.r].short)
            if s.s == "yes" then roleCount[s.r] = roleCount[s.r] + 1 end
        end
        table.insert(groups[s.s], label)
    end
    local lines = {
        (L["Zusagen nach Rolle: %sTanks %d|r · %sHeiler %d|r · %sDD %d|r"]):format(
            ROLES.TANK.color, roleCount.TANK, ROLES.HEALER.color, roleCount.HEALER,
            ROLES.DAMAGER.color, roleCount.DAMAGER),
    }
    if #groups.yes > 0 then lines[#lines + 1] = Lineup(roleCount, #groups.yes) end
    for _, key in ipairs({ "yes", "maybe", "no" }) do
        table.sort(groups[key])
        lines[#lines + 1] = ("%s%s (%d):|r %s"):format(STATUS[key].color, STATUS[key].label, #groups[key],
            #groups[key] > 0 and table.concat(groups[key], ", ") or "–")
    end
    dPeople:SetText(table.concat(lines, "\n"))
end

---------------------------------------------------------------------
-- Dialog: Event erstellen
---------------------------------------------------------------------
local dlg = CreateFrame("Frame", "GuildPrideCreateEvent", UIParent, "BackdropTemplate")
dlg:SetSize(360, 256)
dlg:SetPoint("CENTER")
dlg:SetFrameStrata("DIALOG")
dlg:EnableMouse(true)
dlg:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
})
dlg:Hide()
tinsert(UISpecialFrames, "GuildPrideCreateEvent")

local dh = dlg:CreateFontString(nil, "OVERLAY", "GPFont_Large")
dh:SetPoint("TOP", 0, -16); dh:SetText(L["Neues Gildenevent"])

local function Field(label, y, width, maxLen, x)
    x = x or 24
    local l = dlg:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
    l:SetPoint("TOPLEFT", x, y); l:SetText(label)
    local eb = CreateFrame("EditBox", nil, dlg, "InputBoxTemplate")
    eb:SetSize(width, 22); eb:SetPoint("TOPLEFT", x + 4, y - 14)
    eb:SetAutoFocus(false); eb:SetMaxLetters(maxLen)
    return eb
end
local fTitle = Field(L["Titel"], -44, 300, 40)
local fDate  = Field(L["Datum (TT.MM.JJJJ)"], -86, 130, 10)
local fTime  = Field(L["Uhrzeit (HH:MM)"], -86, 80, 8, 190)
local fDesc  = Field(L["Beschreibung (optional)"], -128, 300, 120)

-- Tab springt ins nächste Feld
local order = { fTitle, fDate, fTime, fDesc }
for i, eb in ipairs(order) do
    eb:SetScript("OnTabPressed", function() order[i % #order + 1]:SetFocus() end)
end
local fRepeat = CreateFrame("CheckButton", nil, dlg, "UICheckButtonTemplate")
fRepeat:SetSize(24, 24); fRepeat:SetPoint("TOPLEFT", 24, -170)
local fRepeatText = dlg:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
fRepeatText:SetPoint("LEFT", fRepeat, "RIGHT", 2, 0); fRepeatText:SetText(L["Jede Woche wiederholen"])
local fErr   = dlg:CreateFontString(nil, "OVERLAY", "GPFont_Red")
fErr:SetPoint("BOTTOM", 0, 48)

local ok = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
ok:SetSize(120, 24); ok:SetPoint("BOTTOMLEFT", 40, 18); ok:SetText(L["Erstellen"])
local cancel = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
cancel:SetSize(120, 24); cancel:SetPoint("BOTTOMRIGHT", -40, 18); cancel:SetText(CANCEL)
cancel:SetScript("OnClick", function() dlg:Hide() end)

ok:SetScript("OnClick", function()
    local title = strtrim(fTitle:GetText())
    if title == "" then fErr:SetText(L["Bitte einen Titel eingeben."]); return end
    local t, bad = ParseDate(strtrim(fDate:GetText()), strtrim(fTime:GetText()))
    if bad == "date" then fErr:SetText(L["Datum bitte als TT.MM.JJJJ eingeben (z. B. 24.12.2026)."]); return end
    if bad == "time" then fErr:SetText(L["Uhrzeit bitte als HH:MM eingeben (z. B. 20:00)."]); return end
    if t < time() then fErr:SetText(L["Der Termin liegt in der Vergangenheit."]); return end
    CreateEvent(title, t, strtrim(fDesc:GetText()), fRepeat:GetChecked() and 7 or 0)
    dlg:Hide()
end)
for _, eb in ipairs(order) do
    eb:SetScript("OnEnterPressed", function() ok:Click() end)
    eb:SetScript("OnEscapePressed", function() dlg:Hide() end)
end

function ns.ShowCreateDialog()
    if not CanManage() then ns.Print(L["Nur Offiziere können Events erstellen."]); return end
    -- Vorschlag: heute um 20:00 (nach 20 Uhr: morgen)
    local start = time()
    if tonumber(date("%H")) >= 20 then start = start + 86400 end
    fTitle:SetText(""); fDate:SetText(date("%d.%m.%Y", start)); fTime:SetText("20:00")
    fDesc:SetText(""); fErr:SetText(""); fRepeat:SetChecked(false)
    dlg:Show(); fTitle:SetFocus()
end

---------------------------------------------------------------------
-- Sync beim Login + Erinnerung 15 Min. vorher
---------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    -- nach dem Kanalbeitritt (15 s), damit die Antworten über den Kanal kommen
    C_Timer.After(20, function() Queue("REQ", nil, "1") end)
end)

C_Timer.NewTicker(30, function()
    if not GuildPrideDB then return end
    local now = Now()
    ns.RollEvents()
    for _, e in pairs(DB()) do
        -- 10 Min. nach Beginn Anwesenheit erfassen (Ersteller bzw. Offizier in der Gruppe)
        if e.title and not e.deleted and now >= e.t + 600 and now < e.t + 3 * 3600 and IsInGroup()
           and (e.creator == Me() or CanManage()) and not Attendance()[e.id .. ":" .. e.t] then
            RecordAttendance(e, true)
        end
        local mine = e.signups and e.signups[Me()]
        if e.title and not e.deleted and mine and mine.s ~= "no" and not e.reminded
           and e.t - now <= 900 and e.t - now > 0 then
            e.reminded = true
            RaidNotice_AddMessage(RaidWarningFrame,
                (L["%s %s beginnt in %d Min.!"]):format(ns.IconString(20), e.title, math.ceil((e.t - now) / 60)),
                ChatTypeInfo["GUILD"])
            if GuildPrideDB.sound then PlaySound(SOUNDKIT.RAID_WARNING) end
        end
    end
end)
