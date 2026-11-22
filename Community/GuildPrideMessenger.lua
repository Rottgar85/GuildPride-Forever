-- GuildPride Messenger: Nachrichten an Gildenmitglieder – auch, wenn sie offline sind.
--
-- Zustellung:
--   * Empfänger online (irgendein Charakter seines Mains): direkt per Addon-Flüstern (NMS).
--   * Empfänger offline: die Nachricht geht an alle GuildPride-Nutzer der Gilde, die online sind (NMR);
--     sie heben sie auf (höchstens 14 Tage). Loggt der Empfänger ein, fragt er nach (NMQ) und bekommt
--     sie von einem von ihnen (NMF). Auch der Absender selbst schickt Offenes nach, sobald der
--     Empfänger nachfragt.
--   * Der Empfänger quittiert (NMA, an die Gilde): Aufbewahrer löschen ihre Kopie, der Absender sieht
--     „zugestellt“.
-- Adressiert wird der Main (ns.MainOf): schreibst du einem Twink, kommt es bei allen Charakteren an.
-- Kein Geheimnisschutz: Offline-Nachrichten liegen bei anderen Mitgliedern in den gespeicherten Daten.
--
--   NMS  id · an(Main) · Zeit · Text · Frage            direkt vom Absender
--   NMR  id · an(Main) · Zeit · Text · Frage            „bitte aufheben“ (an die Gilde)
--   NMF  id · Absender · an(Main) · Zeit · Text · Frage weitergereicht von einem Aufbewahrer
--   (Frage = Kennung einer Frage an die Offiziere, GuildPrideQuestions.lua; sonst leer)
--   NMA  id                                     Quittung des Empfängers (an die Gilde)
--   NMQ  1                                      „ich bin da – habt ihr etwas für mich?“
-- Gespeichert in GuildTable("messenger"):
--   convs[Main] = { { id, out, text, t, state ("sent"|"stored"|"delivered"|"expired"), via } }, unread[Main] = n,
--   outbox[id] = { to, text, t, stored }, relay[id] = { author, to, text, t }, seen[id] = Zeit
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP

local M = {}
ns.Messenger = M
local MAX_TEXT = 400
local MAX_CONV = 200            -- Nachrichten je Unterhaltung
local KEEP = 14 * 86400         -- Aufbewahrung bei anderen und offene Nachrichten
local RELAY_MAX, RELAY_PER_AUTHOR = 200, 20
local ACK_WAIT = 20             -- so lange auf die Quittung einer Direktnachricht warten

local function Me() return ns.Me() end
local function Now() return GetServerTime() end
local function MainOf(name) return ns.MainOf and ns.MainOf(name) or name end
local function MyMain() return MainOf(Me()) end

function M.DB()
    local db = ns.GuildTable("messenger")
    for _, k in ipairs({ "convs", "unread", "outbox", "relay", "seen" }) do
        if type(db[k]) ~= "table" then db[k] = {} end
    end
    return db
end
local DB = M.DB

function M.Clean(s)
    s = tostring(s or ""):gsub("|", ""):gsub(SEP, " "):gsub("[%c]", " ")
    return (strtrim(s):sub(1, MAX_TEXT))
end
local Clean = M.Clean

local counter = 0
local function NewId()
    counter = counter % 9999 + 1
    return ("%x%x%d"):format(Now(), math.random(0, 0xffff), counter)
end

local function ValidId(id) return type(id) == "string" and #id >= 4 and #id <= 24 and id:match("^%w+$") ~= nil end

-- Online-Charaktere eines Mains (aus der Gildenliste), ohne mich
function M.OnlineChars(main)
    local out = {}
    if not (IsInGuild() and GetNumGuildMembers) then return out end
    for i = 1, GetNumGuildMembers() or 0 do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        local full = name and ns.Normalize(name)
        if full and online and full ~= Me() and MainOf(full) == main then out[#out + 1] = full end
    end
    return out
end

-- Gibt es den Main (oder einen seiner Charaktere) in der Gilde?
function M.Known(main)
    if type(main) ~= "string" or main == "" then return false end
    if ns.IsGuildMember(main) then return true end
    for i = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
        local name = GetGuildRosterInfo(i)
        if name and MainOf(ns.Normalize(name)) == main then return true end
    end
    return false
end

-- Namen auflösen: "anna" → Main des Charakters aus der Gildenliste (nil, wenn unbekannt)
function M.Resolve(text)
    text = strtrim(tostring(text or ""))
    if text == "" then return nil end
    local want = text:lower()
    for i = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
        local name = GetGuildRosterInfo(i)
        local full = name and ns.Normalize(name)
        if full and (full:lower() == want or Ambiguate(full, "none"):lower() == want or Ambiguate(full, "guild"):lower() == want) then
            return MainOf(full)
        end
    end
    return nil
end

local function Conv(main)
    local db = DB()
    db.convs[main] = db.convs[main] or {}
    return db.convs[main]
end
M.Conv = Conv

local function AddToConv(main, entry)
    local c = Conv(main)
    for _, e in ipairs(c) do if e.id == entry.id then return false end end
    c[#c + 1] = entry
    table.sort(c, function(a, b) return (a.t or 0) < (b.t or 0) end)
    while #c > MAX_CONV do table.remove(c, 1) end
    return true
end

local function SetState(id, state)
    for _, c in pairs(DB().convs) do
        for _, e in ipairs(c) do
            if e.id == id and e.out then
                if e.state ~= "delivered" then e.state = state end   -- „zugestellt“ bleibt
                return
            end
        end
    end
end

local function Changed() if M.Refresh then M.Refresh() end end

---------------------------------------------------------------------
-- Senden
---------------------------------------------------------------------
local function Store(id, o)
    if o.stored then return end
    o.stored = true
    ns.Queue("NMR", nil, id, o.to, o.t, o.text, o.q or "")
    SetState(id, "stored")
    Changed()
end

-- Nachricht an einen Main (oder Charakter). Gibt id zurück oder nil, Grund.
-- opts.q = Kennung einer Frage an die Offiziere (GuildPrideQuestions.lua)
function M.Send(to, text, opts)
    if not IsInGuild() then return nil, "gilde" end
    local main = type(to) == "string" and to ~= "" and (M.Resolve(to) or MainOf(ns.Normalize(to))) or nil
    text = Clean(text)
    if text == "" then return nil, "leer" end
    if not main or not M.Known(main) then return nil, "unbekannt" end
    if main == MyMain() then return nil, "selbst" end
    local q = opts and ValidId(opts.q) and opts.q or nil
    local id, t = NewId(), Now()
    local db = DB()
    db.outbox[id] = { to = main, text = text, t = t, q = q }
    db.seen[id] = t
    AddToConv(main, { id = id, out = true, text = text, t = t, state = "sent", q = q })
    local chars = M.OnlineChars(main)
    if #chars > 0 then
        for _, c in ipairs(chars) do ns.Queue("NMS", c, id, main, t, text, q or "") end
        -- keine Quittung? dann doch bei den anderen aufheben lassen
        C_Timer.After(ACK_WAIT, function()
            local o = DB().outbox[id]
            if o then Store(id, o) end
        end)
    else
        Store(id, db.outbox[id])
    end
    -- Offizier antwortet einem Mitglied: dessen offene Fragen gelten als beantwortet
    if not q and ns.Questions and ns.Questions.AfterSend then pcall(ns.Questions.AfterSend, main) end
    Changed()
    return id
end

-- Offene eigene Nachrichten an einen Main direkt nachschicken (er hat sich gerade gemeldet)
local function Resend(main, char)
    for id, o in pairs(DB().outbox) do
        if o.to == main then ns.Queue("NMS", char, id, o.to, o.t, o.text, o.q or "") end
    end
end

---------------------------------------------------------------------
-- Empfangen
---------------------------------------------------------------------
local notifyAt = 0
local function Notify(fromMain, text, via, q)
    if M.IsOpenOn and M.IsOpenOn(fromMain) then return end
    if GetTime() - notifyAt > 2 then
        notifyAt = GetTime()
        if PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then PlaySound(SOUNDKIT.TELL_MESSAGE) end
    end
    local short = #text > 60 and (text:sub(1, 60) .. " …") or text
    local fmt = q and L["|cffffd100Frage eines Mitglieds von %s:|r %s  |cff888888(/gp nachrichten)|r"]
        or L["|cffd4af37Nachricht von %s:|r %s  |cff888888(/gp nachrichten)|r"]
    ns.Print(fmt:format(Ambiguate(fromMain, "guild"), short)
        .. (via and (" |cff777777" .. L["(später zugestellt)"] .. "|r") or ""))
end

-- Eingang einer Nachricht für mich. author = Charakter des Absenders, via = Aufbewahrer (oder nil)
function M.Receive(id, author, to, t, text, via, q)
    if not ValidId(id) or type(author) ~= "string" or author == Me() then return false end
    if to ~= MyMain() and not (ns.IsMyChar and ns.IsMyChar(to)) then return false end
    local db = DB()
    -- Quittung immer schicken, auch bei Doppelten (die erste könnte verloren gegangen sein)
    ns.Queue("NMA", nil, id)
    if db.seen[id] then return false end
    text = Clean(text)
    if text == "" then return false end
    db.seen[id] = Now()
    local from = MainOf(author)
    t = math.min(ns.Stamp(t), Now())
    if t == 0 then t = Now() end
    q = ValidId(q) and q or nil
    AddToConv(from, { id = id, out = false, text = text, t = t, author = author, via = via, q = q })
    if not (M.IsOpenOn and M.IsOpenOn(from)) then db.unread[from] = (db.unread[from] or 0) + 1 end
    if q and ns.Questions and ns.Questions.Record then pcall(ns.Questions.Record, q, author, text, t) end
    Notify(from, text, via, q)
    Changed()
    return true
end

local function Fields(payload) return strsplit(SEP, payload or "") end

ns.On("NMS", function(payload, sender)
    if not ns.IsGuildMember(sender) then return end
    local id, to, t, text, q = Fields(payload)
    M.Receive(id, sender, to, t, text, nil, q)
end)

ns.On("NMF", function(payload, sender)
    if not ns.IsGuildMember(sender) then return end
    local id, author, to, t, text, q = Fields(payload)
    if not author or not ns.IsGuildMember(author) then return end
    M.Receive(id, author, to, t, text, sender, q)
end)

-- Aufheben für jemanden, der offline ist
function M.Keep(id, author, to, t, text, q)
    if not ValidId(id) or author == Me() then return false end
    if to == MyMain() then return M.Receive(id, author, to, t, text, nil, q) end   -- ist ja für mich
    local db = DB()
    if db.relay[id] or db.seen[id] then return false end
    text = Clean(text)
    if text == "" or not M.Known(to) then return false end
    local total, mine = 0, 0
    for _, r in pairs(db.relay) do
        total = total + 1
        if r.author == author then mine = mine + 1 end
    end
    if total >= RELAY_MAX or mine >= RELAY_PER_AUTHOR then return false end
    t = math.min(ns.Stamp(t), Now())
    db.relay[id] = { author = author, to = to, text = text, t = t > 0 and t or Now(), q = ValidId(q) and q or nil }
    return true
end

ns.On("NMR", function(payload, sender)
    if not ns.IsGuildMember(sender) then return end
    local id, to, t, text, q = Fields(payload)
    M.Keep(id, sender, to, t, text, q)
end)

-- Quittung: nur vom Empfänger selbst (einem Charakter seines Mains)
function M.Ack(id, sender)
    if not ValidId(id) then return end
    local db = DB()
    local r = db.relay[id]
    if r and MainOf(sender) == r.to then db.relay[id] = nil end
    local o = db.outbox[id]
    if o and MainOf(sender) == o.to then
        db.outbox[id] = nil
        SetState(id, "delivered")
        Changed()
    end
end
ns.On("NMA", function(payload, sender) M.Ack((Fields(payload)), sender) end)

-- Jemand ist eingeloggt und fragt nach: eigene offene Nachrichten und Aufbewahrtes schicken
ns.On("NMQ", function(_, sender)
    if sender == Me() or not ns.IsGuildMember(sender) then return end
    local main = MainOf(sender)
    Resend(main, sender)
    local list = {}
    for id, r in pairs(DB().relay) do if r.to == main then list[#list + 1] = id end end
    if #list == 0 then return end
    C_Timer.After(2 + math.random() * 6, function()
        local db = DB()
        for _, id in ipairs(list) do
            local r = db.relay[id]   -- inzwischen quittiert? dann nil
            if r then ns.Queue("NMF", sender, id, r.author, r.to, r.t, r.text, r.q or "") end
        end
    end)
end)

-- Aufräumen: alte Kopien, alte Kennungen, nie zugestellte Nachrichten
function M.Prune(now)
    now = now or Now()
    local db = DB()
    for id, r in pairs(db.relay) do if now - (r.t or 0) > KEEP then db.relay[id] = nil end end
    for id, t in pairs(db.seen) do if now - t > 2 * KEEP then db.seen[id] = nil end end
    for id, o in pairs(db.outbox) do
        if now - (o.t or 0) > KEEP then db.outbox[id] = nil; SetState(id, "expired") end
    end
end

function M.UnreadTotal()
    local n = 0
    for _, c in pairs(DB().unread) do n = n + c end
    return n
end

function M.MarkRead(main)
    if DB().unread[main] then DB().unread[main] = nil; Changed() end
end

-- Unterhaltungen, neueste zuerst: { { main, last, unread } }
function M.Conversations()
    local db, out = DB(), {}
    for main, c in pairs(db.convs) do
        if #c > 0 then out[#out + 1] = { main = main, last = c[#c], unread = db.unread[main] or 0 } end
    end
    table.sort(out, function(a, b) return (a.last.t or 0) > (b.last.t or 0) end)
    return out
end

function M.Delete(main)
    local db = DB()
    db.convs[main], db.unread[main] = nil, nil
    Changed()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    C_Timer.After(20, function()
        if not IsInGuild() then return end
        M.Prune()
        ns.Queue("NMQ", nil, "1")
        Changed()
    end)
end)
