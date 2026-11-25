-- GuildPride Auktionshaus: Reiter „Aufträge“, „Scanner“ und „Meine Auktionen“ des eigenen Fensters
-- (Fenster, Suche, Kaufen, Listen und Verkaufen: GuildPrideAHModernUI.lua, vorher geladen)
local ADDON, GP = ...
local AH = GP.AH
local L = GP.L or setmetatable({}, { __index = function(_, k) return k end })
local U = AH.modernUI
local Button, Edit, Label, Money, Status, ToDiscord, Pane, Section = U.Button, U.Edit, U.Label, U.Money, U.Status, U.ToDiscord, U.Pane, U.Section

local OWN_ROWS, OWN_H = 18, 22
local own = { list = {}, offset = 0 }   -- Meine Auktionen; confirm: Abbrechen nach Bestätigung
U.own = own

---------------------------------------------------------------------
-- Gildenaufträge (GuildPrideAHOrders.lua): eigene einstellen, fremde annehmen
---------------------------------------------------------------------
local orderRows = { offset = 0, list = {} }
local ORD_ROWS, ORD_H = 18, 22

local function Age(t)
    local h = math.floor((GetServerTime() - (t or 0)) / 3600)
    if h < 1 then return L["vor < 1 Std."] end
    if h < 48 then return (L["vor %d Std."]):format(h) end
    return (L["vor %d Tag(en)"]):format(math.floor(h / 24))
end

local function ItemText(id) return AH.ItemName(id) or ("#" .. id) end

function U.RefreshOrders()
    local p = U.panel and U.panel.orders
    if not p or not p:IsShown() then return end
    orderRows.list = AH.Orders()
    local list, me = orderRows.list, GP.Me()
    orderRows.offset = math.max(0, math.min(orderRows.offset, #list - ORD_ROWS))
    p.empty:SetText(#list == 0 and L["Noch keine Aufträge in der Gilde. Stell oben einen ein – Hersteller sehen ihn hier."] or "")
    for i, row in ipairs(p.rows) do
        local o = list[orderRows.offset + i]
        row.order = o
        if not o then row:Hide() else
            row:Show()
            row.icon:SetTexture(AH.ItemIcon(o.item))
            row.name:SetText(ItemText(o.item))
            row.qty:SetText(tostring(o.qty))
            row.owner:SetText(o.mine and ("|cff66ccff" .. L["du"] .. "|r") or o.owner)
            row.age:SetText(Age(o.t))
            if o.by == me then row.status:SetText("|cff40ff40" .. L["du stellst es her"] .. "|r")
            elseif o.by then row.status:SetText("|cff40ff40" .. (L["übernommen von %s"]):format(o.by) .. "|r")
            else row.status:SetText(L["offen"]) end
            if o.mine then row.action:SetText(L["Löschen"]); row.action:Show()
            elseif o.by == me then row.action:SetText(L["Abgeben"]); row.action:Show()
            elseif not o.by then row.action:SetText(L["Annehmen"]); row.action:Show()
            else row.action:Hide() end
        end
    end
end
AH.OrdersChanged = function() if U.panel and U.panel:IsShown() and U.Mode() == "orders" then U.RefreshOrders() end end

local function OrderAction(o)
    if not o then return end
    local me = GP.Me()
    if o.mine then
        AH.RemoveOrder(o.id)
        Status(L["Auftrag gelöscht."])
    elseif o.by == me then
        AH.TakeOrder(o.owner, o.id, false)
        Status(L["Auftrag abgegeben."])
    elseif not o.by and AH.TakeOrder(o.owner, o.id, true) then
        Status((L["Du stellst %dx %s für %s her."]):format(o.qty, ItemText(o.item), o.owner))
        ToDiscord(("Auftrag angenommen: %dx %s für %s – macht %s"):format(o.qty, ItemText(o.item), o.owner, me), true)
    end
    U.RefreshOrders()
end

local function AddOrderClicked()
    local p = U.panel.orders
    local o, why = AH.AddOrder(p.itemBox:GetText(), tonumber(p.qtyBox:GetText()) or 1)
    if not o then Status(why); return end
    p.itemBox:SetText(""); p.itemBox:ClearFocus(); p.qtyBox:SetText("1")
    Status((L["Auftrag eingestellt: %dx %s."]):format(o.qty, ItemText(o.item)))
    ToDiscord(("Auftrag: %dx %s (von %s)"):format(o.qty, ItemText(o.item), GP.Me()), true)
    U.RefreshOrders()
end

function U.MakeOrdersPane()
    local p = Pane()
    Section(p, { "TOPLEFT", "TOPLEFT", 8, -6 }, { "BOTTOMRIGHT", "TOPRIGHT", -10, -36 })
    Section(p, { "TOPLEFT", "TOPLEFT", 8, -40 }, { "BOTTOMRIGHT", "BOTTOMRIGHT", -10, 8 }, 18)
    local nl = Label(p, L["Neuer Auftrag – Item-ID:"]); nl:SetPoint("TOPLEFT", 20, -16)
    p.itemBox = Edit(p, 150); p.itemBox:SetPoint("LEFT", nl, "RIGHT", 8, 0)
    local ql = Label(p, L["Menge:"]); ql:SetPoint("LEFT", p.itemBox, "RIGHT", 12, 0)
    p.qtyBox = Edit(p, 50, true); p.qtyBox:SetPoint("LEFT", ql, "RIGHT", 8, 0); p.qtyBox:SetText("1")
    p.addBtn = Button(p, L["Auftrag einstellen"], 150); p.addBtn:SetPoint("LEFT", p.qtyBox, "RIGHT", 10, 0)
    p.addBtn:SetScript("OnClick", AddOrderClicked)
    p.itemBox:SetScript("OnEnterPressed", AddOrderClicked)
    local hint = Label(p, L["Die Gilde sieht ihn hier, Hersteller können ihn annehmen. Umschalt+Klick auf ein Item trägt es ein."], "GameFontDisableSmall")
    hint:SetPoint("LEFT", p.addBtn, "RIGHT", 12, 0); hint:SetPoint("RIGHT", p, "RIGHT", -18, 0)
    local cols = { { L["Item"], 44 }, { L["Menge"], 330 }, { L["Auftraggeber"], 400 }, { L["Alter"], 540 }, { L["Status"], 630 } }
    for _, c in ipairs(cols) do
        local h = Label(p, c[1], "GameFontNormalSmall"); h:SetPoint("TOPLEFT", c[2], -43)
    end
    p.empty = Label(p, "", "GameFontDisableSmall"); p.empty:SetPoint("TOPLEFT", 20, -64)
    p.rows = {}
    for i = 1, ORD_ROWS do
        local row = CreateFrame("Button", nil, p)
        row:SetHeight(ORD_H)
        row:SetPoint("TOPLEFT", 16, -60 - (i - 1) * ORD_H); row:SetPoint("RIGHT", p, "RIGHT", -16, 0)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(ORD_H - 2, ORD_H - 2); row.icon:SetPoint("LEFT")
        row.name = Label(row, "", "GameFontHighlightSmall"); row.name:SetPoint("LEFT", 28, 0); row.name:SetWidth(280)
        row.qty = Label(row, "", "GameFontHighlightSmall"); row.qty:SetPoint("LEFT", 314, 0); row.qty:SetWidth(60)
        row.owner = Label(row, "", "GameFontHighlightSmall"); row.owner:SetPoint("LEFT", 384, 0); row.owner:SetWidth(130)
        row.age = Label(row, "", "GameFontDisableSmall"); row.age:SetPoint("LEFT", 524, 0); row.age:SetWidth(84)
        row.status = Label(row, "", "GameFontHighlightSmall"); row.status:SetPoint("LEFT", 614, 0); row.status:SetWidth(150)
        row.search = Button(row, L["Suchen"], 70); row.search:SetPoint("RIGHT", -2, 0)
        row.search:SetScript("OnClick", function() if row.order then U.SearchItem(row.order.item) end end)
        row.action = Button(row, L["Annehmen"], 90); row.action:SetPoint("RIGHT", row.search, "LEFT", -4, 0)
        row.action:SetScript("OnClick", function() OrderAction(row.order) end)
        row:SetScript("OnEnter", function()
            if not row.order then return end
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(row.order.item); GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Hide()
        p.rows[i] = row
    end
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", function(_, d)
        orderRows.offset = math.max(0, math.min(orderRows.offset - d * 3, math.max(0, #orderRows.list - ORD_ROWS)))
        U.RefreshOrders()
    end)
    if hooksecurefunc and ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", function(link)
            local id = type(link) == "string" and link:match("item:(%d+)")
            if id and p:IsShown() and p.itemBox:HasFocus() then p.itemBox:SetText(id) end
        end)
    end
    return p
end

---------------------------------------------------------------------
-- Scanner
---------------------------------------------------------------------
-- Zählen geht über den ganzen Preis-Speicher (Tausende Einträge): nur alle 10 s neu
local priceCount, priceCountAt = 0, nil
local function CountPrices()
    if priceCountAt and GetTime() - priceCountAt < 10 then return priceCount end
    local n = 0
    for _ in pairs(AH.Store()) do n = n + 1 end
    priceCount, priceCountAt = n, GetTime()
    return n
end

function U.RefreshScan()
    local p = U.panel and U.panel.scan
    if not p or not p:IsShown() then return end
    local st = AH.ScanStatus()
    if st.running then
        p.state:SetText(L["Komplett-Scan läuft …"])
    elseif st.wait > 0 then
        p.state:SetText((L["Nächster Komplett-Scan möglich in %d Min."]):format(math.ceil(st.wait / 60)))
    else
        p.state:SetText(L["Komplett-Scan möglich."])
    end
    p.go:SetEnabled(not st.running and st.wait == 0)
    p.last:SetText(st.read > 0 and (L["Letzter Komplett-Scan: %d Angebote gelesen."]):format(st.read) or "")
    p.known:SetText((L["Bekannte Preise: %d"]):format(CountPrices()))
    local s = AH.stats
    p.share:SetText(L["Preise werden mit allen GuildPride-Spielern geteilt."]
        .. "  ·  " .. (L["Gesendet: %d · Empfangen: %d · Verworfen: %d"]):format(s.sent, s.received, s.dropped))
end

function U.MakeScanPane()
    local p = Pane()
    Section(p, { "TOPLEFT", "TOPLEFT", 8, -6 }, { "BOTTOMRIGHT", "TOPRIGHT", -10, -66 })
    Section(p, { "TOPLEFT", "TOPLEFT", 8, -70 }, { "BOTTOMRIGHT", "TOPRIGHT", -10, -188 })
    local text = Label(p, L["Der Komplett-Scan liest das ganze Auktionshaus auf einmal (Blizzard erlaubt das alle 15 Minuten). Die Preise stehen danach im Item-Tooltip und beim Verkaufen; andere GuildPride-Spieler bekommen sie auf Nachfrage."], "GameFontHighlight")
    text:SetPoint("TOPLEFT", 20, -16); text:SetPoint("RIGHT", p, "RIGHT", -20, 0)
    p.go = Button(p, L["Komplett-Scan starten"], 200)
    p.go:SetPoint("TOPLEFT", 20, -80)
    p.go:SetScript("OnClick", function()
        if AH.FullScan() then
            Status(L["Auktionshaus: Komplett-Scan läuft …"])
        elseif AH.ScanWait() > 0 then
            Status((L["Nächster Komplett-Scan möglich in %d Min."]):format(math.ceil(AH.ScanWait() / 60)))
        end
        U.RefreshScan()
    end)
    p.state = Label(p, ""); p.state:SetPoint("LEFT", p.go, "RIGHT", 16, 0)
    p.last = Label(p, "", "GameFontHighlightSmall"); p.last:SetPoint("TOPLEFT", 20, -120)
    p.known = Label(p, "", "GameFontHighlightSmall"); p.known:SetPoint("TOPLEFT", 20, -142)
    p.share = Label(p, "", "GameFontHighlightSmall"); p.share:SetPoint("TOPLEFT", 20, -164)
    local tick = 0
    p:SetScript("OnUpdate", function(_, el)
        tick = tick + el
        if tick >= 1 then tick = 0; U.RefreshScan() end
    end)
    return p
end

---------------------------------------------------------------------
-- Meine Auktionen: was gerade drin ist, Gesamtwert, abbrechen
---------------------------------------------------------------------
StaticPopupDialogs["GUILDPRIDE_AH_CANCEL"] = {
    text = "%s",
    button1 = L["Abbrechen"], button2 = CANCEL,
    OnAccept = function()
        local f = own.confirm
        own.confirm = nil
        if f then f() end
    end,
    OnCancel = function() own.confirm = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function TimeLeft(sec)
    if not sec then return "" end
    if sec >= 3600 then return (L["%d Std."]):format(math.floor(sec / 3600)) end
    return (L["%d Min."]):format(math.max(1, math.floor(sec / 60)))
end

function U.RefreshOwn()
    local p = U.panel and U.panel.own
    if not p or not p:IsShown() then return end
    own.list = AH.OwnedAuctions()
    local list = own.list
    own.offset = math.max(0, math.min(own.offset, #list - OWN_ROWS))
    local sum = AH.OwnedSummary(list)
    p.total:SetText((L["Gesamtwert: %s in %d Auktionen"]):format(Money(sum.value), sum.active)
        .. (sum.sold > 0 and ("  ·  " .. (L["Verkauft (Geld kommt per Post): %s"]):format(Money(sum.soldValue))) or ""))
    p.empty:SetText(#list == 0 and L["Du hast gerade nichts im Auktionshaus."] or "")
    for i, row in ipairs(p.rows) do
        local a = list[own.offset + i]
        row.auction = a
        if not a then row:Hide() else
            row:Show()
            row.icon:SetTexture(a.icon or AH.ItemIcon(a.itemKey.itemID))
            row.name:SetText(a.link or a.name or ("#" .. a.itemKey.itemID))
            row.qty:SetText(tostring(a.qty))
            row.unit:SetText(Money(a.unit))
            row.total:SetText(Money(a.total))
            row.time:SetText(a.sold and L["verkauft"] or TimeLeft(a.timeLeft))
            row.cancel:SetShown(AH.CanCancel(a))
        end
    end
end

local function AskCancel(a)
    if not AH.CanCancel(a) then return end
    local cost = AH.CancelCost(a)
    local text = (L["Auktion abbrechen: %s (%d Stück)?"]):format(a.link or a.name or "?", a.qty)
    if cost and cost > 0 then text = text .. "\n" .. (L["Kosten: %s"]):format(Money(cost)) end
    own.confirm = function()
        if AH.CancelOwned(a) then Status(L["Auktion wird abgebrochen …"]) end
    end
    StaticPopup_Show("GUILDPRIDE_AH_CANCEL", text)
end

function U.MakeOwnPane()
    local p = Pane()
    Section(p, { "TOPLEFT", "TOPLEFT", 8, -2 }, { "BOTTOMRIGHT", "TOPRIGHT", -10, -28 })
    Section(p, { "TOPLEFT", "TOPLEFT", 8, -32 }, { "BOTTOMRIGHT", "BOTTOMRIGHT", -10, 8 }, 18)
    p.total = Label(p, "", "GameFontHighlight"); p.total:SetPoint("TOPLEFT", 20, -10)
    p.refresh = Button(p, L["Aktualisieren"], 120); p.refresh:SetPoint("TOPRIGHT", -16, -4)
    p.refresh:SetScript("OnClick", function() if AH.QueryOwned() then Status(L["Lade deine Auktionen …"]) end end)
    local cols = { { L["Item"], 44 }, { L["Menge"], 350 }, { L["Stückpreis"], 450 }, { L["Gesamt"], 620 }, { L["Restzeit"], 760 } }
    for _, c in ipairs(cols) do
        local h = Label(p, c[1], "GameFontNormalSmall"); h:SetPoint("TOPLEFT", c[2], -36)
    end
    p.empty = Label(p, "", "GameFontDisableSmall"); p.empty:SetPoint("TOPLEFT", 20, -58)
    p.rows = {}
    for i = 1, OWN_ROWS do
        local row = CreateFrame("Button", nil, p)
        row:SetHeight(OWN_H)
        row:SetPoint("TOPLEFT", 16, -54 - (i - 1) * OWN_H); row:SetPoint("RIGHT", p, "RIGHT", -16, 0)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(18, 18); row.icon:SetPoint("LEFT", 4, 0)
        row.name = Label(row, "", "GameFontHighlightSmall"); row.name:SetPoint("LEFT", 28, 0); row.name:SetWidth(300)
        row.qty = Label(row, "", "GameFontHighlightSmall"); row.qty:SetPoint("LEFT", 334, 0); row.qty:SetWidth(60)
        row.unit = Label(row, "", "GameFontHighlightSmall"); row.unit:SetPoint("LEFT", 400, 0); row.unit:SetWidth(150)
        row.unit:SetJustifyH("RIGHT")
        row.total = Label(row, "", "GameFontHighlightSmall"); row.total:SetPoint("LEFT", 560, 0); row.total:SetWidth(160)
        row.total:SetJustifyH("RIGHT")
        row.time = Label(row, "", "GameFontHighlightSmall"); row.time:SetPoint("LEFT", 744, 0); row.time:SetWidth(90)
        row.cancel = Button(row, L["Abbrechen"], 100); row.cancel:SetPoint("RIGHT", -4, 0)
        row.cancel:SetScript("OnClick", function() AskCancel(row.auction) end)
        row:SetScript("OnEnter", function()
            local a = row.auction
            if not a or not a.link then return end
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(a.link); GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Hide()
        p.rows[i] = row
    end
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", function(_, d)
        own.offset = math.max(0, math.min(own.offset - d * 3, math.max(0, #own.list - OWN_ROWS)))
        U.RefreshOwn()
    end)
    return p
end

---------------------------------------------------------------------
-- Auktions-Tipps (Knopf „Tipps“ beim Verkaufen): was gerade über dem Schnitt liegt
---------------------------------------------------------------------
local tips = { list = {}, offset = 0 }

function U.RefreshTips()
    local p = U.panel and U.panel.tips
    if not p or not p:IsShown() then return end
    tips.list = AH.SellTips()
    local list, sum = tips.list, 0
    for _, e in ipairs(list) do sum = sum + e.gain end
    tips.offset = math.max(0, math.min(tips.offset, #list - OWN_ROWS))
    p.total:SetText(#list > 0 and (L["Gerade mehr wert als üblich: %s nach Gebühr"]):format(Money(sum)) or L["Gute Zeitpunkte zum Verkaufen"])
    p.empty:SetText(#list == 0 and L["Nichts in Taschen und Bank liegt gerade 25 % über dem Schnitt. Je öfter du suchst oder scannst, desto genauer wird das."] or "")
    for i, row in ipairs(p.rows) do
        local e = list[tips.offset + i]
        row.tip = e
        if not e then row:Hide() else
            row:Show()
            row.icon:SetTexture(e.icon or AH.ItemIcon(e.itemID))
            row.name:SetText(AH.ItemName(e.link) or ("#" .. e.itemID))
            row.qty:SetText(e.bank > 0 and (L["%d + %d Bank"]):format(e.bags, e.bank) or tostring(e.bags))
            row.unit:SetText(Money(e.price))
            row.total:SetText("|cff999999" .. Money(math.floor(e.avg)) .. "|r")
            row.time:SetText("|cff40ff40+" .. e.pct .. " %|r")
        end
    end
end

function U.MakeTipsPane()
    local p = Pane()
    Section(p, { "TOPLEFT", "TOPLEFT", 8, -2 }, { "BOTTOMRIGHT", "TOPRIGHT", -10, -28 })
    Section(p, { "TOPLEFT", "TOPLEFT", 8, -32 }, { "BOTTOMRIGHT", "BOTTOMRIGHT", -10, 8 }, 18)
    p.total = Label(p, "", "GameFontHighlight"); p.total:SetPoint("TOPLEFT", 20, -10)
    p.back = Button(p, L["Zurück"], 100); p.back:SetPoint("TOPRIGHT", -16, -4)
    p.back:SetScript("OnClick", function() U.ShowMode("sell") end)
    for _, c in ipairs({ { L["Item"], 44 }, { L["Menge"], 350 }, { L["Preis"], 510 }, { L["Schnitt"], 660 }, { L["Darüber"], 770 } }) do
        local h = Label(p, c[1], "GameFontNormalSmall"); h:SetPoint("TOPLEFT", c[2], -36)
    end
    p.empty = Label(p, "", "GameFontDisableSmall"); p.empty:SetPoint("TOPLEFT", 20, -58)
    p.rows = {}
    for i = 1, OWN_ROWS do
        local row = CreateFrame("Button", nil, p)
        row:SetHeight(OWN_H)
        row:SetPoint("TOPLEFT", 16, -54 - (i - 1) * OWN_H); row:SetPoint("RIGHT", p, "RIGHT", -16, 0)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(18, 18); row.icon:SetPoint("LEFT", 4, 0)
        row.name = Label(row, "", "GameFontHighlightSmall"); row.name:SetPoint("LEFT", 28, 0); row.name:SetWidth(300)
        row.qty = Label(row, "", "GameFontHighlightSmall"); row.qty:SetPoint("LEFT", 334, 0); row.qty:SetWidth(120)
        row.unit = Label(row, "", "GameFontHighlightSmall"); row.unit:SetPoint("LEFT", 400, 0); row.unit:SetWidth(150)
        row.unit:SetJustifyH("RIGHT")
        row.total = Label(row, "", "GameFontHighlightSmall"); row.total:SetPoint("LEFT", 550, 0); row.total:SetWidth(150)
        row.total:SetJustifyH("RIGHT")
        row.time = Label(row, "", "GameFontHighlightSmall"); row.time:SetPoint("LEFT", 754, 0); row.time:SetWidth(90)
        row.search = Button(row, L["Suchen"], 80); row.search:SetPoint("RIGHT", -4, 0)
        row.search:SetScript("OnClick", function() if row.tip then U.SearchItem(row.tip.itemID) end end)
        row:SetScript("OnEnter", function()
            if not row.tip then return end
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(row.tip.itemID); GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Hide()
        p.rows[i] = row
    end
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", function(_, d)
        tips.offset = math.max(0, math.min(tips.offset - d * 3, math.max(0, #tips.list - OWN_ROWS)))
        U.RefreshTips()
    end)
    return p
end
