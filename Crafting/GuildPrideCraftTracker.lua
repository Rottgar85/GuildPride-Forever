-- GuildPride Handwerk: Item-Tracker
-- Kleines Fenster, das zählt, was du sammelst: „Kupfererz 12 / 20“ mit Balken, je Rezept
-- gruppiert (−/+ ändert die Anzahl Herstellungen, alle Zutaten folgen). Gezählt werden
-- Taschen und Bank. Ist ein Ziel erreicht, sagt der Chat Bescheid. Am Auktionshaus sucht
-- ein Klick auf eine Zeile das Item, „Fehlendes suchen“ alles auf einmal.
-- Gespeichert je Charakter: GuildPrideDB.craftTrack[Name] = { recipes = { [Rezept] = Anzahl },
--                                                            items = { [itemID] = Ziel }, done = { [itemID] = true } }
local ADDON, ns = ...
local L = ns.L
local Craft = ns.Craft

local Track = {}
ns.CraftTrack = Track

local ROWS, ROW_H, WIDTH = 16, 18, 260

local function DB()
    if type(GuildPrideDB) ~= "table" then return { recipes = {}, items = {}, done = {} } end
    GuildPrideDB.craftTrack = type(GuildPrideDB.craftTrack) == "table" and GuildPrideDB.craftTrack or {}
    local me = Craft.Me()
    local d = GuildPrideDB.craftTrack[me]
    if type(d) ~= "table" then d = {}; GuildPrideDB.craftTrack[me] = d end
    d.recipes = type(d.recipes) == "table" and d.recipes or {}
    d.items = type(d.items) == "table" and d.items or {}
    d.done = type(d.done) == "table" and d.done or {}
    return d
end
Track.DB = DB

---------------------------------------------------------------------
-- Daten
---------------------------------------------------------------------
-- Rezept tracken (crafts Herstellungen; 0 = entfernen)
function Track.AddRecipe(id, crafts)
    id = tonumber(id)
    if not id then return false end
    crafts = math.max(0, math.floor(tonumber(crafts) or 1))
    local d = DB()
    d.recipes[id] = crafts > 0 and math.min(999, (d.recipes[id] or 0) + crafts) or nil
    wipe(d.done)
    Track.Refresh(true)
    return true
end

function Track.SetRecipe(id, crafts)
    local d = DB()
    crafts = math.floor(tonumber(crafts) or 0)
    d.recipes[id] = crafts > 0 and math.min(999, crafts) or nil
    wipe(d.done)
    Track.Refresh()
end

function Track.AddItem(id, goal)
    id = tonumber(id)
    if not id then return false end
    local d = DB()
    d.items[id] = math.min(9999, math.max(1, (d.items[id] or 0) + math.floor(tonumber(goal) or 1)))
    d.done[id] = nil
    Track.Refresh(true)
    return true
end

function Track.SetItem(id, goal)
    local d = DB()
    goal = math.floor(tonumber(goal) or 0)
    d.items[id] = goal > 0 and math.min(9999, goal) or nil
    d.done[id] = nil
    Track.Refresh()
end

function Track.Clear()
    local d = DB()
    wipe(d.recipes); wipe(d.items); wipe(d.done)
    Track.Refresh()
end

-- Gesamtbedarf: { [itemID] = Menge } (Rezepte × Zutaten + einzelne Items)
function Track.Needs()
    local d, need = DB(), {}
    for id, crafts in pairs(d.recipes) do
        for _, r in ipairs(Craft.Reagents(id) or {}) do
            need[r[1]] = (need[r[1]] or 0) + r[2] * crafts
        end
    end
    for id, goal in pairs(d.items) do need[id] = (need[id] or 0) + goal end
    return need
end

function Track.Have(id)
    local bags, bank = Craft.Count(id)
    return bags + bank
end

-- Was fehlt noch? { [itemID] = Menge }, Anzahl Items
function Track.Missing()
    local out, n = {}, 0
    for id, want in pairs(Track.Needs()) do
        local m = want - Track.Have(id)
        if m > 0 then out[id] = m; n = n + 1 end
    end
    return out, n
end

function Track.IsEmpty()
    local d = DB()
    return next(d.recipes) == nil and next(d.items) == nil
end

-- Zeilen fürs Fenster: Kopf je Rezept, darunter seine Zutaten; dann einzelne Items
function Track.Lines()
    local d, lines = DB(), {}
    local recs = {}
    for id in pairs(d.recipes) do recs[#recs + 1] = id end
    table.sort(recs, function(a, b) return Craft.RecipeName(a) < Craft.RecipeName(b) end)
    for _, id in ipairs(recs) do
        local crafts = d.recipes[id]
        lines[#lines + 1] = { head = true, recipe = id, crafts = crafts }
        local r = Craft.Reagents(id)
        if not r then
            lines[#lines + 1] = { note = L["Zutaten unbekannt – Berufsfenster einmal öffnen."] }
        else
            for _, x in ipairs(r) do
                lines[#lines + 1] = { item = x[1], want = x[2] * crafts }
            end
        end
    end
    local items = {}
    for id in pairs(d.items) do items[#items + 1] = id end
    table.sort(items, function(a, b) return Craft.ItemName(a) < Craft.ItemName(b) end)
    if #items > 0 then
        lines[#lines + 1] = { head = true, title = L["Einzelne Items"] }
        for _, id in ipairs(items) do lines[#lines + 1] = { item = id, want = d.items[id], single = true } end
    end
    return lines
end

---------------------------------------------------------------------
-- Nacheinander herstellen: jeder Klick stellt das nächste getrackte Rezept her
-- (so viele, wie getrackt und mit deinen Zutaten möglich). Zwischenprodukte zuerst –
-- wer Barren für ein anderes getracktes Rezept schmilzt, schmilzt vor dem Schmieden.
-- Jede fertige Herstellung zählt den Tracker um eins runter.
---------------------------------------------------------------------
function Track.CraftOrder()
    local d = DB()
    local ids, feeds = {}, {}
    for id in pairs(d.recipes) do ids[#ids + 1] = id end
    -- liefert id etwas, das ein anderes getracktes Rezept braucht?
    for _, id in ipairs(ids) do
        local out = Craft.OutputItem and Craft.OutputItem(id)
        if out then
            for _, other in ipairs(ids) do
                if other ~= id then
                    for _, x in ipairs(Craft.KnownReagents(other) or {}) do
                        if x[1] == out then feeds[id] = true end
                    end
                end
            end
        end
    end
    table.sort(ids, function(a, b)
        if (feeds[a] or false) ~= (feeds[b] or false) then return feeds[a] == true end
        return Craft.RecipeName(a) < Craft.RecipeName(b)
    end)
    return ids
end

-- Wie oft geht es gerade? Live aus dem Berufsfenster, sonst nach deinen Taschen
-- (Forever meldet numAvailable nicht immer richtig: deshalb zählt auch, was deine Taschen hergeben)
local function Possible(id)
    local info = Craft.RecipeInfo(id)
    local live = tonumber(info and info.numAvailable) or 0
    local bags = tonumber(Craft.CanCraft(id)) or 0
    return math.max(live, bags), info and info.learned, info
end

-- Gehört das Rezept zum offenen Beruf? (gemerkte Rezeptliste oder das Spiel kennt es gelernt)
local function InOpenProfession(id, line, info)
    local all = type(GuildPrideDB) == "table" and type(GuildPrideDB.craftAll) == "table" and GuildPrideDB.craftAll[line]
    if type(all) == "table" and all[id] then return true end
    return info ~= nil and info.learned == true
end

-- Nächstes herstellbares Rezept im offenen Berufsfenster: id, Anzahl – sonst nil, Grund
function Track.NextCraft()
    local d = DB()
    if next(d.recipes) == nil then return nil, L["Im Tracker steht kein Rezept."] end
    local line = Craft.OpenLine()
    if not line then return nil, L["Öffne das Berufsfenster, dann geht es los."] end
    local missing, unlearned
    for _, id in ipairs(Track.CraftOrder()) do
        local can, learned, info = Possible(id)
        if InOpenProfession(id, line, info) then
            if learned == false then
                unlearned = unlearned or id
            elseif can > 0 then
                return id, math.min(can, d.recipes[id])
            else
                missing = missing or id
            end
        end
    end
    if missing then return nil, (L["Für %s fehlen dir Zutaten."]):format(Craft.RecipeName(missing)) end
    if unlearned then return nil, (L["%s kannst du noch nicht – erst beim Lehrer lernen."]):format(Craft.RecipeName(unlearned)) end
    return nil, L["Keins der getrackten Rezepte gehört zu diesem Beruf."]
end

-- Für /gp handwerk diag: warum der Herstellen-Knopf (nicht) geht
function Track.CraftDiag()
    local line = Craft.OpenLine()
    local id, why = Track.NextCraft()
    ns.Print(("Tracker diag: line=%s next=%s %s"):format(tostring(line), tostring(id), tostring(why or "")))
    for _, rid in ipairs(Track.CraftOrder()) do
        local info = Craft.RecipeInfo(rid)
        ns.Print(("  %s (%s): info=%s learned=%s numAvailable=%s taschen=%s hier=%s"):format(
            Craft.RecipeName(rid), tostring(rid), tostring(info ~= nil), tostring(info and info.learned),
            tostring(info and info.numAvailable), tostring(Craft.CanCraft(rid)),
            tostring(line and InOpenProfession(rid, line, info) or false)))
    end
end

function Track.CraftNext()
    local id, n = Track.NextCraft()
    if not id then ns.Print(n); return false end
    local T = C_TradeSkillUI
    if not (T and T.CraftRecipe) then return false end
    local ok = pcall(T.CraftRecipe, id, n)
    if ok then ns.Print((L["Stelle her: %d× %s"]):format(n, Craft.RecipeName(id))) end
    return ok
end

-- fertige Herstellung: Tracker zählt runter
function Track.Crafted(id)
    local d = DB()
    if not d.recipes[id] then return false end
    local left = d.recipes[id] - 1
    d.recipes[id] = left > 0 and left or nil
    if left <= 0 then ns.Print((L["Tracker: %s fertig."]):format(Craft.RecipeName(id))) end
    Track.Refresh()
    return true
end

-- Ziel erreicht? Einmal im Chat melden
local function CheckDone()
    local d = DB()
    for id, want in pairs(Track.Needs()) do
        local have = Track.Have(id)
        if have >= want and not d.done[id] then
            d.done[id] = true
            ns.Print((L["Tracker: %s erreicht (%d/%d)."]):format(Craft.ItemName(id), have, want))
        elseif have < want then
            d.done[id] = nil
        end
    end
end
Track.CheckDone = CheckDone

---------------------------------------------------------------------
-- Auktionshaus: GuildPride-Suche, sonst Auctionator, sonst Hinweis
---------------------------------------------------------------------
function Track.Search(ids, need, title)
    local AH = ns.AH
    if AH and AH.IsOpen and AH.IsOpen() and AH.ShowItemSearch and AH.ShowItemSearch(ids, need, title) then
        return true
    end
    local A = Auctionator and Auctionator.API and Auctionator.API.v1
    if A and A.MultiSearch and AuctionHouseFrame and AuctionHouseFrame:IsShown() then
        local names = {}
        for _, id in ipairs(ids) do names[#names + 1] = Craft.ItemName(id) end
        local ok = pcall(A.MultiSearch, "GuildPride", names)
        if ok then return true end
    end
    ns.Print(L["Tracker: Erst das Auktionshaus öffnen."])
    return false
end

function Track.SearchMissing()
    local miss = Track.Missing()
    local ids = {}
    for id in pairs(miss) do ids[#ids + 1] = id end
    if #ids == 0 then ns.Print(L["Tracker: Es fehlt nichts."]); return false end
    return Track.Search(ids, miss, L["Tracker"])
end

---------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------
local win
local function SmallButton(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 18)
    b:SetText(text)
    if ns.SkinButton then ns.SkinButton(b) end
    b:SetScript("OnClick", onClick)
    return b
end

local function Build()
    win = CreateFrame("Frame", "GuildPrideCraftTracker", UIParent, "BackdropTemplate")
    win:SetSize(WIDTH, 122 + ROWS * ROW_H)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        GuildPrideDB.craftTrackPos = { p, rp, x, y }
    end)
    if ns.SkinDialog then ns.SkinDialog(win) end
    local pos = type(GuildPrideDB) == "table" and GuildPrideDB.craftTrackPos
    if type(pos) == "table" then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else win:SetPoint("RIGHT", UIParent, "RIGHT", -60, 40) end
    win:Hide()

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText(L["Tracker"])
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    if ns.SkinClose then ns.SkinClose(close) end
    close:SetScript("OnClick", function() win:Hide(); GuildPrideDB.craftTrackShown = false end)

    win.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, win)
        r:SetSize(WIDTH - 20, ROW_H)
        r:SetPoint("TOPLEFT", 10, -30 - (i - 1) * ROW_H)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(14, 14); r.icon:SetPoint("LEFT", 2, 0)
        r.bar = r:CreateTexture(nil, "BACKGROUND")
        r.bar:SetPoint("LEFT", 0, 0); r.bar:SetHeight(ROW_H - 2)
        r.bar:SetColorTexture(0.2, 0.5, 0.2, 0.35)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
        r.text:SetPoint("RIGHT", -60, 0)
        r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
        r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.count:SetPoint("RIGHT", -2, 0)
        r.minus = SmallButton(r, "-", 18, function()
            local l = r.line
            if l and l.recipe then Track.SetRecipe(l.recipe, l.crafts - (IsShiftKeyDown() and 10 or 1)) end
        end)
        r.minus:SetPoint("RIGHT", -42, 0)
        r.plus = SmallButton(r, "+", 18, function()
            local l = r.line
            if l and l.recipe then Track.SetRecipe(l.recipe, l.crafts + (IsShiftKeyDown() and 10 or 1)) end
        end)
        r.plus:SetPoint("LEFT", r.minus, "RIGHT", 2, 0)
        r.del = SmallButton(r, "x", 18, function()
            local l = r.line
            if l and l.recipe then Track.SetRecipe(l.recipe, 0) end
        end)
        r.del:SetPoint("LEFT", r.plus, "RIGHT", 2, 0)
        r:SetScript("OnClick", function(_, button)
            local l = r.line
            if not (l and l.item) then return end
            if button == "RightButton" and l.single then
                Track.SetItem(l.item, 0)
            else
                local have = Track.Have(l.item)
                Track.Search({ l.item }, { [l.item] = math.max(0, l.want - have) }, Craft.ItemName(l.item))
            end
        end)
        r:SetScript("OnEnter", function(self)
            local l = self.line
            if not (l and l.item) then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            if GameTooltip.SetItemByID then GameTooltip:SetItemByID(l.item) else GameTooltip:SetHyperlink("item:" .. l.item) end
            local bags, bank = Craft.Count(l.item)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine((L["Taschen %d · Bank %d"]):format(bags, bank), 1, 1, 1)
            local where = ns.CraftVendor and ns.CraftVendor.Where(l.item)
            if where then GameTooltip:AddLine((L["Händler: %s"]):format(where), 0.6, 0.8, 1, true) end
            local alts, sum = Craft.AltCounts(l.item)
            if sum > 0 then
                for i = 1, math.min(4, #alts) do GameTooltip:AddLine(("%s: %d"):format(alts[i].name, alts[i].n), 0.7, 0.8, 1) end
            end
            GameTooltip:AddLine(L["Klick: im Auktionshaus suchen"] .. (l.single and ("  ·  " .. L["Rechtsklick: entfernen"]) or ""), 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", GameTooltip_Hide)
        win.rows[i] = r
    end
    win.offset = 0
    -- dünne Scrollleiste rechts, nur wenn mehr Zeilen da sind als Platz
    win.scroll = Craft.ThinScroll(win, function(v) win.offset = v; Track.Refresh() end, 4)
    win.scroll:SetPoint("TOPRIGHT", -4, -30)
    win.scroll:SetHeight(ROWS * ROW_H)
    win:EnableMouseWheel(true)
    win:SetScript("OnMouseWheel", function(_, delta)
        win.offset = math.max(0, win.offset - delta)
        Track.Refresh()
    end)

    -- Am Händler: fehlende Sachen, die er verkauft, passend kaufen
    win.vendor = SmallButton(win, L["Beim Händler kaufen"], WIDTH - 20, function()
        if ns.CraftVendor then ns.CraftVendor.AskBuy() end
    end)
    win.vendor:SetPoint("BOTTOMLEFT", 10, 32)
    -- nacheinander herstellen: jeder Klick das nächste Rezept
    win.craft = SmallButton(win, L["Nächstes herstellen"], WIDTH - 20, function() Track.CraftNext() end)
    win.craft:SetPoint("BOTTOMLEFT", 10, 54)
    win.craft:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Nächstes herstellen"], 1, 0.82, 0)
        GameTooltip:AddLine(L["Jeder Klick stellt das nächste getrackte Rezept her – so oft, wie getrackt und mit deinen Zutaten möglich. Zwischenprodukte (z. B. Barren) kommen zuerst. Der Tracker zählt mit."], 1, 1, 1, true)
        local id, why = Track.NextCraft()
        if not id then GameTooltip:AddLine(why, 1, 0.5, 0.3, true) end
        GameTooltip:Show()
    end)
    win.craft:SetScript("OnLeave", GameTooltip_Hide)
    win.vendor:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Beim Händler kaufen"], 1, 0.82, 0)
        local list = ns.CraftVendor and ns.CraftVendor.Buyable() or {}
        local money = ns.AH and ns.AH.Money or tostring
        for i, b in ipairs(list) do
            if i > 12 then break end
            GameTooltip:AddDoubleLine(("%d× %s"):format(b.buy, Craft.ItemName(b.id)), money(b.cost), 1, 1, 1, 1, 1, 1)
        end
        if #list == 0 then GameTooltip:AddLine(L["Dieser Händler hat nichts, was dir fehlt."], 0.7, 0.7, 0.7) end
        GameTooltip:Show()
    end)
    win.vendor:SetScript("OnLeave", GameTooltip_Hide)
    win.search = SmallButton(win, L["Fehlendes suchen"], 118, Track.SearchMissing)
    win.search:SetPoint("BOTTOMLEFT", 10, 10)
    win.clear = SmallButton(win, L["Leeren"], 70, function() Track.Clear() end)
    win.clear:SetPoint("LEFT", win.search, "RIGHT", 6, 0)
    win.empty = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.empty:SetPoint("TOPLEFT", 14, -36); win.empty:SetPoint("RIGHT", -14, 0)
    win.empty:SetJustifyH("LEFT")
    win.empty:SetText(L["Noch nichts getrackt. Im Berufsfenster bei einem Rezept „Tracken“ klicken oder im Handwerk-Guide Umschalt+Klick auf einen Schritt."])
end

function Track.Refresh(show)
    if show then Track.Show() end
    CheckDone()
    if not win or not win:IsShown() then return end
    local lines = Track.Lines()
    local offer = ns.CraftVendor and ns.CraftVendor.open and ns.CraftVendor.Offer() or {}
    win.offset = math.min(win.offset, math.max(0, #lines - ROWS))
    win.scroll:Update(win.offset, #lines, ROWS)
    win.empty:SetShown(#lines == 0)
    for i, r in ipairs(win.rows) do
        local l = lines[i + win.offset]
        r.line = l
        r:SetShown(l ~= nil)
        if l then
            r.minus:SetShown(l.head and l.recipe ~= nil)
            r.plus:SetShown(l.head and l.recipe ~= nil)
            r.del:SetShown(l.head and l.recipe ~= nil)
            r.bar:Hide()
            r.count:SetText("")
            if l.head then
                r.icon:SetTexture(l.recipe and ((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(l.recipe)) or 134939) or 133784)
                r.text:SetText(l.recipe and ("|cffffd100%s|r |cffaaaaaa×%d|r"):format(Craft.RecipeName(l.recipe), l.crafts)
                    or ("|cffffd100%s|r"):format(l.title))
                r.text:SetPoint("RIGHT", l.recipe and -64 or -2, 0)
            elseif l.note then
                r.icon:SetTexture(nil)
                r.text:SetText("|cff888888" .. l.note .. "|r")
                r.text:SetPoint("RIGHT", -2, 0)
            else
                local have = Track.Have(l.item)
                r.icon:SetTexture(Craft.ItemIcon(l.item))
                r.text:SetText(Craft.ItemName(l.item))
                r.text:SetPoint("RIGHT", -60, 0)
                local done = have >= l.want
                r.count:SetText((done and "|cff40ff40" or "|cffffffff") .. ("%d / %d"):format(math.min(have, 9999), l.want) .. "|r")
                -- gibt es beim offenen Händler
                if not done and offer[l.item] then r.text:SetText(Craft.ItemName(l.item) .. "  |cff8899aa(" .. L["Händler"] .. ")|r") end
                local frac = l.want > 0 and math.min(1, have / l.want) or 1
                if frac > 0 then
                    r.bar:SetWidth(math.max(1, (WIDTH - 20) * frac))
                    r.bar:SetColorTexture(done and 0.2 or 0.25, done and 0.6 or 0.4, done and 0.2 or 0.6, 0.35)
                    r.bar:Show()
                end
            end
        end
    end
    win.search:SetEnabled(next((Track.Missing())) ~= nil)
    local cid, cn = Track.NextCraft()
    win.craft:SetText(cid and (L["Herstellen: %s ×%d"]):format(Craft.RecipeName(cid), cn)
        or (not Craft.OpenLine() and L["Erst Berufsfenster öffnen"]) or L["Nächstes herstellen"])
    win.craft:SetEnabled(cid ~= nil)
    win.craft:SetShown(next(DB().recipes) ~= nil)
    local V = ns.CraftVendor
    win.vendor:SetShown(V and V.open or false)
    -- Herstellen-Knopf rutscht nach unten, wenn kein Händler offen ist
    win.craft:ClearAllPoints()
    win.craft:SetPoint("BOTTOMLEFT", 10, (V and V.open) and 54 or 32)
    if V and V.open then
        local list, total = V.Buyable()
        local money = ns.AH and ns.AH.Money or tostring
        win.vendor:SetText(#list > 0 and (L["Beim Händler kaufen"] .. " (" .. money(total) .. ")") or L["Händler hat nichts davon"])
        win.vendor:SetEnabled(#list > 0)
    end
end

function Track.Show()
    if not win then Build() end
    win:Show()
    if type(GuildPrideDB) == "table" then GuildPrideDB.craftTrackShown = true end
    Track.Refresh()
end

function Track.Toggle()
    if win and win:IsShown() then win:Hide(); GuildPrideDB.craftTrackShown = false else Track.Show() end
end

-- Bestand ändert sich: neu zählen (gebündelt)
local pending = false
local function Soon()
    if pending then return end
    pending = true
    C_Timer.After(0.5, function() pending = false; Track.Refresh() end)
end
Craft.OnChanged(Soon)
local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "AUCTION_HOUSE_SHOW", "UNIT_SPELLCAST_SUCCEEDED",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE")
ev:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit == "player" and spellID then Track.Crafted(spellID) end
    elseif event == "PLAYER_LOGIN" then
        C_Timer.After(3, function()
            if type(GuildPrideDB) == "table" and GuildPrideDB.craftTrackShown and not Track.IsEmpty() then Track.Show() end
        end)
    elseif event == "AUCTION_HOUSE_SHOW" then
        -- am Auktionshaus geht der Tracker von selbst auf, wenn etwas fehlt
        if next((Track.Missing())) then Track.Show() end
    else
        Soon()
    end
end)
