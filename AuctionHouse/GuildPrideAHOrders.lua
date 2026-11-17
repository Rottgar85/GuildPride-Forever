-- GuildPride: Gildenaufträge („Ich brauche 3× Kupferkettenweste“)
-- Jeder stellt eigene Aufträge ein; Hersteller in der Gilde nehmen sie an.
-- Abgleich wie bei der Wunschliste: jeder schickt nur seine EIGENEN Aufträge, nie weitergeleitet.
--   ORD  ver · "id:item:menge:zeit,…"   eigene Aufträge (an die Gilde, oder per Flüstern als Antwort)
--   ORQ  1                               Aufträge anfragen (alle antworten per Flüstern)
--   ORA  besitzer · id · 1|0             „ich übernehme den Auftrag“ bzw. „ich gebe ihn ab“ –
--                                        nur der Hersteller selbst über sich (nie weitergeleitet)
-- Gespeichert je Gilde: orders[Name] = { v, o = { { id, i, q, t } } },
--                       orderTakes["Besitzer\030id"] = { by, t }
local ADDON, GP = ...
GP.AH = GP.AH or {}
local AH = GP.AH
local L = GP.L or setmetatable({}, { __index = function(_, k) return k end })
local SEP = GP.SEP or "\031"

local MAX_OWN, MAX_PEOPLE, MAX_QTY = 20, 1000, 999
local KEEP = 14 * 86400          -- Aufträge verfallen nach 14 Tagen

local function DB() return GP.GuildTable("orders") end
local function Takes() return GP.GuildTable("orderTakes") end
local function Me() return GP.Me() end
local function Now() return GetServerTime() end
local function TakeKey(owner, id) return owner .. "\030" .. id end

local function Encode(list)
    local parts = {}
    for _, o in ipairs(list) do parts[#parts + 1] = ("%s:%d:%d:%d"):format(o.id, o.i, o.q, o.t) end
    return table.concat(parts, ",")
end

local function Decode(s)
    local out = {}
    for part in tostring(s or ""):gmatch("[^,]+") do
        local id, i, q, t = part:match("^([%w]+):(%d+):(%d+):(%d+)$")
        i, q, t = tonumber(i), tonumber(q), tonumber(t)
        if id and #id <= 16 and i and i >= 1 and i <= 999999 and q and q >= 1 and q <= MAX_QTY and t then
            out[#out + 1] = { id = id, i = i, q = q, t = t }
            if #out >= MAX_OWN then break end
        end
    end
    return out
end

local function Mine()
    local e = DB()[Me()]
    if not e then e = { v = 0, o = {} }; DB()[Me()] = e end
    e.o = e.o or {}
    return e
end

local function Send(target)
    local e = DB()[Me()]
    if e and e.v and e.v > 0 and GP.Queue then GP.Queue("ORD", target, e.v, Encode(e.o)) end
end

local function Changed()
    if AH.OrdersChanged then AH.OrdersChanged() end
end

local function Prune(e, now)
    for i = #e.o, 1, -1 do if (now or Now()) - (e.o[i].t or 0) > KEEP then table.remove(e.o, i) end end
end

-- Alle gültigen Aufträge, neueste zuerst: { owner, id, item, qty, t, by, mine }
function AH.Orders(now)
    now = now or Now()
    local out, takes, me = {}, Takes(), Me()
    for owner, e in pairs(DB()) do
        if owner == me or (GP.IsGuildMember and GP.IsGuildMember(owner)) then
            for _, o in ipairs(e.o or {}) do
                if now - (o.t or 0) <= KEEP then
                    local tk = takes[TakeKey(owner, o.id)]
                    out[#out + 1] = { owner = owner, id = o.id, item = o.i, qty = o.q, t = o.t,
                                      by = tk and tk.by or nil, mine = owner == me }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.t ~= b.t then return a.t > b.t end
        return a.owner < b.owner
    end)
    return out
end

-- Neuen eigenen Auftrag einstellen: Item (ID, Link oder Text mit ID), Menge 1–999
function AH.AddOrder(item, qty)
    local id = AH.ParseItemIDs(item)[1]
    if not id then return nil, L["Keine gültige Item-ID gefunden."] end
    local e = Mine()
    Prune(e)
    if #e.o >= MAX_OWN then return nil, (L["Höchstens %d eigene Aufträge."]):format(MAX_OWN) end
    qty = math.max(1, math.min(math.floor(tonumber(qty) or 1), MAX_QTY))
    local t = Now()
    local oid
    local n = 0
    repeat
        n = n + 1
        oid = ("%x%d"):format(t % 16777216, n)
        local used = false
        for _, o in ipairs(e.o) do if o.id == oid then used = true end end
    until not used
    local o = { id = oid, i = id, q = qty, t = t }
    e.o[#e.o + 1] = o
    e.v = math.max((e.v or 0) + 1, t)
    Send(nil)
    Changed()
    return { owner = Me(), id = oid, item = id, qty = qty, t = t, mine = true }
end

function AH.RemoveOrder(id)
    local e = Mine()
    for i, o in ipairs(e.o) do
        if o.id == id then
            table.remove(e.o, i)
            Takes()[TakeKey(Me(), id)] = nil
            e.v = math.max((e.v or 0) + 1, Now())
            Send(nil)
            Changed()
            return true
        end
    end
    return false
end

-- Auftrag eines anderen übernehmen (on = true) oder wieder abgeben
function AH.TakeOrder(owner, id, on)
    if not owner or not id or owner == Me() then return false end
    local key, takes = TakeKey(owner, id), Takes()
    local cur = takes[key]
    if on then
        if cur and cur.by ~= Me() then return false end
        takes[key] = { by = Me(), t = Now() }
    else
        if not cur or cur.by ~= Me() then return false end
        takes[key] = nil
    end
    if GP.Queue then GP.Queue("ORA", nil, owner, id, on and 1 or 0) end
    Changed()
    return true
end

-- Aufträge der Gilde anfragen (z. B. beim Öffnen des Reiters)
local asked = -60
function AH.RequestOrders()
    if not GP.Queue or GetTime() - asked < 60 then return end
    asked = GetTime()
    GP.Queue("ORQ", nil, 1)
end

---------------------------------------------------------------------
-- Empfangen
---------------------------------------------------------------------
local function Accept(sender)
    return sender ~= Me() and GP.IsDirect and GP.IsDirect(sender, sender) and GP.IsGuildMember(sender)
end

local function Count()
    local n = 0
    for _ in pairs(DB()) do n = n + 1 end
    return n
end

GP.On("ORD", function(payload, sender)
    if not Accept(sender) then return end
    local ver, list = strsplit(SEP, payload)
    ver = GP.Stamp(ver)
    if ver == 0 then return end
    local e = DB()[sender]
    if e and ver <= (e.v or 0) then return end
    if not e and Count() >= MAX_PEOPLE then return end
    local orders = Decode(list)
    if #orders == 0 then DB()[sender] = nil else DB()[sender] = { v = ver, o = orders } end
    Changed()
end)

-- Anfrage: höchstens alle 30 Minuten je Fragendem antworten
local answered = {}
GP.On("ORQ", function(_, sender)
    if sender == Me() or not GP.IsGuildMember(sender) then return end
    local now = GetTime()
    if answered[sender] and now - answered[sender] < 1800 then return end
    answered[sender] = now
    C_Timer.After(math.random() * 5, function() Send(sender) end)
end)

GP.On("ORA", function(payload, sender)
    if not Accept(sender) then return end
    local owner, id, flag = strsplit(SEP, payload)
    if not owner or not id or not id:match("^[%w]+$") or #id > 16 or owner == sender then return end
    if owner ~= Me() and not GP.IsGuildMember(owner) then return end
    local key, takes = TakeKey(owner, id), Takes()
    local cur = takes[key]
    if flag == "1" then
        if cur and cur.by ~= sender then return end    -- schon vergeben
        takes[key] = { by = sender, t = Now() }
        if owner == Me() then
            local name = id
            for _, o in ipairs(Mine().o) do
                if o.id == id then name = AH.ItemName(o.i) or ("#" .. o.i) end
            end
            AH.Print((L["Gildenauftrag: %s übernimmt deinen Auftrag „%s“."]):format(sender, name))
        end
    elseif flag == "0" then
        if cur and cur.by == sender then takes[key] = nil end
    end
    Changed()
end)
