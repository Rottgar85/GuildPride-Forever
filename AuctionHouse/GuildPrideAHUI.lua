-- GuildPride Auktionshaus: eigener Reiter „GuildPride“ mit Suchen/Kaufen und Verkaufen
-- Nur ohne Auctionator und wenn der Reiter in den Einstellungen an ist.
local ADDON, GP = ...
local AH = GP.AH
local L = GP.L or setmetatable({}, { __index = function(_, k) return k end })

local ROWS, ROW_H = 12, 20
local DURATIONS = { { 1, "2" }, { 2, "8" }, { 3, "24" } }   -- Blizzard-Dauer-Index → Stunden

local panel, tabID
local mode = "search"          -- "search" | "sell"
local results, list, offset = {}, {}, 0
local detailKey                -- gewähltes Item in der Suche (zeigt Einzelangebote)
local sell = { duration = 2 }  -- link, key, name, manual

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
    return fs
end

---------------------------------------------------------------------
-- Suchen
---------------------------------------------------------------------
local RefreshList

local function SortedResults()
    local out = {}
    for key, r in pairs(results) do out[#out + 1] = { key = key, r = r } end
    table.sort(out, function(a, b)
        if (a.r.min or math.huge) ~= (b.r.min or math.huge) then return (a.r.min or math.huge) < (b.r.min or math.huge) end
        return a.r.name < b.r.name
    end)
    return out
end

local function SortedOffers(r)
    local me, out = UnitName("player"), {}
    for _, o in ipairs(r.offers) do
        if o.buyout > 0 then
            out[#out + 1] = { o = o, unit = math.floor(o.buyout / o.count), mine = o.owner == me }
        end
    end
    table.sort(out, function(a, b) return a.unit < b.unit end)
    return out
end

local function StartSearch(text)
    if AH.Searching() then AH.CancelSearch() end
    detailKey, offset = nil, 0
    panel.status:SetText(L["Suche läuft …"])
    AH.Search(text, function(res)
        results = res
        local n = 0
        for _ in pairs(res) do n = n + 1 end
        panel.status:SetText(n == 0 and L["Nichts gefunden."] or "")
        RefreshList()
    end)
end

-- Angebot in der aktuell geladenen Ergebnisseite wiederfinden (Index kann veraltet sein)
local function FindOffer(name, o)
    local n = GetNumAuctionItems("list") or 0
    for i = 1, n do
        local nm, _, count, _, _, _, _, _, _, buyout, _, _, _, owner = GetAuctionItemInfo("list", i)
        if nm == name and count == o.count and buyout == o.buyout and owner == o.owner then return i end
    end
end

-- Kaufen mit Rückfrage (wie Blizzard); OnAccept ist ebenfalls ein Klick-Ereignis
StaticPopupDialogs["GUILDPRIDE_AH_BUY"] = {
    text = L["%s kaufen für %s?"],
    button1 = YES, button2 = NO,
    OnAccept = function(_, data)
        local i = FindOffer(data.name, data.o)
        if not i then AH.Print(L["Auktionshaus: Angebot nicht mehr da – suche neu."]); return end
        PlaceAuctionBid("list", i, data.o.buyout)
        data.o.bought = true      -- Zeile bleibt stehen, Knopf aus: kein Doppelkauf
        RefreshList()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function Buy(row)
    local entry = row.entry
    if not entry or not entry.offer or entry.offer.o.bought then return end
    local r, o = results[detailKey], entry.offer.o
    if not r then return end
    if not FindOffer(r.name, o) then
        -- Angebot steht auf einer anderen Ergebnisseite: diese laden, dann erneut klicken
        if o.page and AH.LoadPage(r.name, o.page) then
            panel.status:SetText(L["Seite wird geladen – bitte noch einmal auf Kaufen klicken."])
        else
            AH.Print(L["Auktionshaus: Angebot nicht mehr da – suche neu."])
            StartSearch(r.name)
        end
        return
    end
    local dlg = StaticPopup_Show("GUILDPRIDE_AH_BUY", ("%s x%d"):format(r.name, o.count), Money(o.buyout))
    if dlg then dlg.data = { name = r.name, o = o } end
end

local function MakeSearchPane()
    local p = CreateFrame("Frame", nil, panel)
    p:SetAllPoints()
    local box = Edit(p, 220)
    box:SetPoint("TOPLEFT", 8, -40)
    local go = Button(p, L["Suchen"], 90)
    go:SetPoint("LEFT", box, "RIGHT", 8, 0)
    go:SetScript("OnClick", function() box:ClearFocus(); StartSearch(box:GetText()) end)
    box:SetScript("OnEnterPressed", function() box:ClearFocus(); StartSearch(box:GetText()) end)
    local back = Button(p, L["Zurück"], 90)
    back:SetPoint("LEFT", go, "RIGHT", 8, 0)
    back:SetScript("OnClick", function() detailKey, offset = nil, 0; RefreshList() end)
    p.back = back

    p.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, p)
        row:SetSize(560, ROW_H)
        row:SetPoint("TOPLEFT", 8, -68 - (i - 1) * ROW_H)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(ROW_H - 2, ROW_H - 2); row.icon:SetPoint("LEFT")
        row.name = Label(row, "", "GameFontHighlightSmall"); row.name:SetPoint("LEFT", 24, 0); row.name:SetWidth(250); row.name:SetJustifyH("LEFT")
        row.price = Label(row, "", "GameFontHighlightSmall"); row.price:SetPoint("LEFT", 280, 0); row.price:SetWidth(130); row.price:SetJustifyH("RIGHT")
        row.info = Label(row, "", "GameFontDisableSmall"); row.info:SetPoint("LEFT", 420, 0); row.info:SetWidth(140); row.info:SetJustifyH("LEFT")
        row.buy = Button(row, L["Kaufen"], 70); row.buy:SetPoint("RIGHT", 70, 0)
        row.buy:SetScript("OnClick", function() Buy(row) end)
        row:SetScript("OnClick", function()
            if row.entry and row.entry.key then detailKey, offset = row.entry.key, 0; RefreshList() end
        end)
        row:SetScript("OnEnter", function()
            local link = row.entry and row.entry.link
            if link then GameTooltip:SetOwner(row, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(link); GameTooltip:Show() end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p.rows[i] = row
    end
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", function(_, d)
        offset = math.max(0, math.min(offset - d * 3, math.max(0, #list - ROWS)))
        RefreshList()
    end)
    return p
end

RefreshList = function()
    local p = panel and panel.search
    if not p then return end
    list = {}
    local r = detailKey and results[detailKey]
    if r then
        for _, of in ipairs(SortedOffers(r)) do
            list[#list + 1] = { offer = of, link = r.link, name = r.name }
        end
    else
        detailKey = nil
        for _, e in ipairs(SortedResults()) do
            list[#list + 1] = { key = e.key, link = e.r.link, name = e.r.name, r = e.r }
        end
    end
    p.back:SetShown(r ~= nil)
    for i, row in ipairs(p.rows) do
        local e = list[offset + i]
        row.entry = e
        if not e then row:Hide() else
            row:Show()
            row.icon:SetTexture(AH.ItemIcon(e.link))
            if e.offer then
                local o = e.offer.o
                row.name:SetText(("%s  x%d"):format(e.name, o.count))
                row.price:SetText(Money(e.offer.unit))
                row.info:SetText(e.offer.mine and L["eigenes Angebot"] or (o.owner or ""))
                row.buy:SetShown(not e.offer.mine and o.buyout > 0)
                row.buy:SetEnabled(not o.bought)
                if o.bought then row.info:SetText(L["gekauft"]) end
            else
                row.name:SetText(e.link or e.name)
                row.price:SetText(e.r.min and Money(e.r.min) or "-")
                row.info:SetText((L["%d Angebote, %d Stück"]):format(e.r.n, e.r.qty))
                row.buy:Hide()
            end
        end
    end
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
    if tag == "fresh" then return "" end
    return L["kein Preis bekannt"]
end

local function SetPrice(copper)
    sell.setting = true
    MoneyInputFrame_SetCopper(panel.sell.price, copper or 0)
    sell.setting = nil
end

local function UpdateDeposit()
    local s = panel.sell
    local stacks = tonumber(s.stacks:GetText()) or 1
    local dep = CalculateAuctionDeposit and select(2, pcall(CalculateAuctionDeposit, sell.duration)) or nil
    s.deposit:SetText(type(dep) == "number" and (L["Einzahlung: %s"]):format(Money(dep * stacks)) or "")
end

local function ApplySuggestion(freshMin)
    local p, tag = AH.Suggest(sell.key, freshMin, GetServerTime())
    if not sell.manual then SetPrice(p) end
    panel.sell.tag:SetText(TagText(p and tag, sell.key))
end

local function LoadSellItem()
    local name, tex, count, _, _, _, _, stackCount, totalCount, itemID = GetAuctionSellItemInfo()
    local s = panel.sell
    if not name then
        sell.link, sell.key, sell.name = nil, nil, nil
        s.item.icon:SetTexture(nil); s.itemName:SetText(L["Item hierher ziehen"])
        s.tag:SetText(""); s.deposit:SetText("")
        return
    end
    if sell.name == name then UpdateDeposit(); return end   -- dasselbe Item: Eingaben behalten
    -- Item kam über Blizzards Feld statt über unseres: Link passt nicht → nur Item-ID
    if sell.link and AH.ItemName(sell.link) ~= name then sell.link = nil end
    if not sell.link then sell.key = itemID and AH.Key(itemID) or nil end
    sell.name = name
    s.item.icon:SetTexture(tex)
    s.itemName:SetText(sell.link or name)
    s.size:SetText(tostring(math.max(1, count or stackCount or 1)))
    local per = math.max(1, count or 1)
    s.stacks:SetText(tostring(math.max(1, math.floor((totalCount or per) / per))))
    sell.manual = nil
    ApplySuggestion(nil)
    UpdateDeposit()
    if sell.key and not AH.AuctionatorLoaded() then
        AH.Search(name, function(res)
            if sell.name ~= name then return end
            local r = res[sell.key]
            ApplySuggestion(r and r.min)
        end)
    end
end

local function DropItem()
    local kind, _, link = GetCursorInfo()
    if kind ~= "item" then return end
    sell.link = link
    sell.key = AH.KeyFromLink(link)
    ClickAuctionSellItemButton()
    ClearCursor()
end

local function Post()
    local s = panel.sell
    if not sell.name then return end
    local unit = MoneyInputFrame_GetCopper(s.price)
    local size = tonumber(s.size:GetText()) or 1
    local stacks = tonumber(s.stacks:GetText()) or 1
    if unit < 1 or size < 1 or stacks < 1 then
        AH.Print(L["Auktionshaus: Preis, Stapelgröße und Stapel angeben."])
        return
    end
    local buyout = unit * size
    PostAuction(buyout, buyout, sell.duration, size, stacks)   -- direkt im OnClick
    if sell.key then AH.Share({ sell.key }) end
end

local function MakeSellPane()
    local p = CreateFrame("Frame", nil, panel)
    p:SetAllPoints()
    local item = CreateFrame("Button", nil, p)
    item:SetSize(37, 37); item:SetPoint("TOPLEFT", 12, -44)
    item:SetNormalTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
    item.icon = item:CreateTexture(nil, "ARTWORK"); item.icon:SetAllPoints()
    item:RegisterForDrag("LeftButton")
    item:SetScript("OnReceiveDrag", DropItem)
    item:SetScript("OnClick", function() if GetCursorInfo() then DropItem() else ClickAuctionSellItemButton() end end)
    p.item = item
    p.itemName = Label(p, L["Item hierher ziehen"]); p.itemName:SetPoint("LEFT", item, "RIGHT", 10, 0)

    local y = -100
    local function Row(text)
        local fs = Label(p, text); fs:SetPoint("TOPLEFT", 12, y); y = y - 30
        return fs
    end
    local priceLabel = Row(L["Stückpreis"])
    local price = CreateFrame("Frame", "GuildPrideAHPrice", p, "MoneyInputFrameTemplate")
    price:SetPoint("LEFT", priceLabel, "LEFT", 110, 0)
    MoneyInputFrame_SetOnValueChangedFunc(price, function()
        if not sell.setting then sell.manual = true end
    end)
    p.price = price
    p.tag = Label(p, "", "GameFontDisableSmall"); p.tag:SetPoint("LEFT", priceLabel, "LEFT", 300, 0)

    local sizeLabel = Row(L["Stapelgröße"])
    p.size = Edit(p, 50, true); p.size:SetPoint("LEFT", sizeLabel, "LEFT", 116, 0)
    local stacksLabel = Row(L["Stapel"])
    p.stacks = Edit(p, 50, true); p.stacks:SetPoint("LEFT", stacksLabel, "LEFT", 116, 0)
    p.stacks:SetScript("OnTextChanged", UpdateDeposit)

    local durLabel = Row(L["Dauer"])
    p.dur = {}
    for i, d in ipairs(DURATIONS) do
        local b = Button(p, (L["%s Std."]):format(d[2]), 70)
        b:SetPoint("LEFT", durLabel, "LEFT", 110 + (i - 1) * 76, 0)
        b:SetScript("OnClick", function()
            sell.duration = d[1]
            for j, o in ipairs(p.dur) do o:SetEnabled(j ~= i) end
            UpdateDeposit()
        end)
        b:SetEnabled(d[1] ~= sell.duration)
        p.dur[i] = b
    end
    p.deposit = Label(p, "", "GameFontHighlightSmall"); p.deposit:SetPoint("TOPLEFT", 12, y)
    local post = Button(p, L["Einstellen"], 120)
    post:SetPoint("TOPLEFT", 12, y - 30)
    post:SetScript("OnClick", Post)
    return p
end

---------------------------------------------------------------------
-- Reiter im Auktionshaus
---------------------------------------------------------------------
local function ShowMode(m)
    mode = m
    panel.search:SetShown(m == "search")
    panel.sell:SetShown(m == "sell")
    panel.modeSearch:SetEnabled(m ~= "search")
    panel.modeSell:SetEnabled(m ~= "sell")
    -- Rechtsklick in den Taschen: beim Verkaufen ins Verkaufsfeld, sonst nichts benutzen
    if SetAuctionsTabShowing and panel:IsShown() then SetAuctionsTabShowing(m == "sell") end
    if m == "sell" then LoadSellItem() else RefreshList() end
end

local function Setup()
    if tabID or not AuctionFrame or not AH.Opt("ahTab") or AH.AuctionatorLoaded() then return end
    local n = (AuctionFrame.numTabs or 3) + 1
    local prev = _G["AuctionFrameTab" .. (n - 1)]
    local ok, tab = pcall(CreateFrame, "Button", "AuctionFrameTab" .. n, AuctionFrame, "AuctionTabTemplate")
    if not ok or not tab then tab = CreateFrame("Button", "AuctionFrameTab" .. n, AuctionFrame, "CharacterFrameTabButtonTemplate") end
    tab:SetID(n)
    tab:SetText("GuildPride")
    if prev then tab:SetPoint("LEFT", prev, "RIGHT", -15, 0) end
    PanelTemplates_SetNumTabs(AuctionFrame, n)
    PanelTemplates_EnableTab(AuctionFrame, n)
    tabID = n

    panel = CreateFrame("Frame", nil, AuctionFrame, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", 20, -70)
    panel:SetPoint("BOTTOMRIGHT", -12, 36)
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    panel:SetBackdropColor(0.05, 0.05, 0.07, 0.96)
    panel:SetFrameLevel(AuctionFrame:GetFrameLevel() + 20)
    panel:EnableMouse(true)
    panel:Hide()
    panel.modeSearch = Button(panel, L["Suchen"], 110); panel.modeSearch:SetPoint("TOPLEFT", 8, -8)
    panel.modeSell = Button(panel, L["Verkaufen"], 110); panel.modeSell:SetPoint("LEFT", panel.modeSearch, "RIGHT", 8, 0)
    panel.modeSearch:SetScript("OnClick", function() ShowMode("search") end)
    panel.modeSell:SetScript("OnClick", function() ShowMode("sell") end)
    panel.status = Label(panel, "", "GameFontHighlightSmall"); panel.status:SetPoint("LEFT", panel.modeSell, "RIGHT", 16, 0)
    panel.search = MakeSearchPane()
    panel.sell = MakeSellPane()
    ShowMode(mode)

    hooksecurefunc("AuctionFrameTab_OnClick", function(self)
        local id = self and self.GetID and self:GetID()
        if id == tabID then
            if AuctionFrameBrowse then AuctionFrameBrowse:Hide() end
            if AuctionFrameBid then AuctionFrameBid:Hide() end
            if AuctionFrameAuctions then AuctionFrameAuctions:Hide() end
            panel:Show()
            ShowMode(mode)
        else
            panel:Hide()
        end
    end)
end

AH.Listen("ADDON_LOADED", function(name) if name == "Blizzard_AuctionUI" then Setup() end end)
AH.Listen("PLAYER_LOGIN", Setup)
AH.Listen("AUCTION_HOUSE_SHOW", Setup)
AH.Listen("NEW_AUCTION_UPDATE", function()
    if panel and panel:IsShown() and mode == "sell" then LoadSellItem() end
end)
AH.Listen("AUCTION_HOUSE_CLOSED", function()
    if panel then panel:Hide() end
    results, list, detailKey, offset = {}, {}, nil, 0
    sell.link, sell.key, sell.name, sell.manual = nil, nil, nil, nil
end)

---------------------------------------------------------------------
-- /gp ah · /gp ah status · /gp ah scan
---------------------------------------------------------------------
local origSlash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd = strtrim(arg or ""):lower()
    if cmd == "ah" then
        AH.Print(L["/gp ah status – Kanal und Zähler · /gp ah scan – ganzes Auktionshaus lesen (offenes AH, ohne Auctionator)"])
        if AH.IsModern() then
            AH.Print(L["/gp ah fenster – GuildPride-Fenster öffnen oder schließen (Auktionshaus offen)"])
            AH.Print(L["/gp ah aus – nur Blizzards Auktionshaus nutzen · /gp ah an – GuildPride-Fenster wieder nutzen"])
        end
    elseif cmd == "ah status" then
        local st, id, atr = AH.stats, AH.ChannelId(), AH.AuctionatorLoaded()
        AH.Print(L["Preise teilen: "] .. (AH.Opt("ahShare") and L["an"] or L["aus"])
            .. "  ·  " .. (L["Kanal %s: %s"]):format(AH.CHANNEL, id and ("#" .. id) or L["nicht beigetreten"]))
        AH.Print((L["Gesendet: %d · Empfangen: %d · Verworfen: %d"]):format(st.sent, st.received, st.dropped)
            .. "  ·  Auctionator: " .. (atr and L["ja"] or L["nein"])
            .. (atr and (" (" .. L["mitlesen: "] .. (AH.Opt("ahReadAuctionator") and L["an"] or L["aus"]) .. ")") or ""))
        local tabState = AH.ModernTabState and AH.ModernTabState()
        if tabState then AH.Print(L["GuildPride-Fenster: "] .. tabState) end
    elseif (cmd == "ah aus" or cmd == "ah off" or cmd == "ah an" or cmd == "ah on") and AH.SetModernUI then
        local on = cmd == "ah an" or cmd == "ah on"
        AH.SetModernUI(on)
        AH.Print(on and L["Auktionshaus: GuildPride-Fenster ist wieder an."]
            or L["Auktionshaus: GuildPride-Fenster ist aus, du nutzt Blizzards Auktionshaus. Wieder an: /gp ah an"])
    elseif cmd == "ah fenster" or cmd == "ah window" then
        if not (AH.ToggleWindow and AH.ToggleWindow()) then AH.Print(L["Auktionshaus: Erst das Auktionshaus öffnen."]) end
    elseif cmd == "ah scan" then
        if AH.AuctionatorLoaded() and not AH.IsModern() then
            AH.Print(L["Auktionshaus: Mit Auctionator bitte dessen Scan nutzen – GuildPride liest mit."])
        elseif not AH.IsOpen() then
            AH.Print(L["Auktionshaus: Erst das Auktionshaus öffnen."])
        elseif AH.FullScan() then
            AH.Print(L["Auktionshaus: Komplett-Scan läuft …"])
        else
            AH.Print(L["Auktionshaus: Komplett-Scan gerade nicht erlaubt (Blizzard erlaubt ihn nur alle 15 Minuten)."])
        end
    else
        origSlash(arg)
    end
end
