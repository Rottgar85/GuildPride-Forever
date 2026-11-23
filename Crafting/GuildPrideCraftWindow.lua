-- GuildPride Handwerk: Hauptfenster (/gp handwerk) – vier Reiter:
--   Leveln:  links deine Berufe (mit Balken), rechts Kopf mit Fortschritt und Rang, der Kasten
--            „Als Nächstes“ (aktueller Schritt mit Zutaten, Bestand, was fehlt) und der ganze
--            Weg bis 300. Klick wählt das Rezept, Umschalt+Klick trackt, Rechtsklick hakt ab.
--   Rezepte: alle Rezepte des Berufs, wer sie kann, Filter „nur fehlende“
--   Gewinn:  Rezepte deiner Charaktere nach Gewinn
--   Gilde & Twinks: deine Charaktere (Berufe, Abklingzeiten), darunter wer in der Gilde was kann;
--            Klick flüstert, Umschalt+Klick stellt einen Gildenauftrag ein
local ADDON, ns = ...
local L = ns.L
local Craft, G = ns.Craft, ns.CraftGuides

local W = {}
ns.CraftWindow = W

local ROWS, ROW_H = 26, 19
local win, mode, selLine = nil, "prof", nil

local function Button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    if ns.SkinButton then ns.SkinButton(b) end
    b:SetScript("OnClick", onClick)
    return b
end

local ICONS = {
    [164] = "Interface\\Icons\\Trade_BlackSmithing", [165] = "Interface\\Icons\\INV_Misc_ArmorKit_17",
    [171] = "Interface\\Icons\\Trade_Alchemy", [197] = "Interface\\Icons\\Trade_Tailoring",
    [202] = "Interface\\Icons\\Trade_Engineering", [333] = "Interface\\Icons\\Trade_Engraving",
    [185] = "Interface\\Icons\\INV_Misc_Food_15", [129] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    [186] = "Interface\\Icons\\Trade_Mining", [182] = "Interface\\Icons\\Spell_Nature_NatureTouchGrow",
    [393] = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", [356] = "Interface\\Icons\\Trade_Fishing",
}
W.ICONS = ICONS

---------------------------------------------------------------------
-- Inhalte (ohne Fenster prüfbar)
---------------------------------------------------------------------
-- Berufsliste links: deine zuerst, dann alle anderen
function W.ProfList()
    local mine, seen, out = Craft.MyProfessions(), {}, {}
    for _, p in ipairs(mine) do out[#out + 1] = { line = p.line, skill = p.skill, max = p.max, mine = true }; seen[p.line] = true end
    for _, line in ipairs(G.ORDER) do
        if not seen[line] then out[#out + 1] = { line = line } end
    end
    return out
end

-- Zeilen des Guides: { step, current, done, text }
function W.GuideLines(line)
    local skill = Craft.Skill(line) or 0
    local _, cur, steps = Craft.CurrentStep(line, skill)
    local out = {}
    for i, s in ipairs(steps) do
        local skipped = Craft.IsSkipped(line, s)
        local done = skill >= s.to or skipped
        local name = s.spell and Craft.RecipeName(s.spell) or s.text
        local diff = s.spell and Craft.OpenLine() == line and Craft.Difficulty(s.spell)
        if diff then name = "|cff" .. Craft.COLORS[diff] .. name .. "|r" end
        local count = ""
        if s.count then
            local left = (i == cur) and G.Remaining(s, skill) or s.count
            count = ("~%d×"):format(left)
        end
        local note = ""
        if skipped and skill < s.to then
            note = "  |cff777777" .. L["(übersprungen)"] .. "|r"
        elseif s.spell and Craft.InGame(line, s.spell) == false then
            note = "  |cffff6060" .. L["(nicht in deinem Spiel)"] .. "|r"
        elseif s.pattern then
            note = "  |cff8899aa" .. (L["Bauplan beim Händler: %s"]):format(s.vendor or "?") .. "|r"
        end
        out[#out + 1] = {
            step = s, current = (i == cur), done = done,
            text = ("%s%3d–%d|r  %s  |cffaaaaaa%s|r%s"):format(done and "|cff40ff40" or (i == cur and "|cffffd100" or "|cffcccccc"),
                s.from, s.to, name or "?", count, note),
        }
    end
    return out, cur
end

-- Kopf: Name, Stufe, Rang, nächster Rang, Hinweis
function W.Header(line)
    local skill, max = Craft.Skill(line)
    local parts = { "|cffffd100" .. G.Name(line) .. "|r" }
    if skill then
        local rank, nextRank = G.Rank(max)
        parts[#parts + 1] = ("%d / %d  ·  %s"):format(skill, max or 0, G.Lang(rank))
        if nextRank then
            if skill >= nextRank.learnAt then
                parts[#parts + 1] = "|cff40ff40" .. (L["Jetzt %s beim Lehrer lernen (ab Charakterstufe %d)."]):format(G.Lang(nextRank), nextRank.level) .. "|r"
            else
                parts[#parts + 1] = "|cffaaaaaa" .. (L["%s ab Fertigkeit %d (Charakterstufe %d)"]):format(G.Lang(nextRank), nextRank.learnAt, nextRank.level) .. "|r"
            end
        end
        -- Was kostet der Rest? (GuildPride-Preise, abzüglich Bestand aller Charaktere)
        local money = ns.AH and ns.AH.Money
        if money and skill < 300 then
            local target = math.min(300, math.max(max or 75, skill + 1))
            local c1, u1 = Craft.RouteCost(line, target, skill)
            local c2 = Craft.RouteCost(line, 300, skill)
            parts[#parts + 1] = "|cffaaaaaa" .. (L["Kosten bis %d: ~%s · bis 300: ~%s"]):format(target, money(c1), money(c2))
                .. (u1 > 0 and ("  " .. (L["(%d ohne Preis)"]):format(u1)) or "") .. "|r"
        end
        local M = ns.CraftMini
        local gain = M and M.TodayGain(line) or 0
        if gain > 0 then
            local ph = M.PerHour(line)
            parts[#parts + 1] = "|cff40ff40" .. (L["Heute +%d"]):format(gain) .. "|r" .. (ph and ("  |cffaaaaaa~" .. (L["%d/Std."]):format(ph) .. "|r") or "")
        end
    else
        parts[#parts + 1] = "|cffaaaaaa" .. L["Diesen Beruf hast du nicht."] .. "|r"
    end
    local note = G.RANK_NOTES[line]
    return table.concat(parts, "\n"), note and G.Lang(note) or nil
end

-- Twinks: { text }
function W.AltLines()
    local out, names = {}, {}
    for name in pairs(Craft.Chars()) do names[#names + 1] = name end
    table.sort(names)
    local me = Craft.Me()
    for _, name in ipairs(names) do
        local e = Craft.Chars()[name]
        local profs = {}
        for _, p in ipairs(Craft.MyProfessions(name)) do
            profs[#profs + 1] = ("%s %d/%d"):format(G.Name(p.line), p.skill or 0, p.max or 0)
        end
        out[#out + 1] = { text = ("%s%s|r  |cffaaaaaa%s|r  %s"):format(name == me and "|cff40ff40" or "|cffffffff", name,
            e.level and ((L["Stufe %d"]):format(e.level)) or "", #profs > 0 and table.concat(profs, " · ") or "|cff777777–|r") }
    end
    local M = ns.CraftMini
    local cds = M and M.CooldownList() or {}
    if #cds > 0 then
        out[#out + 1] = { text = " " }
        out[#out + 1] = { text = "|cffffd100" .. L["Abklingzeiten"] .. "|r" }
        local now = GetServerTime()
        for _, c in ipairs(cds) do
            out[#out + 1] = { text = ("   %s: %s  %s"):format(c.name, c.what,
                c.ready and ("|cff40ff40" .. L["bereit"] .. "|r") or ("|cffaaaaaa" .. M.Left(c.readyAt - now) .. "|r")) }
        end
    end
    return out
end

-- Rezept-Lexikon: alle Rezepte, die dein Spiel für den Beruf kennt (auch ungelernte), mit wer
-- sie kann. text = Suche im Namen, missing = nur die, die keiner deiner Charaktere kann
function W.CodexLines(line, text, missing)
    local ids, seen = {}, {}
    local all = type(GuildPrideDB) == "table" and type(GuildPrideDB.craftAll) == "table" and GuildPrideDB.craftAll[line]
    for id in pairs(all or {}) do if not seen[id] then seen[id] = true; ids[#ids + 1] = id end end
    for _, st in ipairs(G.STEPS[line] or {}) do if not seen[st[3]] then seen[st[3]] = true; ids[#ids + 1] = st[3] end end
    text = strtrim(text or ""):lower()
    local me, out = Craft.Me(), {}
    for _, id in ipairs(ids) do
        local name = Craft.RecipeName(id)
        if text == "" or name:lower():find(text, 1, true) then
            local who = {}
            for char, e in pairs(Craft.Chars()) do
                if type(e) == "table" and e.known and e.known[line] and e.known[line][id] then
                    who[#who + 1] = char == me and L["du"] or char
                end
            end
            table.sort(who)
            if not missing or #who == 0 then
                local diff = Craft.OpenLine() == line and Craft.Difficulty(id)
                local shown = diff and ("|cff" .. Craft.COLORS[diff] .. name .. "|r") or ("|cffffffff" .. name .. "|r")
                out[#out + 1] = { recipe = id, name = name, text = shown .. "  " .. (#who > 0
                    and ("|cff40ff40✓ " .. table.concat(who, ", ") .. "|r") or ("|cffff8040" .. L["fehlt"] .. "|r")) }
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Gewinn: alle Rezepte deiner Charaktere, bester Gewinn zuerst
function W.ProfitLines()
    local X = ns.CraftExtras
    local out = {}
    if not (X and X.ProfitList) then return out end
    local money = ns.AH and ns.AH.Money or tostring
    for _, p in ipairs(X.ProfitList()) do
        local v = p.v
        out[#out + 1] = { profit = p, text = ("%s%s|r  %s  |cffaaaaaa%s → %s|r  |cff8899aa%s|r"):format(
            v.profit >= 0 and "|cff40ff40+" or "|cffff6060-", money(math.abs(v.profit)), Craft.RecipeName(p.id),
            money(v.cost), money(v.sell or 0), table.concat(p.who, ", ")) }
    end
    return out
end

-- Anleitung: je Schritt „von–bis: N× Rezept herstellen“, darunter die Zutaten mit Gesamtmenge,
-- Bestand (du + Twinks) und was fehlt, dazu Bauplan und Händler. Erledigte Schritte nur kurz.
function W.InstructionLines(line)
    local skill = Craft.Skill(line) or 0
    local _, cur, steps = Craft.CurrentStep(line, skill)
    local out, total = {}, 0
    for i, s in ipairs(steps) do
        local done = skill >= s.to or Craft.IsSkipped(line, s)
        local n = s.count and ((i == cur) and G.Remaining(s, skill) or s.count) or nil
        if s.spell then
            local name = Craft.RecipeName(s.spell)
            if done then
                out[#out + 1] = { step = s, done = true, text = ("|cff40ff40%d–%d|r  |cff777777%s – %s|r"):format(s.from, s.to, name, L["erledigt"]) }
            else
                total = total + (n or 0)
                local stepCost = ns.AH and ns.AH.Money and n and n > 0 and Craft.StepCost(s.spell, n)
                out[#out + 1] = { step = s, current = (i == cur),
                    text = ("%s%d–%d|r  " .. L["%d× %s herstellen"]):format(i == cur and "|cffffd100" or "|cffffffff", s.from, s.to, n or 0, "|cffffd100" .. name .. "|r")
                        .. ((stepCost and stepCost > 0) and ("  |cffaaaaaa≈ " .. ns.AH.Money(stepCost) .. "|r") or "") }
                for _, x in ipairs(Craft.KnownReagents(s.spell) or {}) do
                    local need = x[2] * (n or 0)
                    local bags, bank = Craft.Count(x[1])
                    local _, alts = Craft.AltCounts(x[1])
                    local have = bags + bank + alts
                    local miss = math.max(0, need - have)
                    -- günstiger selbst herstellen? (z. B. Erz schmelzen statt Barren kaufen)
                    local _, how, via = Craft.CheapestPrice(x[1])
                    local craftHint = (miss > 0 and how == "craft" and via)
                        and ("  |cff8899aa" .. (L["billiger selbst: %s"]):format(Craft.RecipeName(via)) .. "|r") or ""
                    out[#out + 1] = { step = s, item = x[1], text = ("      %d× %s  %s"):format(need, Craft.ItemName(x[1]),
                        miss > 0 and ("|cffff6060" .. (L["(hast %d, fehlt %d)"]):format(have, miss) .. "|r")
                                 or ("|cff40ff40" .. (L["(hast %d)"]):format(have) .. "|r")) .. craftHint }
                end
                if s.pattern then
                    out[#out + 1] = { step = s, item = s.pattern, text = "      |cff8899aa" .. (L["Bauplan „%s“ bei %s kaufen"]):format(Craft.ItemName(s.pattern), s.vendor or "?") .. "|r" }
                end
            end
        else
            out[#out + 1] = { step = s, done = done, current = (i == cur) and not done,
                text = ("%s%d–%d|r  %s"):format(done and "|cff40ff40" or "|cffffffff", s.from, s.to, s.text or "") }
        end
    end
    return out, cur, total
end

-- Route bis zum Ende des aktuellen Rangs (oder 300) in den Tracker
function W.TrackRoute(line)
    local skill, max = Craft.Skill(line)
    if not skill then return 0 end
    local target = math.min(300, math.max(max or 75, skill + 1))
    local recipes = Craft.RouteNeeds(line, target, skill)
    local n = 0
    for id, crafts in pairs(recipes) do
        if ns.CraftTrack then ns.CraftTrack.AddRecipe(id, crafts) end
        n = n + 1
    end
    return n, target
end

-- Gilde: Suche im Handwerker-Verzeichnis
function W.GuildLines(text)
    local C = ns.Crafts
    local out = {}
    if not (C and C.Search) then return out end
    local A = ns.CraftAsk
    for _, a in ipairs(A and A.Find(text) or {}) do
        out[#out + 1] = { row = { name = a.who, id = a.id }, text = ("|cff40ff40%s|r  |cffffffff%s|r%s  " .. L["kann"] .. "  |cffffd100%s|r"):format(
            L["Antwort"], a.who, (a.char and a.char ~= a.who) and (" (" .. a.char .. ")") or "", Craft.RecipeName(a.id)) }
    end
    local ok, rows = pcall(C.Search, text or "")
    for _, r in ipairs(ok and rows or {}) do
        out[#out + 1] = { row = r, text = ("|cffffffff%s|r  %s %d/%d%s"):format(r.name, r.prof, r.level or 0, r.max or 0,
            r.recipe and ("  ·  |cffffd100" .. r.recipe .. "|r") or (r.recipes and r.recipes > 0 and ("  |cff777777" .. (L["%d Rezepte"]):format(r.recipes) .. "|r") or "")) }
    end
    return out
end

---------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------
-- kleines Bild im Text
local function Icon(tex) return tex and ("|T" .. tostring(tex) .. ":16:16:0:0|t ") or "" end
W.Icon = Icon

local function StepTooltip(owner, s)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if s.spell then
        -- oben das hergestellte Item mit allen Werten, darunter Rezept und Zutaten mit Bildern
        local out, made = Craft.OutputItem(s.spell)
        if out and GameTooltip.SetItemByID then
            GameTooltip:SetItemByID(out)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(Icon(Craft.RecipeIcon(s.spell)) .. (L["Herstellen: %s"]):format(Craft.RecipeName(s.spell))
                .. ((made or 1) > 1 and ("  |cffaaaaaa" .. (L["(ergibt %d)"]):format(made) .. "|r") or ""), 1, 0.82, 0)
        else
            GameTooltip:AddLine(Icon(Craft.RecipeIcon(s.spell)) .. Craft.RecipeName(s.spell), 1, 0.82, 0)
            GameTooltip:AddLine(L["Was es herstellt, zeigt das Spiel erst nach einmal Berufsfenster öffnen."], 0.7, 0.7, 0.7, true)
        end
        local r = Craft.Reagents(s.spell)
        if r then
            for _, x in ipairs(r) do
                local need = x[2] * (s.count or 1)
                local bags, bank = Craft.Count(x[1])
                local have = bags + bank
                GameTooltip:AddDoubleLine(Icon(Craft.ItemIcon(x[1])) .. ("%d× %s"):format(need, Craft.ItemName(x[1])), ("%d"):format(have),
                    1, 1, 1, have >= need and 0.25 or 1, have >= need and 1 or 0.4, 0.25)
            end
        else
            GameTooltip:AddLine(L["Zutaten unbekannt – Berufsfenster einmal öffnen."], 0.7, 0.7, 0.7, true)
        end
        if s.pattern then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine((L["Bauplan: %s"]):format(Craft.ItemName(s.pattern)), 0.6, 0.8, 1, true)
            GameTooltip:AddLine((L["Händler: %s"]):format(s.vendor or "?"), 0.6, 0.8, 1, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Klick: im Berufsfenster wählen · Umschalt+Klick: tracken · Rechtsklick: abhaken"], 0.6, 0.6, 0.6, true)
    else
        GameTooltip:AddLine(s.text or "", 1, 1, 1, true)
    end
    GameTooltip:Show()
end

-- „Als Nächstes“: der aktuelle Schritt mit seinen Zutaten (aus der Anleitung)
function W.NowLines(line)
    local lines = W.InstructionLines(line)
    local out, step = {}, nil
    for _, l in ipairs(lines) do
        if not step and l.current then step = l.step end
        if step and l.step == step then out[#out + 1] = l end
    end
    return out
end

local GOLD = { 0.79, 0.64, 0.36 }
local MODES = {
    { key = "prof",   text = "Leveln",         w = 100 },
    { key = "codex",  text = "Rezepte",        w = 100 },
    { key = "profit", text = "Gewinn",         w = 100 },
    { key = "guild",  text = "Gilde & Twinks", w = 130 },
}

local function Line(parent, x1, y, x2)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    t:SetPoint("TOPLEFT", x1, y); t:SetPoint("RIGHT", parent, "RIGHT", x2, 0)
    t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
    return t
end

local function Bar(parent, h)
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetHeight(h)
    b:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    b:SetStatusBarColor(GOLD[1], GOLD[2], GOLD[3])
    b:SetMinMaxValues(0, 1); b:SetValue(0)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints(); b.bg:SetColorTexture(0, 0, 0, 0.45)
    return b
end

local function Tip(btn, title, text)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(title, 1, 0.82, 0)
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)
end

local function SearchText()
    local t = win and win.search and win.search:GetText()
    return type(t) == "string" and t or ""
end

local X0 = 210   -- rechte Seite beginnt hier

local function Build()
    win = CreateFrame("Frame", "GuildPrideCraftWindow", UIParent, "BackdropTemplate")
    win:SetSize(720, 600)
    win:SetPoint("CENTER")
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    if ns.SkinDialog then ns.SkinDialog(win) end
    win:Hide()
    tinsert(UISpecialFrames, "GuildPrideCraftWindow")

    local title = win:CreateFontString(nil, "OVERLAY", "GPFont_Large")
    title:SetPoint("TOPLEFT", 18, -16)
    title:SetText(L["GuildPride Handwerk"])
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    if ns.SkinClose then ns.SkinClose(close) end

    -- nur vier Reiter, in einer Reihe neben dem Titel
    win.tabs = {}
    local prev
    for _, m in ipairs(MODES) do
        local b = Button(win, L[m.text], m.w, function() W.SetMode(m.key) end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", X0, -12) end
        win.tabs[m.key] = b
        prev = b
    end
    Line(win, 14, -44, -14)

    -- Berufsliste links: „Deine Berufe“, darunter „Weitere Berufe“
    win.side = CreateFrame("Frame", nil, win)
    win.side:SetPoint("TOPLEFT", 12, -50); win.side:SetSize(186, 538)
    local sbg = win.side:CreateTexture(nil, "BACKGROUND")
    sbg:SetAllPoints(); sbg:SetColorTexture(0, 0, 0, 0.25)
    win.mineLabel = win.side:CreateFontString(nil, "OVERLAY", "GPFont_TextBold")
    win.mineLabel:SetText(L["Deine Berufe"])
    win.otherLabel = win.side:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
    win.otherLabel:SetText(L["Weitere Berufe"])
    win.profs = {}
    for i = 1, #G.ORDER do
        local b = CreateFrame("Button", nil, win.side)
        b:SetSize(178, 30)
        b.hl = b:CreateTexture(nil, "BACKGROUND")
        b.hl:SetAllPoints(); b.hl:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.22); b.hl:Hide()
        b.edge = b:CreateTexture(nil, "ARTWORK")
        b.edge:SetPoint("TOPLEFT"); b.edge:SetPoint("BOTTOMLEFT"); b.edge:SetWidth(3)
        b.edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1); b.edge:Hide()
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(24, 24); b.icon:SetPoint("LEFT", 6, 0)
        b.text = b:CreateFontString(nil, "OVERLAY", "GPFont_Text")
        b.text:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 6, 0); b.text:SetPoint("RIGHT", -34, 0)
        b.text:SetJustifyH("LEFT"); b.text:SetWordWrap(false)
        b.skill = b:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
        b.skill:SetPoint("TOPRIGHT", -4, -3)
        b.bar = Bar(b, 4)
        b.bar:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 6, 1); b.bar:SetPoint("RIGHT", -4, 0)
        b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
        b:SetScript("OnClick", function()
            selLine = b.line
            if ns.CraftNPC then ns.CraftNPC.SetLine(selLine) end
            win.offset = 0; win.jump = true
            W.Refresh()
        end)
        win.profs[i] = b
    end

    -- Kopf rechts: großes Symbol, Name, Fortschrittsbalken, Rang
    win.head = CreateFrame("Frame", nil, win)
    win.head:SetPoint("TOPLEFT", X0, -54); win.head:SetPoint("RIGHT", -16, 0); win.head:SetHeight(100)
    win.head.icon = win.head:CreateTexture(nil, "ARTWORK")
    win.head.icon:SetSize(44, 44); win.head.icon:SetPoint("TOPLEFT", 0, -2)
    win.head.name = win.head:CreateFontString(nil, "OVERLAY", "GPFont_Huge")
    win.head.name:SetPoint("TOPLEFT", win.head.icon, "TOPRIGHT", 10, 0)
    win.head.rank = win.head:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
    win.head.rank:SetPoint("BOTTOMLEFT", win.head.name, "BOTTOMRIGHT", 8, 1)
    win.head.bar = Bar(win.head, 16)
    win.head.bar:SetPoint("BOTTOMLEFT", win.head.icon, "BOTTOMRIGHT", 10, 0); win.head.bar:SetWidth(300)
    win.head.barText = win.head.bar:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
    win.head.barText:SetPoint("CENTER")
    win.head.info = win.head:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
    win.head.info:SetPoint("TOPLEFT", win.head.icon, "BOTTOMLEFT", 0, -8); win.head.info:SetPoint("RIGHT", 0, 0)
    win.head.info:SetJustifyH("LEFT"); win.head.info:SetSpacing(2)

    -- zwei Knöpfe statt vier
    win.route = Button(win.head, L["In den Tracker"], 136, function()
        local n, target = W.TrackRoute(selLine)
        if n > 0 then
            ns.Print((L["%d Rezepte bis %d im Tracker."]):format(n, target))
            if ns.CraftTrack then ns.CraftTrack.Show() end
        else ns.Print(L["Für diesen Beruf gibt es gerade nichts zu tracken."]) end
    end)
    win.route:SetPoint("TOPRIGHT", 0, 0)
    Tip(win.route, L["In den Tracker"], L["Alle restlichen Guide-Schritte bis zum Ende deines Rangs kommen in den Tracker – mit den Zutaten, die dir noch fehlen."])
    win.map = Button(win.head, L["Lehrer zeigen"], 136, function()
        if ns.CraftNPC and selLine then ns.CraftNPC.ShowOnMap(selLine) end
    end)
    win.map:SetPoint("TOPRIGHT", win.route, "BOTTOMRIGHT", 0, -4)
    Tip(win.map, L["Lehrer zeigen"], L["Zeigt alle Lehrer dieses Berufs (und bekannte Bauplan-Händler) auf der Weltkarte und setzt einen Wegpunkt zum passenden Lehrer."])

    -- Kasten „Als Nächstes“
    win.now = CreateFrame("Frame", nil, win)
    win.now:SetPoint("TOPLEFT", X0, -178); win.now:SetPoint("RIGHT", -16, 0); win.now:SetHeight(94)
    local nbg = win.now:CreateTexture(nil, "BACKGROUND")
    nbg:SetAllPoints(); nbg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.10)
    local nedge = win.now:CreateTexture(nil, "ARTWORK")
    nedge:SetPoint("TOPLEFT"); nedge:SetPoint("BOTTOMLEFT"); nedge:SetWidth(3)
    nedge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    win.now.title = win.now:CreateFontString(nil, "OVERLAY", "GPFont_TextBold")
    win.now.title:SetPoint("TOPLEFT", 12, -8)
    win.now.title:SetText(L["Als Nächstes"])
    win.now.lines = {}
    for i = 1, 4 do
        local t = win.now:CreateFontString(nil, "OVERLAY", i == 1 and "GPFont_Text" or "GPFont_TextSmall")
        t:SetPoint("TOPLEFT", 12, -10 - i * 17); t:SetPoint("RIGHT", -10, 0)
        t:SetJustifyH("LEFT"); t:SetWordWrap(false)
        win.now.lines[i] = t
    end
    win.listTitle = win:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
    win.listTitle:SetPoint("TOPLEFT", X0, -278); win.listTitle:SetPoint("RIGHT", -16, 0)
    win.listTitle:SetJustifyH("LEFT")
    win.listTitle:SetText(L["Der Weg bis 300 · Klick: Rezept wählen · Umschalt+Klick: tracken · Rechtsklick: abhaken"])

    -- Suche (Rezepte, Gilde)
    win.search = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    win.search:SetSize(220, 22)
    win.search:SetAutoFocus(false)
    if ns.SkinEditBox then ns.SkinEditBox(win.search) end
    win.search:SetScript("OnTextChanged", function() win.offset = 0; W.Refresh() end)
    win.search:SetScript("OnEscapePressed", win.search.ClearFocus)
    win.searchHint = win:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
    win.ask = Button(win, L["Gilde fragen"], 120, function()
        if ns.CraftAsk then ns.CraftAsk.Ask(SearchText()) end
    end)
    win.ask:SetPoint("LEFT", win.search, "RIGHT", 10, 0)
    Tip(win.ask, L["Gilde fragen"], L["Fragt alle Mitglieder mit GuildPride, wer das Rezept kann – auch mit Twinks. Antworten erscheinen hier und bleiben gemerkt."])
    win.searchHint:SetPoint("LEFT", win.ask, "RIGHT", 10, 0)
    win.searchHint:SetText(L["Rezept, Beruf oder Name"])
    win.missing = Button(win, L["Nur fehlende"], 120, function()
        W.onlyMissing = not W.onlyMissing
        win.offset = 0
        W.Refresh()
    end)

    win.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, win)
        r:SetHeight(ROW_H)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r.stripe = r:CreateTexture(nil, "BACKGROUND")
        r.stripe:SetAllPoints()
        r.mark = r:CreateTexture(nil, "ARTWORK")
        r.mark:SetSize(12, 12); r.mark:SetPoint("LEFT", 3, 0)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 19, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", 20, 0); r.text:SetPoint("RIGHT", -2, 0)
        r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
        r:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
        r:SetScript("OnEnter", function(self)
            local l = self.data
            if l and l.item then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if GameTooltip.SetItemByID then GameTooltip:SetItemByID(l.item) else GameTooltip:SetHyperlink("item:" .. l.item) end
                GameTooltip:Show()
            elseif l and l.step then StepTooltip(self, l.step)
            elseif l and l.recipe then StepTooltip(self, { spell = l.recipe, count = 1, from = 0, to = 0 }) end
            if l and l.profit then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(Craft.RecipeName(l.profit.id), 1, 0.82, 0)
                if ns.AH and ns.AH.RecipeValueText then
                    local v = l.profit.v
                    GameTooltip:AddLine(ns.AH.RecipeValueText({ cost = v.cost, missing = v.missing, sell = v.sell, profit = v.profit, output = v.out }), 1, 1, 1, true)
                end
                GameTooltip:AddLine(L["Klick: im Berufsfenster wählen · Umschalt+Klick: tracken"], 0.6, 0.6, 0.6, true)
                GameTooltip:Show()
            end
            if l and l.row then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(l.row.name, 1, 0.82, 0)
                GameTooltip:AddLine(L["Klick: anflüstern"], 1, 1, 1)
                if l.row.id then GameTooltip:AddLine(L["Umschalt+Klick: Gildenauftrag für dieses Item"], 1, 1, 1) end
                GameTooltip:Show()
            end
        end)
        r:SetScript("OnLeave", GameTooltip_Hide)
        r:SetScript("OnClick", function(self, button)
            if button == "RightButton" and self.data and self.data.step and selLine then
                Craft.ToggleSkip(selLine, self.data.step)
                W.Refresh()
            else
                W.RowClick(self.data)
            end
        end)
        win.rows[i] = r
    end
    win.offset = 0
    win.visible = ROWS
    win:EnableMouseWheel(true)
    win:SetScript("OnMouseWheel", function(_, d)
        win.offset = math.max(0, math.min(win.offset - d * 3, (win.listLen or 0) - win.visible))
        W.Refresh()
    end)
    win.scroll = Craft.ThinScroll(win, function(v) win.offset = v; W.Refresh() end)
    win.empty = win:CreateFontString(nil, "OVERLAY", "GPFont_Muted")
    win.empty:SetPoint("CENTER", 90, 0)
    win.empty:SetWidth(440)
end

function W.RowClick(l)
    if not l then return end
    if l.profit or l.recipe then
        local id = l.profit and l.profit.id or l.recipe
        if IsShiftKeyDown() and ns.CraftTrack then
            ns.CraftTrack.AddRecipe(id, 1)
        elseif Craft.OpenLine() and ns.CraftCard and ns.CraftCard.Pick then
            ns.CraftCard.Pick(id)
        elseif not Craft.OpenLine() then
            ns.Print(L["Öffne erst das Berufsfenster dieses Berufs."])
        end
        return
    end
    if l.step and l.step.spell then
        local s = l.step
        if IsShiftKeyDown() and ns.CraftTrack then
            local skill = Craft.Skill(selLine) or 0
            local n = (l.current and G.Remaining(s, skill)) or s.count or 1
            ns.CraftTrack.AddRecipe(s.spell, n)
            ns.Print((L["%s ×%d im Tracker."]):format(Craft.RecipeName(s.spell), n))
        elseif Craft.OpenLine() == selLine then
            if ns.CraftCard and ns.CraftCard.Pick then ns.CraftCard.Pick(s.spell) else Craft.SelectRecipe(s.spell) end
        else
            ns.Print(L["Öffne erst das Berufsfenster dieses Berufs."])
        end
    elseif l.row then
        local r = l.row
        if IsShiftKeyDown() and r.id then
            local _, c = Craft.Reagents(r.id)
            local out = c and c.out
            if out and ns.AH and ns.AH.AddOrder and ns.AH.AddOrder(out, 1) then
                ns.Print((L["Gildenauftrag eingestellt: %s"]):format(Craft.ItemName(out)))
            else
                ns.Print(L["Dafür kennt GuildPride das Item noch nicht – stell den Auftrag im Auktionshaus unter „Gildenaufträge“ ein."])
            end
        elseif ChatFrame_SendTell then
            ChatFrame_SendTell(r.name)
        end
    end
end

-- Bild einer Zeile: Item, sonst Rezept (hergestelltes Item), sonst keins
function W.RowIcon(l)
    if not l then return nil end
    if l.item then return Craft.ItemIcon(l.item) end
    local id = (l.step and l.step.spell) or l.recipe or (l.profit and l.profit.id)
    return id and Craft.RecipeIcon(id) or nil
end

-- Zeilen zeigen: ab (x, top), höchstens n Stück; Streifen, aktueller Schritt golden, erledigte blass
local function SetRows(list, x, top, n)
    n = math.min(n, ROWS)
    win.visible, win.listLen = n, #list
    win.offset = math.max(0, math.min(win.offset, #list - n))
    -- dünne Scrollleiste rechts neben den Zeilen, nur wenn nötig
    win.scroll:ClearAllPoints()
    win.scroll:SetPoint("TOPRIGHT", win, "TOPRIGHT", -12, top)
    win.scroll:SetHeight(n * ROW_H)
    win.scroll:Update(win.offset, #list, n)
    for i, r in ipairs(win.rows) do
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", x, top - (i - 1) * ROW_H)
        r:SetPoint("RIGHT", win, "RIGHT", -24, 0)
        local l = i <= n and list[i + win.offset] or nil
        r.data = l
        r:SetShown(l ~= nil)
        if l then
            r.text:SetText(l.text)
            if l.current then
                r.stripe:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
            elseif (i + win.offset) % 2 == 0 then
                r.stripe:SetColorTexture(1, 1, 1, 0.04)
            else
                r.stripe:SetColorTexture(0, 0, 0, 0)
            end
            r:SetAlpha(l.done and 0.6 or 1)
            local tex = W.RowIcon(l)
            r.icon:SetShown(tex ~= nil)
            if tex then r.icon:SetTexture(tex) end
            r.text:ClearAllPoints()
            r.text:SetPoint("LEFT", tex and 40 or 20, 0); r.text:SetPoint("RIGHT", -2, 0)
            if l.current then r.mark:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"); r.mark:Show()
            elseif l.done then r.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check"); r.mark:Show()
            else r.mark:Hide() end
        end
    end
end

function W.SetMode(m)
    mode = m
    if win then win.offset = 0; win.jump = true end
    W.Refresh()
end

-- Berufsliste links mit Überschriften und Balken
local function RefreshSide()
    local list = W.ProfList()
    if not selLine then selLine = list[1] and list[1].line end
    local y, others = -8, false
    win.mineLabel:SetShown(list[1] and list[1].mine or false)
    if list[1] and list[1].mine then
        win.mineLabel:ClearAllPoints(); win.mineLabel:SetPoint("TOPLEFT", 10, y); y = y - 20
    end
    for i, b in ipairs(win.profs) do
        local p = list[i]
        b.line = p and p.line
        b:SetShown(p ~= nil)
        if p then
            if not p.mine and not others then
                others = true
                y = y - 6
                win.otherLabel:ClearAllPoints(); win.otherLabel:SetPoint("TOPLEFT", 10, y); y = y - 18
            end
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", 4, y)
            y = y - (p.mine and 32 or 26)
            b:SetHeight(p.mine and 30 or 24)
            b.icon:SetTexture(ICONS[p.line])
            b.icon:SetDesaturated(not p.mine)
            b.icon:SetSize(p.mine and 24 or 18, p.mine and 24 or 18)
            b.text:SetText((p.mine and "|cffffffff" or "|cff888888") .. G.Name(p.line) .. "|r")
            b.text:ClearAllPoints()
            if p.mine then b.text:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 6, 0)
            else b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0) end
            b.text:SetPoint("RIGHT", -34, 0)
            b.skill:SetText(p.skill and ("|cffffd100" .. p.skill .. "|r") or "")
            b.bar:SetShown(p.mine and p.skill ~= nil)
            if p.skill then b.bar:SetMinMaxValues(0, math.max(1, p.max or 300)); b.bar:SetValue(p.skill) end
            local sel = p.line == selLine
            b.hl:SetShown(sel); b.edge:SetShown(sel)
        end
    end
    win.otherLabel:SetShown(others)
end

-- Kopf: Symbol, Name, Balken, Rang und die Hinweise aus W.Header
local function RefreshHead()
    local h = win.head
    local skill, max = Craft.Skill(selLine)
    h.icon:SetTexture(ICONS[selLine])
    h.icon:SetDesaturated(skill == nil)
    h.name:SetText(G.Name(selLine))
    local text, note = W.Header(selLine)
    local parts = {}
    for part in (text .. "\n"):gmatch("(.-)\n") do parts[#parts + 1] = part end
    -- Zeile 1 ist der Name, Zeile 2 (mit Beruf) Stufe und Rang – beides zeigt der Kopf grafisch
    local first = skill and 3 or 2
    local info = {}
    for i = first, #parts do info[#info + 1] = parts[i] end
    if note then info[#info + 1] = "|cff888888" .. note .. "|r" end
    h.info:SetText(table.concat(info, "\n"))
    if skill then
        local rank = G.Rank(max)
        h.rank:SetText(rank and G.Lang(rank) or "")
        h.bar:Show()
        h.bar:SetMinMaxValues(0, math.max(1, max or 300)); h.bar:SetValue(skill)
        h.barText:SetText(("%d / %d"):format(skill, max or 0))
    else
        h.rank:SetText("")
        h.bar:Hide()
    end
    win.route:SetShown(skill ~= nil)

    -- Als Nächstes
    local now = skill and W.NowLines(selLine) or {}
    for i, t in ipairs(win.now.lines) do
        local l = now[i]
        t:SetText(l and (Icon(W.RowIcon(l)) .. (l.text:gsub("^%s+", ""))) or "")
    end
    if #now > 4 then win.now.lines[4]:SetText("|cffaaaaaa" .. (L["… und %d weitere Zutaten (Maus über den Schritt)"]):format(#now - 3) .. "|r") end
    if not skill then
        win.now.lines[1]:SetText("|cffaaaaaa" .. L["Diesen Beruf hast du nicht – hier siehst du trotzdem den ganzen Weg."] .. "|r")
    elseif #now == 0 then
        win.now.lines[1]:SetText("|cff40ff40" .. L["Fertig – für diesen Beruf gibt es nichts mehr zu tun."] .. "|r")
    end
end

function W.Refresh()
    if not (win and win:IsShown()) then return end
    for key, b in pairs(win.tabs) do
        if b.gpBg then b.gpBg:SetTexture("Interface\\AddOns\\GuildPrideForever\\Media\\" .. (key == mode and "nav_active" or "nav")) end
    end
    local isProf, isCodex, isGuild = mode == "prof", mode == "codex", mode == "guild"
    win.side:SetShown(isProf or isCodex)
    win.head:SetShown(isProf); win.now:SetShown(isProf); win.listTitle:SetShown(isProf)
    win.search:SetShown(isGuild or isCodex); win.searchHint:SetShown(isGuild); win.ask:SetShown(isGuild)
    win.search:ClearAllPoints()
    if isCodex then win.search:SetPoint("TOPLEFT", X0 + 6, -56) else win.search:SetPoint("TOPLEFT", 24, -56) end
    win.missing:SetShown(isCodex)
    win.missing:ClearAllPoints(); win.missing:SetPoint("LEFT", win.search, "RIGHT", 10, 0)
    win.missing:SetText(W.onlyMissing and L["Alle Rezepte"] or L["Nur fehlende"])
    win.empty:SetText("")
    if isProf or isCodex then
        RefreshSide()
        if isCodex then
            local lines = W.CodexLines(selLine, SearchText(), W.onlyMissing)
            SetRows(lines, X0, -86, 25)
            if #lines == 0 then win.empty:SetText(L["Keine Rezepte – öffne einmal das Berufsfenster dieses Berufs."]) end
            return
        end
        RefreshHead()
        local lines, cur = W.GuideLines(selLine)
        -- beim ersten Zeigen zum aktuellen Schritt blättern
        if win.jump and cur then win.offset = math.max(0, cur - 3); win.jump = false end
        SetRows(lines, X0, -294, 14)
    elseif mode == "profit" then
        local lines = W.ProfitLines()
        SetRows(lines, 16, -54, ROWS)
        if #lines == 0 then win.empty:SetText(L["Noch keine Preise – öffne einmal das Auktionshaus und die Berufsfenster deiner Charaktere."]) end
    else
        -- Gilde & Twinks: ohne Suche oben deine Charaktere, darunter die Gilde
        local text = SearchText()
        local lines = {}
        if strtrim(text or "") == "" then
            lines[#lines + 1] = { text = "|cffe8c27a" .. L["Deine Charaktere"] .. "|r" }
            for _, l in ipairs(W.AltLines()) do lines[#lines + 1] = l end
            lines[#lines + 1] = { text = " " }
            lines[#lines + 1] = { text = "|cffe8c27a" .. L["Gilde"] .. "|r" }
        end
        for _, l in ipairs(W.GuildLines(text)) do lines[#lines + 1] = l end
        SetRows(lines, 16, -86, 25)
        if #lines == 0 then win.empty:SetText(L["Nichts gefunden. Das Verzeichnis füllt sich, wenn Mitglieder ihre Berufsfenster öffnen."]) end
    end
end

function W.Show(line, m)
    if not win then Build() end
    if line then selLine = line end
    if ns.CraftNPC and selLine then ns.CraftNPC.SetLine(selLine) end
    mode = m or mode
    win.jump = true
    win:Show()
    W.Refresh()
end

function W.Toggle()
    if win and win:IsShown() then win:Hide() else W.Show() end
end

Craft.OnChanged(function() if win and win:IsShown() then W.Refresh() end end)

-- /gp handwerk · /gp tracker
local origSlash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd, rest = strtrim(arg or ""):match("^(%S*)%s*(.-)$")
    cmd, rest = (cmd or ""):lower(), (rest or ""):lower()
    if (cmd == "handwerk" or cmd == "crafting") and rest == "diag" then Craft.Diag()
    elseif (cmd == "handwerk" or cmd == "crafting") and (rest == "mini" or rest == "kompakt") then
        if ns.CraftMini then ns.CraftMini.Toggle() end
    elseif cmd == "handwerk" or cmd == "crafting" or cmd == "guide" then W.Toggle()
    elseif cmd == "tracker" or cmd == "track" then if ns.CraftTrack then ns.CraftTrack.Toggle() end
    elseif origSlash then origSlash(arg) end
end
