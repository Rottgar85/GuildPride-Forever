-- GuildPride Auktionshaus: eigenes Fenster „GuildPride – Auktionshaus“ für das neue
-- Auktionshaus (C_AuctionHouse, WoW Forever) mit Suchen/Kaufen, Verkaufen, Meine Auktionen und Scanner.
-- Es ersetzt Blizzards Auktionshaus-Fenster: Blizzards Fenster wird unsichtbar (nicht
-- geschlossen – das würde die Sitzung am Auktionator beenden). Knopf „Blizzard-Auktionshaus“
-- schaltet zurück, Knopf „GuildPride“ in Blizzards Fenster wieder hierher.
-- Gekauft wird in der eigenen Kaufansicht (Klick auf eine Zeile unter „Suchen“).
-- Reiter „Einkaufsliste“: Favoriten (Stern) und eigene, benannte Listen mit Item-IDs.
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
local mode = "search"            -- "search" | "list" | "sell" | "own" | "scan"
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
local ShowMode                   -- weiter unten: Reiter wechseln
-- Einkaufsliste: sel = gewählte Liste (Index in AH.Lists()), renaming/deleting = Liste im Dialog
local shop = { sel = 1, offset = 0, listOffset = 0, ROWS = 18, ROW_H = 22, LIST_ROWS = 14, LIST_H = 20 }
local searchNeed                 -- Item-Suche (Zutaten, Liste): { [itemID] = benötigte Menge }

local function Skin(b) if GP.SkinButton then GP.SkinButton(b) end return b end
local function EditSkin(e) if GP.SkinEditBox then GP.SkinEditBox(e) end return e end
local function Money(c) return AH.Money(c) end

local function Button(parent, text, w)
    local b = Skin(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
    b:SetSize(w or 100, 22); b:SetText(text)
    -- Schrift immer mittig; ist der Text breiter als der Knopf, wird der Knopf breiter
    -- (sonst rutscht er bei der GuildPride-Schrift aus der Mitte)
    local fs = b.GetFontString and b:GetFontString()
    if type(fs) == "table" and fs.ClearAllPoints then
        fs:ClearAllPoints(); fs:SetPoint("CENTER", b, "CENTER", 0, 0)
        local tw = fs.GetStringWidth and fs:GetStringWidth()
        if type(tw) == "number" and tw + 20 > (w or 100) then b:SetWidth(math.ceil(tw + 20)) end
    end
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

-- Geld als einfacher Text (für Discord-Zeilen: dort gibt es keine Münz-Symbole)
local function PlainMoney(c)
    c = math.floor(tonumber(c) or 0)
    local g, sv, cu = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if sv > 0 then parts[#parts + 1] = sv .. "s" end
    if cu > 0 or #parts == 0 then parts[#parts + 1] = cu .. "c" end
    return table.concat(parts, " ")
end

-- Zeile an Discord (GuildPrideDiscord.lua). quiet: ohne Hinweis, wenn die Anbindung aus ist
local function ToDiscord(line, quiet)
    if not (GP.Discord and GP.Discord.Post) or not (GuildPrideDB and GuildPrideDB.discordBridge) then
        if not quiet then Status(L["Die Discord-Anbindung ist aus (Einstellungen › Gilde)."]) end
        return false
    end
    GP.Discord.Post(line, true)
    return true
end

local RefreshOrders, MakeOrdersPane   -- weiter unten: Reiter „Aufträge“

-- Bereich unter Titel und Umschalt-Knöpfen
local function Pane()
    local p = CreateFrame("Frame", nil, panel.content)
    p:SetPoint("TOPLEFT", 0, -30)
    p:SetPoint("BOTTOMRIGHT", 0, 0)
    return p
end

-- Optischer Abschnitt: etwas hellerer Hintergrund mit feinem goldenen Rahmen, optional eine
-- Kopfleiste (header = Höhe in Pixeln). Nur Texturen auf dem Bereich selbst, damit alle
-- Knöpfe, Zeilen und Texte darüber liegen. a, b = { Punkt, Bezugspunkt, x, y }.
local function Section(parent, a, b, header)
    local fill = parent:CreateTexture(nil, "BACKGROUND")
    fill:SetColorTexture(1, 1, 1, 0.035)
    fill:SetPoint(a[1], parent, a[2], a[3], a[4])
    fill:SetPoint(b[1], parent, b[2], b[3], b[4])
    local function Line(p1, p2, w, h)
        local t = parent:CreateTexture(nil, "BORDER")
        t:SetColorTexture(1, 0.82, 0, 0.25)
        t:SetPoint(p1, fill, p1); t:SetPoint(p2, fill, p2)
        if w then t:SetWidth(w) else t:SetHeight(h) end
    end
    Line("TOPLEFT", "TOPRIGHT", nil, 1); Line("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    Line("TOPLEFT", "BOTTOMLEFT", 1); Line("TOPRIGHT", "BOTTOMRIGHT", 1)
    if header then
        local strip = parent:CreateTexture(nil, "BORDER")
        strip:SetColorTexture(1, 0.82, 0, 0.08)
        strip:SetPoint("TOPLEFT", fill, "TOPLEFT", 1, -1); strip:SetPoint("TOPRIGHT", fill, "TOPRIGHT", -1, -1)
        strip:SetHeight(header)
    end
    return fill
end

---------------------------------------------------------------------
-- Favoriten-Stern: Blizzards Auktionshaus-Stern, sonst der Ruf-Stern (aus = grau und blass)
local FAV_ATLAS = "auctionhouse-icon-favorite"
local function SetStar(b, on)
    local t = b.tex
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(FAV_ATLAS) then
        t:SetAtlas(on and FAV_ATLAS or (FAV_ATLAS .. "-off"))
        t:SetAlpha(1)
    else
        t:SetTexture("Interface\\Common\\ReputationStar")
        t:SetTexCoord(0, 0.5, 0, 0.5)
        t:SetDesaturated(not on)
        t:SetAlpha(on and 1 or 0.45)
    end
    b.on = on and true or false
end

local function StarButton(parent, size, getID, after)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints()
    SetStar(b, false)
    b:SetScript("OnClick", function()
        local id = getID()
        if not id then return end
        SetStar(b, AH.ToggleFavorite(id))
        if after then after() end
    end)
    b:SetScript("OnEnter", function()
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:SetText(b.on and L["Favorit entfernen"] or L["Zu den Favoriten"])
        GameTooltip:AddLine(L["Favoriten findest du im Reiter „Einkaufsliste“."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
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
            local need = searchNeed and searchNeed[e.itemKey.itemID]
            if need then info = "|cffffd100" .. (L["benötigt %d"]):format(need) .. "|r · " .. info end
            if e.mine then info = info .. " · " .. L["eigenes Angebot"] end
            local p2, _, src = AH.PriceFor(e.key)
            if src == "srv" and p2 then info = info .. " · " .. L["Server"] .. " " .. Money(p2) end
            row.info:SetText(info)
            SetStar(row.fav, AH.IsFavorite(e.itemKey.itemID))
        end
    end
end

local levelBoxes = {}   -- Stufe von/bis neben dem Suchfeld (MakeSearchPane)
local function StartSearch(text)
    offset = 0
    searchNeed = nil
    if CloseDetail then CloseDetail() end
    local lo, hi = AH.LevelRange(levelBoxes.min and levelBoxes.min:GetText(), levelBoxes.max and levelBoxes.max:GetText())
    if AH.ModernBrowse(text, catSel and catSel.filters, lo, hi) then Status(L["Suche läuft …"]) end
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
            b.text:SetPoint("LEFT", 8 + r.depth * 12, 0)
            local on = r.cat == catSel
            b.sel:SetShown(on)
            if r.depth == 0 then b.text:SetFontObject(on and "GameFontHighlight" or "GameFontNormal")
            else b.text:SetFontObject(on and "GameFontHighlightSmall" or "GameFontNormalSmall") end
        end
    end
end

local function MakeCategoryList(p, box)
    local side = CreateFrame("Frame", nil, p)
    -- genau innerhalb des Rahmens (Abschnitt x 8..CAT_W+2, Rand 1 px), damit der Auswahlbalken bündig sitzt
    side:SetPoint("TOPLEFT", 9, -41); side:SetSize(CAT_W - 8, CAT_ROWS * CAT_H)
    p.catButtons = {}
    for i = 1, CAT_ROWS do
        local b = CreateFrame("Button", nil, side)
        b:SetSize(CAT_W - 8, CAT_H)
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
StaticPopupDialogs["GUILDPRIDE_AH_MODERN_BUY"] = {   -- eigener Name: das alte Auktionshaus hat GUILDPRIDE_AH_BUY
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
    StaticPopup_Show("GUILDPRIDE_AH_MODERN_BUY", text)
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

-- Preisverlauf (Tagestiefstwerte, bis 7 Tage) als Balken und wer in der Gilde es herstellen kann
local function DrawHistory(p, key)
    local h = AH.History(key)
    local lo, hi
    for _, x in ipairs(h) do lo = math.min(lo or x.p, x.p); hi = math.max(hi or x.p, x.p) end
    local n = #p.histBars
    for i, bar in ipairs(p.histBars) do
        local x = h[#h - n + i]          -- neueste rechts
        if x then
            local f = (hi > lo) and (x.p - lo) / (hi - lo) or 1
            bar:SetHeight(6 + f * 70); bar:Show()
        else bar:Hide() end
    end
    p.histInfo:SetText(#h == 0 and L["Noch kein Verlauf – er entsteht mit jeder Suche."]
        or (L["tiefster %s · höchster %s"]):format(Money(lo), Money(hi)))
end

local function DrawCrafters(p, name)
    local who = AH.GuildCrafters and AH.GuildCrafters(name) or {}
    if #who == 0 then p.crafters:SetText(""); return end
    local shown = {}
    for i = 1, math.min(#who, 6) do shown[i] = who[i] end
    p.crafters:SetText((L["In der Gilde herstellbar von: %s"]):format(table.concat(shown, ", ") .. (#who > 6 and " …" or "")))
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
    SetStar(p.dFav, AH.IsFavorite(e.itemKey.itemID))
    DrawHistory(p, e.key)
    DrawCrafters(p, e.name)
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
    shop.buyQueue = nil            -- „Zurück zur Liste“ beendet auch „Liste kaufen“
    if p.nextBtn then p.nextBtn:Hide() end
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
            if AH.BuyItem(o) then
                buy.lastBuy = { id = info.itemID, qty = o.qty or 1 }   -- für die temporäre Liste
                Status(L["Kauf läuft …"])
            end
        end)
    end
end

-- Blizzard hat den genauen Preis der Ware ermittelt: jetzt nachfragen
local function OnCommodityPrice(unit, total)
    local p = buy.pending
    if not p then return end
    AskBuy((L["%d Stück für %s kaufen (%s je Stück)?"]):format(p.qty, Money(total), Money(unit)), function()
        buy.pending = nil
        if AH.ConfirmCommodity(p.itemID, p.qty) then
            buy.lastBuy = { id = p.itemID, qty = p.qty }   -- für die temporäre Liste
            Status(L["Kauf läuft …"])
        end
    end)
end

-- Kauf fertig. Blizzard meldet manchmal zwei Ereignisse: abgehakt wird nur einmal.
local function OnBought()
    Status(L["Gekauft."])
    local b = buy.lastBuy
    buy.lastBuy = nil
    if b then
        local changed, done = AH.Bought(b.id, b.qty)
        if done then
            Status(L["Gekauft – die temporäre Liste ist erledigt und wurde entfernt."])
            AH.Print(L["Auktionshaus: Alles von der temporären Liste gekauft – die Liste wurde entfernt."])
        elseif changed then
            Status(L["Gekauft und auf der temporären Liste abgehakt."])
        end
        -- „Liste kaufen“ läuft: gleich das nächste Item zeigen
        if shop.buyQueue and shop.BuyNext then shop.BuyNext(); return end
    end
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
    p.dFav = StarButton(d, 22, function() return buy.info and buy.info.itemID end)
    p.dFav:SetPoint("LEFT", p.dName, "RIGHT", 10, 0)
    -- Preis an Discord (über die Discord-Anbindung der Gilde, nur auf Klick)
    p.discordBtn = Button(d, L["Preis an Discord"], 140); p.discordBtn:SetPoint("TOPRIGHT", -6, 0)
    p.discordBtn:SetScript("OnClick", function()
        local info = buy.info
        if not info then return end
        local o = buy.offers and buy.offers[1]
        local price = o and o.unit or AH.PriceFor(info.key)
        if not price then Status(L["Noch kein Preis bekannt."]); return end
        if ToDiscord(("Preis: %s – %s je Stück"):format(AH.ItemName(info.itemID) or ("#" .. info.itemID), PlainMoney(price))) then
            Status(L["Preis an Discord gemeldet."])
        end
    end)
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

    -- rechts neben den Angeboten: Preisverlauf und Gilden-Hersteller
    local ht = Label(d, L["Preisverlauf (bis 7 Tage)"], "GameFontNormalSmall"); ht:SetPoint("TOPLEFT", 470, -72)
    local chart = CreateFrame("Frame", nil, d)
    chart:SetPoint("TOPLEFT", 470, -90); chart:SetSize(7 * 34, 80)
    local base = chart:CreateTexture(nil, "BORDER"); base:SetColorTexture(1, 0.82, 0, 0.3)
    base:SetPoint("BOTTOMLEFT"); base:SetPoint("BOTTOMRIGHT"); base:SetHeight(1)
    p.histBars = {}
    for i = 1, 7 do
        local bar = chart:CreateTexture(nil, "ARTWORK")
        bar:SetColorTexture(1, 0.82, 0, 0.6)
        bar:SetWidth(26); bar:SetPoint("BOTTOMLEFT", (i - 1) * 34 + 4, 1)
        bar:Hide()
        p.histBars[i] = bar
    end
    p.histInfo = Label(d, "", "GameFontHighlightSmall"); p.histInfo:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", 0, -6)
    p.crafters = Label(d, "", "GameFontHighlightSmall"); p.crafters:SetPoint("TOPLEFT", p.histInfo, "BOTTOMLEFT", 0, -14)
    p.crafters:SetWidth(280); p.crafters:SetWordWrap(true)

    local y = -100 - DETAIL_ROWS * DETAIL_H - 14
    p.qtyRow = CreateFrame("Frame", nil, d)
    p.qtyRow:SetSize(200, 24); p.qtyRow:SetPoint("TOPLEFT", 8, y)
    local ql = Label(p.qtyRow, L["Menge"]); ql:SetPoint("LEFT")
    p.qty = Edit(p.qtyRow, 60, true); p.qty:SetPoint("LEFT", 70, 0)
    p.qty:SetScript("OnTextChanged", function() RefreshDetail() end)
    p.total = Label(d, "", "GameFontHighlight"); p.total:SetPoint("TOPLEFT", 210, y - 5)
    p.buyBtn = Button(d, L["Kaufen"], 140); p.buyBtn:SetPoint("TOPLEFT", 8, y - 32)
    p.buyBtn:SetScript("OnClick", Buy)
    -- nur während „Liste kaufen“: dieses Item überspringen
    p.nextBtn = Button(d, L["Weiter ›"], 110); p.nextBtn:SetPoint("LEFT", p.buyBtn, "RIGHT", 10, 0)
    p.nextBtn:SetScript("OnClick", function() if shop.BuyNext then shop.BuyNext() end end)
    p.nextBtn:Hide()
end

local function MakeSearchPane()
    local p = Pane()
    Section(p, { "TOPLEFT", "TOPLEFT", 8, -6 }, { "BOTTOMRIGHT", "TOPRIGHT", -10, -36 })
    Section(p, { "TOPLEFT", "TOPLEFT", 8, -40 }, { "BOTTOMRIGHT", "BOTTOMLEFT", CAT_W + 2, 8 })
    Section(p, { "TOPLEFT", "TOPLEFT", CAT_W + 8, -40 }, { "BOTTOMRIGHT", "BOTTOMRIGHT", -10, 8 }, 18)
    local box = Edit(p, 260)
    box:SetPoint("TOPLEFT", 20, -14)
    local go = Button(p, L["Suchen"], 100)
    go:SetPoint("LEFT", box, "RIGHT", 8, 0)
    go:SetScript("OnClick", function() box:ClearFocus(); StartSearch(box:GetText()) end)
    box:SetScript("OnEnterPressed", function() box:ClearFocus(); StartSearch(box:GetText()) end)
    -- Stufenbereich wie bei Blizzard: von – bis, leer = ohne Grenze
    local lvl = Label(p, L["Stufe"], "GameFontNormalSmall")
    lvl:SetPoint("LEFT", go, "RIGHT", 14, 0)
    levelBoxes.min = Edit(p, 34, true); levelBoxes.min:SetMaxLetters(3)
    levelBoxes.min:SetPoint("LEFT", lvl, "RIGHT", 8, 0)
    local dash = Label(p, "–", "GameFontHighlightSmall"); dash:SetPoint("LEFT", levelBoxes.min, "RIGHT", 4, 0)
    levelBoxes.max = Edit(p, 34, true); levelBoxes.max:SetMaxLetters(3)
    levelBoxes.max:SetPoint("LEFT", dash, "RIGHT", 6, 0)
    for _, e in ipairs({ levelBoxes.min, levelBoxes.max }) do
        e:SetScript("OnEnterPressed", function() e:ClearFocus(); StartSearch(box:GetText()) end)
        e:SetScript("OnTabPressed", function() if e == levelBoxes.min then levelBoxes.max:SetFocus() else box:SetFocus() end end)
    end
    local hint = Label(p, L["Klick auf eine Zeile zeigt die Angebote zum Kaufen. Der Stern merkt ein Item als Favorit."], "GameFontDisableSmall")
    hint:SetPoint("LEFT", levelBoxes.max, "RIGHT", 12, 0)
    hint:SetPoint("RIGHT", p, "RIGHT", -16, 0); hint:SetWordWrap(true)

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
        row.info = Label(row, "", "GameFontDisableSmall"); row.info:SetPoint("LEFT", 460, 0); row.info:SetWidth(280)
        row.fav = StarButton(row, 16, function() return row.entry and row.entry.itemKey.itemID end)
        row.fav:SetPoint("RIGHT", -4, 0)
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
-- Einkaufsliste: links Favoriten und eigene Listen, rechts die Items der gewählten Liste
---------------------------------------------------------------------
local function CurrentList()
    local lists = AH.Lists()
    shop.sel = math.max(1, math.min(shop.sel, #lists))
    return lists[shop.sel], lists
end

local function RefreshShop()
    local p = panel and panel.lists
    if not p or not p:IsShown() then return end
    local list, lists = CurrentList()
    shop.listOffset = math.max(0, math.min(shop.listOffset, #lists - shop.LIST_ROWS))
    for i, b in ipairs(p.listRows) do
        local idx = shop.listOffset + i
        local l = lists[idx]
        b.index = idx
        if not l then b:Hide() else
            b:Show()
            b.text:SetText((l.temp and "|cff66ccff%s|r |cff999999(%d)|r" or "%s |cff999999(%d)|r"):format(l.name, #l.items))
            b.sel:SetShown(idx == shop.sel)
            b.text:SetFontObject(idx == shop.sel and "GameFontHighlight" or "GameFontNormal")
        end
    end
    p.title:SetText(list.name)
    p.renameBtn:SetEnabled(not list.fav and not list.temp)
    p.deleteBtn:SetEnabled(not list.fav)
    local items = list.items
    shop.offset = math.max(0, math.min(shop.offset, #items - shop.ROWS))
    p.empty:SetText(#items == 0 and (list.fav and L["Noch keine Favoriten: Stern in der Suche anklicken oder oben Item-IDs eintragen."]
        or L["Noch leer: oben Item-IDs eintragen."]) or "")
    for i, row in ipairs(p.rows) do
        local id = items[shop.offset + i]
        row.itemID = id
        if not id then row:Hide() else
            row:Show()
            local name, _, quality = AH.ItemInfo(id)
            row.icon:SetTexture(AH.ItemIcon(id))
            row.name:SetText(name or L["Item wird geladen …"])
            local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
            if color then row.name:SetTextColor(color.r, color.g, color.b) else row.name:SetTextColor(1, 1, 1) end
            row.id:SetText(tostring(id))
            if not row.qtyBox:HasFocus() then row.qtyBox:SetText(tostring(AH.ItemQty(list, id) or "")) end
            -- Bestand: mit Menge „hast 5 · noch 7“, ohne Menge nur „hast 5“
            local have, left = AH.ItemCount(id), AH.Remaining(list, id)
            if left == 0 then row.have:SetText("|cff40ff40" .. (L["genug (%d)"]):format(have) .. "|r")
            elseif left then row.have:SetText((L["hast %d · noch %d"]):format(have, left))
            else row.have:SetText(have > 0 and (L["hast %d"]):format(have) or "") end
            row.alarm:SetText(AH.Alert(id) and ("|cffffd100" .. L["Alarm"] .. "|r") or L["Alarm"])
            -- Preis: für die noch fehlende Menge, sonst je Stück
            local price = AH.PriceFor(AH.Key(id))
            if price and left and left > 0 then row.price:SetText(Money(price * left))
            else row.price:SetText(price and Money(price) or "-") end
        end
    end
    local total, unknown = AH.ListCost(list)
    p.total:SetText(total > 0 and ((L["Noch zu kaufen, ungefähr: %s"]):format(Money(total))
        .. (unknown > 0 and ("  ·  " .. (L["%d ohne bekannten Preis"]):format(unknown)) or "")) or "")
end

-- Item aus der Liste suchen: direkt die Kaufansicht unter „Suchen“ öffnen
local function SearchItem(id)
    if not id then return end
    ShowMode("search")
    local _, _, quality = AH.ItemInfo(id)
    OpenDetail({ entry = { itemKey = { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 },
        key = AH.Key(id), name = AH.ItemName(id), icon = AH.ItemIcon(id), quality = quality } })
end

-- Alle Items der gewählten Liste suchen: unter „Suchen“ stehen dann nur diese
local function SearchList()
    local list = CurrentList()
    if #list.items == 0 then Status(L["Die Liste ist leer."]); return end
    local need = {}
    for _, id in ipairs(list.items) do need[id] = AH.Remaining(list, id) end
    if not AH.ShowItemSearch(list.items, need, list.name) then Status(L["Auktionshaus: Erst das Auktionshaus öffnen."]) end
end

-- „Liste kaufen“: Items nacheinander in der Kaufansicht zeigen (Menge = was noch fehlt)
shop.BuyNext = function()
    local q = shop.buyQueue
    local id = q and table.remove(q, 1)
    if not id then
        shop.buyQueue = nil
        if panel.search.nextBtn then panel.search.nextBtn:Hide() end
        Status(L["Liste kaufen: fertig."])
        return
    end
    SearchItem(id)
    shop.buyQueue = q                -- SearchItem darf die Warteschlange nicht beenden
    local left = AH.Remaining(q.list, id)
    if left and left > 0 then panel.search.qty:SetText(tostring(left)) end
    panel.search.nextBtn:Show()
    Status((L["Liste kaufen: %s – Menge prüfen und „Kaufen“ klicken (noch %d danach)."]):format(AH.ItemName(id) or ("#" .. id), #q))
end

local function BuyList()
    local list = CurrentList()
    local q = { list = list }
    for _, id in ipairs(list.items) do
        local left = AH.Remaining(list, id)
        if left == nil or left > 0 then q[#q + 1] = id end
    end
    if #q == 0 then Status(L["Nichts mehr zu kaufen – du hast alles."]); return end
    if not AH.IsOpen() then Status(L["Auktionshaus: Erst das Auktionshaus öffnen."]); return end
    shop.buyQueue = q
    shop.BuyNext()
end

local function SaveQty(row)
    if not row.itemID then return end
    AH.SetItemQty(CurrentList(), row.itemID, tonumber(row.qtyBox:GetText()))
    row.qtyBox:ClearFocus()
    RefreshShop()
end

local function AddIDs()
    local p = panel.lists
    local list = CurrentList()
    local added, dup = AH.AddItems(list, p.idBox:GetText())
    if added == 0 and dup == 0 then Status(L["Keine gültige Item-ID gefunden."]); return end
    p.idBox:SetText(""); p.idBox:ClearFocus()
    Status((L["%d eingetragen"]):format(added) .. (dup > 0 and (" · " .. (L["%d schon in der Liste"]):format(dup)) or ""))
    RefreshShop()
end

local function ShopNameAccepted(text)
    local why
    if shop.renaming then
        why = select(2, AH.RenameList(shop.renaming, text))
    else
        local l
        l, why = AH.NewList(text)
        if l then shop.sel, shop.offset = #AH.Lists(), 0 end
    end
    shop.renaming = nil
    Status(why or "")
    RefreshShop()
end

StaticPopupDialogs["GUILDPRIDE_AH_LIST_NAME"] = {
    text = "%s",
    button1 = OKAY, button2 = CANCEL,
    hasEditBox = true, maxLetters = 60,
    OnShow = function(self)
        local eb = self.editBox or self.EditBox
        eb:SetText(shop.renaming and shop.renaming.name or ""); eb:SetFocus(); eb:HighlightText()
    end,
    OnAccept = function(self) ShopNameAccepted((self.editBox or self.EditBox):GetText()) end,
    OnCancel = function() shop.renaming = nil end,
    EditBoxOnEnterPressed = function(eb)
        local dlg = eb:GetParent()
        ShopNameAccepted(eb:GetText()); dlg:Hide()
    end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
local function AlertAccepted(text)
    local id = shop.alerting
    shop.alerting = nil
    if not id then return end
    local c = AH.ParseMoney(text)
    AH.SetAlert(id, c)
    Status(c and (L["Preisalarm: höchstens %s je Stück."]):format(Money(c)) or L["Preisalarm aus."])
    RefreshShop()
end
StaticPopupDialogs["GUILDPRIDE_AH_ALERT"] = {
    text = L["Preisalarm für %s:\nHinweis, wenn es je Stück höchstens so viel kostet (z. B. 1g 50s oder 1,5). Leer = aus."],
    button1 = OKAY, button2 = CANCEL,
    hasEditBox = true, maxLetters = 20,
    OnShow = function(self)
        local eb = self.editBox or self.EditBox
        local a = shop.alerting and AH.Alert(shop.alerting)
        eb:SetText(a and (a % 10000 == 0 and tostring(a / 10000) or (math.floor(a / 10000) .. "g " .. math.floor(a / 100) % 100 .. "s " .. a % 100 .. "c")) or "")
        eb:SetFocus(); eb:HighlightText()
    end,
    OnAccept = function(self) AlertAccepted((self.editBox or self.EditBox):GetText()) end,
    OnCancel = function() shop.alerting = nil end,
    EditBoxOnEnterPressed = function(eb)
        local dlg = eb:GetParent()
        AlertAccepted(eb:GetText()); dlg:Hide()
    end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
local function ImportAccepted(text)
    local l, n, skipped = AH.ImportList(text)
    if not l then Status(L["Nichts erkannt – keine Items im Text."]); return end
    for i, x in ipairs(AH.Lists()) do if x == l then shop.sel = i end end
    shop.offset = 0
    Status((L["Liste „%s“ eingelesen: %d Items"]):format(l.name, n)
        .. ((skipped or 0) > 0 and (" · " .. (L["%d nicht erkannt"]):format(skipped)) or ""))
    RefreshShop()
end
StaticPopupDialogs["GUILDPRIDE_AH_LIST_IMPORT"] = {
    text = L["Einkaufsliste einfügen (Strg+V):\nGuildPride-Text, Auctionator-Liste oder Item-IDs"],
    button1 = OKAY, button2 = CANCEL,
    hasEditBox = true, maxLetters = 0, editBoxWidth = 320,
    OnShow = function(self) local eb = self.editBox or self.EditBox; eb:SetText(""); eb:SetFocus() end,
    OnAccept = function(self) ImportAccepted((self.editBox or self.EditBox):GetText()) end,
    EditBoxOnEnterPressed = function(eb)
        local dlg = eb:GetParent()
        ImportAccepted(eb:GetText()); dlg:Hide()
    end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
StaticPopupDialogs["GUILDPRIDE_AH_LIST_DELETE"] = {
    text = "%s",
    button1 = DELETE or OKAY, button2 = CANCEL,
    OnAccept = function()
        local l = shop.deleting
        shop.deleting = nil
        if AH.DeleteList(l) then shop.sel, shop.offset = 1, 0; Status(L["Liste gelöscht."]) end
        RefreshShop()
    end,
    OnCancel = function() shop.deleting = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function MakeShopPane()
    local p = Pane()
    Section(p, { "TOPLEFT", "TOPLEFT", 8, -6 }, { "BOTTOMRIGHT", "TOPRIGHT", -10, -36 })
    Section(p, { "TOPLEFT", "TOPLEFT", 8, -40 }, { "BOTTOMRIGHT", "BOTTOMLEFT", CAT_W + 2, 8 }, 18)
    Section(p, { "TOPLEFT", "TOPLEFT", CAT_W + 8, -40 }, { "BOTTOMRIGHT", "BOTTOMRIGHT", -10, 8 }, 18)
    p.title = Label(p, "", "GameFontNormalLarge"); p.title:SetPoint("TOPLEFT", 20, -14); p.title:SetWidth(CAT_W - 20)
    p.title:SetWordWrap(false)
    local il = Label(p, L["Item-IDs:"]); il:SetPoint("TOPLEFT", CAT_W + 20, -16)
    p.idBox = Edit(p, 230); p.idBox:SetPoint("LEFT", il, "RIGHT", 8, 0)
    p.addBtn = Button(p, L["Eintragen"], 100); p.addBtn:SetPoint("LEFT", p.idBox, "RIGHT", 8, 0)
    p.addBtn:SetScript("OnClick", AddIDs)
    p.idBox:SetScript("OnEnterPressed", AddIDs)
    p.idBox:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Item-IDs:"])
        GameTooltip:AddLine(L["Mehrere mit Komma trennen. Umschalt+Klick auf ein Item oder ein Wowhead-Link geht auch."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    p.idBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Teilen: Liste als Text zeigen (kopieren) oder Text einlesen (auch Auctionator-Listen)
    p.exportBtn = Button(p, L["Exportieren"], 100); p.exportBtn:SetPoint("LEFT", p.addBtn, "RIGHT", 24, 0)
    p.exportBtn:SetScript("OnClick", function()
        local list = CurrentList()
        if GP.ShowCopy then GP.ShowCopy((L["Einkaufsliste „%s“ – Text kopieren und teilen"]):format(list.name), AH.ExportList(list)) end
    end)
    p.importBtn = Button(p, L["Importieren"], 100); p.importBtn:SetPoint("LEFT", p.exportBtn, "RIGHT", 6, 0)
    p.importBtn:SetScript("OnClick", function() StaticPopup_Show("GUILDPRIDE_AH_LIST_IMPORT") end)

    -- links: Listen
    local lh = Label(p, L["Listen"], "GameFontNormalSmall"); lh:SetPoint("TOPLEFT", 16, -43)
    p.listRows = {}
    for i = 1, shop.LIST_ROWS do
        local b = CreateFrame("Button", nil, p)
        b:SetSize(CAT_W - 8, shop.LIST_H)
        b:SetPoint("TOPLEFT", 9, -60 - (i - 1) * shop.LIST_H)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b.sel = b:CreateTexture(nil, "BACKGROUND"); b.sel:SetAllPoints(); b.sel:SetColorTexture(1, 0.82, 0, 0.18); b.sel:Hide()
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal"); b.text:SetJustifyH("LEFT")
        b.text:SetPoint("LEFT", 8, 0); b.text:SetPoint("RIGHT", -4, 0); b.text:SetWordWrap(false)
        b:SetScript("OnClick", function()
            shop.sel, shop.offset = b.index, 0
            Status("")
            RefreshShop()
        end)
        p.listRows[i] = b
    end
    p.buyListBtn = Button(p, L["Liste kaufen"], CAT_W - 20); p.buyListBtn:SetPoint("BOTTOMLEFT", 14, 152)
    p.buyListBtn:SetScript("OnClick", BuyList)
    p.buyListBtn:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Liste kaufen"])
        GameTooltip:AddLine(L["Zeigt die Items der Liste nacheinander zum Kaufen, mit der noch fehlenden Menge. Jeder Kauf wird wie gewohnt bestätigt, „Weiter ›“ überspringt ein Item."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    p.buyListBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.tempBtn = Button(p, L["Temporäre Liste"], CAT_W - 20); p.tempBtn:SetPoint("BOTTOMLEFT", 14, 126)
    p.tempBtn:SetScript("OnClick", function()
        local t = AH.TempList(true)
        for i, l in ipairs(AH.Lists()) do if l == t then shop.sel = i end end
        shop.offset = 0
        Status(L["Temporäre Liste: Käufe hier im Auktionshaus haken sie ab, ist alles gekauft, verschwindet sie."])
        RefreshShop()
    end)
    p.tempBtn:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Temporäre Liste"])
        GameTooltip:AddLine(L["Für einen Einkauf: Jeder Kauf im GuildPride-Auktionshaus zieht die gekaufte Menge ab. Ist alles gekauft, verschwindet die Liste von selbst."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    p.tempBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.searchAllBtn = Button(p, L["Alle im AH suchen"], CAT_W - 20); p.searchAllBtn:SetPoint("BOTTOMLEFT", 14, 100)
    p.searchAllBtn:SetScript("OnClick", SearchList)
    p.searchAllBtn:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Alle im AH suchen"])
        GameTooltip:AddLine(L["Sucht alle Items dieser Liste. Unter „Suchen“ stehen dann nur diese, mit der benötigten Menge."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    p.searchAllBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.newBtn = Button(p, L["Neue Liste"], CAT_W - 20); p.newBtn:SetPoint("BOTTOMLEFT", 14, 66)
    p.renameBtn = Button(p, L["Umbenennen"], CAT_W - 20); p.renameBtn:SetPoint("BOTTOMLEFT", 14, 40)
    p.deleteBtn = Button(p, L["Liste löschen"], CAT_W - 20); p.deleteBtn:SetPoint("BOTTOMLEFT", 14, 14)
    p.newBtn:SetScript("OnClick", function()
        shop.renaming = nil
        StaticPopup_Show("GUILDPRIDE_AH_LIST_NAME", L["Name der neuen Einkaufsliste:"])
    end)
    p.renameBtn:SetScript("OnClick", function()
        local l = CurrentList()
        if l.fav or l.temp then return end
        shop.renaming = l
        StaticPopup_Show("GUILDPRIDE_AH_LIST_NAME", L["Neuer Name der Liste:"])
    end)
    p.deleteBtn:SetScript("OnClick", function()
        local l = CurrentList()
        if l.fav then return end
        shop.deleting = l
        StaticPopup_Show("GUILDPRIDE_AH_LIST_DELETE", (L["Liste „%s“ löschen?"]):format(l.name))
    end)

    -- rechts: Items der Liste
    local cols = { { L["Item"], CAT_W + 44 }, { L["Menge"], CAT_W + 296 }, { L["Item-ID"], CAT_W + 361 },
                   { L["Preis"], CAT_W + 494 }, { L["Bestand"], CAT_W + 542 } }
    p.total = Label(p, "", "GameFontHighlight"); p.total:SetPoint("BOTTOMLEFT", CAT_W + 20, 16)
    for _, c in ipairs(cols) do
        local h = Label(p, c[1], "GameFontNormalSmall"); h:SetPoint("TOPLEFT", c[2], -43)
    end
    p.empty = Label(p, "", "GameFontDisableSmall"); p.empty:SetPoint("TOPLEFT", CAT_W + 20, -64)
    p.rows = {}
    for i = 1, shop.ROWS do
        local row = CreateFrame("Button", nil, p)
        row:SetHeight(shop.ROW_H)
        row:SetPoint("TOPLEFT", CAT_W + 16, -60 - (i - 1) * shop.ROW_H); row:SetPoint("RIGHT", p, "RIGHT", -16, 0)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(shop.ROW_H - 2, shop.ROW_H - 2); row.icon:SetPoint("LEFT")
        row.name = Label(row, "", "GameFontHighlightSmall"); row.name:SetPoint("LEFT", 28, 0); row.name:SetWidth(240)
        row.qtyBox = Edit(row, 50, true); row.qtyBox:SetPoint("LEFT", 282, 0)
        row.qtyBox:SetScript("OnEnterPressed", function() SaveQty(row) end)
        row.qtyBox:SetScript("OnEditFocusLost", function() SaveQty(row) end)
        row.id = Label(row, "", "GameFontDisableSmall"); row.id:SetPoint("LEFT", 345, 0); row.id:SetWidth(60)
        row.price = Label(row, "", "GameFontHighlightSmall"); row.price:SetPoint("LEFT", 410, 0); row.price:SetWidth(110)
        row.have = Label(row, "", "GameFontDisableSmall"); row.have:SetPoint("LEFT", 526, 0); row.have:SetWidth(90)
        row.price:SetJustifyH("RIGHT")
        row.remove = Button(row, "X", 26); row.remove:SetPoint("RIGHT", -2, 0)
        row.search = Button(row, L["Suchen"], 70); row.search:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
        row.search:SetScript("OnClick", function() SearchItem(row.itemID) end)
        row.alarm = Button(row, L["Alarm"], 54); row.alarm:SetPoint("RIGHT", row.search, "LEFT", -4, 0)
        row.alarm:SetScript("OnClick", function()
            if not row.itemID then return end
            shop.alerting = row.itemID
            StaticPopup_Show("GUILDPRIDE_AH_ALERT", AH.ItemName(row.itemID) or ("#" .. row.itemID))
        end)
        row.alarm:SetScript("OnEnter", function(b)
            local a = row.itemID and AH.Alert(row.itemID)
            GameTooltip:SetOwner(b, "ANCHOR_TOP")
            GameTooltip:SetText(L["Preisalarm"])
            GameTooltip:AddLine(a and (L["Hinweis, sobald es je Stück höchstens %s kostet."]):format(Money(a))
                or L["Klick: Wunschpreis eingeben. Taucht es so billig im Auktionshaus auf, gibt es einen Hinweis."], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row.alarm:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.remove:SetScript("OnClick", function()
            if AH.RemoveItem(CurrentList(), row.itemID) then RefreshShop() end
        end)
        row:SetScript("OnClick", function() SearchItem(row.itemID) end)
        row:SetScript("OnEnter", function()
            if not row.itemID then return end
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(row.itemID)
            GameTooltip:AddLine(L["Klick: im Auktionshaus suchen und kaufen"], 0.6, 0.8, 1)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Hide()
        p.rows[i] = row
    end
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", function(_, d)
        local list = CurrentList()
        shop.offset = math.max(0, math.min(shop.offset - d * 3, math.max(0, #list.items - shop.ROWS)))
        RefreshShop()
    end)
    -- Umschalt+Klick auf ein Item trägt die ID ins Feld ein (wie in den Chat)
    if hooksecurefunc and ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", function(link)
            local id = type(link) == "string" and link:match("item:(%d+)")
            if id and p:IsShown() and p.idBox:HasFocus() then p.idBox:Insert(id .. " ") end
        end)
    end
    return p
end

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

RefreshOrders = function()
    local p = panel and panel.orders
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
AH.OrdersChanged = function() if panel and panel:IsShown() and mode == "orders" then RefreshOrders() end end

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
    RefreshOrders()
end

local function AddOrderClicked()
    local p = panel.orders
    local o, why = AH.AddOrder(p.itemBox:GetText(), tonumber(p.qtyBox:GetText()) or 1)
    if not o then Status(why); return end
    p.itemBox:SetText(""); p.itemBox:ClearFocus(); p.qtyBox:SetText("1")
    Status((L["Auftrag eingestellt: %dx %s."]):format(o.qty, ItemText(o.item)))
    ToDiscord(("Auftrag: %dx %s (von %s)"):format(o.qty, ItemText(o.item), GP.Me()), true)
    RefreshOrders()
end

MakeOrdersPane = function()
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
        row.search:SetScript("OnClick", function() if row.order then SearchItem(row.order.item) end end)
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
        RefreshOrders()
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
            row.name:SetText(("%s |cffffffffx%d|r"):format(e.link or e.name or "?", e.count)
                .. (AH.WasPosted(e.key) and (" |cff66ccff" .. L["(zurück)"] .. "|r") or ""))
            local price = AH.PriceFor(e.key)
            row.price:SetText(price and Money(price) or "|cff808080–|r")
            row.selected:SetShown(sell.info ~= nil and sell.info.key == e.key)
        end
    end
end

-- Zurückgekommene Items nacheinander zum Einstellen wählen (mit aktuellem Preisvorschlag)
local function NextReturned()
    for _, e in ipairs(AH.BagItems()) do
        if e.loc and AH.WasPosted(e.key) then
            SelectItem(e.loc); RefreshBags()
            Status((L["Zurückgekommen: %s – Preis prüfen und „Einstellen“ klicken."]):format(e.name or "?"))
            return true
        end
    end
    sell.returning = nil
    Status(L["Keine zurückgekommenen Items in den Taschen."])
    return false
end

local function MakeBagList(p)
    p.bagTitle = Label(p, "", "GameFontNormal")
    p.bagTitle:SetPoint("TOPLEFT", p, "TOP", 10, -16)
    p.returnBtn = Button(p, L["Zurückgekommene einstellen"], 190); p.returnBtn:SetPoint("TOPRIGHT", -16, -12)
    p.returnBtn:SetScript("OnClick", function() sell.returning = true; NextReturned() end)
    p.returnBtn:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Zurückgekommene einstellen"])
        GameTooltip:AddLine(L["Wählt nacheinander die Items, die du schon einmal eingestellt hattest und die wieder in den Taschen liegen (z. B. unverkauft per Post zurück). Klick auf eine Zeile wählt ein Item von Hand."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    p.returnBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
    Section(p, { "TOPLEFT", "TOPLEFT", 8, -4 }, { "BOTTOMRIGHT", "TOPLEFT", 490, -254 })
    Section(p, { "TOPLEFT", "TOPLEFT", 8, -258 }, { "BOTTOMRIGHT", "BOTTOMLEFT", 490, 8 }, 20)
    Section(p, { "TOPLEFT", "TOP", 0, -8 }, { "BOTTOMRIGHT", "BOTTOMRIGHT", -10, 8 }, 24)
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
-- Zählen geht über den ganzen Preis-Speicher (Tausende Einträge): nur alle 10 s neu
local priceCount, priceCountAt = 0, nil
local function CountPrices()
    if priceCountAt and GetTime() - priceCountAt < 10 then return priceCount end
    local n = 0
    for _ in pairs(AH.Store()) do n = n + 1 end
    priceCount, priceCountAt = n, GetTime()
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
        RefreshOwn()
    end)
    return p
end

---------------------------------------------------------------------
-- Eigenes Fenster und Knopf neben dem X des Auktionshauses
---------------------------------------------------------------------
ShowMode = function(m)
    mode = m
    panel.search:SetShown(m == "search")
    panel.lists:SetShown(m == "list")
    panel.orders:SetShown(m == "orders")
    panel.modeOrders:SetEnabled(m ~= "orders")
    panel.modeList:SetEnabled(m ~= "list")
    panel.sell:SetShown(m == "sell")
    panel.scan:SetShown(m == "scan")
    panel.own:SetShown(m == "own")
    panel.modeOwn:SetEnabled(m ~= "own")
    panel.modeSearch:SetEnabled(m ~= "search")
    panel.modeSell:SetEnabled(m ~= "sell")
    panel.modeScan:SetEnabled(m ~= "scan")
    Status("")
    if m == "search" then RefreshCategories(); RefreshList() elseif m == "scan" then RefreshScan() elseif m == "sell" then RefreshBags()
    elseif m == "list" then RefreshShop()
    elseif m == "orders" then AH.RequestOrders(); RefreshOrders()
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

-- Standard ist Blizzards Auktionshaus; erst wer einmal auf „GuildPride“ klickt, bekommt
-- beim Öffnen das GuildPride-Fenster (ahGuildPride = true), bis er wieder Blizzard wählt.
local function Remember(blizzard)
    if type(GuildPrideDB) == "table" then GuildPrideDB.ahGuildPride = not blizzard end
end

-- remember = false: nur dieses Mal (z. B. Zutaten-Suche aus dem Berufsfenster), die Wahl bleibt
local function ShowGuildPride(remember)
    if remember ~= false then Remember(false) end
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
        GameTooltip:AddLine(L["Ganz ausschalten: Einstellungen › Auktionshaus oder /gp ah aus."], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function Build()
    panel = CreateFrame("Frame", "GuildPrideAHWindow", UIParent, "BackdropTemplate")
    panel:SetSize(WIN_W, WIN_H)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    if GP.SkinDialog then GP.SkinDialog(panel) end   -- Goldrahmen wie das Gildenfenster
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
    if GP.SkinClose then GP.SkinClose(close) end
    panel.blizzard = Button(panel, L["Blizzard-AH"], 110)
    panel.blizzard:SetPoint("RIGHT", close, "LEFT", -4, 0)
    panel.blizzard:SetScript("OnClick", function()
        if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
        ShowBlizzard()
    end)
    panel.blizzard:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Blizzard-Auktionshaus"])
        GameTooltip:AddLine(L["Zurück zu Blizzards Auktionshaus. Der Knopf „GuildPride“ dort bringt dich wieder hierher."], 1, 1, 1, true)
        GameTooltip:AddLine(L["Ganz ausschalten: Einstellungen › Auktionshaus oder /gp ah aus."], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    panel.blizzard:SetScript("OnLeave", function() GameTooltip:Hide() end)

    panel.modeSearch = Button(panel, L["Suchen"], 76); panel.modeSearch:SetPoint("LEFT", title, "RIGHT", 14, 0)
    -- Reihenfolge: Suchen · Verkaufen · Meine Auktionen · Einkaufsliste · Aufträge · Scanner
    panel.modeSell = Button(panel, L["Verkaufen"], 82); panel.modeSell:SetPoint("LEFT", panel.modeSearch, "RIGHT", 5, 0)
    panel.modeOwn = Button(panel, L["Meine Auktionen"], 124); panel.modeOwn:SetPoint("LEFT", panel.modeSell, "RIGHT", 5, 0)
    panel.modeList = Button(panel, L["Einkaufsliste"], 100); panel.modeList:SetPoint("LEFT", panel.modeOwn, "RIGHT", 5, 0)
    panel.modeOrders = Button(panel, L["Aufträge"], 80); panel.modeOrders:SetPoint("LEFT", panel.modeList, "RIGHT", 5, 0)
    panel.modeScan = Button(panel, L["Scanner"], 74); panel.modeScan:SetPoint("LEFT", panel.modeOrders, "RIGHT", 5, 0)
    panel.modeOrders:SetScript("OnClick", function() ShowMode("orders") end)
    panel.modeList:SetScript("OnClick", function() ShowMode("list") end)
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
    panel.lists = MakeShopPane()
    panel.orders = MakeOrdersPane()
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
    if not AH.IsModern() or not AH.Opt("ahTab") or not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return false end
    Setup()
    if not panel then return false end
    if panel:IsShown() then ShowBlizzard() else ShowGuildPride() end
    return true
end

-- Eigenes Fenster an/aus (Einstellungen, /gp ah an|aus) – wirkt sofort, auch bei offenem Auktionshaus.
-- Aus: Blizzards Auktionshaus ganz ohne GuildPride-Fenster und ohne Knopf. Preise im Tooltip,
-- Mitlesen und Teilen laufen weiter.
function AH.SetModernUI(on)
    if type(GuildPrideDB) == "table" then GuildPrideDB.ahTab = on and true or false end
    if on then
        Setup()
        if button then button:Show() end
    else
        if panel and (panel:IsShown() or hidden) then ShowBlizzard(false) end
        if button then button:Hide() end
    end
end

-- Beim Öffnen bleibt Blizzards Fenster; GuildPride ersetzt es nur, wenn der Spieler zuletzt
-- selbst GuildPride gewählt hat (Knopf „GuildPride“) und es nicht ausgeschaltet ist
local function OnAuctionHouseShow()
    Setup()
    if button then button:SetShown(AH.Opt("ahTab") and true or false) end
    if panel and AH.Opt("ahTab") and GuildPrideDB and GuildPrideDB.ahGuildPride == true then ShowGuildPride() end
end
AH.Listen("AUCTION_HOUSE_SHOW", function()
    if AuctionHouseFrame then OnAuctionHouseShow() else C_Timer.After(0, OnAuctionHouseShow) end
end)

-- Nur bestimmte Items suchen (Rezept-Zutaten, Einkaufsliste) und unter „Suchen“ zeigen.
-- need = { [itemID] = benötigte Menge } erscheint in der Zeile. Braucht das offene Auktionshaus.
function AH.ShowItemSearch(ids, need, title)
    if not AH.IsModern() or not AH.Opt("ahTab") or not AH.IsOpen() then return false end
    Setup()
    if not panel then return false end
    if not panel:IsShown() then ShowGuildPride(false) end
    ShowMode("search")
    CloseDetail()
    offset = 0
    if not AH.SearchItems(ids) then return false end
    searchNeed = need or {}
    shop.searchTitle = title
    RefreshList()
    return true
end

-- Fortschritt der Item-Suche im Status zeigen
AH.onMultiUpdate = function(st)
    if not (panel and panel:IsShown() and mode == "search" and st) then return end
    RefreshList()
    local title = shop.searchTitle and (shop.searchTitle .. ": ") or ""
    if not st.done then
        Status(title .. (L["suche %d von %d …"]):format(st.total - #st.queue, st.total))
        return
    end
    local names = {}
    for _, id in ipairs(st.missing) do names[#names + 1] = AH.ItemName(id) or ("#" .. id) end
    Status(title .. (#names == 0 and L["alles gefunden."]
        or (L["nicht im Auktionshaus: %s"]):format(table.concat(names, ", "))))
end

-- Einkaufslisten wurden von außen geändert (Berufsfenster)
function AH.ListsChanged()
    if panel and panel:IsShown() and mode == "list" then RefreshShop() end
end

local function OnBrowse()
    if panel and panel:IsShown() and mode == "search" then
        if not AH.MultiState() then Status(#AH.BrowseRows() == 0 and L["Nichts gefunden."] or "") end
        RefreshList()
    end
end
AH.Listen("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", OnBrowse)
AH.Listen("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", OnBrowse)
AH.Listen("ITEM_KEY_ITEM_INFO_RECEIVED", function() if panel and panel:IsShown() then RefreshList() end end)
AH.Listen("GET_ITEM_INFO_RECEIVED", function() if panel and panel:IsShown() and mode == "list" then RefreshShop() end end)

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
    AH.MarkPosted(p.info.key)          -- kommt es zurück, wird es unter „Verkaufen“ markiert
    if panel then
        ClearSell(); Status(L["Eingestellt."]); RefreshBags()
        if sell.returning and C_Timer then C_Timer.After(0.3, NextReturned) end   -- Taschen erst aktualisieren lassen
    end
end)

AH.Listen("AUCTION_HOUSE_CLOSED", function()
    buy.pending, buy.confirm, own.confirm = nil, nil, nil
    RestoreBlizzard()   -- zuerst, damit das Ausblenden unten das Auktionshaus nicht erneut schließt
    if panel then panel:Hide() end
    sell.pending = nil
end)
