-- GuildPride Handwerk: Helfer rund um die Berufe
--   • Hinweise: Guide-Schritt geschafft (was als Nächstes kommt), Beruf am Rang-Limit
--     (welchen Rang du jetzt beim Lehrer lernst)
--   • Am Lehrer: Rezepte, die dein Guide braucht, stehen im Tooltip; beim Öffnen sagt der
--     Chat, welche du jetzt lernen solltest
--   • Gewinn: alle Rezepte deiner Charaktere mit Kosten, Wert und Gewinn (GuildPride-Preise)
--   • Item-Tooltip: Bestand je Charakter und was dein Guide davon noch braucht
-- Schalter: craftHints (Hinweise und Lehrer), craftTooltip (Item-Tooltip)
local ADDON, ns = ...
local L = ns.L
local Craft, G = ns.Craft, ns.CraftGuides

local X = {}
ns.CraftExtras = X

local function Opt(key) return not (type(GuildPrideDB) == "table" and GuildPrideDB[key] == false) end

---------------------------------------------------------------------
-- Hinweise bei Fortschritt
---------------------------------------------------------------------
local last = {}   -- [Skill-Line] = Stufe beim letzten Blick
local function Notice(text)
    ns.Print(text)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        UIErrorsFrame:AddMessage(plain, 1, 0.82, 0)
    end
    if PlaySound and SOUNDKIT and SOUNDKIT.UI_PROFESSIONS_SKILL_UP then pcall(PlaySound, SOUNDKIT.UI_PROFESSIONS_SKILL_UP) end
end

-- Was ist zwischen alter und neuer Stufe passiert? Liste von Hinweisen (auch für Tests)
function X.ProgressNotes(line, old, new, max)
    local out = {}
    if not (old and new and new > old) then return out end
    for _, s in ipairs(G.Steps(line)) do
        if old < s.to and new >= s.to and not s.gather then
            local nextStep = Craft.CurrentStep(line, new)
            local name = s.spell and Craft.RecipeName(s.spell) or s.text or "?"
            if nextStep then
                local nextName = nextStep.spell and Craft.RecipeName(nextStep.spell) or nextStep.text or "?"
                out[#out + 1] = (L["%s: Schritt „%s“ geschafft. Weiter mit „%s“ (%d–%d)."]):format(G.Name(line), name, nextName, nextStep.from, nextStep.to)
            else
                out[#out + 1] = (L["%s: Guide geschafft – 300!"]):format(G.Name(line))
            end
        end
    end
    local _, nextRank = G.Rank(max)
    if max and nextRank and new >= max - 5 and old < max - 5 and new >= nextRank.learnAt then
        out[#out + 1] = (L["%s: fast am Limit (%d/%d) – lern jetzt %s beim Lehrer (ab Charakterstufe %d)."]):format(
            G.Name(line), new, max, G.Lang(nextRank), nextRank.level)
    end
    return out
end

local function CheckProgress()
    if not Opt("craftHints") then return end
    for _, p in ipairs(Craft.MyProfessions()) do
        local old = last[p.line]
        if old then
            for _, t in ipairs(X.ProgressNotes(p.line, old, p.skill, p.max)) do Notice(t) end
        end
        last[p.line] = p.skill
    end
end
Craft.OnChanged(CheckProgress)

---------------------------------------------------------------------
-- Am Lehrer
---------------------------------------------------------------------
-- Rezeptname → { line, step } für alle Guide-Rezepte deiner Berufe, die noch vor dir liegen
local function GuideByName()
    local map = {}
    for _, p in ipairs(Craft.MyProfessions()) do
        for _, s in ipairs(G.Steps(p.line)) do
            if s.spell and s.to > (p.skill or 0) then
                local n = Craft.RecipeName(s.spell)
                if n and not map[n] then map[n] = { line = p.line, step = s } end
            end
        end
    end
    return map
end
X.GuideByName = GuideByName

local function ServiceName(i)
    if not GetTrainerServiceInfo then return nil end
    local ok, name, _, kind = pcall(GetTrainerServiceInfo, i)
    if ok then return name, kind end
end

if GameTooltip and GameTooltip.SetTrainerService and hooksecurefunc then
    hooksecurefunc(GameTooltip, "SetTrainerService", function(tt, i)
        if not Opt("craftHints") then return end
        local name = ServiceName(i)
        local hit = name and GuideByName()[name]
        if hit then
            tt:AddLine(" ")
            tt:AddLine((L["GuildPride-Guide: %s %d–%d"]):format(G.Name(hit.line), hit.step.from, hit.step.to), 1, 0.82, 0)
            tt:Show()
        end
    end)
end

-- Beim Lehrer: welche Guide-Rezepte kannst du hier jetzt lernen?
function X.TrainerSuggestions()
    if not (GetNumTrainerServices and GetTrainerServiceInfo) then return {} end
    local map, out = GuideByName(), {}
    local ok, n = pcall(GetNumTrainerServices)
    for i = 1, (ok and tonumber(n) or 0) do
        local name, kind = ServiceName(i)
        if name and kind == "available" and map[name] then out[#out + 1] = name end
    end
    return out
end

---------------------------------------------------------------------
-- Gewinn je Rezept (aus dem Zutaten-Cache, auch ohne Berufsfenster)
---------------------------------------------------------------------
function X.RecipeProfit(id)
    local AH = ns.AH
    local c = type(GuildPrideDB) == "table" and type(GuildPrideDB.craftReagents) == "table" and GuildPrideDB.craftReagents[id]
    if not (c and c.r and AH and AH.PriceFor and AH.Key) then return nil end
    local v = { cost = 0, missing = 0, out = c.out, made = c.made or 1 }
    for _, x in ipairs(c.r) do
        local p = AH.PriceFor(AH.Key(x[1]))
        if p then v.cost = v.cost + p * x[2] else v.missing = v.missing + 1 end
    end
    if c.out then
        local p = AH.PriceFor(AH.Key(c.out))
        if p then
            v.sell = p * v.made
            v.profit = math.floor(v.sell * 0.95 - v.cost)
        end
    end
    return v
end

-- Alle Rezepte, die einer deiner Charaktere kann: { { id, who = { Namen }, v } }, bester Gewinn zuerst
function X.ProfitList()
    local by = {}
    for name, e in pairs(Craft.Chars()) do
        if type(e) == "table" and e.known then
            for _, set in pairs(e.known) do
                for id in pairs(set) do
                    by[id] = by[id] or {}
                    by[id][#by[id] + 1] = name
                end
            end
        end
    end
    local out = {}
    for id, who in pairs(by) do
        local v = X.RecipeProfit(id)
        if v and v.profit then
            table.sort(who)
            out[#out + 1] = { id = id, who = who, v = v }
        end
    end
    table.sort(out, function(a, b) return a.v.profit > b.v.profit end)
    return out
end

---------------------------------------------------------------------
-- Item-Tooltip: Bestand je Charakter, Guide-Bedarf
---------------------------------------------------------------------
-- Wie viel brauchen deine Guides (alle deine Berufe, ab jetzt bis 300) von diesem Item?
-- Einmal für alle Items gerechnet und gemerkt, bis sich etwas ändert (Tooltips sind häufig)
local needCache, needAt = nil, 0
Craft.OnChanged(function() needCache = nil end)
function X.GuideNeed(itemID)
    if not needCache or (GetTime and GetTime() - needAt > 60) then
        needCache, needAt = {}, GetTime and GetTime() or 0
        for _, p in ipairs(Craft.MyProfessions()) do
            local _, items = Craft.RouteNeeds(p.line, 300, p.skill)
            for _, it in ipairs(items) do
                if it.need > 0 then
                    local c = needCache[it.id] or { total = 0, lines = {} }
                    c.total = c.total + it.need
                    c.lines[#c.lines + 1] = { line = p.line, need = it.need }
                    needCache[it.id] = c
                end
            end
        end
    end
    local c = needCache[itemID]
    if not c then return 0, {} end
    return c.total, c.lines
end

function X.TooltipLines(itemID)
    local out = {}
    if not itemID then return out end
    local bags, bank = Craft.Count(itemID)
    local alts, altSum = Craft.AltCounts(itemID)
    if bags + bank + altSum > 0 and (#alts > 0 or bank > 0) then
        local parts = { (L["Du %d"]):format(bags + bank) }
        for i = 1, math.min(4, #alts) do parts[#parts + 1] = ("%s %d"):format(alts[i].name, alts[i].n) end
        out[#out + 1] = { L["Bestand:"], table.concat(parts, " · ") }
    end
    local need, per = X.GuideNeed(itemID)
    if need > 0 then
        local names = {}
        for _, x in ipairs(per) do names[#names + 1] = G.Name(x.line) end
        out[#out + 1] = { L["Guide braucht noch:"], ("%d (%s)"):format(need, table.concat(names, ", ")) }
    end
    local origin = ns.CraftMats and ns.CraftMats.Origin(itemID)
    if origin then out[#out + 1] = { L["Herkunft:"], origin } end
    return out
end

ns.Tip.Add(30, function(ctx)
    if not Opt("craftTooltip") then return nil end
    local lines = X.TooltipLines(ctx.id)
    -- Herkunft ist eine Einzelheit, Bestand und Bedarf stehen immer da
    for _, l in ipairs(lines) do if l[1] == L["Herkunft:"] then l.more = true end end
    return lines
end)

---------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------
local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "PLAYER_LOGIN", "TRAINER_SHOW")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(8, function()
            for _, p in ipairs(Craft.MyProfessions()) do last[p.line] = p.skill end
        end)
    elseif event == "TRAINER_SHOW" and Opt("craftHints") then
        C_Timer.After(0.5, function()
            local list = X.TrainerSuggestions()
            if #list > 0 then
                ns.Print((L["Guide: hier jetzt lernen – %s"]):format(table.concat(list, ", ")))
            end
        end)
    end
end)
