-- GuildPride: „Heute“ auf der Übersicht – was gerade ansteht
-- Events der nächsten 24 Stunden, fertige Abklingzeiten, Post, eigene Auktionen, offene Aufträge;
-- für Offiziere offene Fragen und Bewerbungen. Nur Auswertung eigener Daten, nichts wird gesendet.
-- Gespeichert: GuildPrideDB.ahOwned[Charakter] = { ends = { [auctionID] = Ende }, sold = Anzahl }
local ADDON, ns = ...
local L = ns.L

local T = {}
ns.Today = T
local DAY = 86400

---------------------------------------------------------------------
-- Eigene Auktionen merken
---------------------------------------------------------------------
local function Store()
    if type(GuildPrideDB) ~= "table" then return {} end
    if type(GuildPrideDB.ahOwned) ~= "table" then GuildPrideDB.ahOwned = {} end
    return GuildPrideDB.ahOwned
end
local function Mine()
    local s, me = Store(), ns.Me()
    if type(s[me]) ~= "table" then s[me] = { ends = {}, sold = 0 } end
    return s[me]
end

-- Liste aus „Meine Auktionen“ (AH.OwnedAuctions)
function T.NoteOwned(list, now)
    local e = Mine()
    e.ends, e.sold = {}, 0
    for _, a in ipairs(list or {}) do
        if a.sold then e.sold = e.sold + 1
        elseif a.auctionID and type(a.timeLeft) == "number" then e.ends[a.auctionID] = math.floor(now + a.timeLeft) end
    end
end

function T.Sold(auctionID)
    local e = Mine()
    if auctionID then e.ends[auctionID] = nil end
    e.sold = (e.sold or 0) + 1
end

-- Am Briefkasten: Verkauftes und Abgelaufenes ist abgeholt
function T.MailOpened(now)
    local e = Mine()
    e.sold = 0
    for id, t in pairs(e.ends) do if t <= now then e.ends[id] = nil end end
end

-- Alle Charaktere zusammen: { soon (laufen in 24 Stunden ab), over (abgelaufen), sold }
function T.Auctions(now)
    local out = { soon = 0, over = 0, sold = 0 }
    for _, e in pairs(Store()) do
        if type(e) == "table" then
            out.sold = out.sold + (tonumber(e.sold) or 0)
            for _, t in pairs(type(e.ends) == "table" and e.ends or {}) do
                -- abgelaufene Post verfällt nach 30 Tagen
                if t <= now then if t > now - 30 * DAY then out.over = out.over + 1 end
                elseif t <= now + DAY then out.soon = out.soon + 1 end
            end
        end
    end
    return out
end

---------------------------------------------------------------------
-- Zeilen
---------------------------------------------------------------------
local ANSWER = { yes = "|cff40ff40" .. L["du bist dabei"] .. "|r", maybe = "|cffffd100" .. L["du hast „vielleicht“ gesagt"] .. "|r",
                 no = "|cff999999" .. L["du hast abgesagt"] .. "|r" }

local function Events(add, now)
    if ns.RollEvents then ns.RollEvents() end
    local list = {}
    for _, e in pairs(ns.GuildTable("events")) do
        if type(e) == "table" and e.title and not e.deleted and e.t and e.t > now and e.t <= now + DAY then list[#list + 1] = e end
    end
    table.sort(list, function(a, b) return a.t < b.t end)
    for i, e in ipairs(list) do
        if i > 3 then break end
        local s = type(e.signups) == "table" and e.signups[ns.Me()]
        local day = date("%d.%m.", e.t) == date("%d.%m.", now) and L["heute"] or L["morgen"]
        add(("|cfff0c88c%s|r %s %s – %s"):format(ns.Clean(e.title, 60), day, date("%H:%M", e.t),
            s and ANSWER[s.s] or ("|cffff9040" .. L["noch keine Antwort von dir"] .. "|r")))
    end
end

local function Cooldowns(add)
    local M = ns.CraftMini
    if not (M and M.CooldownList) then return end
    local parts = {}
    for _, c in ipairs(M.CooldownList()) do
        if c.ready and #parts < 4 then
            parts[#parts + 1] = ns.Craft and ns.Craft.Me and c.name == ns.Craft.Me() and c.what or ("%s (%s)"):format(c.what, Ambiguate(c.name, "guild"))
        end
    end
    if #parts > 0 then add(L["Wieder bereit: "] .. table.concat(parts, " · ")) end
end

local function Mail(add)
    if HasNewMail and HasNewMail() == true then add(L["Neue Post im Briefkasten"]) end
end

local function Auctions(add, now)
    local a, parts = T.Auctions(now), {}
    if a.sold > 0 then parts[#parts + 1] = "|cff40ff40" .. (L["%d verkauft"]):format(a.sold) .. "|r" end
    if a.soon > 0 then parts[#parts + 1] = (L["%d laufen in 24 Stunden ab"]):format(a.soon) end
    if a.over > 0 then parts[#parts + 1] = "|cffff9040" .. (L["%d abgelaufen"]):format(a.over) .. "|r" end
    if #parts > 0 then add(L["Deine Auktionen: "] .. table.concat(parts, " · ")) end
end

local function Orders(add)
    local n = 0
    for _, o in ipairs(ns.AH and ns.AH.Orders and ns.AH.Orders() or {}) do if not o.mine and not o.by then n = n + 1 end end
    if n > 0 then add((L["Offene Gildenaufträge: %d (Auktionshaus › Gildenaufträge)"]):format(n)) end
end

local function Officers(add)
    if not (ns.IsOfficer and ns.IsOfficer()) then return end
    local q = ns.Questions and ns.Questions.OpenCount and ns.Questions.OpenCount() or 0
    if q > 0 then add((L["Offene Fragen an die Offiziere: %d"]):format(q)) end
    local n = 0
    for _, app in pairs(ns.GuildTable("apps")) do if type(app) == "table" and app.status == "new" then n = n + 1 end end
    if n > 0 then add((L["Neue Bewerbungen: %d"]):format(n)) end
end

function T.Lines()
    local out, now = {}, GetServerTime()
    local function add(text) out[#out + 1] = text end
    for _, fn in ipairs({ Events, Auctions, Mail, Cooldowns, Orders, Officers }) do ns.Try(fn, add, now) end
    return out
end

function T.Text()
    local lines = T.Lines()
    if #lines == 0 then return "|cff888888" .. L["Heute steht nichts an."] .. "|r", 1 end
    while #lines > 6 do table.remove(lines) end   -- mehr passt nicht auf die Seite
    return table.concat(lines, "\n"), #lines
end

---------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------
local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "OWNED_AUCTIONS_UPDATED", "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", "MAIL_SHOW", "UPDATE_PENDING_MAIL")
ev:SetScript("OnEvent", function(_, event, kind, _, auctionID)
    if type(GuildPrideDB) ~= "table" then return end
    if event == "OWNED_AUCTIONS_UPDATED" then
        if ns.AH and ns.AH.OwnedAuctions then
            local ok, list = ns.Try(ns.AH.OwnedAuctions)
            if ok then T.NoteOwned(list, GetServerTime()) end
        end
    elseif event == "MAIL_SHOW" then T.MailOpened(GetServerTime())
    elseif event == "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION" then
        local N = Enum and Enum.AuctionHouseNotification
        if N and N.AuctionSold ~= nil and kind == N.AuctionSold then T.Sold(auctionID) end
    end
    if ns.RefreshUI then ns.RefreshUI() end
end)
