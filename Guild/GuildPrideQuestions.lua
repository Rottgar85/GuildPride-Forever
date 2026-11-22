-- GuildPride: Fragen neuer Mitglieder an die Offiziere
-- Eine Frage aus dem Willkommensfenster geht als Messenger-Nachricht an jeden Offizier (Kennzeichen q),
-- also auch an Offiziere, die gerade offline sind (Zustellung wie im Messenger). Offiziere sehen die
-- Fragen im Messenger und unter Verwaltung › „Fragen neuer Mitglieder“. Antwortet ein Offizier dem
-- Mitglied im Messenger, gilt die Frage für alle Offiziere als beantwortet.
--   FQA  Frage · von        (beantwortet; nur von Offizieren angenommen)
--   FQQ  1                  (Offizier fragt nach dem Einloggen, welche Fragen schon beantwortet sind)
-- Gespeichert: GuildTable("questions")[Frage] = { who, main, text, t, answeredBy, answeredAt }
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP

local Q = {}
ns.Questions = Q
local KEEP = 30 * 86400
local ASK_GAP = 30
local lastAsk = -1000

local function DB() return ns.GuildTable("questions") end
local function MainOf(name) return ns.MainOf and ns.MainOf(name) or name end
local function ValidId(id) return type(id) == "string" and #id >= 4 and #id <= 24 and id:match("^%w+$") ~= nil end
Q.ValidId = ValidId

-- Offiziere der Gilde (Mains), ohne mich: { { main, online } }
function Q.Officers()
    local by, list, me = {}, {}, MainOf(ns.Me())
    for i = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
        local name, _, rankIndex, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if name and ns.IsOfficerRank(tonumber(rankIndex) or 99) then
            local main = MainOf(ns.Normalize(name))
            if main ~= me then
                local e = by[main]
                if not e then e = { main = main, online = false }; by[main] = e; list[#list + 1] = e end
                if online then e.online = true end
            end
        end
    end
    table.sort(list, function(a, b) return a.main < b.main end)
    return list
end

local counter = 0
local function NewId()
    counter = counter % 999 + 1
    return ("q%x%x%d"):format(GetServerTime(), math.random(0, 0xfff), counter)
end

-- Frage stellen: gibt Anzahl Offiziere und wie viele davon online sind zurück, oder nil, Grund
function Q.Ask(text)
    local M = ns.Messenger
    if not (IsInGuild() and M) then return nil, "gilde" end
    text = M.Clean(text)
    if text == "" then return nil, "leer" end
    if GetTime() - lastAsk < ASK_GAP then return nil, "wait" end
    local officers = Q.Officers()
    if #officers == 0 then return nil, "keine" end
    lastAsk = GetTime()
    local qid, sent, online = NewId(), 0, 0
    for _, o in ipairs(officers) do
        if M.Send(o.main, text, { q = qid }) then
            sent = sent + 1
            if o.online then online = online + 1 end
        end
    end
    if sent == 0 then return nil, "keine" end
    return sent, online
end

-- Eine Frage ist bei mir (Offizier) angekommen
function Q.Record(qid, author, text, t)
    if not ValidId(qid) or not (ns.IsOfficer and ns.IsOfficer()) then return false end
    local db = DB()
    if db[qid] then return false end
    db[qid] = { who = author, main = MainOf(author), text = text, t = t or GetServerTime() }
    if Q.Changed then Q.Changed() end
    return true
end

local function MarkAnswered(qid, by, t)
    local e = DB()[qid]
    if not e or e.answeredBy then return false end
    e.answeredBy, e.answeredAt = by, t or GetServerTime()
    if Q.Changed then Q.Changed() end
    return true
end

-- Ein Offizier hat einem Main geschrieben: offene Fragen dieses Mains sind beantwortet
function Q.AfterSend(main)
    if not (ns.IsOfficer and ns.IsOfficer()) then return end
    for qid, e in pairs(DB()) do
        if e.main == main and not e.answeredBy then
            MarkAnswered(qid, ns.Me())
            ns.Queue("FQA", nil, qid, ns.Me())
        end
    end
end

ns.On("FQA", function(payload, sender)
    if not (ns.IsOfficerName and ns.IsOfficerName(sender)) then return end
    local qid = strsplit(SEP, payload or "")
    if ValidId(qid) then MarkAnswered(qid, sender) end
end)

-- Nach dem Einloggen: welche Fragen haben andere Offiziere inzwischen beantwortet?
ns.On("FQQ", function(_, sender)
    if not (ns.IsOfficer and ns.IsOfficer()) or sender == ns.Me() then return end
    local list = {}
    for qid, e in pairs(DB()) do if e.answeredBy == ns.Me() then list[#list + 1] = qid end end
    if #list == 0 then return end
    C_Timer.After(1 + math.random() * 5, function()
        for i = 1, math.min(#list, 20) do ns.Queue("FQA", sender, list[i], ns.Me()) end
    end)
end)

-- Fragen, neueste zuerst: { { qid, who, main, text, t, answeredBy } }
function Q.List(onlyOpen)
    local out = {}
    for qid, e in pairs(DB()) do
        if not onlyOpen or not e.answeredBy then
            out[#out + 1] = { qid = qid, who = e.who, main = e.main, text = e.text, t = e.t, answeredBy = e.answeredBy }
        end
    end
    table.sort(out, function(a, b) return (a.t or 0) > (b.t or 0) end)
    return out
end

function Q.OpenCount()
    local n = 0
    for _, e in pairs(DB()) do if not e.answeredBy then n = n + 1 end end
    return n
end

function Q.Prune(now)
    now = now or GetServerTime()
    local db = DB()
    for qid, e in pairs(db) do if now - (e.t or 0) > KEEP then db[qid] = nil end end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    C_Timer.After(40, function()
        if not IsInGuild() then return end
        Q.Prune()
        if ns.IsOfficer and ns.IsOfficer() then ns.Queue("FQQ", nil, "1") end
    end)
end)
