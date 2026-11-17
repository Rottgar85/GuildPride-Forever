-- GuildPride Auktionshaus: eigenes Fenster „GuildPride – Auktionshaus“ für das neue
-- Auktionshaus (C_AuctionHouse, WoW Forever) mit Suchen/Kaufen, Verkaufen, Meine Auktionen und Scanner.
-- Es ersetzt Blizzards Auktionshaus-Fenster: Blizzards Fenster wird unsichtbar (nicht
-- geschlossen – das würde die Sitzung am Auktionator beenden). Knopf „Blizzard-Auktionshaus“
-- schaltet zurück, Knopf „GuildPride“ in Blizzards Fenster wieder hierher.
-- Gekauft wird in der eigenen Kaufansicht (Klick auf eine Zeile unter „Suchen“).
local ADDON, GP = ...
local AH = GP.AH
local L = GP.L or setmetatable({}, { __index = function(_, k) return k end })

local ROWS, ROW_H = 16, 22
local BAG_ROWS, BAG_H = 18, 20
local OFFER_ROWS, OFFER_H = 10, 18
local WIN_W, WIN_H = 1000, 580
local CAT_W, CAT_ROWS, CAT_H = 190, 22, 20
local DURATIONS = { { 1, "12" }, { 2, "24" }, { 3, "48" } }   -- Blizzard-Dauer-Index → Stunden

local button, panel, setupError
local mode = "search"            -- "search" | "sell" | "own" | "scan"
local OWN_ROWS, OWN_H = 18, 22
local own = { list = {}, offset = 0 }   -- Meine Auktionen; confirm: Abbrechen nach Bestätigung
local rows, offset = {}, 0
local catSel, catExpanded, catOffset, catRows = nil, {}, 0, {}
local buy = {}                   -- entry, info, offers, selected, loaded, pending, confirm
local DETAIL_ROWS, DETAIL_H = 15, 20
local CloseDetail                -- weiter unten: Kaufansicht schließen
local bagItems, bagOffset = {}, 0
local sell = { duration = 2 }    -- info, manual, setting, pending
local ShowBlizzard               -- weiter unten: zu Blizzards Fenster wechseln

local function Skin(b) if GP.SkinButton then GP.SkinButton(b) end return b end
local function EditSkin(e) if GP.SkinEditBox then GP.SkinEditBox(e) end return e end
local function Money(c) return AH.Money(c) end

local function Button(parent, text, w)
    local b = Skin(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
    b:SetSize(w or 100, 22); b:SetText(text)
    return b
end

local function Edit(parent, w, numeric)
    local e = EditSkin(CreateFrame("EditBox", nil, parent, "InputBoxTemplate"))
    e:SetSize(w, 20); e:SetAutoFocus(false)
    if numeric then e:SetNumeric(true) end
    e:SetScript("OnEscapePressed", e.ClearFocus)
    return e
end

local function Label(parent, text, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    fs:SetText(text or "")
    fs:SetJustifyH("LEFT")
    return fs
end

local function Status(text) if panel then panel.status:SetText(text or "") end end

-- Bereich unter Titel und Umschalt-Knöpfen
local function Pane()
    local p = CreateFrame("Frame", nil, panel.content)
    p:SetPoint("TOPLEFT", 0, -30)
    p:SetPoint("BOTTOMRIGHT", 0, 0)
    return p
end

---------------------------------------------------------------------
-- Suchen
---------------------------------------------------------------------
local function RefreshList()
    local p = panel and panel.search
    if not p or not p:IsShown() then return end
    rows = AH.BrowseRows()
    offset = math.max(0, math.min(offset, #rows - ROWS))
    for i, row in ipairs(p.rows) do
        local e = rows[offset + i]
        row.entry = e
        if not e then row:Hide() else
            row:Show()
            row.icon:SetTexture(e.icon or AH.ItemIcon(e.itemKey.itemID))
            local color = e.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[e.quality]
            row.name:SetText(e.name or ("#" .. e.itemKey.itemID))
            if color then row.name:SetTextColor(color.r, color.g, color.b) else row.name:SetTextColor(1, 1, 1) end
            row.price:SetText(e.min and Money(e.min) or "-")
            local info = (L["%d Stück"]):format(e.qty)
            if e.mine then info = info .. " · " .. L["eigenes Angebot"] end
            local p2, _, src = AH.PriceFor(e.key)
            if src == "srv" and p2 then info = info .. " · " .. L["Server"] .. " " .. Money(p2) end
            row.info:SetText(info)
        end
    end
end

local function StartSearch(text)
    offset = 0
    if CloseDetail then CloseDetail() end
    if AH.ModernBrowse(text, catSel and catSel.filters) then Status(L["Suche läuft …"]) end
end

-- Kategorien links wie bei Blizzard: Klick wählt und sucht, „+“ klappt Unterkategorien auf
local function RefreshCategories()
    local p = panel and panel.search
    if not p or not p.catButtons then return end
    catRows = AH.CategoryRows(catExpanded)
    table.insert(catRows, 1, { name = L["Alle Kategorien"], depth = 0 })
    catOffset = math.max(0, math.min(catOffset, #catRows - CAT_ROWS))
    for i, b in ipairs(p.catButtons) do
        local r = catRows[catOffset + i]
        b.row = r
        if not r then b:Hide() else
            b:Show()
            local mark = r.hasSub and (catExpanded[r.cat] and "– " or "+ ") or "   "
            b.text:SetText(mark .. r.name)
            b.text:SetPoint("LEFT", 6 + r.depth * 12, 0)
            local on = r.cat == catSel
            b.sel:SetShown(on)
            if r.depth == 0 then b.text:SetFontObject(on and "GameFontHighlight" or "GameFontNormal")
            else b.text:SetFontObject(on and "GameFontHighlightSmall" or "GameFontNormalSmall") end
        end
    end
end

local function MakeCategoryList(p, box)
    local side = CreateFrame("Frame", nil, p)
    side:SetPoint("TOPLEFT", 14, -44); side:SetSize(CAT_W - 10, CAT_ROWS * CAT_H)
    p.catButtons = {}
    for i = 1, CAT_ROWS do
        local b = CreateFrame("Button", nil, side)
        b:SetSize(CAT_W - 10, CAT_H)
        b:SetPoint("TOPLEFT", 0, -(i - 1) * CAT_H)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b.sel = b:CreateTexture(nil, "BACKGROUND"); b.sel:SetAllPoints(); b.sel:SetColorTexture(1, 0.82, 0, 0.18); b.sel:Hide()
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal"); b.text:SetJustifyH("LEFT")
        b.text:SetPoint("RIGHT", -4, 0)
        b:SetScript("OnClick", function()
            local r = b.row
            if not r then return end
            if r.hasSub then catExpanded[r.cat] = not catExpanded[r.cat] or nil end
            catSel = r.cat
            RefreshCategories()
            StartSearch(box:GetText())
        end)
        p.catButtons[i] = b
    end
    side:EnableMouseWheel(true)
    side:SetScript("OnMouseWheel", function(_, d)
        catOffset = math.max(0, math.min(catOffset - d * 3, math.max(0, #catRows - CAT_ROWS)))
        RefreshCategories()
    end)
end

-- Zeile anklicken: Blizzards Kaufansicht für dieses Item öffnen.
-- Die gemerkte Wahl bleibt GuildPride; der Knopf „GuildPride“ führt zurück.
---------------------------------------------------------------------
-- Kaufansicht: Angebote eines Items, Menge wählen, kaufen
---------------------------------------------------------------------
StaticPopupDialogs["GUILDPRIDE_AH_BUY"] = {
    text = "%s",
    button1 = L["Kaufen"], button2 = CANCEL,
    OnAccept = function()
        local f = buy.confirm
        buy.confirm = nil
        if f then f() end
    end,
    OnCancel = function() buy.confirm, buy.pending = nil, nil end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function AskBuy(text, fn)
    buy.confirm = fn
    StaticPopup_Show("GUILDPRIDE_AH_BUY", text)
end

local function DetailQty()
    return tonumber(panel.search.qty:GetText()) or 0
end

local function RefreshDetail()
    local p = panel and panel.search
    if not p or not p.detail:IsShown() or not buy.info then return end
    local info = buy.info
    buy.offers = AH.CurrentOffers(info)
    local list = buy.offers
    p.empty:SetText(#list == 0 and (buy.loaded and L["Keine Angebote im Auktionshaus."] or L["Angebote werden geladen …"]) or "")
    for i, row in ipairs(p.detailRows) do
        local o = list[i]
        row.offer = o
        if not o then row:Hide() else
            row:Show()
            row.price:SetText(Money(o.unit))
            row.qty:SetText((L["%d Stück"]):format(o.qty))
            row.mine:SetText(o.mine and L["eigenes"] or "")
            row.sel:SetShown(not info.commodity and buy.selected == o)
        end
    end
    p.more:SetText(#list > DETAIL_ROWS and (L["+%d weitere"]):format(#list - DETAIL_ROWS) or "")
    p.qtyRow:SetShown(info.commodity == true)
    if info.commodity then
        local total, have = AH.CommodityCost(list, DetailQty())
        p.total:SetText(have > 0 and (L["Gesamt: %s"]):format(Money(total))
            .. (have < DetailQty() and ("  " .. (L["(nur %d verfügbar)"]):format(have)) or "") or "")
        p.buyBtn:SetEnabled(have > 0 and DetailQty() > 0)
    else
        local o = buy.selected
        p.total:SetText(o and (L["Gesamt: %s"]):format(Money(o.buyout)) or L["Angebot in der Liste wählen."])
        p.buyBtn:SetEnabled(o ~= nil and not o.mine)
    end
end

local function RequestOffers()
    buy.loaded = nil
    if buy.info and buy.info.itemKey and AH.IsModern() then
        C_AuctionHouse.SendSearchQuery(buy.info.itemKey, {}, true)
    end
end

local function OpenDetail(row)
    local e = row.entry
    if not e then return end
    local p = panel.search
    local commodity = e.commodity
    if commodity == nil and C_AuctionHouse.GetItemKeyInfo then
        local ki = C_AuctionHouse.GetItemKeyInfo(e.itemKey)
        commodity = ki and ki.isCommodity
    end
    buy.entry, buy.selected = e, nil
    buy.info = { itemID = e.itemKey.itemID, itemKey = e.itemKey, key = e.key, commodity = commodity }
    p.dIcon:SetTexture(e.icon or AH.ItemIcon(e.itemKey.itemID))
    p.dName:SetText(e.name or ("#" .. e.itemKey.itemID))
    local color = e.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[e.quality]
    if color then p.dName:SetTextColor(color.r, color.g, color.b) else p.dName:SetTextColor(1, 1, 1) end
    p.qty:SetText("1")
    p.listFrame:Hide()
    p.detail:Show()
    RequestOffers()
    RefreshDetail()
end

CloseDetail = function()
    local p = panel and panel.search
    if not p or not p.detail then return end
    buy.info, buy.selected, buy.pending = nil, nil, nil
    p.detail:Hide()
    p.listFrame:Show()
end

local function Buy()
    local info = buy.info
    if not info then return end
    if info.commodity then
        local qty = DetailQty()
        if AH.BuyCommodity(info.itemID, qty) then
            buy.pending = { itemID = info.itemID, qty = qty }
            Status(L["Preis wird geprüft …"])
        end
    else
        local o = buy.selected
        if not o or o.mine then return end
        AskBuy((L["%s für %s kaufen?"]):format(o.link or panel.search.dName:GetText(), Money(o.buyout)), function()
            if AH.BuyItem(o) then Status(L["Kauf läuft …"]) end
        end)
    end
end

-- Blizzard hat den genauen Preis der Ware ermittelt: jetzt nachfragen
local function OnCommodityPrice(unit, total)
    local p = buy.pending
    if not p then return end
    AskBuy((L["%d Stück für %s kaufen (%s je Stück)?"]):format(p.qty, Money(total), Money(unit)), function()
        buy.pending = nil
        if AH.ConfirmCommodity(p.itemID, p.qty) then Status(L["Kauf läuft …"]) end
    end)
end

local function OnBought()
    Status(L["Gekauft."])
    buy.selected = nil
    RequestOffers()
    RefreshDetail()
end

local function MakeDetail(p)
    local d = CreateFrame("Frame", nil, p)
    d:SetPoint("TOPLEFT", CAT_W + 10, -40); d:SetPoint("BOTTOMRIGHT", -12, 8)
    d:Hide()
    p.detail = d
    p.back = Button(d, L["‹ Zurück zur Liste"], 150); p.back:SetPoint("TOPLEFT", 6, 0)
    p.back:SetScript("OnClick", function() CloseDetail() end)
    p.dIcon = d:CreateTexture(nil, "ARTWORK"); p.dIcon:SetSize(32, 32); p.dIcon:SetPoint("TOPLEFT", 8, -30)
    p.dName = Label(d, "", "GameFontNormalLarge"); p.dName:SetPoint("LEFT", p.dIcon, "RIGHT", 10, 0)
    local hp = Label(d, L["Stückpreis"], "GameFontNormalSmall"); hp:SetPoint("TOPLEFT", 60, -72)
    local hq = Label(d, L["Menge"], "GameFontNormalSmall"); hq:SetPoint("TOPLEFT", 186, -72)
    p.empty = Label(d, "", "GameFontDisableSmall"); p.empty:SetPoint("TOPLEFT", 12, -92)
    p.detailRows = {}
    for i = 1, DETAIL_ROWS do
        local row = CreateFrame("Button", nil, d)
        row:SetSize(420, DETAIL_H)
        row:SetPoint("TOPLEFT", 6, -88 - (i - 1) * DETAIL_H)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.sel = row:CreateTexture(nil, "BACKGROUND"); row.sel:SetAllPoints(); row.sel:SetColorTexture(1, 0.82, 0, 0.18); row.sel:Hide()
        row.price = Label(row, "", "GameFontHighlightSmall"); row.price:SetPoint("LEFT", 4, 0); row.price:SetWidth(150)
        row.price:SetJustifyH("RIGHT")
        row.qty = Label(row, "", "GameFontHighlightSmall"); row.qty:SetPoint("LEFT", 180, 0); row.qty:SetWidth(110)
        row.mine = Label(row, "", "GameFontDisableSmall"); row.mine:SetPoint("LEFT", 300, 0)
        row:SetScript("OnClick", function()
            local o = row.offer
            if not o or not buy.info then return end
            if buy.info.commodity then
                -- wie bei Blizzard: Menge bis einschließlich dieser Zeile
                local n = 0
                for j = 1, i do
                    local x = buy.offers[j]
                    if x and not x.mine then n = n + x.qty end
                end
                panel.search.qty:SetText(tostring(math.max(1, n)))
            else
                buy.selected = o
            end
            RefreshDetail()
        end)
        row:SetScript("OnEnter", function()
            local o = row.offer
            if not o or not o.link then return end
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(o.link); GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Hide()
        p.detailRows[i] = row
    end
    p.more = Label(d, "", "GameFontDisableSmall"); p.more:SetPoint("TOPLEFT", 12, -92 - DETAIL_ROWS * DETAIL_H)

    local y = -100 - DETAIL_ROWS * DETAIL_H - 14
    p.qtyRow = CreateFrame("Frame", nil, d)
    p.qtyRow:SetSize(200, 24); p.qtyRow:SetPoint("TOPLEFT", 8, y)
    local ql = Label(p.qtyRow, L["Menge"]); ql:SetPoint("LEFT")
    p.qty = Edit(p.qtyRow, 60, true); p.qty:SetPoint("LEFT", 70, 0)
    p.qty:SetScript("OnTextChanged", function() RefreshDetail() end)
    p.total = Label(d, "", "GameFontHighlight"); p.total:SetPoint("TOPLEFT", 210, y - 5)
    p.buyBtn = Button(d, L["Kaufen"], 140); p.buyBtn:SetPoint("TOPLEFT", 8, y - 32)
    p.buyBtn:SetScript("OnClick", Buy)
end

local function MakeSearchPane()
    local p = Pane()
    local box = Edit(p, 260)
    box:SetPoint("TOPLEFT", 20, -14)
    local go = Button(p, L["Suchen"], 100)
    go:SetPoint("LEFT", box, "RIGHT", 8, 0)
    go:SetScript("OnClick", function() box:ClearFocus(); StartSearch(box:GetText()) end)
    box:SetScript("OnEnterPressed", function() box:ClearFocus(); StartSearch(box:GetText()) end)
    local hint = Label(p, L["Klick auf eine Zeile zeigt die Angebote zum Kaufen."], "GameFontDisableSmall")
    hint:SetPoint("LEFT", go, "RIGHT", 12, 0)

    MakeCategoryList(p, box)
    p.listFrame = CreateFrame("Frame", nil, p)
    p.listFrame:SetAllPoints()
    local head = Label(p.listFrame, L["Item"], "GameFontNormalSmall"); head:SetPoint("TOPLEFT", CAT_W + 44, -42)
    local headP = Label(p.listFrame, L["Stückpreis"], "GameFontNormalSmall"); headP:SetPoint("TOPLEFT", CAT_W + 334, -42)
    p.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, p.listFrame)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", CAT_W + 16, -58 - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", p, "RIGHT", -16, 0)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(ROW_H - 2, ROW_H - 2); row.icon:SetPoint("LEFT")
        row.name = Label(row, "", "GameFontHighlightSmall"); row.name:SetPoint("LEFT", 28, 0); row.name:SetWidth(260)
        row.price = Label(row, "", "GameFontHighlightSmall"); row.price:SetPoint("LEFT", 290, 0); row.price:SetWidth(150)
        row.price:SetJustifyH("RIGHT")
        row.info = Label(row, "", "GameFontDisableSmall"); row.info:SetPoint("LEFT", 460, 0); row.info:SetWidth(300)
        row:SetScript("OnClick", OpenDetail)
        row:SetScript("OnEnter", function()
            local e = row.entry
            if not e then return end
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            local k = e.itemKey
            if GameTooltip.SetItemKey then GameTooltip:SetItemKey(k.itemID, k.itemLevel or 0, k.itemSuffix or 0)
            else GameTooltip:SetItemByID(k.itemID) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p.rows[i] = row
    end
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", function(_, d)
        offset = math.max(0, math.min(offset - d * 3, math.max(0, #rows - ROWS)))
        RefreshList()
    end)
    MakeDetail(p)
    return p
end

---------------------------------------------------------------------
-- Verkaufen
---------------------------------------------------------------------
local function TagText(tag, key)
    if tag == "own" then return L["eigener Preis"] end
    if tag == "server" then return L["Serverpreis"] end
    if tag == "old" then
        local _, t = AH.PriceFor(key)
        local h = t and math.floor((GetServerTime() - t) / 3600) or 0
        return h >= 24 and (L["alt (vor %d Tagen)"]):format(math.floor(h / 24)) or (L["alt (vor %d Std.)"]):format(h)
    end
    if tag == "fresh" then return L["aktuell günstigstes Angebot −1 Kupfer"] end
    return L["kein Preis bekannt"]
end

-- Preis-Eingabe: eigene Felder Gold/Silber/Kupfer (Blizzards Geld-Eingabe fehlt in manchen Clients)
local function SetPrice(copper)
    local s = panel.sell
    copper = math.max(0, math.floor(tonumber(copper) or 0))
    sell.setting = true
    s.gold:SetText(tostring(math.floor(copper / 10000)))
    s.silver:SetText(tostring(math.floor(copper / 100) % 100))
    s.copper:SetText(tostring(copper % 100))
    sell.setting = nil
end

local function GetPrice()
    local s = panel.sell
    local function N(e) return tonumber(e:GetText()) or 0 end
    return N(s.gold) * 10000 + N(s.silver) * 100 + N(s.copper)
end

local function Qty()
    local info = sell.info
    if not info or not info.commodity then return 1 end
    return tonumber(panel.sell.qty:GetText()) or 0
end

local function UpdateDeposit()
    local s = panel and panel.sell
    if not s then return end
    local dep = sell.info and AH.Deposit(sell.info, math.max(1, Qty()), sell.duration)
    s.deposit:SetText(dep and (L["Einzahlung: %s"]):format(Money(dep)) or "")
end

local RefreshOffers

local function ApplySuggestion()
    if not sell.info then return end
    local key = sell.info.key
    -- immer zuerst der niedrigste Preis, der gerade im Auktionshaus steht
    local low = sell.loaded and AH.LowestSellPrice(AH.CurrentOffers(sell.info))
    local p, tag
    if low then p, tag = low, "fresh" else p, tag = AH.Suggest(key, nil, GetServerTime()) end
    if not sell.manual then SetPrice(p) end
    panel.sell.tag:SetText(TagText(p and tag, key))
end

local function ClearSell()
    sell.info, sell.manual, sell.pending = nil, nil, nil
    local s = panel.sell
    s.item.icon:SetTexture(nil)
    s.item.IconBorder:Hide()
    s.itemName:SetText(L["Item rechts aus „Deine Taschen“ wählen oder hierher ziehen"])
    s.itemName:SetTextColor(1, 0.82, 0)
    s.itemSub:SetText("")
    s.tag:SetText(""); s.deposit:SetText(""); s.single:SetText(""); s.qtyRow:Hide()
    SetPrice(0)
    if RefreshOffers then RefreshOffers() end
end

-- Item-Karte: großes Symbol mit Qualitätsrahmen, Name in Qualitätsfarbe, Menge, Stufe, Händlerpreis
local function ShowItemCard(info)
    local s = panel.sell
    s.item.icon:SetTexture(AH.ItemIcon(info.itemID))
    local name, _, quality, level, _, _, _, _, _, _, vendor = AH.ItemInfo(info.link or info.itemID)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    s.itemName:SetText(name or info.link or ("#" .. info.itemID))
    if color then
        s.itemName:SetTextColor(color.r, color.g, color.b)
        s.item.IconBorder:SetVertexColor(color.r, color.g, color.b); s.item.IconBorder:Show()
    else
        s.itemName:SetTextColor(1, 1, 1); s.item.IconBorder:Hide()
    end
    local have = 0
    for _, e in ipairs(AH.BagItems()) do if e.key == info.key then have = e.count end end
    local parts = { (L["In den Taschen: %d"]):format(have) }
    if type(level) == "number" and level > 1 then parts[#parts + 1] = (L["Stufe %d"]):format(level) end
    if type(vendor) == "number" and vendor > 0 then parts[#parts + 1] = (L["Händler: %s"]):format(Money(vendor)) end
    s.itemSub:SetText(table.concat(parts, "  ·  "))
end

local function SelectItem(loc)
    local info = loc and AH.SellInfo(loc)
    if not info then return end
    local s = panel.sell
    sell.info, sell.manual, sell.loaded = info, nil, nil
    AH.lastSeen[info.key] = nil          -- nur frische Angebote zählen
    ShowItemCard(info)
    if info.commodity then
        s.qtyRow:Show()
        s.qty:SetText(tostring(info.max))
        s.max:SetText((L["Max. %d"]):format(info.max))
        s.single:SetText("")
    else
        s.qtyRow:Hide()
        s.single:SetText(L["Ausrüstung wird einzeln eingestellt."])
    end
    ApplySuggestion()
    UpdateDeposit()
    RefreshOffers()
    AH.RequestPrice(info)
end

local function DropItem()
    local loc = C_Cursor and C_Cursor.GetCursorItem and C_Cursor.GetCursorItem()
    ClearCursor()
    SelectItem(loc)
end

local function Post()
    local info = sell.info
    if not info then return end
    local unit, qty = GetPrice(), Qty()
    if not AH.PostModern(info, unit, qty, sell.duration) then
        AH.Print(L["Auktionshaus: Preis und Menge prüfen."])
        return
    end
    sell.pending = { info = info, unit = unit, qty = qty, duration = sell.duration }
end

-- Blizzard warnt (z. B. Preis weit unter Markt): wie im Blizzard-Fenster nachfragen
StaticPopupDialogs["GUILDPRIDE_AH_POST_WARNING"] = {
    text = L["Blizzard warnt bei diesem Angebot. Trotzdem einstellen?"],
    button1 = YES, button2 = NO,
    OnAccept = function()
        local p = sell.pending
        if not p then return end
        if p.info.commodity and C_AuctionHouse.ConfirmPostCommodity then
            C_AuctionHouse.ConfirmPostCommodity(p.info.loc, p.duration, p.qty, p.unit)
        elseif C_AuctionHouse.ConfirmPostItem then
            C_AuctionHouse.ConfirmPostItem(p.info.loc, p.duration, 1, nil, p.unit)
        end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- Angebote, die gerade im Auktionshaus stehen: Klick übernimmt den Preis −1 Kupfer
RefreshOffers = function()
    local p = panel and panel.sell
    if not p or not p.offerRows then return end
    local list = sell.info and AH.CurrentOffers(sell.info) or {}
    if sell.info and #list == 0 then
        p.offerEmpty:SetText(sell.loaded and L["Keine Angebote im Auktionshaus."] or L["Noch keine Angebote geladen."])
    else
        p.offerEmpty:SetText("")
    end
    for i, row in ipairs(p.offerRows) do
        local o = list[i]
        row.offer = o
        if not o then row:Hide() else
            row:Show()
            row.price:SetText(Money(o.unit))
            row.qty:SetText((L["%d Stück"]):format(o.qty))
            row.mine:SetText(o.mine and L["eigenes"] or "")
        end
    end
    p.offerMore:SetText(#list > OFFER_ROWS and (L["+%d weitere"]):format(#list - OFFER_ROWS) or "")
end

local function MakeOfferList(p, y)
    local title = Label(p, L["Gerade im Auktionshaus"], "GameFontNormal"); title:SetPoint("TOPLEFT", 20, y)
    local hint = Label(p, L["Klick übernimmt den Preis −1 Kupfer."], "GameFontDisableSmall")
    hint:SetPoint("LEFT", title, "RIGHT", 10, 0)
    p.offerEmpty = Label(p, "", "GameFontDisableSmall"); p.offerEmpty:SetPoint("TOPLEFT", 24, y - 22)
    p.offerRows = {}
    for i = 1, OFFER_ROWS do
        local row = CreateFrame("Button", nil, p)
        row:SetSize(400, OFFER_H)
        row:SetPoint("TOPLEFT", 20, y - 20 - (i - 1) * OFFER_H)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.price = Label(row, "", "GameFontHighlightSmall"); row.price:SetPoint("LEFT", 4, 0); row.price:SetWidth(150)
        row.price:SetJustifyH("RIGHT")
        row.qty = Label(row, "", "GameFontHighlightSmall"); row.qty:SetPoint("LEFT", 180, 0); row.qty:SetWidth(110)
        row.mine = Label(row, "", "GameFontDisableSmall"); row.mine:SetPoint("LEFT", 300, 0)
        row:SetScript("OnClick", function()
            local o = row.offer
            if not o or not sell.info then return end
            SetPrice(o.mine and o.unit or math.max(1, o.unit - 1))
            sell.manual = true
            UpdateDeposit()
        end)
        row:Hide()
        p.offerRows[i] = row
    end
    p.offerMore = Label(p, "", "GameFontDisableSmall")
    p.offerMore:SetPoint("TOPLEFT", 24, y - 22 - OFFER_ROWS * OFFER_H)
end

-- Taschen-Liste rechts: alle handelbaren Items, Klick wählt das Item zum Verkaufen
local function RefreshBags()
    local p = panel and panel.sell
    if not p or not p:IsShown() then return end
    bagItems = AH.BagItems()
    bagOffset = math.max(0, math.min(bagOffset, #bagItems - BAG_ROWS))
    p.bagTitle:SetText((L["Deine Taschen (%d)"]):format(#bagItems))
    for i, row in ipairs(p.bagRows) do
        local e = bagItems[bagOffset + i]
        row.entry = e
        if not e then row:Hide() else
            row:Show()
            row.icon:SetTexture(e.icon or AH.ItemIcon(e.itemID))
            row.name:SetText(("%s |cffffffffx%d|r"):format(e.link or e.name or "?", e.count))
            local price = AH.PriceFor(e.key)
            row.price:SetText(price and Money(price) or "|cff808080–|r")
            row.selected:SetShown(sell.info ~= nil and sell.info.key == e.key)
        end
    end
end

local function MakeBagList(p)
    p.bagTitle = Label(p, "", "GameFontNormal")
    p.bagTitle:SetPoint("TOPLEFT", p, "TOP", 10, -16)
    local hint = Label(p, L["Klick wählt das Item zum Verkaufen."], "GameFontDisableSmall")
    hint:SetPoint("LEFT", p.bagTitle, "RIGHT", 10, 0)
    p.bagRows = {}
    for i = 1, BAG_ROWS do
        local row = CreateFrame("Button", nil, p)
        row:SetHeight(BAG_H)
        row:SetPoint("TOPLEFT", p, "TOP", 6, -38 - (i - 1) * BAG_H)
        row:SetPoint("RIGHT", p, "RIGHT", -16, 0)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.selected = row:CreateTexture(nil, "BACKGROUND")
        row.selected:SetAllPoints(); row.selected:SetColorTexture(1, 0.82, 0, 0.15); row.selected:Hide()
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(BAG_H - 2, BAG_H - 2); row.icon:SetPoint("LEFT")
        row.name = Label(row, "", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 24, 0); row.name:SetPoint("RIGHT", -112, 0)
        row.price = Label(row, "", "GameFontHighlightSmall"); row.price:SetPoint("RIGHT"); row.price:SetWidth(108)
        row.price:SetJustifyH("RIGHT")
        row:SetScript("OnClick", function()
            if row.entry then SelectItem(row.entry.loc); RefreshBags() end
        end)
        row:SetScript("OnEnter", function()
            if not row.entry then return end
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(row.entry.link); GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p.bagRows[i] = row
    end
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", function(_, d)
        bagOffset = math.max(0, math.min(bagOffset - d * 3, math.max(0, #bagItems - BAG_ROWS)))
        RefreshBags()
    end)
end

local function MakeSellPane()
    local p = Pane()
    local card = CreateFrame("Frame", nil, p, "BackdropTemplate")
    card:SetSize(410, 70); card:SetPoint("TOPLEFT", 14, -10)
    card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    card:SetBackdropColor(1, 1, 1, 0.04); card:SetBackdropBorderColor(1, 0.82, 0, 0.35)
    local item = CreateFrame("Button", nil, card)
    item:SetSize(52, 52); item:SetPoint("LEFT", 9, 0)
    local bg = item:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.6)
    item.icon = item:CreateTexture(nil, "ARTWORK"); item.icon:SetAllPoints()
    item.IconBorder = item:CreateTexture(nil, "OVERLAY")
    item.IconBorder:SetTexture("Interface\\Common\\WhiteIconFrame"); item.IconBorder:SetAllPoints(); item.IconBorder:Hide()
    item:RegisterForDrag("LeftButton")
    item:SetScript("OnReceiveDrag", DropItem)
    item:SetScript("OnClick", function() if GetCursorInfo() then DropItem() end end)
    item:SetScript("OnEnter", function()
        if not sell.info or not sell.info.link then return end
        GameTooltip:SetOwner(item, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(sell.info.link); GameTooltip:Show()
    end)
    item:SetScript("OnLeave", function() GameTooltip:Hide() end)
    card:EnableMouse(true)
    card:SetScript("OnReceiveDrag", DropItem)
    card:SetScript("OnMouseUp", function() if GetCursorInfo() then DropItem() end end)
    p.item = item
    p.itemName = Label(card, "", "GameFontNormalLarge"); p.itemName:SetPoint("TOPLEFT", item, "TOPRIGHT", 12, -2)
    p.itemName:SetWidth(330); p.itemName:SetWordWrap(false)
    p.itemSub = Label(card, "", "GameFontHighlightSmall"); p.itemSub:SetPoint("TOPLEFT", p.itemName, "BOTTOMLEFT", 0, -4)
    p.tag = Label(card, "", "GameFontDisableSmall"); p.tag:SetPoint("TOPLEFT", p.itemSub, "BOTTOMLEFT", 0, -3)

    local y = -94
    local function Row(text)
        local fs = Label(p, text); fs:SetPoint("TOPLEFT", 20, y); y = y - 34
        return fs
    end
    local priceLabel = Row(L["Stückpreis"])
    local function Coin(prev, icon)
        local e = Edit(p, prev and 34 or 56, true)
        if prev then e:SetPoint("LEFT", prev.icon, "RIGHT", 8, 0) else e:SetPoint("LEFT", priceLabel, "LEFT", 120, 0) end
        e.icon = p:CreateTexture(nil, "ARTWORK"); e.icon:SetSize(14, 14)
        e.icon:SetTexture("Interface\\MoneyFrame\\UI-" .. icon .. "Icon"); e.icon:SetPoint("LEFT", e, "RIGHT", 2, 0)
        e:SetScript("OnTextChanged", function() if not sell.setting then sell.manual = true end end)
        return e
    end
    p.gold = Coin(nil, "Gold")
    p.silver = Coin(p.gold, "Silver")
    p.copper = Coin(p.silver, "Copper")

    p.qtyRow = CreateFrame("Frame", nil, p)
    p.qtyRow:SetSize(380, 24); p.qtyRow:SetPoint("TOPLEFT", 20, y + 6)
    local qtyLabel = Label(p.qtyRow, L["Menge"]); qtyLabel:SetPoint("LEFT")
    p.qty = Edit(p.qtyRow, 60, true); p.qty:SetPoint("LEFT", 126, 0)
    p.qty:SetScript("OnTextChanged", UpdateDeposit)
    p.max = Label(p.qtyRow, "", "GameFontDisableSmall"); p.max:SetPoint("LEFT", p.qty, "RIGHT", 10, 0)
    p.qtyRow:Hide()
    p.single = Label(p, "", "GameFontDisableSmall"); p.single:SetPoint("TOPLEFT", 20, y)
    y = y - 34

    local durLabel = Row(L["Dauer"])
    p.dur = {}
    for i, d in ipairs(DURATIONS) do
        local b = Button(p, (L["%s Std."]):format(d[2]), 70)
        b:SetPoint("LEFT", durLabel, "LEFT", 120 + (i - 1) * 76, 0)
        b:SetScript("OnClick", function()
            sell.duration = d[1]
            for j, o in ipairs(p.dur) do o:SetEnabled(j ~= i) end
            UpdateDeposit()
        end)
        b:SetEnabled(d[1] ~= sell.duration)
        p.dur[i] = b
    end
    p.deposit = Label(p, "", "GameFontHighlightSmall"); p.deposit:SetPoint("TOPLEFT", 20, y)
    local post = Button(p, L["Einstellen"], 140)
    post:SetPoint("TOPLEFT", 20, y - 30)
    post:SetScript("OnClick", Post)
    MakeOfferList(p, y - 66)
    MakeBagList(p)
    return p
end

---------------------------------------------------------------------
-- Scanner
---------------------------------------------------------------------
local function CountPrices()
    local n = 0
    for _ in pairs(AH.Store()) do n = n + 1 end
    return n
end

local function RefreshScan()
    local p = panel and panel.scan
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

local function MakeScanPane()
    local p = Pane()
    local text = Label(p, L["Der Komplett-Scan liest das ganze Auktionshaus auf einmal (Blizzard erlaubt das alle 15 Minuten). Die Preise stehen danach im Item-Tooltip und beim Verkaufen; andere GuildPride-Spieler bekommen sie auf Nachfrage."], "GameFontHighlight")
    text:SetPoint("TOPLEFT", 20, -16); text:SetPoint("RIGHT", p, "RIGHT", -20, 0)
    p.go = Button(p, L["Komplett-Scan starten"], 200)
    p.go:SetPoint("TOPLEFT", 20, -80)
    p.go:SetScript("OnClick", function()
        if AH.FullScan() then Status(L["Auktionshaus: Komplett-Scan läuft …"]) end
        RefreshScan()
    end)
    p.state = Label(p, ""); p.state:SetPoint("LEFT", p.go, "RIGHT", 16, 0)
    p.last = Label(p, "", "GameFontHighlightSmall"); p.last:SetPoint("TOPLEFT", 20, -120)
    p.known = Label(p, "", "GameFontHighlightSmall"); p.known:SetPoint("TOPLEFT", 20, -142)
    p.share = Label(p, "", "GameFontHighlightSmall"); p.share:SetPoint("TOPLEFT", 20, -164)
    local tick = 0
    p:SetScript("OnUpdate", function(_, el)
        tick = tick + el
        if tick >= 1 then tick = 0; RefreshScan() end
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

local function RefreshOwn()
    local p = panel and panel.own
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
    if cost and cost > 0 then text = text .. "\\n" .. (L["Kosten: %s"]):format(Money(cost)) end
    own.confirm = function()
        if AH.CancelOwned(a) then Status(L["Auktion wird abgebrochen …"]) end
    end
    StaticPopup_Show("GUILDPRIDE_AH_CANCEL", text)
end

local function MakeOwnPane()
    local p = Pane()
    p.total = Label(p, "", "GameFontHighlight"); p.total:SetPoint("TOPLEFT", 20, -6)
    p.refresh = Button(p, L["Aktualisieren"], 120); p.refresh:SetPoint("TOPRIGHT", -16, -22)
    p.refresh:SetScript("OnClick", function() if AH.QueryOwned() then Status(L["Lade deine Auktionen …"]) end end)
    local cols = { { L["Item"], 44 }, { L["Menge"], 350 }, { L["Stückpreis"], 450 }, { L["Gesamt"], 620 }, { L["Restzeit"], 760 } }
    for _, c in ipairs(cols) do
        local h = Label(p, c[1], "GameFontNormalSmall"); h:SetPoint("TOPLEFT", c[2], -32)
    end
    p.empty = Label(p, "", "GameFontDisableSmall"); p.empty:SetPoint("TOPLEFT", 20, -54)
    p.rows = {}
    for i = 1, OWN_ROWS do
        local row = CreateFrame("Button", nil, p)
        row:SetHeight(OWN_H)
        row:SetPoint("TOPLEFT", 16, -48 - (i - 1) * OWN_H); row:SetPoint("RIGHT", p, "RIGHT", -16, 0)
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
        RefreshOwn()
    end)
    return p
end

---------------------------------------------------------------------
-- Eigenes Fenster und Knopf neben dem X des Auktionshauses
---------------------------------------------------------------------
local function ShowMode(m)
    mode = m
    panel.search:SetShown(m == "search")
    panel.sell:SetShown(m == "sell")
    panel.scan:SetShown(m == "scan")
    panel.own:SetShown(m == "own")
    panel.modeOwn:SetEnabled(m ~= "own")
    panel.modeSearch:SetEnabled(m ~= "search")
    panel.modeSell:SetEnabled(m ~= "sell")
    panel.modeScan:SetEnabled(m ~= "scan")
    Status("")
    if m == "search" then RefreshCategories(); RefreshList() elseif m == "scan" then RefreshScan() elseif m == "sell" then RefreshBags()
    elseif m == "own" then RefreshOwn(); if AH.QueryOwned() then Status(L["Lade deine Auktionen …"]) end end
end

-- Blizzards Fenster unsichtbar machen statt schließen (Schließen beendet die Sitzung)
local hidden, saved, switching = false, nil, false
local function HideBlizzard()
    if hidden or not AuctionHouseFrame then return end
    saved = { scale = AuctionHouseFrame:GetScale(), alpha = AuctionHouseFrame:GetAlpha() }
    hidden = true
    AuctionHouseFrame:SetAlpha(0)
    AuctionHouseFrame:SetScale(0.001)   -- winzig: nichts davon lässt sich mehr anklicken
end

local function RestoreBlizzard()
    if not hidden then return end
    hidden = false
    AuctionHouseFrame:SetScale(saved and saved.scale or 1)
    AuctionHouseFrame:SetAlpha(saved and saved.alpha or 1)
end

local function Remember(blizzard)
    if type(GuildPrideDB) == "table" then GuildPrideDB.ahBlizzard = blizzard end
end

local function ShowGuildPride()
    Remember(false)
    HideBlizzard()
    if not panel.moved then
        panel:ClearAllPoints()
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
    panel:Show()
    ShowMode(mode)
end

-- remember = false: nur kurz (z. B. zum Kaufen), die Wahl bleibt GuildPride
ShowBlizzard = function(remember)
    if remember ~= false then Remember(true) end
    switching = true
    panel:Hide()
    switching = false
    RestoreBlizzard()
end

-- X oder ESC am GuildPride-Fenster: das ganze Auktionshaus schließen wie bei Blizzard
local function OnWindowHide()
    if switching or not hidden then return end
    RestoreBlizzard()
    if HideUIPanel then HideUIPanel(AuctionHouseFrame) end
end

local function MakeButton()
    local b = Skin(CreateFrame("Button", "GuildPrideAHOpenButton", AuctionHouseFrame, "UIPanelButtonTemplate"))
    b:SetSize(96, 20); b:SetText("GuildPride")
    local close = AuctionHouseFrame.CloseButton
    if close then b:SetPoint("RIGHT", close, "LEFT", -4, 0)
    else b:SetPoint("TOPRIGHT", AuctionHouseFrame, "TOPRIGHT", -30, -2) end
    -- Über Blizzards Rahmen und Titelleiste legen, sonst verdecken die den Knopf
    b:SetFrameStrata("HIGH")
    b:SetFrameLevel(AuctionHouseFrame:GetFrameLevel() + 50)
    b:Show()
    b:SetScript("OnClick", function()
        if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
        ShowGuildPride()
    end)
    b:SetScript("OnEnter", function()
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["GuildPride – Auktionshaus"])
        GameTooltip:AddLine(L["Zum GuildPride-Auktionshaus wechseln."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function Build()
    panel = CreateFrame("Frame", "GuildPrideAHWindow", UIParent, "BackdropTemplate")
    panel:SetSize(WIN_W, WIN_H)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    panel:SetBackdropColor(0.05, 0.05, 0.07, 0.97)
    panel:SetFrameStrata("HIGH")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", function(f) f:StopMovingOrSizing(); f.moved = true end)
    panel:SetScript("OnHide", OnWindowHide)
    panel:Hide()
    tinsert(UISpecialFrames, "GuildPrideAHWindow")   -- ESC schließt

    local title = Label(panel, L["GuildPride – Auktionshaus"], "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -16)
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    panel.blizzard = Button(panel, L["Blizzard-Auktionshaus"], 160)
    panel.blizzard:SetPoint("RIGHT", close, "LEFT", -4, 0)
    panel.blizzard:SetScript("OnClick", function()
        if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
        ShowBlizzard()
    end)
    panel.blizzard:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Blizzard-Auktionshaus"])
        GameTooltip:AddLine(L["Zurück zu Blizzards Auktionshaus. Der Knopf „GuildPride“ dort bringt dich wieder hierher."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    panel.blizzard:SetScript("OnLeave", function() GameTooltip:Hide() end)

    panel.modeSearch = Button(panel, L["Suchen"], 110); panel.modeSearch:SetPoint("LEFT", title, "RIGHT", 24, 0)
    panel.modeSell = Button(panel, L["Verkaufen"], 110); panel.modeSell:SetPoint("LEFT", panel.modeSearch, "RIGHT", 8, 0)
    panel.modeOwn = Button(panel, L["Meine Auktionen"], 130); panel.modeOwn:SetPoint("LEFT", panel.modeSell, "RIGHT", 8, 0)
    panel.modeScan = Button(panel, L["Scanner"], 110); panel.modeScan:SetPoint("LEFT", panel.modeOwn, "RIGHT", 8, 0)
    panel.modeOwn:SetScript("OnClick", function() ShowMode("own") end)
    panel.modeSearch:SetScript("OnClick", function() ShowMode("search") end)
    panel.modeSell:SetScript("OnClick", function() ShowMode("sell") end)
    panel.modeScan:SetScript("OnClick", function() ShowMode("scan") end)
    panel.status = Label(panel, "", "GameFontHighlightSmall")
    panel.status:SetPoint("TOPRIGHT", -20, -42); panel.status:SetJustifyH("RIGHT")   -- unter der Titelleiste, rechts

    -- Inhalt unter der Titelzeile
    panel.content = CreateFrame("Frame", nil, panel)
    panel.content:SetPoint("TOPLEFT", 0, -20); panel.content:SetPoint("BOTTOMRIGHT", 0, 8)
    panel.search = MakeSearchPane()
    panel.sell = MakeSellPane()
    panel.scan = MakeScanPane()
    panel.own = MakeOwnPane()
    ClearSell()
    ShowMode(mode)
    panel:Hide()

    button = MakeButton()
end

local function Setup()
    if button or setupError or not AuctionHouseFrame or not AH.IsModern() or not AH.Opt("ahTab") then return end
    local ok, err = pcall(Build)
    if not ok then
        setupError = tostring(err)
        AH.Print((L["Auktionshaus: GuildPride-Fenster konnte nicht aufgebaut werden: %s"]):format(setupError))
    end
end

-- Zustand für /gp ah status
function AH.ModernTabState()
    if not AH.IsModern() then return nil end
    if setupError then return (L["Fehler: %s"]):format(setupError) end
    if not button then return AH.Opt("ahTab") and L["noch nicht aufgebaut (Auktionshaus öffnen)"] or L["aus"] end
    return panel and (panel:IsShown() and L["offen"] or L["bereit"]) or L["unvollständig"]
end

function AH._ModernTab() return button, panel end   -- für Tests und /gp ah status

-- /gp ah fenster: Fenster auch ohne Knopf öffnen
function AH.ToggleWindow()
    if not AH.IsModern() or not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return false end
    Setup()
    if not panel then return false end
    if panel:IsShown() then ShowBlizzard() else ShowGuildPride() end
    return true
end

-- Beim Öffnen sofort ersetzen (außer der Spieler hat zuletzt Blizzard gewählt)
local function OnAuctionHouseShow()
    Setup()
    if panel and not AH.Opt("ahBlizzard") then ShowGuildPride() end
end
AH.Listen("AUCTION_HOUSE_SHOW", function()
    if AuctionHouseFrame then OnAuctionHouseShow() else C_Timer.After(0, OnAuctionHouseShow) end
end)

local function OnBrowse()
    if panel and panel:IsShown() and mode == "search" then
        Status(#AH.BrowseRows() == 0 and L["Nichts gefunden."] or "")
        RefreshList()
    end
end
AH.Listen("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", OnBrowse)
AH.Listen("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", OnBrowse)
AH.Listen("ITEM_KEY_ITEM_INFO_RECEIVED", function() if panel and panel:IsShown() then RefreshList() end end)

local function OnSellPrice()
    if panel and panel:IsShown() and mode == "sell" and sell.info then
        sell.loaded = true
        ApplySuggestion(); RefreshOffers(); RefreshBags()
    end
end
AH.Listen("COMMODITY_SEARCH_RESULTS_UPDATED", OnSellPrice)
AH.Listen("ITEM_SEARCH_RESULTS_UPDATED", OnSellPrice)

-- Kaufansicht: Ergebnisse zeigen; ob Ware oder Einzel-Item, verrät das Ereignis
AH.Listen("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
    if not buy.info or buy.info.itemID ~= itemID then return end
    buy.info.commodity, buy.loaded = true, true
    RefreshDetail()
end)
AH.Listen("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
    if not buy.info or type(itemKey) ~= "table" or itemKey.itemID ~= buy.info.itemID then return end
    buy.info.commodity, buy.loaded = false, true
    RefreshDetail()
end)
AH.Listen("COMMODITY_PRICE_UPDATED", OnCommodityPrice)
AH.Listen("COMMODITY_PRICE_UNAVAILABLE", function()
    if buy.pending then buy.pending = nil; Status(L["Preis nicht mehr verfügbar – bitte erneut versuchen."]) end
end)
AH.Listen("COMMODITY_PURCHASE_SUCCEEDED", OnBought)
AH.Listen("AUCTION_HOUSE_PURCHASE_COMPLETED", OnBought)
AH.Listen("COMMODITY_PURCHASE_FAILED", function() Status(L["Kauf fehlgeschlagen."]) end)
AH.Listen("OWNED_AUCTIONS_UPDATED", function()
    if panel and panel:IsShown() and mode == "own" then Status(""); RefreshOwn() end
end)
AH.Listen("AUCTION_CANCELED", function()
    if not panel or not panel:IsShown() or mode ~= "own" then return end
    Status(L["Auktion abgebrochen."])
    AH.QueryOwned()
end)
AH.Listen("BAG_UPDATE_DELAYED", function()
    if panel and panel:IsShown() and mode == "sell" then RefreshBags() end
end)

AH.Listen("AUCTION_HOUSE_POST_WARNING", function()
    if sell.pending then StaticPopup_Show("GUILDPRIDE_AH_POST_WARNING") end
end)
AH.Listen("AUCTION_HOUSE_AUCTION_CREATED", function()
    local p = sell.pending
    if not p then return end
    -- Den zuvor gesehenen Marktpreis teilen (der eigene Einstellpreis zählt nie)
    AH.Share({ p.info.key })
    if panel then ClearSell(); Status(L["Eingestellt."]); RefreshBags() end
end)

AH.Listen("AUCTION_HOUSE_CLOSED", function()
    buy.pending, buy.confirm, own.confirm = nil, nil, nil
    RestoreBlizzard()   -- zuerst, damit das Ausblenden unten das Auktionshaus nicht erneut schließt
    if panel then panel:Hide() end
    sell.pending = nil
end)
