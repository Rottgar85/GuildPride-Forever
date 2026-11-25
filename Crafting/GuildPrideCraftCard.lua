-- GuildPride Handwerk: Karte am Berufsfenster
-- Eigenes, frei verschiebbares Fenster (geht mit dem Berufsfenster auf und zu) zum gewählten Rezept:
--   Farbe (Skill-Up sicher/möglich), Guide-Schritt und wie viele noch,
--   Zutaten mit Bestand (Taschen, Bank, Twinks), Kosten/Verkauf/Gewinn,
--   wer es außerdem kann (Twinks, Gilde), nächster Rang,
--   Knöpfe: Tracken, Bestes jetzt, Guide-Rezept, Handwerk, Tracker.
-- Ein-/ausblenden: Knopf „GP“ oben am Berufsfenster, Einstellung craftCard.
local ADDON, ns = ...
local L = ns.L
local Craft, G = ns.Craft, ns.CraftGuides

local Card = {}
ns.CraftCard = Card

local WIDTH = 250
local MAX_LINES = 26

local function Enabled() return not (type(GuildPrideDB) == "table" and GuildPrideDB.craftCard == false) end
Card.Enabled = Enabled

local function Color(diff, text)
    local c = diff and Craft.COLORS[diff]
    return c and ("|cff" .. c .. text .. "|r") or text
end

local DIFF_TEXT = {
    orange = "Orange: sicherer Punkt",
    yellow = "Gelb: meist ein Punkt",
    green  = "Grün: selten ein Punkt",
    gray   = "Grau: kein Punkt mehr",
}

-- Zeilen der Karte für ein Rezept (auch für Tests ohne Fenster)
function Card.Lines(id, crafts, line)
    local out = {}
    local function Add(s) out[#out + 1] = s end
    crafts = math.max(1, tonumber(crafts) or 1)
    local diff = Craft.Difficulty(id)
    Add("|cffffd100" .. Craft.RecipeName(id) .. "|r")
    if diff then Add(Color(diff, L[DIFF_TEXT[diff]])) end
    -- Ab welcher Stufe gibt es keinen Punkt mehr? (Forever: maxTrivialLevel)
    local info = Craft.RecipeInfo(id)
    local gray = info and tonumber(info.maxTrivialLevel)
    if gray and gray > 0 and diff ~= "gray" then Add("|cff808080" .. (L["Grau ab Stufe %d"]):format(gray) .. "|r") end

    -- Guide
    line = line or Craft.OpenLine()
    if line then
        local skill = Craft.Skill(line)
        local step = skill and Craft.CurrentStep(line, skill)
        if step and step.spell == id then
            local left = G.Remaining(step, skill)
            Add((L["Guide: %d–%d, noch etwa %d×"]):format(step.from, step.to, left or 0))
        elseif step and step.spell then
            Add((L["Guide empfiehlt jetzt: %s (%d–%d)"]):format(Craft.RecipeName(step.spell), step.from, step.to))
        end
    end

    -- Zutaten
    local r = Craft.Reagents(id)
    if r and #r > 0 then
        Add(" ")
        Add((L["Zutaten für %d×:"]):format(crafts))
        for _, x in ipairs(r) do
            local need = x[2] * crafts
            local bags, bank = Craft.Count(x[1])
            local have = bags + bank
            local _, alt = Craft.AltCounts(x[1])
            local col = have >= need and "|cff40ff40" or "|cffff6060"
            local extra = {}
            if bank > 0 then extra[#extra + 1] = (L["Bank %d"]):format(bank) end
            if alt > 0 then extra[#extra + 1] = (L["Twinks %d"]):format(alt) end
            Add(("%s%d/%d|r %s%s"):format(col, have, need, Craft.ItemName(x[1]),
                #extra > 0 and ("  |cff8899aa(" .. table.concat(extra, ", ") .. ")|r") or ""))
        end
    end

    -- Kosten und Gewinn (GuildPride-Preise)
    local AH = ns.AH
    if AH and AH.RecipeValue and AH.RecipeValueText then
        local ok, v = ns.Try(AH.RecipeValue, id)
        if ok and v and (v.cost > 0 or v.sell) then
            Add(" ")
            Add(AH.RecipeValueText(v))
        end
    end

    -- Wer kann es noch?
    local alts = Craft.AltsKnowing(id)
    local guild = Craft.GuildKnowing(id)
    if #alts > 0 or #guild > 0 then Add(" ") end
    if #alts > 0 then Add((L["Twinks: %s"]):format(table.concat(alts, ", "))) end
    if #guild > 0 then
        local shown = {}
        for i = 1, math.min(5, #guild) do shown[i] = guild[i] end
        Add((L["Gilde: %s"]):format(table.concat(shown, ", ") .. (#guild > 5 and (" +" .. (#guild - 5)) or "")))
    end

    -- Nächster Rang
    if line then
        local skill, max = Craft.Skill(line)
        local _, nextRank = G.Rank(max)
        if skill and nextRank and skill >= nextRank.learnAt then
            Add(" ")
            Add(("|cffffd100%s|r"):format((L["Jetzt %s beim Lehrer lernen (ab Charakterstufe %d)."]):format(G.Lang(nextRank), nextRank.level)))
        end
    end
    return out
end

---------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------
local panel, toggle

local function Button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 20)
    b:SetText(text)
    if ns.SkinButton then ns.SkinButton(b) end
    b:SetScript("OnClick", onClick)
    return b
end

-- Rezept wählen und sagen, was passiert ist
local function Pick(id)
    local name = Craft.RecipeName(id)
    local info = Craft.RecipeInfo(id)
    if info and info.learned == false then
        ns.Print((L["%s kannst du noch nicht – erst beim Lehrer oder Händler lernen."]):format(name))
    end
    Craft.SelectRecipe(id, function(ok, how)
        if ok then return end
        if how == "suche" then
            ns.Print((L["%s steht jetzt oben in der Rezeptliste (Suche)."]):format(name))
        elseif not (info and info.learned == false) then
            ns.Print((L["%s ließ sich nicht auswählen – such es in der Rezeptliste (/gp handwerk diag hilft bei der Fehlersuche)."]):format(name))
        end
    end)
end
Card.Pick = Pick

local function CurrentID()
    local AH = ns.AH
    local r = AH and AH.CurrentRecipe and AH.CurrentRecipe()
    return r and r.id
end

local function Crafts()
    local AH = ns.AH
    return AH and AH.CraftCount and AH.CraftCount() or 1
end

local function Build()
    if panel or not ProfessionsFrame then return end
    -- Eigenes Fenster (nicht am Berufsfenster angeheftet): frei verschiebbar, Position gemerkt;
    -- geht mit dem Berufsfenster auf und zu
    panel = CreateFrame("Frame", "GuildPrideCraftCard", UIParent, "BackdropTemplate")
    panel:SetSize(WIDTH, 520)
    panel:SetFrameStrata("HIGH")
    panel:SetToplevel(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        GuildPrideDB.craftCardPos = { p, rp, x, y }
    end)
    local pos = type(GuildPrideDB) == "table" and GuildPrideDB.craftCardPos
    if type(pos) == "table" then panel:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else panel:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0) end
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    if ns.SkinClose then ns.SkinClose(close) end
    -- X schließt nur bis zum nächsten Öffnen des Berufsfensters (ganz aus: Knopf „GP“ oder Einstellungen)
    close:SetScript("OnClick", function() panel:Hide() end)
    ProfessionsFrame:HookScript("OnShow", function() Card.ShowSoon() end)
    ProfessionsFrame:HookScript("OnHide", function() panel:Hide() end)
    if ns.SkinDialog then ns.SkinDialog(panel) end
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText(L["GuildPride Handwerk"])
    panel.lines = {}
    for i = 1, MAX_LINES do
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 12, -32 - (i - 1) * 14)
        fs:SetWidth(WIDTH - 24)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        panel.lines[i] = fs
    end
    panel.track = Button(panel, L["Tracken"], 110, function()
        local id = CurrentID()
        if id and ns.CraftTrack then
            ns.CraftTrack.AddRecipe(id, Crafts())
            ns.Print((L["%s ×%d im Tracker."]):format(Craft.RecipeName(id), Crafts()))
        end
    end)
    panel.track:SetPoint("BOTTOMLEFT", 12, 62)
    panel.best = Button(panel, L["Bestes jetzt"], 110, function()
        local id, why = Craft.BestNow()
        if id then Pick(id)
        elseif why == "keine Farben" then ns.Print(L["Das Spiel liefert hier keine Rezeptfarben – nimm das Guide-Rezept."])
        else ns.Print(L["Kein Rezept gibt gerade sicher einen Punkt."]) end
    end)
    panel.best:SetPoint("LEFT", panel.track, "RIGHT", 6, 0)
    panel.best:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Bestes jetzt"], 1, 0.82, 0)
        GameTooltip:AddLine(L["Wählt das Rezept, das am sichersten einen Punkt gibt (orange vor gelb), das du herstellen kannst und das am wenigsten kostet."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    panel.best:SetScript("OnLeave", GameTooltip_Hide)
    panel.guide = Button(panel, L["Guide-Rezept"], 110, function()
        local line = Craft.OpenLine()
        local step = line and Craft.CurrentStep(line)
        if step and step.spell then Pick(step.spell)
        else ns.Print(L["Für diesen Beruf hat der Guide gerade keinen Rezept-Schritt."]) end
    end)
    panel.guide:SetPoint("BOTTOMLEFT", 12, 38)
    panel.window = Button(panel, L["Handwerk"], 110, function()
        if ns.CraftWindow then ns.CraftWindow.Show(Craft.OpenLine()) end
    end)
    panel.window:SetPoint("LEFT", panel.guide, "RIGHT", 6, 0)
    panel.tracker = Button(panel, L["Tracker"], 226, function() if ns.CraftTrack then ns.CraftTrack.Toggle() end end)
    panel.tracker:SetPoint("BOTTOMLEFT", 12, 14)

    local last, wait = nil, 0
    panel:SetScript("OnUpdate", function(_, elapsed)
        wait = wait - (elapsed or 0)
        local id = CurrentID()
        local key = tostring(id) .. ":" .. Crafts()
        if key == last and wait > 0 then return end
        last, wait = key, 3
        Card.Refresh(id)
    end)
    panel:SetShown(Enabled() and ProfessionsFrame:IsShown())

    -- Knopf oben am Berufsfenster: Karte ein/aus
    toggle = CreateFrame("Button", nil, ProfessionsFrame, "UIPanelButtonTemplate")
    toggle:SetSize(34, 20)
    toggle:SetText("GP")
    if ns.SkinButton then ns.SkinButton(toggle) end
    toggle:SetPoint("TOPRIGHT", ProfessionsFrame, "TOPRIGHT", -60, -1)
    toggle:SetFrameLevel(ProfessionsFrame:GetFrameLevel() + 20)
    toggle:SetScript("OnClick", function()
        GuildPrideDB.craftCard = not Enabled()
        panel:SetShown(Enabled())
    end)
    toggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["GuildPride Handwerk"], 1, 0.82, 0)
        GameTooltip:AddLine(L["Klick: Rezeptkarte ein/aus"], 1, 1, 1)
        GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave", GameTooltip_Hide)
end

function Card.Refresh(id)
    if not (panel and panel:IsShown()) then return end
    id = id or CurrentID()
    local lines = id and Card.Lines(id, Crafts()) or { L["Wähle links ein Rezept."] }
    for i, fs in ipairs(panel.lines) do fs:SetText(lines[i] or "") end
    panel.track:SetEnabled(id ~= nil)
    local line = Craft.OpenLine()
    local step = line and Craft.CurrentStep(line)
    panel.guide:SetEnabled(step and step.spell ~= nil and step.spell ~= id)
end

function Card.SetShown(on)
    if type(GuildPrideDB) == "table" then GuildPrideDB.craftCard = on and true or false end
    if panel then panel:SetShown(on and ProfessionsFrame and ProfessionsFrame:IsShown() and true or false) end
end

local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "ADDON_LOADED", "TRADE_SKILL_SHOW")
-- Einen Moment nach dem Öffnen zeigen: das Berufsfenster ist beim Ereignis oft noch nicht sichtbar
function Card.ShowSoon()
    C_Timer.After(0.1, function()
        Build()
        if panel and Enabled() and ProfessionsFrame and ProfessionsFrame:IsShown() then
            panel:Show()
            Card.Refresh()
        end
    end)
end

ev:SetScript("OnEvent", function(_, event, name)
    if event == "TRADE_SKILL_SHOW" or name == "Blizzard_Professions" then
        -- Bis 2.41: das X schaltete die Karte dauerhaft aus – einmal wieder einschalten
        if type(GuildPrideDB) == "table" and not GuildPrideDB.craftCardV2 then
            GuildPrideDB.craftCardV2 = true
            GuildPrideDB.craftCard = true
        end
        Build()
        Card.ShowSoon()
    end
end)
Craft.OnChanged(function() if panel and panel:IsShown() then Card.Refresh() end end)
