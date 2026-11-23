-- GuildPride Handwerk: Tooltip- und Chat-Helfer
--   • Baupläne (Rezept-Items): je Charakter mit dem Beruf „kennt es“, „kann es lernen“ oder
--     „braucht noch Fertigkeit X“ – erkannt am Namen hinter „Pläne:/Muster:/…“ und an der
--     verlangten Fertigkeit im Tooltip
--   • Alt-Klick auf einen Item- oder Rezept-Link im Chat: das Rezept kommt in den Tracker
--   • Beute-Berater: grüne und blaue Rüstung/Waffen – Händler, Auktionshaus oder Entzaubern
--   • Handels-Chat: sucht jemand etwas, das einer deiner Charaktere herstellen kann → Hinweis
-- Schalter: craftTips (Tooltips, Alt-Klick), craftTrade (Handels-Chat)
local ADDON, ns = ...
local L = ns.L
local Craft, G = ns.Craft, ns.CraftGuides

local T = {}
ns.CraftTips = T

local function Opt(key) return not (type(GuildPrideDB) == "table" and GuildPrideDB[key] == false) end

-- Rezept-Item-Unterklasse → Beruf
local RECIPE_SUB = { [1] = 165, [2] = 197, [3] = 202, [4] = 164, [5] = 185, [6] = 171, [7] = 129, [8] = 333, [9] = 356 }
T.RECIPE_SUB = RECIPE_SUB

local function ItemInfo(id)
    local f = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if not f then return nil end
    local _, _, _, _, _, classID, subID = f(id)
    return classID, subID
end

-- Rezeptname aus dem Itemnamen („Pläne: Ebenholzklinge“ → „Ebenholzklinge“)
function T.RecipeNameOf(itemName)
    if type(itemName) ~= "string" then return nil end
    return strtrim(itemName:match("^[^:]+:%s*(.+)$") or itemName)
end

-- Rezept (Zauber-ID) eines Berufs mit diesem Namen, aus allem, was dein Spiel kennt
function T.FindRecipe(line, name)
    if not name then return nil end
    local all = type(GuildPrideDB) == "table" and type(GuildPrideDB.craftAll) == "table" and GuildPrideDB.craftAll[line]
    local low = name:lower()
    for id in pairs(all or {}) do
        local n = Craft.RecipeName(id)
        if n and n:lower() == low then return id end
    end
    for _, s in ipairs(G.STEPS[line] or {}) do
        local n = Craft.RecipeName(s[3])
        if n and n:lower() == low then return s[3] end
    end
    return nil
end

-- Status je Charakter mit dem Beruf: { { name, state = "known"/"can"/"skill", need } }
function T.PatternStatus(line, recipeID, required)
    local out = {}
    for name, e in pairs(Craft.Chars()) do
        local p = type(e) == "table" and e.profs and e.profs[line]
        if p then
            local known = recipeID and e.known and e.known[line] and e.known[line][recipeID]
            local state = known and "known" or ((not required or (p.skill or 0) >= required) and "can" or "skill")
            out[#out + 1] = { name = name, state = state, need = required, skill = p.skill or 0 }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Verlangte Fertigkeit aus den Tooltip-Zeilen lesen („… (225)“ in einer Zeile mit dem Berufsnamen)
local function RequiredSkill(tt, line)
    local name = G.Name(line)
    for i = 2, math.min(tt:NumLines(), 12) do
        local fs = _G[tt:GetName() .. "TextLeft" .. i]
        local text = fs and fs:GetText()
        if text and (text:find(name, 1, true) or text:find(G.NAMES[line].en, 1, true)) then
            local n = tonumber(text:match("%((%d+)%)"))
            if n then return n end
        end
    end
end

local STATE = { known = "|cff808080" .. "%s|r", can = "|cff40ff40%s|r", skill = "|cffff8040%s|r" }
function T.PatternLines(line, recipeID, required)
    local out = {}
    for _, s in ipairs(T.PatternStatus(line, recipeID, required)) do
        local text = s.state == "known" and L["kennt es schon"] or (s.state == "can" and L["kann es lernen"]
            or (L["braucht %d (hat %d)"]):format(s.need or 0, s.skill))
        out[#out + 1] = { s.name, STATE[s.state]:format(text) }
    end
    return out
end

---------------------------------------------------------------------
-- Beute-Berater
---------------------------------------------------------------------
-- Rückgabe: vendor, ah (Kupfer oder nil), Entzauberer (Name oder nil), Empfehlung ("ah"/"vendor"/"de")
function T.LootAdvice(itemID)
    local classID = ItemInfo(itemID)
    if classID ~= 2 and classID ~= 4 then return nil end
    local _, _, quality, _, _, _, _, _, _, _, sell = GetItemInfo(itemID)
    if not quality or quality < 2 or quality > 3 then return nil end
    local vendor = tonumber(sell) or 0
    local AH = ns.AH
    local ah = AH and AH.PriceFor and AH.Key and AH.PriceFor(AH.Key(itemID))
    local de
    for name, e in pairs(Craft.Chars()) do
        if type(e) == "table" and e.profs and e.profs[333] then de = name; break end
    end
    local best = "vendor"
    if ah and ah * 0.95 > vendor * 1.2 then best = "ah" elseif de and not ah then best = "de" end
    return vendor, ah, de, best
end

---------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------
local done = {}
local function AddTooltip(tt, link)
    if not Opt("craftTips") or done[tt] or type(link) ~= "string" then return end
    local id = tonumber(link:match("item:(%d+)"))
    if not id then return end
    local classID, subID = ItemInfo(id)
    local added = false
    if classID == 9 and RECIPE_SUB[subID] then
        local line = RECIPE_SUB[subID]
        local recipe = T.FindRecipe(line, T.RecipeNameOf(GetItemInfo(id)))
        local lines = T.PatternLines(line, recipe, RequiredSkill(tt, line))
        if #lines > 0 then
            tt:AddLine(" ")
            tt:AddLine("|cffffd100GuildPride|r " .. G.Name(line), 1, 1, 1)
            for _, l in ipairs(lines) do tt:AddDoubleLine("  " .. l[1], l[2], 1, 1, 1) end
            added = true
        end
        -- was das Ergebnis wert ist
        local X = ns.CraftExtras
        local v = recipe and X and X.RecipeProfit(recipe)
        if v and v.profit and ns.AH then
            tt:AddDoubleLine("  " .. L["Gewinn je Herstellung"], (v.profit >= 0 and "|cff40ff40" or "|cffff6060") .. ns.AH.Money(math.abs(v.profit)) .. "|r", 1, 1, 1)
            added = true
        end
    else
        local S = ns.CraftSell
        local sellText = S and S.Opt() and S.TooltipText(id)
        local vendor, ah, de, best
        if not sellText then vendor, ah, de, best = T.LootAdvice(id) end
        if sellText then
            tt:AddDoubleLine("|cffffd100GuildPride|r " .. L["Verkaufen:"], sellText, 1, 1, 1, 1, 1, 1)
            added = true
        elseif vendor then
            local money = ns.AH and ns.AH.Money or tostring
            local parts = {}
            parts[#parts + 1] = (best == "vendor" and "|cff40ff40" or "|cffaaaaaa") .. L["Händler"] .. " " .. money(vendor) .. "|r"
            if ah then parts[#parts + 1] = (best == "ah" and "|cff40ff40" or "|cffaaaaaa") .. L["AH"] .. " " .. money(ah) .. "|r" end
            if de then parts[#parts + 1] = (best == "de" and "|cff40ff40" or "|cffaaaaaa") .. (L["Entzaubern: %s"]):format(de) .. "|r" end
            tt:AddDoubleLine("|cffffd100GuildPride|r " .. L["Beute:"], table.concat(parts, " · "), 1, 1, 1)
            added = true
        end
    end
    if added then done[tt] = true; tt:Show() end
end
T.AddTooltip = AddTooltip

if GameTooltip and GameTooltip.HookScript then
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tt:HasScript("OnTooltipCleared") then tt:HookScript("OnTooltipCleared", function(self) done[self] = nil end) end
        tt:HookScript("OnHide", function(self) done[self] = nil end)
    end
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
        local _, link = tooltip:GetItem()
        pcall(AddTooltip, tooltip, link or (data and data.hyperlink))
    end)
end

---------------------------------------------------------------------
-- Alt-Klick auf Links im Chat → Tracker
---------------------------------------------------------------------
-- Welches Rezept stellt dieses Item her (aus dem Zutaten-Cache)?
function T.RecipeForItem(itemID)
    local cache = type(GuildPrideDB) == "table" and type(GuildPrideDB.craftReagents) == "table" and GuildPrideDB.craftReagents or {}
    for id, c in pairs(cache) do if c.out == itemID then return id end end
    return nil
end

function T.TrackLink(link)
    if type(link) ~= "string" or not ns.CraftTrack then return false end
    local spell = tonumber(link:match("^enchant:(%d+)") or link:match("^spell:(%d+)"))
    local item = tonumber(link:match("^item:(%d+)"))
    local recipe = spell
    if not recipe and item then
        local classID, subID = ItemInfo(item)
        if classID == 9 and RECIPE_SUB[subID] then
            recipe = T.FindRecipe(RECIPE_SUB[subID], T.RecipeNameOf(GetItemInfo(item)))
        else
            recipe = T.RecipeForItem(item)
        end
    end
    if not recipe or not Craft.KnownReagents(recipe) then return false end
    ns.CraftTrack.AddRecipe(recipe, 1)
    ns.Print((L["%s ×%d im Tracker."]):format(Craft.RecipeName(recipe), 1))
    return true
end

if hooksecurefunc and SetItemRef then
    hooksecurefunc("SetItemRef", function(link)
        if Opt("craftTips") and IsAltKeyDown and IsAltKeyDown() then pcall(T.TrackLink, link) end
    end)
end

---------------------------------------------------------------------
-- Handels-Chat: Kunden für deine Rezepte
---------------------------------------------------------------------
local WANT = { "lf", "wtb", "suche", "brauche", "need", "looking", "kaufe", "craft" }
function T.IsRequest(text)
    local low = (text or ""):lower()
    for _, w in ipairs(WANT) do
        if low:find("%f[%a]" .. w .. "%f[%A]") then return true end
    end
    return false
end

-- Welche deiner Charaktere können ein verlinktes Item herstellen? → { Item-ID, { Namen } }
function T.CanMake(text)
    for id in (text or ""):gmatch("item:(%d+)") do
        local recipe = T.RecipeForItem(tonumber(id))
        if recipe then
            local who = {}
            for name, e in pairs(Craft.Chars()) do
                if type(e) == "table" and e.known then
                    for _, set in pairs(e.known) do if set[recipe] then who[#who + 1] = name; break end end
                end
            end
            if #who > 0 then table.sort(who); return tonumber(id), who end
        end
    end
    return nil
end

local lastFrom = {}
local function OnChannel(text, sender, _, _, _, _, _, _, chanBase)
    if not Opt("craftTrade") or type(text) ~= "string" or type(sender) ~= "string" then return end
    local base = type(chanBase) == "string" and chanBase:lower() or ""
    if not (base:find("trade", 1, true) or base:find("handel", 1, true)) then return end
    if sender == (UnitName and UnitName("player")) or not T.IsRequest(text) then return end
    local id, who = T.CanMake(text)
    if not id then return end
    if lastFrom[sender] and GetTime() - lastFrom[sender] < 300 then return end
    lastFrom[sender] = GetTime()
    local short = Ambiguate and Ambiguate(sender, "none") or sender
    ns.Print((L["Kunde im Handel: %s sucht %s – kann: %s"]):format(
        ("|Hplayer:%s|h[%s]|h"):format(sender, short), Craft.ItemName(id), table.concat(who, ", ")))
    if PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then pcall(PlaySound, SOUNDKIT.TELL_MESSAGE) end
end
T.OnChannel = OnChannel

local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "CHAT_MSG_CHANNEL")
ev:SetScript("OnEvent", function(_, _, ...)
    local text, sender = ...
    if ns.IsSecret and (ns.IsSecret(text) or ns.IsSecret(sender)) then return end
    pcall(OnChannel, ...)
end)
