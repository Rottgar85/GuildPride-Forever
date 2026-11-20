-- GuildPride Auktionshaus: Berufsfenster
-- Zwei Knöpfe unten im Berufsfenster (neben „Alle herstellen“):
--   „AH: Zutaten“      sucht im GuildPride-Auktionshaus nur die Zutaten des gewählten Rezepts
--                      (Menge = eingestellte Anzahl zum Herstellen)
--   „Zur Einkaufsliste“ trägt die Zutaten mit Menge in eine Einkaufsliste ein (Mengen addieren sich)
-- Gelesen wird wie bei Auctionator über C_TradeSkillUI.GetRecipeSchematic (WoW Forever: ProfessionsFrame).
local ADDON, GP = ...
GP.AH = GP.AH or {}
local AH = GP.AH
local L = GP.L or setmetatable({}, { __index = function(_, k) return k end })

-- Nur Pflicht-Zutaten (keine optionalen oder verändernden Zutaten)
local function BasicType()
    local t = Enum and Enum.CraftingReagentType
    local v = type(t) == "table" and t.Basic
    return type(v) == "number" and v or 1
end

-- Zutaten eines Rezepts: { { itemID, Menge je Herstellung }, … } (doppelte zusammengefasst)
function AH.RecipeReagents(recipeID, level)
    local T = C_TradeSkillUI
    if not (T and T.GetRecipeSchematic and recipeID) then return {} end
    local ok, schematic = pcall(T.GetRecipeSchematic, recipeID, false, level)
    if not ok or type(schematic) ~= "table" or type(schematic.reagentSlotSchematics) ~= "table" then return {} end
    local basic, out, at = BasicType(), {}, {}
    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        local first = type(slot.reagents) == "table" and slot.reagents[1]
        local id = first and tonumber(first.itemID)
        if id and slot.reagentType == basic then
            local n = tonumber(slot.quantityRequired) or 1
            if at[id] then out[at[id]][2] = out[at[id]][2] + n
            else out[#out + 1] = { id, n }; at[id] = #out end
        end
    end
    return out
end

-- Was ein Rezept kostet und bringt (je Herstellung, mit den bekannten GuildPride-Preisen):
-- { cost, missing = Zutaten ohne Preis, output = itemID, made = Stück, sell = Verkaufswert, profit = nach 5 % Gebühr }
local AH_CUT = 0.95
function AH.RecipeValue(recipeID, level)
    local v = { cost = 0, missing = 0 }
    for _, r in ipairs(AH.RecipeReagents(recipeID, level)) do
        local p = AH.PriceFor(AH.Key(r[1]))
        if p then v.cost = v.cost + p * r[2] else v.missing = v.missing + 1 end
    end
    local T = C_TradeSkillUI
    if not (T and T.GetRecipeSchematic) then return v end
    local ok, sch = pcall(T.GetRecipeSchematic, recipeID, false, level)
    local out = ok and type(sch) == "table" and tonumber(sch.outputItemID)
    if not out and T.GetRecipeOutputItemData then
        local ok2, d = pcall(T.GetRecipeOutputItemData, recipeID)
        out = ok2 and type(d) == "table" and (tonumber(d.itemID) or (d.hyperlink and tonumber(d.hyperlink:match("item:(%d+)"))))
    end
    if out then
        v.output = out
        v.made = ok and type(sch) == "table" and tonumber(sch.quantityMin) or 1
        local p = AH.PriceFor(AH.Key(out))
        if p then
            v.sell = p * v.made
            v.profit = math.floor(v.sell * AH_CUT - v.cost)
        end
    end
    return v
end

function AH.RecipeValueText(v)
    local parts = { (L["Zutaten: %s"]):format(AH.Money(v.cost)) .. (v.missing > 0 and (" (+" .. (L["%d ohne Preis"]):format(v.missing) .. ")") or "") }
    if v.sell then
        parts[#parts + 1] = (L["Verkauf: %s"]):format(AH.Money(v.sell))
        local pr = v.profit
        parts[#parts + 1] = (pr >= 0 and "|cff40ff40" or "|cffff4040") .. (L["Gewinn: %s"]):format((pr < 0 and "-" or "") .. AH.Money(math.abs(pr))) .. "|r"
    elseif v.output then
        parts[#parts + 1] = L["Verkaufspreis noch unbekannt"]
    end
    return table.concat(parts, "  ·  ")
end

-- Wer in der Gilde kann das Item herstellen? Über GuildPrides Handwerker-Verzeichnis: das Rezept
-- heißt wie das Item (Classic-Inhalte). Gibt Namen sortiert und ohne Doppelte zurück.
function AH.GuildCrafters(itemName)
    local C = GP.Crafts
    if type(itemName) ~= "string" or itemName == "" or not (C and C.Search) then return {} end
    local want, seen, out = itemName:lower(), {}, {}
    local ok, rows = pcall(C.Search, itemName)
    for _, r in ipairs(ok and rows or {}) do
        if r.recipe and r.recipe:lower() == want and not seen[r.name] then
            seen[r.name] = true
            out[#out + 1] = r.name
        end
    end
    table.sort(out)
    return out
end

local function Page()
    local f = ProfessionsFrame
    return type(f) == "table" and type(f.CraftingPage) == "table" and f.CraftingPage or nil
end

-- Gerade gewähltes Rezept im Berufsfenster: { id, name, reagents } oder nil
function AH.CurrentRecipe()
    local page = Page()
    local form = page and page.SchematicForm
    if type(form) ~= "table" or type(form.GetRecipeInfo) ~= "function" then return nil end
    local ok, info = pcall(form.GetRecipeInfo, form)
    if not ok or type(info) ~= "table" or not info.recipeID then return nil end
    local level
    if type(form.GetCurrentRecipeLevel) == "function" then
        local ok2, lv = pcall(form.GetCurrentRecipeLevel, form)
        if ok2 then level = lv end
    end
    return { id = info.recipeID, name = info.name or ("#" .. tostring(info.recipeID)),
             reagents = AH.RecipeReagents(info.recipeID, level) }
end

-- Anzahl zum Herstellen aus dem Berufsfenster (Feld neben „Herstellen“), sonst 1
function AH.CraftCount()
    local page = Page()
    local box = page and page.CreateMultipleInputBox
    local n
    if type(box) == "table" and type(box.GetValue) == "function" then
        local ok, v = pcall(box.GetValue, box)
        if ok then n = tonumber(v) end
    end
    return (n and n >= 1) and math.floor(n) or 1
end

-- Zutaten des gewählten Rezepts in eine Liste eintragen
function AH.CraftToList(list, crafts)
    local r = AH.CurrentRecipe()
    if not r or #r.reagents == 0 or not list then return false end
    AH.AddReagents(list, r.reagents, crafts)
    if AH.ListsChanged then AH.ListsChanged() end
    return true, r
end

-- Nur die Zutaten im GuildPride-Auktionshaus suchen
function AH.CraftSearch(crafts)
    local r = AH.CurrentRecipe()
    if not r or #r.reagents == 0 then return false, L["Dieses Rezept braucht keine Zutaten aus dem Auktionshaus."] end
    if not AH.IsOpen() then return false, L["Auktionshaus: Erst das Auktionshaus öffnen."] end
    crafts = math.max(1, math.floor(tonumber(crafts) or 1))
    local ids, need = {}, {}
    for _, x in ipairs(r.reagents) do
        ids[#ids + 1] = x[1]
        need[x[1]] = math.max(0, x[2] * crafts - AH.ItemCount(x[1]))   -- was du schon hast, zählt mit
    end
    if not (AH.ShowItemSearch and AH.ShowItemSearch(ids, need, r.name)) then
        return false, L["Das GuildPride-Auktionshaus ist ausgeschaltet (/gp ah an)."]
    end
    return true
end

---------------------------------------------------------------------
-- Auswahl „Zur Einkaufsliste“: Anzahl und Liste wählen
---------------------------------------------------------------------
local MAX_PICK = 12
local picker
local function AddTo(list)
    local crafts = tonumber(picker.qtyBox:GetText()) or 1
    local ok, r = AH.CraftToList(list, crafts)
    if ok then
        AH.Print((L["%s ×%d: Zutaten in „%s“ eingetragen."]):format(r.name, math.max(1, math.floor(crafts)), list.name))
    else
        AH.Print(L["Bitte im Berufsfenster ein Rezept mit Zutaten wählen."])
    end
    picker:Hide()
end

StaticPopupDialogs["GUILDPRIDE_AH_CRAFT_NEWLIST"] = {
    text = "%s",
    button1 = OKAY, button2 = CANCEL,
    hasEditBox = true, maxLetters = 60,
    OnShow = function(self)
        local eb = self.editBox or self.EditBox
        local r = AH.CurrentRecipe()
        eb:SetText(r and r.name or ""); eb:SetFocus(); eb:HighlightText()
    end,
    OnAccept = function(self)
        local l, why = AH.NewList((self.editBox or self.EditBox):GetText())
        if not l then AH.Print(why) return end
        if picker then AddTo(l) end
    end,
    EditBoxOnEnterPressed = function(eb)
        local dlg = eb:GetParent()
        StaticPopupDialogs.GUILDPRIDE_AH_CRAFT_NEWLIST.OnAccept(dlg); dlg:Hide()
    end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function BuildPicker()
    local f = CreateFrame("Frame", "GuildPrideCraftListPicker", UIParent, "BackdropTemplate")
    f:SetSize(240, 120)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    if GP.SkinDialog then GP.SkinDialog(f) end   -- Goldrahmen wie das Gildenfenster
    f:Hide()
    tinsert(UISpecialFrames, "GuildPrideCraftListPicker")   -- ESC schließt
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    if GP.SkinClose then GP.SkinClose(close) end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 12, -12); f.title:SetPoint("RIGHT", -28, 0)
    f.title:SetJustifyH("LEFT"); f.title:SetWordWrap(false)
    local ql = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ql:SetPoint("TOPLEFT", 12, -38); ql:SetText(L["Anzahl herstellen:"])
    f.qtyBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.qtyBox:SetSize(50, 20); f.qtyBox:SetPoint("LEFT", ql, "RIGHT", 10, 0)
    f.qtyBox:SetAutoFocus(false); f.qtyBox:SetNumeric(true)
    f.qtyBox:SetScript("OnEscapePressed", function() f:Hide() end)
    if GP.SkinEditBox then GP.SkinEditBox(f.qtyBox) end
    local hl = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hl:SetPoint("TOPLEFT", 12, -62); hl:SetText(L["In welche Liste?"])
    f.buttons = {}
    for i = 1, MAX_PICK do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(216, 20)
        b:SetPoint("TOPLEFT", 12, -78 - (i - 1) * 22)
        if GP.SkinButton then GP.SkinButton(b) end
        b:SetScript("OnClick", function() if b.list then AddTo(b.list) end end)
        b:Hide()
        f.buttons[i] = b
    end
    f.newBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.newBtn:SetSize(216, 20)
    if GP.SkinButton then GP.SkinButton(f.newBtn) end
    f.newBtn:SetText(L["Neue Liste …"])
    f.newBtn:SetScript("OnClick", function()
        StaticPopup_Show("GUILDPRIDE_AH_CRAFT_NEWLIST", L["Name der neuen Einkaufsliste:"])
    end)
    -- Temporäre Liste: verschwindet, sobald alles gekauft ist
    f.tempBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.tempBtn:SetSize(216, 20)
    if GP.SkinButton then GP.SkinButton(f.tempBtn) end
    f.tempBtn:SetText(L["Temporäre Liste"])
    f.tempBtn:SetScript("OnClick", function() AddTo(AH.TempList(true)) end)
    f.tempBtn:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Temporäre Liste"])
        GameTooltip:AddLine(L["Für einen Einkauf: Jeder Kauf im GuildPride-Auktionshaus zieht die gekaufte Menge ab. Ist alles gekauft, verschwindet die Liste von selbst."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.tempBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return f
end

local function ShowPicker(anchor)
    local r = AH.CurrentRecipe()
    if not r or #r.reagents == 0 then
        AH.Print(L["Bitte im Berufsfenster ein Rezept mit Zutaten wählen."])
        return
    end
    picker = picker or BuildPicker()
    picker.title:SetText((L["Zur Einkaufsliste: %s"]):format(r.name))
    picker.qtyBox:SetText(tostring(AH.CraftCount()))
    local lists = AH.Lists()
    local shown = math.min(#lists, MAX_PICK)
    for i, b in ipairs(picker.buttons) do
        local l = i <= shown and lists[i] or nil
        b.list = l
        if l then b:SetText(l.name); b:Show() else b:Hide() end
    end
    picker.newBtn:ClearAllPoints()
    picker.newBtn:SetPoint("TOPLEFT", 12, -82 - shown * 22)
    picker.tempBtn:ClearAllPoints()
    picker.tempBtn:SetPoint("TOPLEFT", 12, -104 - shown * 22)
    picker:SetHeight(142 + shown * 22)
    picker:ClearAllPoints()
    if anchor then picker:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4) else picker:SetPoint("CENTER") end
    picker:Show()
end

---------------------------------------------------------------------
-- Knöpfe im Berufsfenster
---------------------------------------------------------------------
local bar
local function UpdateBar()
    if not bar then return end
    bar.searchBtn:SetEnabled(AH.IsOpen() and true or false)
end

local function Tip(b, title, text)
    b:SetScript("OnEnter", function()
        GameTooltip:SetOwner(b, "ANCHOR_TOP")
        GameTooltip:SetText(title)
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Unterstes sichtbares Material-Feld des gewählten Rezepts (Pflicht- und Zusatz-Zutaten);
-- darunter kommt die GuildPride-Leiste. Ohne Felder: der Materialien-Block selbst.
local function LowestReagent(form)
    if type(form) ~= "table" then return nil end
    local best, bottom
    local function Consider(f)
        if type(f) ~= "table" or type(f.IsShown) ~= "function" or type(f.GetBottom) ~= "function" then return end
        local ok, shown = pcall(f.IsShown, f)
        if not ok or not shown then return end
        local ok2, b = pcall(f.GetBottom, f)
        if ok2 and type(b) == "number" and (not bottom or b < bottom) then best, bottom = f, b end
    end
    if type(form.reagentSlots) == "table" then
        for _, slots in pairs(form.reagentSlots) do
            if type(slots) == "table" then for _, s in pairs(slots) do Consider(s) end end
        end
    end
    if not best then Consider(form.OptionalReagents); Consider(form.Reagents) end
    return best
end

-- Häkchen unten im Rezept („Rezept verfolgen“/„Rezept listen“): bekannte Namen, sonst das
-- unterste sichtbare Häkchen im Rezeptbereich. Die Leiste sitzt direkt darüber.
local function Usable(f)
    if type(f) ~= "table" or type(f.IsShown) ~= "function" or type(f.GetTop) ~= "function" then return false end
    local ok, shown = pcall(f.IsShown, f)
    return ok and shown and true or false
end
local function RecipeCheck(form)
    if type(form) ~= "table" then return nil end
    for _, name in ipairs({ "TrackRecipeCheckbox", "TrackRecipeCheckBox", "TrackRecipeButton" }) do
        local f = rawget(form, name)
        if Usable(f) then return f end
    end
    if type(form.GetChildren) ~= "function" then return nil end
    local best, bottom
    for _, f in ipairs({ pcall(form.GetChildren, form) }) do
        if Usable(f) and type(f.GetObjectType) == "function" and type(f.GetBottom) == "function" then
            local ok, kind = pcall(f.GetObjectType, f)
            local ok2, b = pcall(f.GetBottom, f)
            if ok and kind == "CheckButton" and ok2 and type(b) == "number" and (not bottom or b < bottom) then
                best, bottom = f, b
            end
        end
    end
    return best
end

-- Waagerechte Mitte eines Frames (nil, wenn unbekannt)
local function CenterX(f)
    if type(f) ~= "table" or type(f.GetCenter) ~= "function" then return nil end
    local ok, x = pcall(f.GetCenter, f)
    return ok and type(x) == "number" and x or nil
end

-- Leiste mittig im rechten Bereich (Rezept), ganz unten: direkt über dem Häkchen unten im
-- Rezept. Ohne Häkchen unter das unterste Material; findet sich gar nichts, links
-- neben „Alle herstellen“. Läuft jedes Bild, setzt die Position aber nur bei Änderungen.
local function PlaceBar()
    local page = Page()
    if not bar or not page then return end
    local form = page.SchematicForm
    local check = bar.check
    if not Usable(check) then
        check = RecipeCheck(form) or RecipeCheck(page)
        bar.check = check
    end
    local reagent = LowestReagent(form)
    local target, dx = check or reagent, 0
    if target then
        -- Mitte des rechten Bereichs (Rezept); notfalls die Mitte der Materialien
        local mid, own = CenterX(form) or CenterX(reagent), CenterX(target)
        if mid and own then dx = math.floor(mid - own + 0.5) end
    else
        if bar.anchor then return end
        target = page.CreateAllButton or page
    end
    if target == bar.anchor and dx == bar.dx then return end
    bar.anchor, bar.dx = target, dx
    bar:ClearAllPoints()
    if target == check then
        bar:SetPoint("BOTTOM", target, "TOP", dx, 4)
    elseif target == reagent then
        bar:SetPoint("TOP", target, "BOTTOM", dx, -10)
    elseif target == page.CreateAllButton then
        bar:SetPoint("BOTTOMRIGHT", target, "BOTTOMLEFT", -10, 0)
    else
        bar:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -330, 10)
    end
end

local function BuildBar()
    local page = Page()
    if bar or not page then return end
    bar = CreateFrame("Frame", "GuildPrideCraftBar", page)
    bar:SetSize(260, 42)
    bar:SetFrameLevel((page.GetFrameLevel and page:GetFrameLevel() or 1) + 10)
    PlaceBar()
    -- oben die beiden Knöpfe, darunter die Zeile mit Kosten und Gewinn
    bar.searchBtn = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    bar.searchBtn:SetSize(112, 22); bar.searchBtn:SetPoint("TOPLEFT", 6, 0)   -- beide Knöpfe mittig (6 + 112 + 6 + 130 + 6)
    bar.searchBtn:SetText(L["AH: Zutaten"])
    bar.listBtn = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    bar.listBtn:SetSize(130, 22); bar.listBtn:SetPoint("LEFT", bar.searchBtn, "RIGHT", 6, 0)
    bar.listBtn:SetText(L["Zur Einkaufsliste"])
    if GP.SkinButton then GP.SkinButton(bar.listBtn); GP.SkinButton(bar.searchBtn) end
    bar.searchBtn:SetScript("OnClick", function()
        local ok, why = AH.CraftSearch(AH.CraftCount())
        if not ok and why then AH.Print(why) end
    end)
    bar.listBtn:SetScript("OnClick", function() ShowPicker(bar.listBtn) end)
    Tip(bar.searchBtn, L["GuildPride: Zutaten im Auktionshaus"],
        L["Sucht im GuildPride-Auktionshaus nur die Zutaten dieses Rezepts, mit der Menge für die eingestellte Anzahl. Das Auktionshaus muss offen sein."])
    Tip(bar.listBtn, L["GuildPride: Zur Einkaufsliste"],
        L["Trägt die Zutaten mit Menge in eine Einkaufsliste ein. Mehrere Rezepte in einer Liste werden zusammengezählt."])
    -- Kosten und Gewinn des gewählten Rezepts unter den Knöpfen; neu gerechnet, wenn ein anderes
    -- Rezept gewählt wird, sonst alle 5 Sekunden (neue Preise)
    bar.info = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- eine Zeile, mittig unter den Knöpfen; ohne feste Breite, damit nichts umbricht
    bar.info:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    bar.info:SetJustifyH("CENTER")
    bar.info:SetWordWrap(false)
    -- breiter als der rechte Bereich: Schrift verkleinern, bis sie hineinpasst
    local function Fit()
        if not bar.info.SetTextScale then return end
        bar.info:SetTextScale(1)
        local page = Page()
        local form = page and page.SchematicForm
        local room = form and form.GetWidth and form:GetWidth()
        local w = bar.info:GetStringWidth()
        if type(room) == "number" and type(w) == "number" and room > 40 and w > room - 20 then
            bar.info:SetTextScale(math.max(0.7, (room - 20) / w))
        end
    end
    local last, wait = nil, 0
    bar:SetScript("OnUpdate", function(_, elapsed)
        PlaceBar()   -- andere Rezepte haben unterschiedlich viele Materialien
        wait = wait - (elapsed or 0)
        local r = AH.CurrentRecipe()
        local id = r and r.id
        if id == last and wait > 0 then return end
        last, wait = id, 5
        bar.info:SetText(id and AH.RecipeValueText(AH.RecipeValue(id)) or "")
        Fit()
    end)
    bar:SetScript("OnShow", UpdateBar)
    UpdateBar()
end

function AH._CraftBar() return bar end          -- für Tests
function AH._CraftPicker() return picker end    -- für Tests

AH.Listen("ADDON_LOADED", function(name)
    if name == "Blizzard_Professions" then BuildBar() end
end)
AH.Listen("TRADE_SKILL_SHOW", function() BuildBar(); UpdateBar() end)
AH.Listen("AUCTION_HOUSE_SHOW", UpdateBar)
AH.Listen("AUCTION_HOUSE_CLOSED", function()
    if bar then bar.searchBtn:SetEnabled(false) end
end)
