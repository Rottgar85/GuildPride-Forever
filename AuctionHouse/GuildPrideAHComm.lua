-- GuildPride Auktionshaus: Preise serverweit teilen (Weg C)
--   P:<Seite>:<Schlüssel>=<Preis>,<Menge>,<Zeit>;…   Preise (max. 8 pro Nachricht)
--   Q:<Seite>:<Schlüssel>                            Nachfrage
-- Eigener offener Kanal GPAuktionF mit eigener Sendebremse (1 Nachricht / 1,5 s).
-- In den offenen Kanal kann jeder schreiben: alles wird geprüft und gebremst.
local ADDON, GP = ...
local AH = GP.AH

local PREFIX = "GPAH"
local CHANNEL = "GPAuktionF"    -- eigener Kanal für WoW Forever
local SEND_GAP = 1.5            -- s zwischen eigenen Nachrichten
local MAX_LEN = 250
local MAX_ITEMS = 8
local SHARE_GAP = 1800          -- je Item höchstens alle 30 Min. rundsenden
local ASK_GAP = 600             -- je Item höchstens alle 10 Min. nachfragen
local ASK_PER_MIN = 10
local ANSWER_MAX_AGE = 6 * 3600 -- nur mit eigenem Preis, der jünger ist
local MAX_PRICE = 1000000000    -- 100 000 Gold
local MAX_QTY = 100000
local MAX_AGE = 7 * 86400
local RECV_PER_MIN = 45         -- mehr als die eigene Sendebremse erlaubt (60 / 1,5 = 40)
local NEW_KEYS_PER_HOUR = 200   -- neue Items je Absender und Stunde (Schutz der SavedVariables)
local MAX_QUEUE = 30

AH.stats = { sent = 0, received = 0, dropped = 0 }

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

---------------------------------------------------------------------
-- Eigener Kanal: spät beitreten, Zeilen nie im Chatfenster zeigen,
-- Warteschlange mit Bremse (gleicher Schlüssel ersetzt älteren Eintrag)
---------------------------------------------------------------------
local function ChannelId()
    local id = GetChannelName(CHANNEL)
    return id and id > 0 and id or nil
end
AH.ChannelId = ChannelId
AH.CHANNEL = CHANNEL

local joinWarned = false
function AH.UpdateChannel()
    local on = AH.Opt("ahShare")
    if on and not ChannelId() and JoinTemporaryChannel then
        JoinTemporaryChannel(CHANNEL)
        C_Timer.After(5, function()
            if AH.Opt("ahShare") and not ChannelId() and not joinWarned then
                joinWarned = true
                AH.Print(GP.L and GP.L["Auktionshaus: Kanal konnte nicht betreten werden (höchstens 10 Chatkanäle). Preise teilen ist aus, bis wieder Platz ist."] or "GPAuktionF?")
            end
        end)
    elseif not on and ChannelId() and LeaveChannelByName then
        LeaveChannelByName(CHANNEL)
    end
end

local AddFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
if AddFilter then
    AddFilter("CHAT_MSG_CHANNEL", function(_, _, _, _, _, _, _, _, _, _, chanBase)
        return type(chanBase) == "string" and not (issecretvalue and issecretvalue(chanBase)) and chanBase:lower() == CHANNEL:lower()
    end)
end

local queue, lastSend = {}, 0
-- Tests ersetzen diese Funktion
function AH.SendRaw(msg, key)
    key = key or msg
    for i = #queue, 1, -1 do if queue[i].key == key then table.remove(queue, i) end end
    queue[#queue + 1] = { key = key, msg = msg }
    -- Warteschlange begrenzen: zuerst alte Preislisten verwerfen, Nachfragen behalten
    while #queue > MAX_QUEUE do
        local drop = 1
        for i = 1, #queue do if queue[i].msg:sub(1, 2) == "P:" then drop = i; break end end
        table.remove(queue, drop)
    end
end
C_Timer.NewTicker(0.5, function()
    if #queue == 0 or GetTime() - lastSend < SEND_GAP then return end
    local id = ChannelId()
    if not id then return end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
    local item = table.remove(queue, 1)
    lastSend = GetTime()
    AH.stats.lastRes = C_ChatInfo.SendAddonMessage(PREFIX, item.msg, "CHANNEL", id)
end)
local function Send(msg, key)
    if #msg > MAX_LEN then return end
    AH.stats.sent = AH.stats.sent + 1
    AH.SendRaw(msg, key)
end

local function ValidKey(k)
    -- Item-ID bis 6 Stellen, Zufalls-Suffix 1–4 Stellen (Classic-IDs liegen weit darunter)
    return type(k) == "string" and (k:match("^%d%d?%d?%d?%d?%d?$") or k:match("^%d%d?%d?%d?%d?%d?%.[1-9]%d?%d?%d?$")) and true or false
end
local function KnownItem(k)
    local id = tonumber(k:match("^(%d+)"))
    if not id or id < 1 then return false end
    if (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant then return AH.ItemInfoInstant(id) ~= nil end
    return true
end
local function Int(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= v or v < lo or v > hi or v % 1 ~= 0 then return nil end
    return v
end

function AH.EncodeP(side, items)
    local out, cur, n = {}, nil, 0
    local head = "P:" .. side .. ":"
    for _, it in ipairs(items) do
        local part = ("%s=%d,%d,%d"):format(it.key, it.p, it.q or 0, it.t)
        if cur and (n >= MAX_ITEMS or #cur + 1 + #part > MAX_LEN) then
            out[#out + 1] = cur; cur, n = nil, 0
        end
        if not cur then cur = head .. part else cur = cur .. ";" .. part end
        n = n + 1
    end
    if cur then out[#out + 1] = cur end
    return out
end

function AH.DecodeP(msg)
    if type(msg) ~= "string" then return nil end
    local side, body = msg:match("^P:([AHN]):(.+)$")
    if not side then return nil end
    local now, items = GetServerTime(), {}
    for part in body:gmatch("[^;]+") do
        local k, p, q, t = part:match("^([%d%.]+)=(%d+),(%d+),(%d+)$")
        p, q, t = Int(p, 1, MAX_PRICE), Int(q, 1, MAX_QTY), Int(t, now - MAX_AGE, now + 60)
        if k and ValidKey(k) and p and q and t and KnownItem(k) and #items < MAX_ITEMS then
            items[#items + 1] = { key = k, p = p, q = q, t = t }
        end
    end
    return side, items
end

---------------------------------------------------------------------
-- Rundsenden und Nachfragen
---------------------------------------------------------------------
local lastShare, lastAsk, askTimes = {}, {}, {}

function AH.Share(keys)
    if not AH.Opt("ahShare") then return end
    local now, items = GetServerTime(), {}
    for _, key in ipairs(keys or {}) do
        local p, t, src = AH.PriceFor(key)
        if p and src == "own" and (not lastShare[key] or now - lastShare[key] >= SHARE_GAP) then
            lastShare[key] = now
            items[#items + 1] = { key = key, p = p, q = AH.Store()[key].own.q, t = t }
        end
    end
    for _, msg in ipairs(AH.EncodeP(AH.Side(), items)) do Send(msg) end
end

function AH.Ask(key)
    if not AH.Opt("ahShare") or not ValidKey(key) then return end
    local now = GetTime()
    if lastAsk[key] and now - lastAsk[key] < ASK_GAP then return end
    for i = #askTimes, 1, -1 do if now - askTimes[i] >= 60 then table.remove(askTimes, i) end end
    if #askTimes >= ASK_PER_MIN then return end
    lastAsk[key] = now
    askTimes[#askTimes + 1] = now
    Send("Q:" .. AH.Side() .. ":" .. key, "Q:" .. key)
end

-- Geplante Antworten: genau einer soll antworten. Jeder wartet zufällig
-- 1–4 s; kommt vorher ein mindestens gleich neuer Preis, entfällt die Antwort.
local pending = {}   -- [key] = { due, t }

function AH._answerPlanned(key) return pending[key] ~= nil end

function AH._tick(now)
    now = now or GetTime()
    for key, a in pairs(pending) do
        if now >= a.due then
            pending[key] = nil
            local e = AH.Store()[key]
            local o = e and e.own
            if o and GetServerTime() - o.t < ANSWER_MAX_AGE then
                lastShare[key] = GetServerTime()
                for _, msg in ipairs(AH.EncodeP(AH.Side(), { { key = key, p = o.p, q = o.q, t = o.t } })) do
                    Send(msg, "A:" .. key)
                end
            end
        end
    end
end
C_Timer.NewTicker(0.5, function() AH._tick() end)

---------------------------------------------------------------------
-- Empfang mit Schutz gegen Spam und Unsinn
---------------------------------------------------------------------
local perSender = {}     -- [Name] = { n, since, blockedUntil }
local function Allowed(sender)
    local now = GetTime()
    local s = perSender[sender]
    if not s then s = { n = 0, since = now }; perSender[sender] = s end
    if s.blockedUntil and now < s.blockedUntil then return false end
    if now - s.since > 60 then s.n, s.since = 0, now end
    s.n = s.n + 1
    if s.n > RECV_PER_MIN then s.blockedUntil = now + 300; return false end
    return true
end
-- Neue Items je Absender begrenzen, damit niemand die gespeicherten Daten aufbläht
local function NewKeyAllowed(sender)
    local s, now = perSender[sender], GetTime()
    if not s.keysSince or now - s.keysSince > 3600 then s.keys, s.keysSince = 0, now end
    if s.keys >= NEW_KEYS_PER_HOUR then return false end
    s.keys = s.keys + 1
    return true
end
-- Absender, die lange nichts geschickt haben, vergessen
C_Timer.NewTicker(600, function()
    local now = GetTime()
    for name, s in pairs(perSender) do
        if now - s.since > 3600 and not (s.blockedUntil and now < s.blockedUntil) then perSender[name] = nil end
    end
end)

function AH.OnMessage(msg, sender)
    if type(msg) ~= "string" or type(sender) ~= "string" or #msg > MAX_LEN then return end
    if not Allowed(sender) then AH.stats.dropped = AH.stats.dropped + 1; return end
    AH.stats.received = AH.stats.received + 1
    local kind = msg:sub(1, 2)
    if kind == "P:" then
        local side, items = AH.DecodeP(msg)
        if not side or #items == 0 then AH.stats.dropped = AH.stats.dropped + 1; return end
        if side ~= AH.Side() then return end
        local store = AH.Store()
        for _, it in ipairs(items) do
            if not store[it.key] and not NewKeyAllowed(sender) then
                AH.stats.dropped = AH.stats.dropped + 1
                break
            end
            AH.RecordServer(it.key, it.p, it.q, it.t, sender)
            local a = pending[it.key]
            if a and it.t >= a.t then pending[it.key] = nil end
            if AH.OnPrice then AH.OnPrice(it.key) end
        end
    elseif kind == "Q:" then
        local side, key = msg:match("^Q:([AHN]):([%d%.]+)$")
        if not side or not ValidKey(key) then AH.stats.dropped = AH.stats.dropped + 1; return end
        if side ~= AH.Side() or pending[key] then return end
        local e = AH.Store()[key]
        local o = e and e.own
        if not o or GetServerTime() - o.t >= ANSWER_MAX_AGE then return end
        pending[key] = { due = GetTime() + 1 + math.random() * 3, t = o.t }
    else
        AH.stats.dropped = AH.stats.dropped + 1
    end
end

AH.Listen("CHAT_MSG_ADDON", function(prefix, msg, channel, sender)
    if prefix ~= PREFIX or channel ~= "CHANNEL" or not AH.Opt("ahShare") then return end
    if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
    if type(sender) ~= "string" then return end
    local me = UnitName("player")
    if sender == me or Ambiguate(sender, "none") == me then return end
    AH.OnMessage(msg, Ambiguate(sender, "none"))
end)

-- Spät beitreten, damit Allgemein/Handel ihre gewohnten Nummern behalten
AH.Listen("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(25, AH.UpdateChannel)
end)
