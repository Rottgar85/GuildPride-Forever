-- GuildPride: Jubiläen in der Gilde (30 Tage, 100 Tage, ½ Jahr, jedes Jahr)
-- Aus dem Mitglieds-Verlauf (GuildPrideHistory.lua), nur mit genauem Beitrittsdatum, nur der
-- Main eines Spielers. Steht in der Übersicht unter „Diese Woche“; nichts wird verschickt.
local ADDON, ns = ...
local L = ns.L

local J = {}
ns.Jubilee = J
local DAY = 86400
local FIXED = { 30, 100, 182 }

-- Nächstes Jubiläum (in Tagen seit dem Beitritt) innerhalb der nächsten `within` Tage, sonst nil
function J.Next(first, now, within)
    local function Hit(days)
        local at = first + days * DAY
        return at > now - DAY and at <= now + within * DAY
    end
    for _, d in ipairs(FIXED) do if Hit(d) then return d end end
    local years = math.floor((now - first) / DAY / 365)
    for y = math.max(1, years), years + 1 do if Hit(y * 365) then return y * 365 end end
    return nil
end

function J.Label(days)
    if days % 365 == 0 then
        local y = days / 365
        return y == 1 and L["1 Jahr"] or (L["%d Jahre"]):format(y)
    end
    if days == 182 then return L["ein halbes Jahr"] end
    return (L["%d Tage"]):format(days)
end

function J.Upcoming(within)
    local now, list = GetServerTime(), {}
    for name, e in pairs(ns.GuildTable("history")) do
        if type(e) == "table" and e.first and not e.approx and not e.left and ns.IsGuildMember(name)
            and (not ns.MainOf or (ns.MainOf(name) or name) == name) then
            local days = J.Next(e.first, now, within or 7)
            if days then list[#list + 1] = { name = name, days = days, at = e.first + days * DAY } end
        end
    end
    table.sort(list, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.name < b.name
    end)
    return list
end

-- Zeile für die Übersicht, nil wenn nichts ansteht
function J.Text()
    local list = J.Upcoming(7)
    if #list == 0 then return nil end
    local parts = {}
    for i, e in ipairs(list) do
        if i > 4 then parts[#parts + 1] = (L["und %d weitere"]):format(#list - 4); break end
        parts[#parts + 1] = ("|cfff0c88c%s|r %s (%s)"):format(Ambiguate(e.name, "guild"), J.Label(e.days), ns.FormatDay(e.at))
    end
    return L["Jubiläen: "] .. table.concat(parts, " · ")
end
