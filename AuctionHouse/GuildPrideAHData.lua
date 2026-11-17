-- GuildPride Auktionshaus: Preis-Speicher und Preisvorschlag
-- Gespeichert in GuildPrideAHDB[Realm][Seite][Schlüssel]:
--   own  = { p, q, t }                    jüngster eigener Scan (Stückpreis in Kupfer)
--   srv  = { p, q, t, from = { [Name] = p }, seen = { [Name] = t } }   jüngster Wert vom Server
--   hist = { { d, p }, … }                Tagesminimum eigener Scans, höchstens 7
local ADDON, GP = ...
GP.AH = GP.AH or {}
local AH = GP.AH

local DAY = 86400
local OWN_FRESH = 3600          -- eigener Preis gilt als frisch für den Vorschlag
local SRV_MAX_AGE = 7 * DAY
local OWN_MAX_AGE = 30 * DAY
local MAX_FROM = 5
local MAX_HIST = 7
local SPREAD = 1.25             -- Serverpreise höchstens 25 % auseinander

local side
local FACTION = { Alliance = "A", Horde = "H" }

function AH.Side()
    return side or FACTION[(UnitFactionGroup("player"))] or "N"
end
function AH.SetSide(s) side = s end

function AH.Key(itemID, suffixID)
    itemID, suffixID = tonumber(itemID), tonumber(suffixID)
    if not itemID then return nil end
    if suffixID and suffixID ~= 0 then return itemID .. "." .. suffixID end
    return tostring(itemID)
end

-- item:ID:Verzauberung:Edelstein1-4:Suffix:…
function AH.KeyFromLink(link)
    if type(link) ~= "string" then return nil end
    local body = link:match("item:([%-%d:]+)")
    if not body then return nil end
    local f, i = {}, 0
    for v in (body .. ":"):gmatch("([^:]*):") do i = i + 1; f[i] = v end
    return AH.Key(f[1], f[7])
end

local function Realm() return (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or "?" end

function AH.Store()
    if type(GuildPrideAHDB) ~= "table" then GuildPrideAHDB = {} end
    local r = Realm()
    GuildPrideAHDB[r] = GuildPrideAHDB[r] or {}
    local s = AH.Side()
    GuildPrideAHDB[r][s] = GuildPrideAHDB[r][s] or {}
    return GuildPrideAHDB[r][s]
end

local function Entry(key, create)
    local st = AH.Store()
    if not st[key] and create then st[key] = {} end
    return st[key]
end

function AH.RecordOwn(key, p, q, t)
    if not key or not p or p < 1 then return end
    local e = Entry(key, true)
    if e.own and e.own.t and e.own.t > t then return end
    -- Mehrere Ergebnisseiten derselben Suche: das Minimum zählt, Mengen addieren
    if e.own and t - e.own.t < 120 then
        e.own = { p = math.min(p, e.own.p), q = (q or 0) + (e.own.q or 0), t = t }
    else
        e.own = { p = p, q = q or 0, t = t }
    end
    local d = math.floor(t / DAY)
    e.hist = e.hist or {}
    local last = e.hist[#e.hist]
    if last and last.d == d then
        if p < last.p then last.p = p end
    elseif not last or last.d < d then
        e.hist[#e.hist + 1] = { d = d, p = p }
        while #e.hist > MAX_HIST do table.remove(e.hist, 1) end
    end
end

function AH.RecordServer(key, p, q, t, sender)
    if not key or not p or not sender then return false end
    local now = GetServerTime()
    if t > now then t = now end          -- Zeit aus der Zukunft: auf jetzt kürzen
    local e = Entry(key, true)
    local s = e.srv
    if not s then s = {}; e.srv = s end
    s.from = s.from or {}
    s.seen = s.seen or {}
    -- Jeder Absender zählt unabhängig vom Zeitstempel; „seen“ ist die Empfangszeit
    s.from[sender] = p
    s.seen[sender] = now
    -- höchstens 5 Absender: den am längsten nicht gehörten entfernen
    local count, oldest, oldestT = 0, nil, nil
    for name in pairs(s.from) do
        count = count + 1
        local st = s.seen[name] or 0
        if not oldestT or st < oldestT then oldest, oldestT = name, st end
    end
    if count > MAX_FROM and oldest and oldest ~= sender then s.from[oldest] = nil; s.seen[oldest] = nil end
    if s.t and t < s.t then return false end
    s.p, s.q, s.t = p, q or 0, t
    return true
end

-- Median der Absenderpreise: ein einzelner Ausreißer steuert den Preis nicht
local function Median(from)
    local v = {}
    for _, p in pairs(from or {}) do v[#v + 1] = p end
    if #v == 0 then return nil end
    table.sort(v)
    local m = math.floor((#v + 1) / 2)
    if #v % 2 == 1 then return v[m] end
    return math.floor((v[m] + v[m + 1]) / 2 + 0.5)
end

function AH.ServerConfirmed(key)
    local e = Entry(key)
    local s = e and e.srv
    if not s or not s.from then return nil end
    local n, sum, lo, hi = 0, 0, nil, nil
    for _, p in pairs(s.from) do
        n, sum = n + 1, sum + p
        lo = (not lo or p < lo) and p or lo
        hi = (not hi or p > hi) and p or hi
    end
    if n < 2 or hi > lo * SPREAD then return nil end
    return math.floor(sum / n + 0.5)
end

function AH.PriceFor(key)
    local e = key and Entry(key)
    if not e then return nil end
    local o, s = e.own, e.srv
    if o and (not s or o.t >= s.t) then return o.p, o.t, "own" end
    if s and s.p then return Median(s.from) or s.p, s.t, "srv" end
    return nil
end

-- Preisverlauf: Tagestiefstwerte eigener Suchen (höchstens 7 Tage), älteste zuerst
function AH.History(key)
    local e = key and Entry(key)
    local out = {}
    for _, h in ipairs(e and e.hist or {}) do out[#out + 1] = { d = h.d, p = h.p } end
    table.sort(out, function(a, b) return a.d < b.d end)
    return out
end

function AH.Suggest(key, freshForeignMin, now)
    if freshForeignMin then return math.max(1, freshForeignMin - 1), "fresh" end
    local e = key and Entry(key)
    if not e then return nil end
    now = now or GetServerTime()
    if e.own and now - e.own.t < OWN_FRESH then return e.own.p, "own" end
    local srv = AH.ServerConfirmed(key)
    if srv then return srv, "server" end
    if e.own then return e.own.p, "old" end
    local h = e.hist and e.hist[#e.hist]
    if h then return h.p, "old" end
    return nil
end

function AH.Prune(now)
    if type(GuildPrideAHDB) ~= "table" then return end
    now = now or GetServerTime()
    for _, sides in pairs(GuildPrideAHDB) do
        if type(sides) == "table" then
            for _, items in pairs(sides) do
                if type(items) == "table" then
                    for key, e in pairs(items) do
                        if e.srv and now - (e.srv.t or 0) > SRV_MAX_AGE then e.srv = nil end
                        if e.own and now - (e.own.t or 0) > OWN_MAX_AGE then e.own = nil end
                        if e.hist then
                            for i = #e.hist, 1, -1 do
                                if now - e.hist[i].d * DAY > OWN_MAX_AGE then table.remove(e.hist, i) end
                            end
                            if #e.hist == 0 then e.hist = nil end
                        end
                        if not e.own and not e.srv and not e.hist then items[key] = nil end
                    end
                end
            end
        end
    end
end

-- Kleiner Ereignis-Verteiler für den Auktionshaus-Teil
local handlers = {}
AH.frame = CreateFrame("Frame")
AH.frame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end
end)
-- Unbekannte Events (altes vs. neues Auktionshaus je nach Client) still überspringen
function AH.Listen(event, fn)
    if not handlers[event] then
        if not pcall(AH.frame.RegisterEvent, AH.frame, event) then return false end
        handlers[event] = {}
    end
    table.insert(handlers[event], fn)
    return true
end

-- Item-Daten: neuere Clients (WoW Forever) haben nur noch C_Item.*, ältere die globalen Funktionen
function AH.ItemInfo(item)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if f and item then return f(item) end
end
function AH.ItemInfoInstant(item)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if f and item then return f(item) end
end
function AH.ItemIcon(item)
    if not item then return nil end
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(item) end
    return GetItemIcon and GetItemIcon(item) or nil
end
function AH.ItemName(item) return (AH.ItemInfo(item)) end

-- Geldbetrag mit Münz-Symbolen. WoW Forever hat kein globales GetCoinTextureString mehr.
local COIN = "|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"
function AH.Money(copper)
    copper = math.max(0, math.floor(tonumber(copper) or 0))
    local fns = { C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString, GetCoinTextureString, GetMoneyString }
    for i = 1, 3 do
        local f = fns[i]
        if type(f) == "function" then
            local ok, s = pcall(f, copper)
            if ok and type(s) == "string" then return s end
        end
    end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local out = {}
    if g > 0 then out[#out + 1] = g .. COIN:format("Gold") end
    if s > 0 then out[#out + 1] = s .. COIN:format("Silver") end
    if c > 0 or #out == 0 then out[#out + 1] = c .. COIN:format("Copper") end
    return table.concat(out, " ")
end

-- Neues Auktionshaus (C_AuctionHouse, wie Retail) – WoW Forever nutzt dieses
function AH.IsModern()
    if IsUsingLegacyAuctionClient and IsUsingLegacyAuctionClient() then return false end
    return C_AuctionHouse ~= nil and C_AuctionHouse.SendBrowseQuery ~= nil
end

-- Preise teilen ist Pflicht für alle (kein Schalter mehr in den Einstellungen)
local FORCED = { ahShare = true }
function AH.Opt(k)
    if FORCED[k] then return true end
    return GuildPrideDB and GuildPrideDB[k]
end
function AH.Print(msg) if GP.Print then GP.Print(msg) else print("GuildPride: " .. tostring(msg)) end end

AH.Listen("PLAYER_LOGIN", function() AH.Prune() end)
