-- GuildPride: DKP (Punkte für Anwesenheit und Bosse, Abzug für Loot)
-- Jede Buchung ist ein Eintrag im Gilden-Buch, das alle mit GuildPride
-- abgleichen (Addon-Nachrichten). Der Punktestand ist die Summe aller nicht
-- zurückgenommenen Buchungen. Zusätzlich geht jede Buchung als "[GP] DKP ..."-
-- Zeile an Discord (GuildPrideDiscord.lua), wo GameBot dasselbe Buch führt.
-- Buchen dürfen nur Offiziere (wer die Gildennachricht ändern darf).
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP or "\031"

local DKP = {}
ns.DKP = DKP

local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local function Clean(s, max) return (tostring(s or ""):gsub("[%c|,:]", "")):sub(1, max or 60) end
local function CanManage() return CanEditMOTD and CanEditMOTD() end
local function Now() return GetServerTime() end

local function Book() return ns.GuildTable("dkp") end   -- [id] = { d, r, by, t, n = {names}, x = void }

---------------------------------------------------------------------
-- Stände
---------------------------------------------------------------------
local cache
function DKP.Standings()
    if cache then return cache end
    cache = {}
    -- In zeitlicher Reihenfolge: Verfall wirkt auf den Stand zu seinem Zeitpunkt
    local list = {}
    for id, tx in pairs(Book()) do if not tx.x then list[#list + 1] = { id, tx } end end
    table.sort(list, function(a, b)
        if (a[2].t or 0) ~= (b[2].t or 0) then return (a[2].t or 0) < (b[2].t or 0) end
        -- gleiche Sekunde: Verfall nach den Buchungen
        local da, db = a[2].k == "decay", b[2].k == "decay"
        if da ~= db then return db end
        return a[1] < b[1]
    end)
    for _, it in ipairs(list) do
        local tx = it[2]
        if tx.k == "decay" then
            for name, pts in pairs(cache) do
                if pts > 0 then cache[name] = math.floor(pts * (100 - (tx.d or 0)) / 100) end
            end
        elseif tx.n then
            for _, name in ipairs(tx.n) do cache[name] = (cache[name] or 0) + (tx.d or 0) end
        end
    end
    return cache
end
local function Changed()
    cache = nil
    if DKP.Refresh then DKP.Refresh() end
end

function DKP.Of(name) return DKP.Standings()[name] end

---------------------------------------------------------------------
-- Abgleich
---------------------------------------------------------------------
local function SendTx(id, tx, target)
    ns.Queue("DKP", target, id, tx.d, tx.r, tx.by, tx.t, tx.x and 1 or 0, table.concat(tx.n or {}, ","), tx.k or "")
end

local function Apply(id, d, r, by, t, x, names, k)
    if id == "" or not d or not names then return end
    local book = Book()
    local cur = book[id]
    if cur then
        if x and not cur.x then cur.x = true; Changed() end
        return
    end
    book[id] = { d = d, r = r, by = by, t = t, x = x or nil, n = names, k = (k == "decay") and k or nil }
    Changed()
end

ns.On("DKP", function(payload, sender)
    if sender == ns.Me() or not ns.IsGuildMember(sender) then return end
    -- Buchen und Zurücknehmen dürfen nur Offiziere. Direkt von einem Offizier:
    -- sofort übernehmen. Abgleich über andere Mitglieder: erst, wenn zwei
    -- verschiedene genau dieselbe Buchung melden (ein manipuliertes Addon allein
    -- kann so keine Punkte erfinden oder Buchungen löschen).
    if not ns.IsOfficerName(sender) and not ns.Confirmed("DKP\030" .. payload, sender) then return end
    local a = { strsplit(SEP, payload) }
    local d = ns.Num(a[2], -100000, 100000)
    local names = {}
    for n in (a[7] or ""):gmatch("[^,]+") do
        n = Clean(n, 60)
        if n ~= "" and #names < 80 then names[#names + 1] = n end
    end
    local k = a[8] == "decay" and "decay" or nil
    if k and (not d or d < 1 or d > 50) then return end
    Apply(Clean(a[1], 20), d, Clean(a[3], 60), Clean(a[4], 60), ns.Stamp(a[5]), a[6] == "1", names, k)
end)

local function SendAll(target)
    for id, tx in pairs(Book()) do SendTx(id, tx, target) end
end
for _, k in ipairs({ "REQ", "DKPQ" }) do
    ns.On(k, function(_, sender)
        if sender == ns.Me() then return end
        C_Timer.After(1 + math.random() * 4, function() SendAll(sender) end)
    end)
end

---------------------------------------------------------------------
-- Buchen (nur aus Klicks heraus aufrufen)
---------------------------------------------------------------------
local function NewId()
    local chars, out = "0123456789abcdefghijklmnopqrstuvwxyz", ""
    for _ = 1, 6 do local r = math.random(1, 36); out = out .. chars:sub(r, r) end
    return out
end

local function Short(name) return Ambiguate(name or "", "guild") end

local function PostDiscord(id, d, r, names)
    if not ns.Discord then return end
    local head = ("DKP #%s %+d %s: "):format(id, d, r)
    local chunks, cur = {}, {}
    for _, n in ipairs(names) do
        local test = head .. table.concat(cur, ", ") .. (#cur > 0 and ", " or "") .. Short(n)
        if #cur > 0 and #test > 230 then chunks[#chunks + 1] = cur; cur = {} end
        cur[#cur + 1] = Short(n)
    end
    if #cur > 0 then chunks[#chunks + 1] = cur end
    for i, c in ipairs(chunks) do
        local tag = #chunks > 1 and ("DKP #%s(%d/%d)"):format(id, i, #chunks) or ("DKP #%s"):format(id)
        ns.Discord.Post(("%s %+d %s: %s"):format(tag, d, r, table.concat(c, ", ")), i == 1)
    end
end

local seq = 0
function DKP.Award(names, d, reason, dropId)
    if not CanManage() then ns.Print(L["Nur Offiziere dürfen DKP buchen."]); return end
    d = math.floor(tonumber(d) or 0)
    if d == 0 or #names == 0 then return end
    reason = tostring(reason or "")
    reason = reason:gsub("|c%x%x%x%x%x%x%x%x|H.-|h%[(.-)%]|h|r", "%1")   -- Item-Links -> Name
    local id, r = NewId(), Clean(reason, 40)
    if r == "" then r = d > 0 and L["Bonus"] or L["Abzug"] end
    Apply(id, d, r, ns.Me(), Now(), false, names)
    seq = seq + 1
    Book()[id].s = seq   -- Reihenfolge eigener Buchungen (gleiche Sekunde)
    SendTx(id, Book()[id])
    PostDiscord(id, d, r, names)
    ns.Print((L["DKP gebucht: %+d %s für %d Spieler"]):format(d, r, #names))
    if dropId and d < 0 and #names == 1 then DKP.MarkDrop(dropId, names[1], -d) end
end

-- Verfall: alle positiven Stände um pct Prozent senken
function DKP.Decay(pct)
    if not CanManage() then ns.Print(L["Nur Offiziere dürfen DKP buchen."]); return end
    pct = math.floor(tonumber(pct) or 0)
    if pct < 1 or pct > 50 then return end
    local id = NewId()
    Apply(id, pct, L["Verfall"], ns.Me(), Now(), false, {}, "decay")
    seq = seq + 1
    Book()[id].s = seq
    SendTx(id, Book()[id])
    if ns.Discord then ns.Discord.Post(("DKP #%s %s -%d%%"):format(id, ns.IS_GERMAN and "Verfall" or "Decay", pct), true) end
    ns.Print((L["DKP-Verfall: -%d%% für alle"]):format(pct))
end

function DKP.Undo()
    if not CanManage() then return end
    local lastId, last
    for id, tx in pairs(Book()) do
        if not tx.x and tx.by == ns.Me() and (not last or (tx.t or 0) > (last.t or 0)
            or ((tx.t or 0) == (last.t or 0) and (tx.s or 0) > (last.s or 0))) then lastId, last = id, tx end
    end
    if not last then ns.Print(L["Keine eigene Buchung zum Zurücknehmen."]); return end
    last.x = true
    Changed()
    SendTx(lastId, last)
    if ns.Discord then ns.Discord.Post(("DKP #%s %s"):format(lastId, ns.IS_GERMAN and "zurückgenommen" or "undone"), true) end
    ns.Print((L["Zurückgenommen: %+d %s"]):format(last.k == "decay" and -last.d or last.d, last.r or ""))
end

-- Alle im Raid bzw. in der Gruppe (inkl. mir)
function DKP.GroupNames()
    local names = {}
    local function add(unit)
        if not UnitExists(unit) then return end
        local n, s = UnitFullName(unit)
        if not n or Secret(n) then return end
        if Secret(s) then s = nil end
        names[#names + 1] = ns.Normalize((s and s ~= "") and (n .. "-" .. s) or n)
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do add("raid" .. i) end
    else
        add("player")
        for i = 1, GetNumSubgroupMembers() do add("party" .. i) end
    end
    return names
end

function DKP.TargetName()
    if not UnitIsPlayer("target") then return end
    local n, s = UnitFullName("target")
    if not n or Secret(n) then return end
    if Secret(s) then s = nil end
    return ns.Normalize((s and s ~= "") and (n .. "-" .. s) or n)
end

---------------------------------------------------------------------
-- Tooltip: "DKP: 125" bei Spielern
---------------------------------------------------------------------
local function OnUnitTooltip(tip)
    if not GuildPrideDB or not IsInGuild() then return end
    local ok, _, unit = pcall(tip.GetUnit, tip)
    if not ok or not unit or Secret(unit) or not UnitIsPlayer(unit) then return end
    local n, s = UnitFullName(unit)
    if not n or Secret(n) or Secret(s) then return end
    local pts = DKP.Of(ns.Normalize((s and s ~= "") and (n .. "-" .. s) or n))
    if pts then tip:AddLine(("|cffffd100DKP:|r %d"):format(pts)) end
end
if TooltipDataProcessor and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
end

---------------------------------------------------------------------
-- Drops: epische (und bessere) Items aus dem Raid, für alle mit GuildPride
-- gleich. Der Offizier klickt einen Drop an, vergibt ihn ("Loot an Ziel" oder
-- Bieterrunde) und der Gewinner steht danach mit Preis in der Liste.
---------------------------------------------------------------------
local MIN_QUALITY = 4   -- episch
local function Drops() return ns.GuildTable("drops") end   -- Liste { id, link, t, winner, price }

local function LinkQuality(link)
    local q = link and C_Item and C_Item.GetItemQualityByID and select(1, C_Item.GetItemQualityByID(link))
    if not q and link and GetItemInfo then q = select(3, GetItemInfo(link)) end
    if not q and link then
        -- Farbe im Link: ff a335ee = episch, ff ff8000 = legendär
        local c = link:match("|c(%x%x%x%x%x%x%x%x)")
        if c == "ffa335ee" then q = 4 elseif c == "ffff8000" then q = 5 end
    end
    return q
end

local function AddDrop(id, link, t)
    local list = Drops()
    for _, d in ipairs(list) do if d.id == id then return end end
    table.insert(list, 1, { id = id, link = link, t = t })
    while #list > 40 do table.remove(list) end
    -- Wer in der Gruppe wünscht sich das Item? (GuildPrideWishlist.lua)
    if ns.WishDrop then pcall(ns.WishDrop, link) end
    if DKP.Refresh then DKP.Refresh() end
end

-- Gleicher Drop bei mehreren Mitgliedern: gleiche ID aus Link + Minute
local function DropId(link)
    local item = link:match("item:(%d+)") or "0"
    return item .. "-" .. math.floor(GetServerTime() / 120)
end

local function SawDrop(link)
    if type(link) ~= "string" or Secret(link) or not link:find("item:") then return end
    if (LinkQuality(link) or 0) < MIN_QUALITY then return end
    if not IsInGroup() then return end
    local id = DropId(link)
    for _, d in ipairs(Drops()) do if d.id == id and d.link == link then return end end
    AddDrop(id, link, GetServerTime())
    ns.Queue("DRP", nil, id, link)
end

ns.On("DRP", function(payload, sender)
    if sender == ns.Me() or not ns.IsGuildMember(sender) then return end
    local id, link = strsplit(SEP, payload)
    if id and link and link:find("item:") and #link < 300 then AddDrop(Clean(id, 30), link, GetServerTime()) end
end)

function DKP.MarkDrop(id, winner, price, fromOther)
    for _, d in ipairs(Drops()) do
        if d.id == id then
            d.winner, d.price = winner, price
            if not fromOther then ns.Queue("DRW", nil, id, winner, price) end
            if DKP.Refresh then DKP.Refresh() end
            return
        end
    end
end
ns.On("DRW", function(payload, sender)
    if sender == ns.Me() or not ns.IsOfficerName(sender) then return end
    local id, winner, price = strsplit(SEP, payload)
    DKP.MarkDrop(Clean(id, 30), Clean(winner, 60), ns.Num(price, 0, 100000) or 0, true)
end)

local dropFrame = CreateFrame("Frame")
dropFrame:RegisterEvent("LOOT_OPENED")
dropFrame:RegisterEvent("START_LOOT_ROLL")
pcall(dropFrame.RegisterEvent, dropFrame, "ENCOUNTER_LOOT_RECEIVED")
dropFrame:SetScript("OnEvent", function(_, event, ...)
    if not GuildPrideDB or not IsInGuild() then return end
    if event == "LOOT_OPENED" then
        for i = 1, (GetNumLootItems and GetNumLootItems() or 0) do
            SawDrop(GetLootSlotLink and GetLootSlotLink(i))
        end
    elseif event == "START_LOOT_ROLL" then
        local rollID = ...
        SawDrop(GetLootRollItemLink and GetLootRollItemLink(rollID))
    elseif event == "ENCOUNTER_LOOT_RECEIVED" then
        local _, _, link = ...
        SawDrop(link)
    end
end)

---------------------------------------------------------------------
-- Fenster: /gp dkp
---------------------------------------------------------------------
local win
local function Button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    if ns.SkinButton then pcall(ns.SkinButton, b) end
    return b
end
local function Edit(parent, w, text)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(w, 20)
    e:SetAutoFocus(false)
    e:SetText(text or "")
    if ns.SkinEditBox then pcall(ns.SkinEditBox, e) end
    return e
end

local function Build()
    win = CreateFrame("Frame", "GuildPrideDKPFrame", UIParent, "BasicFrameTemplateWithInset")
    win:SetSize(600, 520)
    win:SetPoint("CENTER")
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetFrameStrata("DIALOG")
    tinsert(UISpecialFrames, "GuildPrideDKPFrame")
    win.title = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    win.title:SetPoint("TOP", 0, -5)
    win.title:SetText("GuildPride – DKP")

    local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -30)
    scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMLEFT", 270, 225)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(280, 10)
    scroll:SetScrollChild(content)
    win.list = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.list:SetPoint("TOPLEFT")
    win.list:SetWidth(280)
    win.list:SetJustifyH("LEFT")
    win.content = content

    -- Rechte Seite: Drops
    local dTitle = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dTitle:SetPoint("TOPLEFT", 300, -30); dTitle:SetText(L["Drops (anklicken zum Vergeben)"])
    local dScroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    dScroll:SetPoint("TOPLEFT", 300, -48)
    dScroll:SetPoint("BOTTOMRIGHT", -32, 12)
    local dContent = CreateFrame("Frame", nil, dScroll)
    dContent:SetSize(260, 10)
    dScroll:SetScrollChild(dContent)
    win.dContent, win.dRows = dContent, {}

    -- Offiziers-Bereich
    local box = CreateFrame("Frame", nil, win)
    box:SetPoint("BOTTOMLEFT", 12, 10)
    box:SetWidth(316)
    box:SetHeight(210)
    win.officer = box

    local lAmt = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lAmt:SetPoint("TOPLEFT", 0, 0); lAmt:SetText(L["Punkte"])
    win.amount = Edit(box, 50, "10"); win.amount:SetPoint("TOPLEFT", 6, -14)
    local lReason = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lReason:SetPoint("TOPLEFT", 70, 0); lReason:SetText(L["Grund / Item"])
    win.reason = Edit(box, 230, L["Anwesenheit"]); win.reason:SetPoint("TOPLEFT", 76, -14)

    local function amount() return tonumber(win.amount:GetText()) or 0 end
    local function reason() return win.reason:GetText() end

    local bRaid = Button(box, L["An Raid/Gruppe"], 150, function()
        DKP.Award(DKP.GroupNames(), amount(), reason())
    end)
    bRaid:SetPoint("TOPLEFT", 0, -42)
    local bTarget = Button(box, L["An Ziel"], 150, function()
        local n = DKP.TargetName()
        if not n then ns.Print(L["Bitte zuerst einen Spieler anvisieren."]); return end
        DKP.Award({ n }, amount(), reason())
    end)
    bTarget:SetPoint("TOPRIGHT", 0, -42)

    local bBoss = Button(box, L["Boss-Kill (+5 Raid)"], 150, function()
        DKP.Award(DKP.GroupNames(), 5, L["Boss"])
    end)
    bBoss:SetPoint("TOPLEFT", 0, -68)
    local bLoot = Button(box, L["Loot an Ziel (abziehen)"], 150, function()
        local n = DKP.TargetName()
        if not n then ns.Print(L["Bitte zuerst einen Spieler anvisieren."]); return end
        local a = math.abs(amount())
        DKP.Award({ n }, -a, L["Loot"] .. " " .. reason(), DKP.selectedDrop)
    end)
    bLoot:SetPoint("TOPRIGHT", 0, -68)

    local bUndo = Button(box, L["Letzte Buchung zurücknehmen"], 150, function() DKP.Undo() end)
    bUndo:SetPoint("TOPLEFT", 0, -98)
    local bDecay = Button(box, L["Verfall -10 %"], 150, function() StaticPopup_Show("GUILDPRIDE_DKP_DECAY") end)
    bDecay:SetPoint("TOPRIGHT", 0, -98)

    local bAuction = Button(box, L["Bieterrunde (30 s)"], 150, function()
        if ns.Raid then ns.Raid.Start(reason(), amount()) end
    end)
    bAuction:SetPoint("TOPLEFT", 0, -128)
    local bSummary = Button(box, L["Raid-Zusammenfassung"], 150, function()
        if ns.Raid then ns.Raid.SendSummary() end
    end)
    bSummary:SetPoint("TOPRIGHT", 0, -128)

    local bLog = Button(box, L["Protokoll …"], 150, function() DKP.ToggleLog() end)
    bLog:SetPoint("TOPLEFT", 0, -158)

    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 0, -188); hint:SetWidth(316); hint:SetJustifyH("LEFT")
    hint:SetText(L["Loot: Item als Grund eintragen (oder mit Umschalt+Klick verlinken), Preis bzw. Mindestgebot als Punkte. „Loot an Ziel“ für festen Preis, „Bieterrunde“ zum Bieten."])

    -- Umschalt+Klick auf ein Item fügt den Link ins Feld "Grund / Item" ein
    hooksecurefunc("ChatEdit_InsertLink", function(link)
        if link and win.reason:HasFocus() then win.reason:Insert(link) end
    end)

    if ns.SkinAll then pcall(ns.SkinAll, win) end
end

function DKP.Refresh()
    if not win or not win:IsShown() then return end
    local rows = {}
    for name, pts in pairs(DKP.Standings()) do rows[#rows + 1] = { name, pts } end
    table.sort(rows, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    local lines = {}
    for i, r in ipairs(rows) do
        lines[#lines + 1] = ("%2d.  %s  |cffffd100%d|r"):format(i, Short(r[1]), r[2])
    end
    win.list:SetText(#lines > 0 and table.concat(lines, "\n") or L["Noch keine DKP-Buchungen."])
    win.content:SetHeight(win.list:GetStringHeight() + 10)
    win.officer:SetShown(CanManage())

    -- Drops
    local list = Drops()
    for i, d in ipairs(list) do
        local row = win.dRows[i]
        if not row then
            row = CreateFrame("Button", nil, win.dContent)
            row:SetSize(260, 30)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * 32)
            row.hl = row:CreateTexture(nil, "BACKGROUND")
            row.hl:SetAllPoints(); row.hl:SetColorTexture(1, 0.82, 0, 0.18)
            row.item = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.item:SetPoint("TOPLEFT", 4, -2); row.item:SetWidth(252); row.item:SetJustifyH("LEFT")
            row.who = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.who:SetPoint("TOPLEFT", 4, -16); row.who:SetWidth(252); row.who:SetJustifyH("LEFT")
            row:SetScript("OnEnter", function(self)
                if not self.link then return end
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row:SetScript("OnClick", function(self)
                if IsModifiedClick("CHATLINK") and self.link then ChatEdit_InsertLink(self.link) return end
                DKP.selectedDrop = self.dropId
                win.reason:SetText(self.link or "")
                DKP.Refresh()
            end)
            win.dRows[i] = row
        end
        row.link, row.dropId = d.link, d.id
        row.item:SetText(d.link)
        if d.winner then
            row.who:SetText(("|cff40ff40→ %s|r  (%d DKP)"):format(Short(d.winner), d.price or 0))
        else
            row.who:SetText(L["noch nicht vergeben"])
        end
        row.hl:SetShown(DKP.selectedDrop == d.id)
        row:Show()
    end
    for i = #list + 1, #win.dRows do win.dRows[i]:Hide() end
    win.dContent:SetHeight(math.max(10, #list * 32))
end

function DKP.Toggle()
    if not win then Build() end
    if win:IsShown() then win:Hide() return end
    win:Show()
    DKP.Refresh()
    ns.Queue("DKPQ", nil, "1")
end

---------------------------------------------------------------------
-- Protokoll: jede Buchung mit Wer, Wann, Wie viel, Warum und für wen.
-- Offiziere können jede einzelne Buchung zurücknehmen (nicht nur die letzte).
---------------------------------------------------------------------
function DKP.Void(id)
    if not CanManage() then ns.Print(L["Nur Offiziere dürfen DKP buchen."]); return end
    local tx = Book()[id]
    if not tx or tx.x then return end
    tx.x = true
    Changed()
    SendTx(id, tx)
    if ns.Discord then ns.Discord.Post(("DKP #%s %s"):format(id, ns.IS_GERMAN and "zurückgenommen" or "undone"), true) end
    ns.Print((L["Zurückgenommen: %+d %s"]):format(tx.k == "decay" and -tx.d or tx.d, tx.r or ""))
    if DKP.RefreshLog then DKP.RefreshLog() end
end

StaticPopupDialogs["GUILDPRIDE_DKP_VOID"] = {
    text = L["Diese Buchung zurücknehmen?\n%s"],
    button1 = YES, button2 = NO,
    OnAccept = function(_, id) DKP.Void(id) end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local logWin
local LOG_ROWS, LOG_ROW_H = 300, 22

local function LogLine(tx)
    local pts = tx.k == "decay" and ("-%d %%"):format(tx.d or 0) or ("%+d"):format(tx.d or 0)
    local color = tx.x and "|cff777777" or ((tx.k == "decay" or (tx.d or 0) < 0) and "|cffff8060" or "|cff60ff60")
    local who = tx.k == "decay" and L["alle"] or (#(tx.n or {}) == 1 and Short(tx.n[1]) or (L["%d Spieler"]):format(#(tx.n or {})))
    return ("%s  %s%s|r  %s  |cffcccccc%s|r  |cff999999%s %s|r%s"):format(
        date("%d.%m. %H:%M", tx.t or 0), color, pts, who, tx.r or "", L["von"], Short(tx.by),
        tx.x and ("  |cffff4040" .. L["zurückgenommen"] .. "|r") or "")
end

local function BuildLog()
    logWin = CreateFrame("Frame", "GuildPrideDKPLogFrame", UIParent, "BasicFrameTemplateWithInset")
    logWin:SetSize(620, 460)
    logWin:SetPoint("CENTER", 40, -20)
    logWin:SetFrameStrata("DIALOG")
    logWin:SetMovable(true); logWin:EnableMouse(true)
    logWin:RegisterForDrag("LeftButton")
    logWin:SetScript("OnDragStart", logWin.StartMoving)
    logWin:SetScript("OnDragStop", logWin.StopMovingOrSizing)
    tinsert(UISpecialFrames, "GuildPrideDKPLogFrame")
    local title = logWin:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
    title:SetText(L["DKP-Protokoll"])

    logWin.search = CreateFrame("EditBox", nil, logWin, "InputBoxTemplate")
    logWin.search:SetSize(200, 20); logWin.search:SetPoint("TOPLEFT", 16, -30)
    logWin.search:SetAutoFocus(false)
    logWin.search:SetScript("OnTextChanged", function() DKP.RefreshLog() end)
    logWin.search:SetScript("OnEscapePressed", logWin.search.ClearFocus)
    local sl = logWin:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sl:SetPoint("LEFT", logWin.search, "RIGHT", 8, 0)
    sl:SetText(L["Suche: Name, Grund oder Offizier"])

    local scroll = CreateFrame("ScrollFrame", nil, logWin, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -56); scroll:SetPoint("BOTTOMRIGHT", -32, 12)
    logWin.content = CreateFrame("Frame", nil, scroll)
    logWin.content:SetSize(560, 10)
    scroll:SetScrollChild(logWin.content)
    logWin.rows = {}
    if ns.SkinWindow then pcall(ns.SkinWindow, logWin) end
end

local function LogRow(i)
    local row = logWin.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, logWin.content)
    row:SetSize(560, LOG_ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * LOG_ROW_H)
    row:EnableMouse(true)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 4, 0); row.text:SetPoint("RIGHT", -96, 0)
    row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(false)
    row.void = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.void:SetSize(90, 18); row.void:SetPoint("RIGHT")
    row.void:SetText(L["Zurücknehmen"])
    row.void:SetScript("OnClick", function()
        if row.id then StaticPopup_Show("GUILDPRIDE_DKP_VOID", LogLine(Book()[row.id]), nil, row.id) end
    end)
    -- Tooltip: alle Spieler der Buchung
    row:SetScript("OnEnter", function(self)
        local tx = self.id and Book()[self.id]
        if not tx or not tx.n or #tx.n == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(("#%s  %s"):format(self.id, tx.r or ""))
        for _, n in ipairs(tx.n) do GameTooltip:AddLine(Short(n), 1, 1, 1) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    logWin.rows[i] = row
    return row
end

function DKP.RefreshLog()
    if not (logWin and logWin:IsShown()) then return end
    local q = strtrim(logWin.search:GetText() or ""):lower()
    local list = {}
    for id, tx in pairs(Book()) do
        local hay = ((tx.r or "") .. " " .. (tx.by or "") .. " " .. table.concat(tx.n or {}, " ")):lower()
        if q == "" or hay:find(q, 1, true) then list[#list + 1] = { id = id, tx = tx } end
    end
    table.sort(list, function(a, b)
        if (a.tx.t or 0) ~= (b.tx.t or 0) then return (a.tx.t or 0) > (b.tx.t or 0) end
        return a.id > b.id
    end)
    local n = math.min(#list, LOG_ROWS)
    local can = CanManage()
    for i = 1, n do
        local row, it = LogRow(i), list[i]
        row.id = it.id
        row.text:SetText(LogLine(it.tx))
        row.void:SetShown(can and not it.tx.x)
        row:Show()
    end
    for i = n + 1, #logWin.rows do logWin.rows[i]:Hide() end
    logWin.content:SetHeight(math.max(10, n * LOG_ROW_H))
end

function DKP.ToggleLog()
    if not logWin then BuildLog() end
    logWin:SetShown(not logWin:IsShown())
    DKP.RefreshLog()
end

-- Neue oder geänderte Buchungen: Protokoll mitziehen
local refresh = DKP.Refresh
DKP.Refresh = function(...)
    if refresh then refresh(...) end
    if DKP.RefreshLog then DKP.RefreshLog() end
end

StaticPopupDialogs["GUILDPRIDE_DKP_DECAY"] = {
    text = L["Alle positiven DKP-Stände um 10 % senken?"],
    button1 = YES, button2 = NO,
    OnAccept = function() DKP.Decay(10) end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local slash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    if strtrim(arg or ""):lower() == "dkp" then return DKP.Toggle() end
    return slash(arg)
end
