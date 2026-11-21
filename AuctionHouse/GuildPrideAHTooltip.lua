-- GuildPride Auktionshaus: Preis im Item-Tooltip – als eigener Abschnitt mit Logo, damit er
-- sich von Auctionator & Co. abhebt (die schreiben auch „Auktionshaus“):
--     (Leerzeile)
--     [Logo] GuildPride
--     Auktionshaus: 30c (vor 2 Std.)
local ADDON, GP = ...
local AH = GP.AH
local L = GP.L or setmetatable({}, { __index = function(_, k) return k end })

local ASK_AFTER = 86400   -- älter als 24 Std.: beim Server nachfragen

local function Age(sec)
    if sec < 120 then return L["gerade eben"] end
    if sec < 3600 then return (L["vor %d Min."]):format(math.floor(sec / 60)) end
    if sec < 86400 then return (L["vor %d Std."]):format(math.floor(sec / 3600)) end
    return (L["vor %d Tagen"]):format(math.floor(sec / 86400))
end

-- Kann das Item überhaupt ins Auktionshaus?
function AH.Tradeable(link)
    local _, _, quality, _, _, _, _, _, _, _, sellPrice, classID, _, bindType = AH.ItemInfo(link)
    if quality == nil then return false end
    if quality == 0 or bindType == 1 or classID == 12 then return false end
    if (sellPrice or 0) == 0 and not AH.PriceFor(AH.KeyFromLink(link)) then return false end
    return true
end

function AH.TooltipLine(link, count, now, shift)
    local key = AH.KeyFromLink(link)
    local p, t, src = AH.PriceFor(key)
    if not p then return nil end
    count = count or 1
    local money = AH.Money(shift and count > 1 and p * count or p)
    if shift and count > 1 then money = money .. " (x" .. count .. ")" end
    local age = Age(math.max(0, (now or GetServerTime()) - t))
    if src == "srv" then age = L["Server, "] .. age end
    return (L["Auktionshaus: %s (%s)"]):format(money, age)
end

-- Einzelne Zeilen lassen sich in den Einstellungen abschalten (Standard: an)
local function On(k) return GuildPrideDB == nil or GuildPrideDB[k] ~= false end

-- Zweite Zeile: wie viele Spieler gemeldet haben und wohin der Preis in der Woche geht
-- (Tagestiefstwerte der letzten 7 Tage; ab 5 % Unterschied). nil, wenn nichts zu sagen ist.
function AH.TooltipExtra(link)
    local key = AH.KeyFromLink(link)
    if not key then return nil end
    local parts = {}
    local n = AH.SenderCount and AH.SenderCount(key) or 0
    if n > 0 and On("ahTipSenders") then parts[#parts + 1] = (L["von %d Spielern gemeldet"]):format(n) end
    local today, h = math.floor(GetServerTime() / 86400), {}
    for _, x in ipairs(AH.History(key)) do if x.d > today - 7 then h[#h + 1] = x end end
    if #h >= 2 and On("ahTipTrend") then
        local first, last = h[1].p, h[#h].p
        if last > first * 1.05 then parts[#parts + 1] = "|cffff6060" .. L["Woche: teurer"] .. "|r"
        elseif last < first * 0.95 then parts[#parts + 1] = "|cff40ff40" .. L["Woche: günstiger"] .. "|r"
        else parts[#parts + 1] = L["Woche: gleich"] end
    end
    if #parts == 0 then return nil end
    return "|cffaaaaaa" .. table.concat(parts, " · ") .. "|r"
end

-- Historischer Preis: aus den Tagestiefstwerten (bis 30 Tage, auch von anderen GuildPride-Spielern)
-- Durchschnitt, Tiefst- und Höchstwert. nil, solange es weniger als zwei Tage gibt.
function AH.TooltipHistory(link)
    if not On("ahTipHistory") then return nil end
    local key = AH.KeyFromLink(link)
    local h = key and AH.History(key) or {}
    if #h < 2 then return nil end
    local sum, lo, hi = 0, nil, nil
    for _, x in ipairs(h) do
        sum = sum + x.p
        lo = (not lo or x.p < lo) and x.p or lo
        hi = (not hi or x.p > hi) and x.p or hi
    end
    local avg = math.floor(sum / #h + 0.5)
    return "|cffaaaaaa" .. (L["Verlauf (%d Tage): Ø %s · Tief %s · Hoch %s"]):format(#h, AH.Money(avg), AH.Money(lo), AH.Money(hi)) .. "|r"
end

-- Händlerpreis; ist der Auktionspreis nach 5 % Gebühr niedriger, lieber beim Händler verkaufen
function AH.TooltipVendor(link, count)
    if not On("ahTipVendor") then return nil end
    local sell = tonumber((select(11, AH.ItemInfo(link))))
    if not sell or sell <= 0 then return nil end
    count = count or 1
    local text = (L["Händler: %s"]):format(AH.Money(sell * count))
    local p = AH.PriceFor(AH.KeyFromLink(link))
    if p and p * 0.95 < sell then text = text .. " · |cffff9040" .. L["lieber beim Händler verkaufen"] .. "|r" end
    return "|cffaaaaaa" .. text .. "|r"
end

-- Herstellkosten (Rezept aus einem früher geöffneten Berufsfenster, GuildPrideAHCrafting.lua)
function AH.TooltipCraft(link)
    if not On("ahTipCraft") or not AH.CraftInfo then return nil end
    local id = tonumber(tostring(link):match("item:(%d+)"))
    local v = id and AH.CraftInfo(id)
    if not v then return nil end
    local text = (L["Herstellung: Zutaten %s"]):format(AH.Money(v.cost))
        .. (v.missing > 0 and (" (+" .. (L["%d ohne Preis"]):format(v.missing) .. ")") or "")
    if v.profit then
        text = text .. " · " .. (v.profit >= 0 and "|cff40ff40" or "|cffff4040")
            .. (L["Gewinn: %s"]):format((v.profit < 0 and "-" or "") .. AH.Money(math.abs(v.profit))) .. "|r"
    end
    return "|cffaaaaaa" .. text .. "|r"
end

-- Kopfzeile des eigenen Abschnitts
function AH.TooltipHeader()
    local icon = GP.IconString and GP.IconString(14) or ""
    return icon .. " |cffd4af37GuildPride|r"
end

local function Show()
    if not AH.Opt("ahTooltip") then return false end
    return not AH.AuctionatorLoaded() or AH.Opt("ahTooltipWithAuctionator")
end

-- Fertige Tooltip-Zeile: gelb mit Preis, grau „noch kein Preis“ bei handelbaren Items, sonst nil
function AH.TooltipText(link, count, now, shift)
    local line = AH.TooltipLine(link, count, now, shift)
    if line then return "|cffffd100" .. line .. "|r" end
    if AH.Tradeable(link) then return "|cff808080" .. L["Auktionshaus: noch kein Preis bekannt"] .. "|r" end
    return nil
end

-- done[tooltip] = true (schon behandelt) oder Nummer der eigenen Zeile
local done = {}
local function LineText(link, count)
    local ok, text = pcall(AH.TooltipText, link, count, GetServerTime(), IsShiftKeyDown())
    if not ok then geterrorhandler()(text); return nil end
    return text
end
local function AddLine(tooltip, link, count)
    if not link or done[tooltip] or not Show() then return end
    if issecretvalue and issecretvalue(link) then return end
    done[tooltip] = true
    local text = LineText(link, count)
    if text then
        tooltip:AddLine(" ")
        tooltip:AddLine(AH.TooltipHeader())
        tooltip:AddLine(text)
        done[tooltip] = tooltip:NumLines()
        local ok, extra = pcall(AH.TooltipExtra, link)
        if ok and extra then tooltip:AddLine(extra) end
        for _, fn in ipairs({ AH.TooltipHistory, AH.TooltipVendor, AH.TooltipCraft }) do
            local okX, line = pcall(fn, link, count)
            if okX and line then tooltip:AddLine(line) end
        end
        tooltip:Show()
    end
    -- Kein oder alter Preis: beim Server nachfragen (gebremst in AH.Ask)
    local key = AH.KeyFromLink(link)
    local _, t = AH.PriceFor(key)
    if key and (not t or GetServerTime() - t > ASK_AFTER) and AH.Tradeable(link) then AH.Ask(key) end
end

local TOOLTIPS = { GameTooltip, ItemRefTooltip }
local function FromTooltip(tooltip) local _, link = tooltip:GetItem(); AddLine(tooltip, link) end

-- Antwort vom Server eingetroffen: offenen Tooltip mit demselben Item neu aufbauen
function AH.OnPrice(key)
    if not GameTooltip or not GameTooltip.IsShown or not GameTooltip:IsShown() then return end
    local _, link = GameTooltip:GetItem()
    if not link or AH.KeyFromLink(link) ~= key or not Show() then return end
    local idx = done[GameTooltip]
    local text = LineText(link)
    if not text then return end
    if type(idx) == "number" then
        -- vorhandene eigene Zeile ersetzen statt eine zweite anzuhängen
        local fs = _G[GameTooltip:GetName() .. "TextLeft" .. idx]
        if fs then fs:SetText(text) end
    else
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(AH.TooltipHeader())
        GameTooltip:AddLine(text)
        done[GameTooltip] = GameTooltip:NumLines()
    end
    GameTooltip:Show()
end

if GameTooltip and GameTooltip.HookScript then
    for _, tt in ipairs(TOOLTIPS) do
        if tt:HasScript("OnTooltipCleared") then tt:HookScript("OnTooltipCleared", function(self) done[self] = nil end) end
        tt:HookScript("OnHide", function(self) done[self] = nil end)
        if tt:HasScript("OnTooltipSetItem") then tt:HookScript("OnTooltipSetItem", FromTooltip) end
    end
    -- Taschen: mit Stapelgröße (Umschalt zeigt Gesamtpreis)
    if GameTooltip.SetBagItem then
        hooksecurefunc(GameTooltip, "SetBagItem", function(self, bag, slot)
            local count = 1
            if C_Container and C_Container.GetContainerItemInfo then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                count = info and info.stackCount or 1
            elseif GetContainerItemInfo then
                count = select(2, GetContainerItemInfo(bag, slot)) or 1
            end
            local _, link = self:GetItem()
            -- OnTooltipSetItem hat die Zeile evtl. schon gesetzt: dann nur mit Stapelgröße neu schreiben
            local idx = done[self]
            if type(idx) == "number" then
                local text = count > 1 and LineText(link, count)
                local fs = text and _G[self:GetName() .. "TextLeft" .. idx]
                if fs then fs:SetText(text); self:Show() end
            elseif not idx then
                AddLine(self, link, count)
            end
        end)
    end
    for _, method in ipairs({ "SetAuctionItem", "SetAuctionSellItem", "SetBuybackItem", "SetHyperlink",
        "SetInboxItem", "SetInventoryItem", "SetItemByID", "SetLootItem", "SetLootRollItem", "SetMerchantItem",
        "SetQuestItem", "SetQuestLogItem", "SetSendMailItem", "SetTradePlayerItem", "SetTradeTargetItem",
        "SetTradeSkillItem" }) do
        if GameTooltip[method] then hooksecurefunc(GameTooltip, method, FromTooltip) end
    end
    if ItemRefTooltip and ItemRefTooltip.SetHyperlink then hooksecurefunc(ItemRefTooltip, "SetHyperlink", FromTooltip) end
end
-- Neuere Clients (wie WoW Forever): Tooltip-Daten kommen über TooltipDataProcessor
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
        local _, link = tooltip:GetItem()
        AddLine(tooltip, link or (data and data.hyperlink))
    end)
end
