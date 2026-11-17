-- GuildPride Auktionshaus: Preis im Item-Tooltip
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
    local _, _, quality, _, _, _, _, _, _, _, sellPrice, classID, _, bindType = GetItemInfo(link)
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
    local money = GetCoinTextureString(shift and count > 1 and p * count or p)
    if shift and count > 1 then money = money .. " (x" .. count .. ")" end
    local age = Age(math.max(0, (now or GetServerTime()) - t))
    if src == "srv" then age = L["Server, "] .. age end
    return (L["Auktionshaus: %s (%s)"]):format(money, age)
end

local function Show()
    if not AH.Opt("ahTooltip") then return false end
    return not AH.AuctionatorLoaded() or AH.Opt("ahTooltipWithAuctionator")
end

local done = {}
local function AddLine(tooltip, link, count)
    if not link or done[tooltip] or not Show() then return end
    if issecretvalue and issecretvalue(link) then return end
    done[tooltip] = true
    local ok, line = pcall(AH.TooltipLine, link, count, GetServerTime(), IsShiftKeyDown())
    if ok and line then
        tooltip:AddLine("|cffffd100" .. line .. "|r")
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
    if link and AH.KeyFromLink(link) == key and not done.refreshing then
        done[GameTooltip] = nil
        done.refreshing = true
        AddLine(GameTooltip, link)
        done.refreshing = nil
    end
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
            done[self] = nil
            AddLine(self, link, count)
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
