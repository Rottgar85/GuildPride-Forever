-- GuildPride Auktionshaus: Preis-Speicher und Preisvorschlag
-- Gespeichert in GuildPrideAHDB[Realm][Seite][Schlüssel]:
--   own  = { p, q, t }                    jüngster eigener Scan (Stückpreis in Kupfer)
--   srv  = { p, q, t, from = { [Name] = p }, seen = { [Name] = t } }   jüngster Wert vom Server
--   hist = { { d, p }, … }                Tagesminimum je Tag, höchstens 30 (eigene Scans; Tage ohne
--                                         eigenen Scan auch von anderen GuildPride-Spielern, AH.MergeHistory)
-- Seit 2.42 liegt ein Eintrag gepackt als Text da (spart Speicher und Ladezeit), zum Beispiel
--   "2|o 2s 7 1njchs|s 32 4 1njchs|f Anna=32@1njchs|h g12:3c 2:2s"   (Zahlen zur Basis 36, Zeiten ab T0,
--   Tage als Abstand zum vorigen; ein einziger Tag, der dem eigenen Preis gleicht, steht nicht extra da)
-- Einträge der ersten Fassung ("1|…", bis 2.43) bleiben lesbar.
-- Beim ersten Zugriff (AH.Entry) wird er wieder zur Tabelle, beim Ausloggen und nach dem
-- Einloggen (in Häppchen) gepackt. Tabellen aus älteren Versionen bleiben lesbar.
local ADDON, GP = ...
GP.AH = GP.AH or {}
local AH = GP.AH

local DAY = 86400
local OWN_FRESH = 3600          -- eigener Preis gilt als frisch für den Vorschlag
local SRV_MAX_AGE = 7 * DAY
local OWN_MAX_AGE = 30 * DAY
local SUFFIX_MAX_AGE = 14 * DAY   -- zufällig verzauberte Gegenstände ("ID.Suffix"): selten zweimal gleich
local MAX_FROM = 5
local MAX_HIST = 30   -- bis 2.37: 7
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

-- Seit Blizzards Hotfix vom 20.11.2026 fehlt oft der Realm-Name: dann der zuletzt bekannte
-- (GP.RealmName, GuildPride.lua); was solange unter „“ oder „?“ lag, kommt dazu
local function Realm()
    local r = GP.RealmName and GP.RealmName(true)
    if type(r) ~= "string" or r == "" then r = GetNormalizedRealmName and GetNormalizedRealmName() end
    if type(r) ~= "string" or r == "" then r = GetRealmName and GetRealmName() end
    return type(r) == "string" and r ~= "" and r or "?"
end
AH.Realm = Realm

-- Packen und Auspacken
local T0 = 1700000000
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function Num(v)
    if not v then return "-" end
    if v < 0 or v ~= math.floor(v) or v > 2 ^ 52 then return "~" .. ("%.14g"):format(v) end
    if v == 0 then return "0" end
    local out = ""
    while v > 0 do
        local r = v % 36
        out = DIGITS:sub(r + 1, r + 1) .. out
        v = (v - r) / 36
    end
    return out
end
local function Read(x)
    if x:sub(1, 1) == "~" then return tonumber(x:sub(2)) end
    return tonumber(x, 36)
end
local function Time(t) return t and Num(t - T0) or "-" end
local function ReadTime(x)
    local v = Read(x)
    return v and v + T0
end
local function OwnDay(o) return math.floor(o.t / DAY) end
local function Pack(e)
    local out = { "2" }
    local o, s, hist = e.own, e.srv, e.hist
    if o then out[#out + 1] = "o " .. Num(o.p) .. " " .. Num(o.q) .. " " .. Time(o.t) end
    if s then
        out[#out + 1] = "s " .. Num(s.p) .. " " .. Num(s.q) .. " " .. Time(s.t)
        local f = {}
        for name, p in pairs(s.from or {}) do
            f[#f + 1] = name:gsub("[|;=@%c]", "") .. "=" .. Num(p) .. "@" .. Time(s.seen and s.seen[name])
        end
        if #f > 0 then out[#out + 1] = "f " .. table.concat(f, ";") end
    end
    if hist and #hist > 0 then
        local same = o and #hist == 1 and hist[1].d == OwnDay(o) and hist[1].p == o.p
        if not same then
            local h, last = {}, 0
            for i, d in ipairs(hist) do h[i] = Num(d.d - last) .. ":" .. Num(d.p); last = d.d end
            out[#out + 1] = "h " .. table.concat(h, " ")
        end
    elseif o then
        out[#out + 1] = "n x"      -- eigener Preis ohne Tagesverlauf
    end
    return table.concat(out, "|")
end
local function Unpack(text)
    local e, v = {}, text:sub(1, 2)
    if v ~= "1|" and v ~= "2|" then return e end
    local n, t = tonumber, tonumber
    if v == "2|" then n, t = Read, ReadTime end
    local bare = v == "1|"
    for kind, body in text:gmatch("|(%a) ([^|]*)") do
        if kind == "o" or kind == "s" then
            local p, q, at = body:match("^(%S+) (%S+) (%S+)$")
            if p then p, q, at = n(p), n(q), t(at) end
            if kind == "o" and p and at then e.own = { p = p, q = q or 0, t = at }
            elseif kind == "s" and at then e.srv = { p = p, q = q or 0, t = at, from = {}, seen = {} } end
        elseif kind == "f" and e.srv then
            for name, p, seen in body:gmatch("([^;=]+)=([^;@]+)@([^;]+)") do
                e.srv.from[name], e.srv.seen[name] = n(p), t(seen)
            end
        elseif kind == "h" then
            local h, last = {}, 0
            for d, p in body:gmatch("([%w~]+):(%S+)") do
                d, p = n(d), n(p)
                if d and p then
                    if v == "2|" then d = d + last; last = d end
                    h[#h + 1] = { d = d, p = p }
                end
            end
            if #h > 0 then e.hist = h end
        elseif kind == "n" then
            bare = true
        end
    end
    if not bare and not e.hist and e.own then e.hist = { { d = OwnDay(e.own), p = e.own.p } } end
    return e
end
local function UnpackSides(realm)
    for _, items in pairs(realm) do
        if type(items) == "table" then
            for key, e in pairs(items) do if type(e) == "string" then items[key] = Unpack(e) end end
        end
    end
end

function AH.Store()
    if type(GuildPrideAHDB) ~= "table" then GuildPrideAHDB = {} end
    local r = Realm()
    GuildPrideAHDB[r] = GuildPrideAHDB[r] or {}
    if r ~= "?" and GP.MergeSaved then
        for _, old in ipairs({ "", "?" }) do
            if type(GuildPrideAHDB[old]) == "table" then
                UnpackSides(GuildPrideAHDB[r]); UnpackSides(GuildPrideAHDB[old])
                GP.MergeSaved(GuildPrideAHDB[r], GuildPrideAHDB[old])
                GuildPrideAHDB[old] = nil
            end
        end
    end
    local s = AH.Side()
    GuildPrideAHDB[r][s] = GuildPrideAHDB[r][s] or {}
    return GuildPrideAHDB[r][s]
end

local function Entry(key, create)
    local st = AH.Store()
    local e = st[key]
    if type(e) == "string" then e = Unpack(e); st[key] = e end
    if not e and create then e = {}; st[key] = e end
    return e
end
AH.Entry = Entry

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

-- Tagespreise anderer GuildPride-Spieler übernehmen: nur Tage, an denen du selbst nichts
-- gesehen hast (deine eigenen Werte überschreibt niemand). list = { { d, p }, … }.
-- Gibt die Zahl neuer Tage zurück.
function AH.MergeHistory(key, list)
    if not key or type(list) ~= "table" then return 0 end
    local today = math.floor(GetServerTime() / DAY)
    local e = Entry(key, true)
    e.hist = e.hist or {}
    local have, added = {}, 0
    for _, h in ipairs(e.hist) do have[h.d] = true end
    for _, h in ipairs(list) do
        local d, p = tonumber(h.d), tonumber(h.p)
        if d and p and p >= 1 and d <= today and d > today - MAX_HIST and not have[d] then
            e.hist[#e.hist + 1] = { d = d, p = math.floor(p) }
            have[d], added = true, added + 1
        end
    end
    table.sort(e.hist, function(a, b) return a.d < b.d end)
    while #e.hist > MAX_HIST do table.remove(e.hist, 1) end
    if #e.hist == 0 then e.hist = nil end
    return added
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
    -- Preisalarm auch mit Preisen anderer GuildPride-Spieler, wenn du nicht selbst am Auktionshaus bist
    -- (dort melden die eigenen Suchergebnisse)
    if AH.CheckAlerts and not (AH.IsOpen and AH.IsOpen()) then
        local id = tonumber(tostring(key):match("^(%d+)"))
        if id then AH.CheckAlerts({ { itemID = id, min = p } }, true) end
    end
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

-- Wie viele GuildPride-Spieler haben einen Preis gemeldet? (für den Tooltip)
function AH.SenderCount(key)
    local e = key and Entry(key)
    local n = 0
    for _ in pairs(e and e.srv and e.srv.from or {}) do n = n + 1 end
    return n
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

-- Tagespreise nach Tag `since` (nil = alle)
function AH.HistorySince(key, since)
    local out = {}
    for _, h in ipairs(AH.History(key)) do
        if not since or h.d > since then out[#out + 1] = h end
    end
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

-- Einen Eintrag aufräumen; gepackte bleiben gepackt, mit pack = true werden auch Tabellen gepackt
local function PruneEntry(items, key, now, pack)
    local e = items[key]
    local packed = type(e) == "string"
    if packed then e = Unpack(e) end
    if type(e) ~= "table" then items[key] = nil; return end
    if e.srv and now - (e.srv.t or 0) > SRV_MAX_AGE then e.srv = nil end
    local maxAge = tostring(key):find(".", 1, true) and SUFFIX_MAX_AGE or OWN_MAX_AGE
    if e.own and now - (e.own.t or 0) > maxAge then e.own = nil end
    if e.hist then
        for i = #e.hist, 1, -1 do
            if now - e.hist[i].d * DAY > maxAge then table.remove(e.hist, i) end
        end
        if #e.hist == 0 then e.hist = nil end
    end
    if not e.own and not e.srv and not e.hist then items[key] = nil
    elseif packed or pack then items[key] = Pack(e) end
end

-- Alle Einträge aller Realms und Seiten: { items, key }, …
local function AllKeys()
    local list = {}
    for _, sides in pairs(type(GuildPrideAHDB) == "table" and GuildPrideAHDB or {}) do
        if type(sides) == "table" then
            for _, items in pairs(sides) do
                if type(items) == "table" then
                    for key in pairs(items) do list[#list + 1] = { items, key } end
                end
            end
        end
    end
    return list
end

function AH.Prune(now)
    now = now or GetServerTime()
    for _, a in ipairs(AllKeys()) do PruneEntry(a[1], a[2], now) end
end

function AH.PackAll()
    for _, a in ipairs(AllKeys()) do
        local e = a[1][a[2]]
        if type(e) == "table" then a[1][a[2]] = Pack(e) end
    end
end

-- Nach dem Einloggen: aufräumen und packen, je 0,1 s nur ein Häppchen (kein Ruckler)
local BATCH = 300
function AH.PackSoon()
    local list, i, now = AllKeys(), 0, GetServerTime()
    local function Step()
        for _ = 1, BATCH do
            i = i + 1
            local a = list[i]
            if not a then return end
            if a[1][a[2]] ~= nil then PruneEntry(a[1], a[2], now, true) end
        end
        C_Timer.After(0.1, Step)
    end
    Step()
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

AH.Listen("PLAYER_LOGIN", function() C_Timer.After(15, AH.PackSoon) end)
AH.Listen("PLAYER_LOGOUT", function() AH.PackAll() end)
