-- GuildPride: ein gemeinsamer Block im Item-Tooltip
--   [Logo] GuildPride                                  AUKTIONSHAUS
--   Händler 1s · Auktionshaus 47s 50c (nach Gebühr) · +46s 50c
--   Umschalt: 3 weitere Zeilen
-- Module melden sich mit T.Add(reihenfolge, fn) an. fn(ctx) gibt Zeilen zurück:
--   { links, rechts (oder nil), more = true (nur mit Umschalt) } und darf ctx.head setzen (rechts im Kopf).
-- ctx = { id, link, tip, count (Stapel in der Tasche), bound (seelengebunden), more (Umschalt) }
local ADDON, ns = ...
local L = ns.L

local T = {}
ns.Tip = T
local parts = {}

function T.Add(order, fn)
    parts[#parts + 1] = { order = order, fn = fn, n = #parts }
    table.sort(parts, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.n < b.n
    end)
end

local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local function More()
    return (IsShiftKeyDown and IsShiftKeyDown() == true) or (type(GuildPrideDB) == "table" and GuildPrideDB.tipDetails == true)
end

-- Inhalt ohne Tooltip (auch für Tests): { head, lines = { { links, rechts } }, hidden = Anzahl }
function T.Build(ctx)
    local out, hidden = {}, 0
    for _, p in ipairs(parts) do
        local ok, lines = ns.Try(p.fn, ctx)
        for _, l in ipairs(ok and type(lines) == "table" and lines or {}) do
            if l.more and not ctx.more then hidden = hidden + 1 else out[#out + 1] = { l[1], l[2] } end
        end
    end
    return { head = ctx.head, lines = out, hidden = hidden }
end

-- Seelen- oder accountgebunden? Steht in den ersten Zeilen
function T.IsBound(tip)
    local name = tip and tip.GetName and tip:GetName()
    for i = 2, math.min(name and tip:NumLines() or 0, 6) do
        local fs = _G[name .. "TextLeft" .. i]
        local text = fs and fs.GetText and fs:GetText()
        if Secret(text) then return false end
        if text and (text == ITEM_SOULBOUND or text == ITEM_ACCOUNTBOUND or text == ITEM_BNETACCOUNTBOUND) then return true end
    end
    return false
end

-- Stapelgröße, wenn der Tooltip einen Taschenplatz zeigt
local function StackCount(tip)
    local info = tip.processingInfo
    if type(info) ~= "table" or info.getterName ~= "GetBagItem" or type(info.getterArgs) ~= "table" then return 1 end
    local ok, item = pcall(function() return C_Container.GetContainerItemInfo(info.getterArgs[1], info.getterArgs[2]) end)
    local n = ok and type(item) == "table" and item.stackCount
    if Secret(n) or type(n) ~= "number" then return 1 end
    return n
end

function T.Header()
    return (ns.IconString and ns.IconString(14) or "") .. " |cffd4af37GuildPride|r"
end

local done, shown = {}, {}
function T.Draw(tip, link)
    if done[tip] or Secret(link) or type(link) ~= "string" then return false end
    local id = tonumber(link:match("item:(%d+)"))
    if not id then return false end
    done[tip] = true
    local ctx = { id = id, link = link, tip = tip, count = StackCount(tip), bound = T.IsBound(tip), more = More() }
    local b = T.Build(ctx)
    shown[tip] = { link = link, hidden = b.hidden, more = ctx.more }
    if #b.lines == 0 and b.hidden == 0 and not b.head then return false end
    tip:AddLine(" ")
    tip:AddDoubleLine(T.Header(), b.head or " ", 1, 1, 1, 1, 1, 1)
    for _, l in ipairs(b.lines) do
        if l[2] then tip:AddDoubleLine(l[1], l[2], 1, 1, 1, 0.85, 0.85, 0.85) else tip:AddLine(l[1], 0.85, 0.85, 0.85, true) end
    end
    if b.hidden > 0 then tip:AddLine((L["Umschalt: %d weitere Zeilen"]):format(b.hidden), 0.5, 0.5, 0.5) end
    tip:Show()
    return true
end
function T.Clear(tip) done[tip], shown[tip] = nil, nil end

-- Neu aufbauen (Preis eingetroffen, Umschalt gedrückt); nur außerhalb des Kampfs
function T.Refresh(match)
    local tip = GameTooltip
    local s = tip and shown[tip]
    if not s or not tip.IsShown or not tip:IsShown() or type(tip.RefreshData) ~= "function" then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    if match and not match(s.link) then return false end
    return (pcall(tip.RefreshData, tip))
end

if GameTooltip and GameTooltip.HookScript then
    for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tip:HasScript("OnTooltipCleared") then tip:HookScript("OnTooltipCleared", T.Clear) end
        tip:HookScript("OnHide", T.Clear)
    end
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
        if tip ~= GameTooltip and tip ~= ItemRefTooltip then return end
        local ok, _, link = pcall(tip.GetItem, tip)
        if not ok then link = nil end
        if not Secret(link) and not link and type(data) == "table" then link = data.hyperlink end
        ns.Try(T.Draw, tip, link)
    end)
end

local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "MODIFIER_STATE_CHANGED")
ev:SetScript("OnEvent", function(_, _, key)
    if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
    local s = GameTooltip and shown[GameTooltip]
    -- nur wenn Umschalt an diesem Tooltip etwas ändert
    if s and (s.hidden > 0 or s.more) then T.Refresh() end
end)
