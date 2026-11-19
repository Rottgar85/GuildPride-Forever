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

-- je Tooltip nur einmal anhängen, bis er geleert oder versteckt wird
local done = {}
local function AddID(tooltip, link)
    if not tooltip or done[tooltip] then return end
    if issecretvalue and issecretvalue(link) then return end
    local text = ns.ItemIDText(link)
    if not text then return end
    done[tooltip] = true
    tooltip:AddLine(text)
    tooltip:Show()
end
ns._ItemIDAdd = AddID   -- für Tests
function ns._ItemIDClear(tooltip) done[tooltip] = nil end

local TOOLTIPS = { GameTooltip, ItemRefTooltip }
if GameTooltip and GameTooltip.HookScript then
    for _, tt in ipairs(TOOLTIPS) do
        if tt:HasScript("OnTooltipCleared") then tt:HookScript("OnTooltipCleared", function(self) done[self] = nil end) end
        tt:HookScript("OnHide", function(self) done[self] = nil end)
        if tt:HasScript("OnTooltipSetItem") then
            tt:HookScript("OnTooltipSetItem", function(self) local _, link = self:GetItem(); AddID(self, link) end)
        end
    end
end
-- Neuere Clients (wie WoW Forever): Tooltip-Daten kommen über TooltipDataProcessor
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
        local _, link = tooltip:GetItem()
        AddID(tooltip, link or (data and (data.hyperlink or data.id)))
    end)
end
