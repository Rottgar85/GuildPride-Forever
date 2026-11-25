-- GuildPride: Item-ID im Item-Tooltip (Einstellung „Item-ID im Item-Tooltip zeigen“, Standard aus)
local _, ns = ...
local L = ns.L

-- Item-ID aus einem Item-Link („item:12345:…“) oder einer Zahl
function ns.ItemIDFromLink(link)
    if type(link) == "number" then return link end
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- Fertige Zeile für den Tooltip oder nil (Schalter aus, kein Item)
function ns.ItemIDText(link)
    if not (GuildPrideDB and GuildPrideDB.showItemID) then return nil end
    local id = ns.ItemIDFromLink(link)
    if not id then return nil end
    return "|cff9d9d9d" .. (L["Item-ID: %d"]):format(id) .. "|r"
end

ns.Tip.Add(90, function(ctx)
    local text = ns.ItemIDText(ctx.link)
    return text and { { text } } or nil
end)
