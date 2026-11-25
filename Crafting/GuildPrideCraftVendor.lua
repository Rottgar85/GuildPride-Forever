-- GuildPride Handwerk: Händler für den Tracker
-- Am Händler: was er von dem verkauft, was dir im Tracker fehlt, mit Preis – ein Klick kauft
-- genau die fehlende Menge (nach Rückfrage mit dem Gesamtpreis). Bündel (z. B. 5 Stück je Kauf)
-- werden passend aufgerundet.
-- Jeder Händler wird gemerkt: GuildPrideDB.craftVendor[itemID] = { p = Preis je Stück, n = Händler, z = Gebiet, t }
-- → im Tracker-Tooltip „Händler: Name (Gebiet), Preis“.
local ADDON, ns = ...
local L = ns.L
local Craft = ns.Craft

local V = {}
ns.CraftVendor = V

local function Known()
    if type(GuildPrideDB) ~= "table" then return {} end
    GuildPrideDB.craftVendor = type(GuildPrideDB.craftVendor) == "table" and GuildPrideDB.craftVendor or {}
    return GuildPrideDB.craftVendor
end
V.Known = Known

V.open = false

-- Angebot des offenen Händlers: { [itemID] = { index, price (je Stück), bundle, stock (-1 = unbegrenzt), maxStack } }
function V.Offer()
    local out = {}
    if not (V.open and GetMerchantNumItems) then return out end
    local GetInfo = (C_MerchantFrame and C_MerchantFrame.GetItemInfo)
    local ok, n = pcall(GetMerchantNumItems)
    for i = 1, (ok and tonumber(n) or 0) do
        local id = GetMerchantItemID and GetMerchantItemID(i)
        if not id and GetMerchantItemLink then
            local link = GetMerchantItemLink(i)
            id = link and tonumber(link:match("item:(%d+)"))
        end
        local price, bundle, stock
        if GetInfo then
            local ok2, info = pcall(GetInfo, i)
            if ok2 and type(info) == "table" then price, bundle, stock = info.price, info.stackCount, info.numAvailable end
        end
        if not tonumber(price) and GetMerchantItemInfo then
            local _, _, p, q, a = GetMerchantItemInfo(i)
            price, bundle, stock = p, q, a
        end
        bundle = math.max(1, tonumber(bundle) or 1)
        price = tonumber(price)
        if id and price and price > 0 then
            local max = GetMerchantItemMaxStack and tonumber(GetMerchantItemMaxStack(i)) or 20
            out[id] = { index = i, price = price / bundle, bundle = bundle, stock = tonumber(stock) or -1, maxStack = math.max(1, max or 1) }
        end
    end
    return out
end

-- Angebot merken (für den Tooltip, wo man es bekommt)
function V.Remember()
    local name = UnitName and UnitName("npc")
    local zone = GetZoneText and GetZoneText() or ""
    local now = GetServerTime()
    for id, o in pairs(V.Offer()) do
        Known()[id] = { p = math.floor(o.price + 0.5), n = name, z = zone, t = now }
    end
end

-- Was fehlt im Tracker und gibt es hier? { { id, missing, buy (Stück), price, cost, o } }, Summe
function V.Buyable()
    local out, total = {}, 0
    local T = ns.CraftTrack
    if not T then return out, 0 end
    local offer = V.Offer()
    for id, miss in pairs((T.Missing())) do
        local o = offer[id]
        if o and miss > 0 then
            local buy = math.ceil(miss / o.bundle) * o.bundle
            if o.stock >= 0 then buy = math.min(buy, o.stock * o.bundle) end
            if buy > 0 then
                local cost = math.floor(buy * o.price + 0.5)
                out[#out + 1] = { id = id, missing = miss, buy = buy, price = o.price, cost = cost, o = o }
                total = total + cost
            end
        end
    end
    table.sort(out, function(a, b) return Craft.ItemName(a.id) < Craft.ItemName(b.id) end)
    return out, total
end

-- Kaufen: je Item die fehlende Menge (Bündel: ganze Bündel; sonst in Stapeln bis maxStack)
function V.BuyAll()
    if not (V.open and BuyMerchantItem) then return 0 end
    local list, total = V.Buyable()
    if GetMoney and total > GetMoney() then
        ns.Print(L["Händler: Dafür reicht dein Gold nicht."])
        return 0
    end
    local bought = 0
    for _, b in ipairs(list) do
        local o = b.o
        if o.bundle > 1 then
            for _ = 1, math.floor(b.buy / o.bundle) do pcall(BuyMerchantItem, o.index, 1) end
        else
            local left = b.buy
            while left > 0 do
                local n = math.min(left, o.maxStack)
                pcall(BuyMerchantItem, o.index, n)
                left = left - n
            end
        end
        bought = bought + 1
    end
    return bought, total
end

-- Text für den Tooltip: wo gibt es das Item beim Händler?
function V.Where(id)
    local k = Known()[tonumber(id) or 0]
    if not k then return nil end
    local money = ns.AH and ns.AH.Money or function(c) return tostring(c) end
    return ("%s%s, %s"):format(k.n or "?", (k.z and k.z ~= "") and (" (" .. k.z .. ")") or "", money(k.p or 0))
end

StaticPopupDialogs["GUILDPRIDE_CRAFT_VENDOR_BUY"] = {
    text = "%s",
    button1 = YES or "Ja", button2 = NO or "Nein",
    OnAccept = function()
        local n, total = V.BuyAll()
        if n and n > 0 then
            local money = ns.AH and ns.AH.Money or tostring
            ns.Print((L["Händler: %d Items gekauft für %s."]):format(n, money(total or 0)))
        end
    end,
    timeout = 0, whileDead = false, hideOnEscape = true,
}

-- Rückfrage mit Liste und Gesamtpreis
function V.AskBuy()
    local list, total = V.Buyable()
    if #list == 0 then ns.Print(L["Händler: Hier gibt es nichts, was dir im Tracker fehlt."]); return end
    local money = ns.AH and ns.AH.Money or tostring
    local lines = {}
    for i, b in ipairs(list) do
        if i > 8 then lines[#lines + 1] = "…"; break end
        lines[#lines + 1] = ("%d× %s"):format(b.buy, Craft.ItemName(b.id))
    end
    StaticPopup_Show("GUILDPRIDE_CRAFT_VENDOR_BUY",
        L["Beim Händler kaufen, was im Tracker fehlt?"] .. "\n\n" .. table.concat(lines, "\n") .. "\n\n"
        .. (L["Zusammen: %s"]):format(money(total)))
end

local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE")
ev:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then
        V.open = true
        C_Timer.After(0.3, function()
            ns.Try(V.Remember)
            local T = ns.CraftTrack
            if T and not T.IsEmpty() and #V.Buyable() > 0 then T.Show() end
            if T then T.Refresh() end
        end)
    elseif event == "MERCHANT_CLOSED" then
        V.open = false
        if ns.CraftTrack then ns.CraftTrack.Refresh() end
    else
        if ns.CraftTrack then ns.CraftTrack.Refresh() end
    end
end)
