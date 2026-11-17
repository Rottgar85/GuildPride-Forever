-- GuildPride Auktionshaus: eigener Reiter „GuildPride“ im neuen Auktionshaus
-- (C_AuctionHouse, WoW Forever) mit Suchen, Verkaufen und Scanner.
-- Gekauft wird über Blizzards Kaufansicht (Klick auf eine Zeile).
local ADDON, GP = ...
local AH = GP.AH
local L = GP.L or setmetatable({}, { __index = function(_, k) return k end })

local ROWS, ROW_H = 16, 22
local DURATIONS = { { 1, "12" }, { 2, "24" }, { 3, "48" } }   -- Blizzard-Dauer-Index → Stunden

local tab, panel, setupError
local mode = "search"            -- "search" | "sell" | "scan"
local rows, offset = {}, 0
local sell = { duration = 2 }    -- info, manual, setting, pending

local function Skin(b) if GP.SkinButton then GP.SkinButton(b) end return b end
local function EditSkin(e) if GP.SkinEditBox then GP.SkinEditBox(e) end return e end
local function Money(c) return GetCoinTextureString(math.max(0, math.floor(c or 0))) end

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
            row.icon:SetTexture(e.icon or (GetItemIcon and GetItemIcon(e.itemKey.itemID)) or nil)
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
    if AH.ModernBrowse(text) then Status(L["Suche läuft …"]) end
end

local function HidePanel()
    if panel and panel:IsShown() then
        panel:Hide()
        if tab then PanelTemplates_DeselectTab(tab) end
    end
end

-- Zeile anklicken: Blizzards Kaufansicht für dieses Item öffnen
local function OpenBuy(row)
    local e = row.entry
    if not e then return end
    HidePanel()
    if AuctionHouseFrame.SelectBrowseResult then
        local ok = pcall(AuctionHouseFrame.SelectBrowseResult, AuctionHouseFrame, e.result)
        if ok then return end
    end
    AH.Print(L["Auktionshaus: Bitte im Reiter „Kaufen“ nach dem Item suchen."])
end

local function MakeSearchPane()
    local p = CreateFrame("Frame", nil, panel)
    p:SetAllPoints()
    local box = Edit(p, 260)
    box:SetPoint("TOPLEFT", 14, -44)
    local go = Button(p, L["Suchen"], 100)
    go:SetPoint("LEFT", box, "RIGHT", 8, 0)
    go:SetScript("OnClick", function() box:ClearFocus(); StartSearch(box:GetText()) end)
    box:SetScript("OnEnterPressed", function() box:ClearFocus(); StartSearch(box:GetText()) end)
    local hint = Label(p, L["Klick auf eine Zeile öffnet Blizzards Kaufansicht."], "GameFontDisableSmall")
    hint:SetPoint("LEFT", go, "RIGHT", 12, 0)

    local head = Label(p, L["Item"], "GameFontNormalSmall"); head:SetPoint("TOPLEFT", 40, -72)
    local headP = Label(p, L["Stückpreis"], "GameFontNormalSmall"); headP:SetPoint("TOPLEFT", 330, -72)
    p.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, p)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 12, -88 - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", p, "RIGHT", -12, 0)
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

local function SetPrice(copper)
    sell.setting = true
    MoneyInputFrame_SetCopper(panel.sell.price, copper or 0)
    sell.setting = nil
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
    s.itemName:SetText(L["Item aus den Taschen hierher ziehen"])
    s.tag:SetText(""); s.deposit:SetText(""); s.single:SetText(""); s.qtyRow:Hide()
    SetPrice(0)
end

local function DropItem()
    local loc = C_Cursor and C_Cursor.GetCursorItem and C_Cursor.GetCursorItem()
    local info = loc and AH.SellInfo(loc)
    ClearCursor()
    if not info then return end
    local s = panel.sell
    sell.info, sell.manual = info, nil
    AH.lastSeen[info.key] = nil          -- nur frische Angebote zählen
    s.item.icon:SetTexture(GetItemIcon and GetItemIcon(info.itemID) or nil)
    s.itemName:SetText(info.link or ("#" .. info.itemID))
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
    AH.RequestPrice(info)
end

local function Post()
    local info = sell.info
    if not info then return end
    local unit, qty = MoneyInputFrame_GetCopper(panel.sell.price), Qty()
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

local function MakeSellPane()
    local p = CreateFrame("Frame", nil, panel)
    p:SetAllPoints()
    local item = CreateFrame("Button", nil, p)
    item:SetSize(40, 40); item:SetPoint("TOPLEFT", 16, -48)
    item:SetNormalTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
    item.icon = item:CreateTexture(nil, "ARTWORK"); item.icon:SetAllPoints()
    item:RegisterForDrag("LeftButton")
    item:SetScript("OnReceiveDrag", DropItem)
    item:SetScript("OnClick", function() if GetCursorInfo() then DropItem() end end)
    p.item = item
    p.itemName = Label(p, L["Item aus den Taschen hierher ziehen"]); p.itemName:SetPoint("LEFT", item, "RIGHT", 12, 0)

    local y = -108
    local function Row(text)
        local fs = Label(p, text); fs:SetPoint("TOPLEFT", 16, y); y = y - 34
        return fs
    end
    local priceLabel = Row(L["Stückpreis"])
    local price = CreateFrame("Frame", "GuildPrideAHModernPrice", p, "MoneyInputFrameTemplate")
    price:SetPoint("LEFT", priceLabel, "LEFT", 120, 0)
    MoneyInputFrame_SetOnValueChangedFunc(price, function()
        if not sell.setting then sell.manual = true end
    end)
    p.price = price
    p.tag = Label(p, "", "GameFontDisableSmall"); p.tag:SetPoint("LEFT", priceLabel, "LEFT", 320, 0)

    p.qtyRow = CreateFrame("Frame", nil, p)
    p.qtyRow:SetSize(400, 24); p.qtyRow:SetPoint("TOPLEFT", 16, y + 6)
    local qtyLabel = Label(p.qtyRow, L["Menge"]); qtyLabel:SetPoint("LEFT")
    p.qty = Edit(p.qtyRow, 60, true); p.qty:SetPoint("LEFT", 126, 0)
    p.qty:SetScript("OnTextChanged", UpdateDeposit)
    p.max = Label(p.qtyRow, "", "GameFontDisableSmall"); p.max:SetPoint("LEFT", p.qty, "RIGHT", 10, 0)
    p.qtyRow:Hide()
    p.single = Label(p, "", "GameFontDisableSmall"); p.single:SetPoint("TOPLEFT", 16, y)
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
    p.deposit = Label(p, "", "GameFontHighlightSmall"); p.deposit:SetPoint("TOPLEFT", 16, y)
    local post = Button(p, L["Einstellen"], 140)
    post:SetPoint("TOPLEFT", 16, y - 30)
    post:SetScript("OnClick", Post)
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
    local p = CreateFrame("Frame", nil, panel)
    p:SetAllPoints()
    local text = Label(p, L["Der Komplett-Scan liest das ganze Auktionshaus auf einmal (Blizzard erlaubt das alle 15 Minuten). Die Preise stehen danach im Item-Tooltip und beim Verkaufen; andere GuildPride-Spieler bekommen sie auf Nachfrage."], "GameFontHighlight")
    text:SetPoint("TOPLEFT", 16, -48); text:SetPoint("RIGHT", p, "RIGHT", -16, 0)
    p.go = Button(p, L["Komplett-Scan starten"], 200)
    p.go:SetPoint("TOPLEFT", 16, -110)
    p.go:SetScript("OnClick", function()
        if AH.FullScan() then Status(L["Auktionshaus: Komplett-Scan läuft …"]) end
        RefreshScan()
    end)
    p.state = Label(p, ""); p.state:SetPoint("LEFT", p.go, "RIGHT", 16, 0)
    p.last = Label(p, "", "GameFontHighlightSmall"); p.last:SetPoint("TOPLEFT", 16, -150)
    p.known = Label(p, "", "GameFontHighlightSmall"); p.known:SetPoint("TOPLEFT", 16, -172)
    p.share = Label(p, "", "GameFontHighlightSmall"); p.share:SetPoint("TOPLEFT", 16, -194)
    local tick = 0
    p:SetScript("OnUpdate", function(_, el)
        tick = tick + el
        if tick >= 1 then tick = 0; RefreshScan() end
    end)
    return p
end

---------------------------------------------------------------------
-- Reiter im Auktionshaus
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
    if m == "search" then RefreshList() elseif m == "scan" then RefreshScan() end
end

local function ShowPanel()
    for _, t in ipairs(AuctionHouseFrame.Tabs or {}) do PanelTemplates_DeselectTab(t) end
    PanelTemplates_SelectTab(tab)
    panel:Show()
    ShowMode(mode)
end

local function MakeTab()
    local tabs = AuctionHouseFrame.Tabs or {}
    local last = tabs[#tabs]
    for _, tpl in ipairs({ "AuctionHouseFrameDisplayModeTabTemplate", "PanelTabButtonTemplate", "CharacterFrameTabButtonTemplate" }) do
        local ok, t = pcall(CreateFrame, "Button", "GuildPrideAHTab", AuctionHouseFrame, tpl)
        if ok and t then tab = t; break end
    end
    if not tab then return false end
    tab:SetText("GuildPride")
    if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
    if last then tab:SetPoint("LEFT", last, "RIGHT", -15, 0)
    else tab:SetPoint("TOPLEFT", AuctionHouseFrame, "BOTTOMLEFT", 20, 2) end
    tab:SetScript("OnClick", function()
        if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
        ShowPanel()
    end)
    PanelTemplates_DeselectTab(tab)
    -- Andere Reiter oder Blizzards Ansichtswechsel blenden unseren Reiter aus.
    -- Die Vorlage trägt unseren Reiter selbst in AuctionHouseFrame.Tabs ein: ihn auslassen,
    -- sonst schließt der Klick auf „GuildPride“ das Fenster sofort wieder.
    for _, t in ipairs(tabs) do
        if t ~= tab then t:HookScript("OnClick", HidePanel) end
    end
    if AuctionHouseFrame.SetDisplayMode then hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", HidePanel) end
    return true
end

local function Build()
    if not MakeTab() then return end

    panel = CreateFrame("Frame", nil, AuctionHouseFrame, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", 4, -24)
    panel:SetPoint("BOTTOMRIGHT", -4, 4)
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    panel:SetBackdropColor(0.05, 0.05, 0.07, 0.97)
    -- Sicher über Blizzards Listen liegen (die haben teils hohe Ebenen)
    panel:SetFrameStrata("HIGH")
    panel:SetFrameLevel(AuctionHouseFrame:GetFrameLevel() + 100)
    panel:EnableMouse(true)
    panel:Hide()
    panel.modeSearch = Button(panel, L["Suchen"], 110); panel.modeSearch:SetPoint("TOPLEFT", 14, -10)
    panel.modeSell = Button(panel, L["Verkaufen"], 110); panel.modeSell:SetPoint("LEFT", panel.modeSearch, "RIGHT", 8, 0)
    panel.modeScan = Button(panel, L["Scanner"], 110); panel.modeScan:SetPoint("LEFT", panel.modeSell, "RIGHT", 8, 0)
    panel.modeSearch:SetScript("OnClick", function() ShowMode("search") end)
    panel.modeSell:SetScript("OnClick", function() ShowMode("sell") end)
    panel.modeScan:SetScript("OnClick", function() ShowMode("scan") end)
    panel.status = Label(panel, "", "GameFontHighlightSmall"); panel.status:SetPoint("LEFT", panel.modeScan, "RIGHT", 16, 0)
    panel.search = MakeSearchPane()
    panel.sell = MakeSellPane()
    panel.scan = MakeScanPane()
    ClearSell()
    ShowMode(mode)
end

local function Setup()
    if tab or setupError or not AuctionHouseFrame or not AH.IsModern() or not AH.Opt("ahTab") then return end
    local ok, err = pcall(Build)
    if not ok then
        setupError = tostring(err)
        AH.Print((L["Auktionshaus: Reiter „GuildPride“ konnte nicht aufgebaut werden: %s"]):format(setupError))
    end
end

-- Zustand für /gp ah status
function AH.ModernTabState()
    if not AH.IsModern() then return nil end
    if setupError then return (L["Fehler: %s"]):format(setupError) end
    if not tab then return AH.Opt("ahTab") and L["noch nicht aufgebaut (Auktionshaus öffnen)"] or L["aus"] end
    return panel and (panel:IsShown() and L["offen"] or L["bereit"]) or L["unvollständig"]
end

function AH._ModernTab() return tab, panel end   -- für Tests und /gp ah status

-- Nach den anderen Addons (z. B. Auctionator) aufbauen, damit der Reiter ganz rechts sitzt
AH.Listen("AUCTION_HOUSE_SHOW", function() C_Timer.After(0.2, Setup) end)

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
    if panel and panel:IsShown() and mode == "sell" and sell.info then ApplySuggestion() end
end
AH.Listen("COMMODITY_SEARCH_RESULTS_UPDATED", OnSellPrice)
AH.Listen("ITEM_SEARCH_RESULTS_UPDATED", OnSellPrice)

AH.Listen("AUCTION_HOUSE_POST_WARNING", function()
    if sell.pending then StaticPopup_Show("GUILDPRIDE_AH_POST_WARNING") end
end)
AH.Listen("AUCTION_HOUSE_AUCTION_CREATED", function()
    local p = sell.pending
    if not p then return end
    -- Den zuvor gesehenen Marktpreis teilen (der eigene Einstellpreis zählt nie)
    AH.Share({ p.info.key })
    if panel then ClearSell(); Status(L["Eingestellt."]) end
end)

AH.Listen("AUCTION_HOUSE_CLOSED", function()
    if panel then panel:Hide() end
    sell.pending = nil
end)
