-- GuildPride Auktionshaus: eigenes Fenster „GuildPride – Auktionshaus“ für das neue
-- Auktionshaus (C_AuctionHouse, WoW Forever) mit Suchen, Verkaufen und Scanner.
-- Es ersetzt Blizzards Auktionshaus-Fenster: Blizzards Fenster wird unsichtbar (nicht
-- geschlossen – das würde die Sitzung am Auktionator beenden). Knopf „Blizzard-Auktionshaus“
-- schaltet zurück, Knopf „GuildPride“ in Blizzards Fenster wieder hierher.
-- Gekauft wird über Blizzards Kaufansicht (Klick auf eine Zeile).
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
local mode = "search"            -- "search" | "sell" | "scan"
local rows, offset = {}, 0
local catSel, catExpanded, catOffset, catRows = nil, {}, 0, {}
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
local function OpenBuy(row)
    local e = row.entry
    if not e then return end
    ShowBlizzard(false)
    if AuctionHouseFrame.SelectBrowseResult then
        local ok = pcall(AuctionHouseFrame.SelectBrowseResult, AuctionHouseFrame, e.result)
        if ok then return end
    end
    AH.Print(L["Auktionshaus: Bitte im Reiter „Kaufen“ nach dem Item suchen."])
end

local function MakeSearchPane()
    local p = Pane()
    local box = Edit(p, 260)
    box:SetPoint("TOPLEFT", 20, -14)
    local go = Button(p, L["Suchen"], 100)
    go:SetPoint("LEFT", box, "RIGHT", 8, 0)
    go:SetScript("OnClick", function() box:ClearFocus(); StartSearch(box:GetText()) end)
    box:SetScript("OnEnterPressed", function() box:ClearFocus(); StartSearch(box:GetText()) end)
    local hint = Label(p, L["Klick auf eine Zeile öffnet Blizzards Kaufansicht."], "GameFontDisableSmall")
    hint:SetPoint("LEFT", go, "RIGHT", 12, 0)

    MakeCategoryList(p, box)
    local head = Label(p, L["Item"], "GameFontNormalSmall"); head:SetPoint("TOPLEFT", CAT_W + 44, -42)
    local headP = Label(p, L["Stückpreis"], "GameFontNormalSmall"); headP:SetPoint("TOPLEFT", CAT_W + 334, -42)
    p.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, p)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", CAT_W + 16, -58 - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", p, "RIGHT", -16, 0)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(ROW_H - 2, ROW_H - 2); row.icon:SetPoint("LEFT")
        row.name = Label(row, "", "GameFontHighlightSmall"); row.name:SetPoint("LEFT", 28, 0); row.name:SetWidth(260)
        row.price = Label(row, "", "GameFontHighlightSmall"); row.price:SetPoint("LEFT", 290, 0); row.price:SetWidth(150)
        row.price:SetJustifyH("RIGHT")
        row.info = Label(row, "", "GameFontDisableSmall"); row.info:SetPoint("LEFT", 460, 0); row.info:SetWidth(300)
        row:SetScript("OnClick", OpenBuy)
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
    local p, tag = AH.Suggest(key, AH.lastSeen[key], GetServerTime())
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
    p.share:SetText(L["Preise teilen: "] .. (AH.Opt("ahShare") and L["an"] or L["aus"])
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
-- Eigenes Fenster und Knopf neben dem X des Auktionshauses
---------------------------------------------------------------------
local function ShowMode(m)
    mode = m
    panel.search:SetShown(m == "search")
    panel.sell:SetShown(m == "sell")
    panel.scan:SetShown(m == "scan")
    panel.modeSearch:SetEnabled(m ~= "search")
    panel.modeSell:SetEnabled(m ~= "sell")
    panel.modeScan:SetEnabled(m ~= "scan")
    Status("")
    if m == "search" then RefreshCategories(); RefreshList() elseif m == "scan" then RefreshScan() elseif m == "sell" then RefreshBags() end
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
    panel.modeScan = Button(panel, L["Scanner"], 110); panel.modeScan:SetPoint("LEFT", panel.modeSell, "RIGHT", 8, 0)
    panel.modeSearch:SetScript("OnClick", function() ShowMode("search") end)
    panel.modeSell:SetScript("OnClick", function() ShowMode("sell") end)
    panel.modeScan:SetScript("OnClick", function() ShowMode("scan") end)
    panel.status = Label(panel, "", "GameFontHighlightSmall"); panel.status:SetPoint("LEFT", panel.modeScan, "RIGHT", 16, 0)

    -- Inhalt unter der Titelzeile
    panel.content = CreateFrame("Frame", nil, panel)
    panel.content:SetPoint("TOPLEFT", 0, -20); panel.content:SetPoint("BOTTOMRIGHT", 0, 8)
    panel.search = MakeSearchPane()
    panel.sell = MakeSellPane()
    panel.scan = MakeScanPane()
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
    RestoreBlizzard()   -- zuerst, damit das Ausblenden unten das Auktionshaus nicht erneut schließt
    if panel then panel:Hide() end
    sell.pending = nil
end)
