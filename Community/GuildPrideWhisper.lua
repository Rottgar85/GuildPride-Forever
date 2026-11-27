-- GuildPride Messenger: Flüstern im Messenger-Fenster (wie WIM)
-- Wer dich anflüstert, bekommt eine eigene Unterhaltung im Messenger; das Fenster geht dabei auf
-- (im Kampf erst danach, abschaltbar). Antworten aus dem Fenster sind normales Flüstern.
-- Blizzards Chat bleibt unverändert: kein Chat-Filter, nichts wird umgeschrieben oder ausgeblendet
-- (ein umschreibender Filter hatte in 2.37.0 Chatnachrichten verschluckt).
-- Gespeichert je eigenem Charakter in GuildPrideDB.whispers[Ich]:
--   convs[Name] = { { t, out, text } }, unread[Name] = n, target[Name] = Name wie das Spiel ihn liefert
local ADDON, ns = ...
local L = ns.L

local Wh = {}
ns.Whisper = Wh
local MAX_CONV, MAX_CONVS = 200, 100
local function SendChat(text, kind, lang, target) assert(ns.SendChat(text, kind, lang, target, true)) end

local Secret = ns.IsSecret
local function WhisperOn() return GuildPrideDB.whisperEnabled ~= false end

function Wh.DB()
    GuildPrideDB.whispers = type(GuildPrideDB.whispers) == "table" and GuildPrideDB.whispers or {}
    local me = ns.Me()
    local db = GuildPrideDB.whispers[me]
    if type(db) ~= "table" then db = {}; GuildPrideDB.whispers[me] = db end
    for _, k in ipairs({ "convs", "unread", "target" }) do
        if type(db[k]) ~= "table" then db[k] = {} end
    end
    return db
end
local DB = Wh.DB

-- Einheitlicher Schlüssel für einen Namen (Forever: „Vorname Nachname“)
function Wh.Key(name) return ns.Normalize(name) end

function Wh.Conv(name)
    local db = DB()
    db.convs[name] = db.convs[name] or {}
    return db.convs[name]
end

local function Changed() if ns.Messenger and ns.Messenger.Refresh then ns.Messenger.Refresh() end end

-- Älteste Unterhaltungen wegräumen, wenn es zu viele werden
local function Trim()
    local db, list = DB(), {}
    for name, c in pairs(db.convs) do list[#list + 1] = { name = name, t = (c[#c] or {}).t or 0 } end
    if #list <= MAX_CONVS then return end
    table.sort(list, function(a, b) return a.t > b.t end)
    for i = MAX_CONVS + 1, #list do
        local n = list[i].name
        db.convs[n], db.unread[n], db.target[n] = nil, nil, nil
    end
end

-- Zeile eintragen; raw = Name wie das Spiel ihn liefert (zum Antworten)
function Wh.Add(raw, text, out, t)
    if type(raw) ~= "string" or raw == "" or type(text) ~= "string" then return nil end
    local key = Wh.Key(raw)
    local db = DB()
    db.target[key] = raw
    local c = Wh.Conv(key)
    c[#c + 1] = { t = t or GetServerTime(), out = out and true or nil, text = text:sub(1, 400) }
    while #c > MAX_CONV do table.remove(c, 1) end
    if not out and not (ns.Messenger and ns.Messenger.IsOpenOn and ns.Messenger.IsOpenOn("W:" .. key)) then
        db.unread[key] = (db.unread[key] or 0) + 1
    end
    Trim()
    Changed()
    return key
end

-- Das Spiel nimmt höchstens 255 Byte je Nachricht und wirft sonst einen Fehler. Getrennt wird an
-- einem Leerzeichen, nie mitten in einem Zeichen (UTF-8) oder in einem Link.
local MAX_BYTES = 255
local function Cut(text)
    if #text <= MAX_BYTES then return text, nil end
    local pos = MAX_BYTES
    while pos > 1 do
        local nextByte = text:byte(pos + 1)
        if not nextByte or nextByte < 128 or nextByte >= 192 then break end
        pos = pos - 1
    end
    local head = text:sub(1, pos)
    local open = head:match(".*()|c%x%x%x%x%x%x%x%x")
    if open and open > 1 and not head:find("|r", open, true) then
        pos = open - 1
    else
        local space = head:match(".*() ")
        if space and space > 1 then pos = space end
    end
    return strtrim(text:sub(1, pos)), strtrim(text:sub(pos + 1))
end
ns.CutMessage = Cut   -- auch für Gildenchat und Begrüßung

-- Antworten: normales Flüstern (aus einem Klick oder Enter – also vom Spieler ausgelöst).
-- Gibt true zurück und, wenn der Text zu lang war, den Rest fürs nächste Enter.
function Wh.Send(key, text)
    text = strtrim(tostring(text or ""))
    if text == "" then return false end
    local target = DB().target[key] or key
    local head, rest = Cut(text)
    if not pcall(SendChat, head, "WHISPER", nil, target) then
        ns.Print(L["Das Spiel hat die Nachricht gerade abgelehnt. Warte kurz und schick sie noch einmal."])
        return false
    end
    return true, rest   -- die eigene Zeile kommt über CHAT_MSG_WHISPER_INFORM
end

function Wh.UnreadTotal()
    if not WhisperOn() then return 0 end
    local n = 0
    for _, c in pairs(DB().unread) do n = n + c end
    return n
end
function Wh.MarkRead(key) DB().unread[key] = nil end
function Wh.Delete(key)
    local db = DB()
    db.convs[key], db.unread[key], db.target[key] = nil, nil, nil
    Changed()
end

-- { { key = "W:Name", name, last, unread, whisper = true } }
function Wh.Conversations()
    if not WhisperOn() then return {} end
    local db, out = DB(), {}
    for name, c in pairs(db.convs) do
        if #c > 0 then
            out[#out + 1] = { key = "W:" .. name, name = name, last = c[#c], unread = db.unread[name] or 0, whisper = true }
        end
    end
    return out
end

-- Kennt man den Absender? (Gilde, Freunde, Gruppe) – für „nur von Bekannten aufgehen“
function Wh.Known(raw, guid)
    if ns.IsGuildMember(ns.Normalize(raw)) then return true end
    if guid and C_FriendList and C_FriendList.IsFriend then
        local ok, friend = pcall(C_FriendList.IsFriend, guid)
        if ok and friend == true then return true end
    end
    local short = Ambiguate(raw, "none")
    if (UnitInParty and UnitInParty(short) == true) or (UnitInRaid and type(UnitInRaid(short)) == "number") then return true end
    return false
end

---------------------------------------------------------------------
-- Fenster aufgehen lassen
---------------------------------------------------------------------
local pendingOpen   -- im Kampf angekommen: nach dem Kampf öffnen
local function PopUp(key)
    local M = ns.Messenger
    if not (M and M.ShowIncoming) then return end
    if InCombatLockdown() and not GuildPrideDB.whisperCombat then pendingOpen = key; return end
    M.ShowIncoming("W:" .. key)
end
Wh._Pending = function() return pendingOpen end   -- für Tests

function Wh.OnWhisper(text, sender, guid)
    if Secret(text) or Secret(sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
    if not WhisperOn() then return end
    local key = Wh.Add(sender, text, false)
    if not key or GuildPrideDB.whisperWindow == false then return end
    if GuildPrideDB.whisperKnownOnly and not Wh.Known(sender, guid) then return end
    PopUp(key)
end

function Wh.OnInform(text, target)
    if not WhisperOn() then return end
    if Secret(text) or Secret(target) or type(text) ~= "string" or type(target) ~= "string" then return end
    Wh.Add(target, text, true)
end

function Wh.AfterCombat()
    if not pendingOpen then return end
    local key = pendingOpen
    pendingOpen = nil
    PopUp(key)
end

---------------------------------------------------------------------
-- Selbst flüstern (/w Name, R zum Antworten, „Flüstern“ im Namensmenü): Messenger öffnen und die
-- Eingabe dort hinlegen. Nur nachgelagerte Hooks und Lesen der Ziel-Angabe – Blizzards Chat-Eingabe
-- wird weder geschlossen noch verändert (sonst könnte normales Chatten blockiert werden).
---------------------------------------------------------------------
local lastOut, lastOutAt = nil, 0
function Wh.StartOutgoing(target)
    if not WhisperOn() or GuildPrideDB.whisperOutgoing == false then return false end
    if type(target) ~= "string" or target == "" or Secret(target) then return false end
    local M = ns.Messenger
    if not (M and M.OpenWhisper) then return false end
    local now = GetTime()
    if target == lastOut and now - lastOutAt < 2 then return false end
    lastOut, lastOutAt = target, now
    M.OpenWhisper(target)
    return true
end

local function FromEditBox(editBox)
    if type(editBox) ~= "table" or not editBox.GetAttribute then return end
    local ok, kind = pcall(editBox.GetAttribute, editBox, "chatType")
    if not ok or kind ~= "WHISPER" then return end
    local ok2, target = pcall(editBox.GetAttribute, editBox, "tellTarget")
    if ok2 then Wh.StartOutgoing(target) end
end
Wh._FromEditBox = FromEditBox   -- für Tests

if hooksecurefunc then
    if type(ChatEdit_UpdateHeader) == "function" then
        hooksecurefunc("ChatEdit_UpdateHeader", function(editBox) ns.Try(FromEditBox, editBox) end)
    end
    if type(ChatFrame_SendTell) == "function" then
        hooksecurefunc("ChatFrame_SendTell", function(name) ns.Try(Wh.StartOutgoing, name) end)
    end
    if type(ChatFrameUtil) == "table" and type(ChatFrameUtil.SendTell) == "function" then
        hooksecurefunc(ChatFrameUtil, "SendTell", function(name) ns.Try(Wh.StartOutgoing, name) end)
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_WHISPER")
ev:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event, text, sender, ...)
    if not GuildPrideDB then return end
    local ok, err = true, nil
    if event == "CHAT_MSG_WHISPER" then
        local guid = select(10, ...)   -- 12. Wert des Events
        ok, err = pcall(Wh.OnWhisper, text, sender, (type(guid) == "string" and not Secret(guid)) and guid or nil)
    elseif event == "CHAT_MSG_WHISPER_INFORM" then
        ok, err = pcall(Wh.OnInform, text, sender)
    elseif event == "PLAYER_REGEN_ENABLED" then
        ok, err = pcall(Wh.AfterCombat)
    end
    if not ok then geterrorhandler()(err) end
end)
