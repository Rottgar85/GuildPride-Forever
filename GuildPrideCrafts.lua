-- GuildPride: Handwerker-Verzeichnis
-- Wer in der Gilde welchen Beruf auf welcher Stufe hat und welche Rezepte er kann.
-- Jeder meldet nur seine eigenen Charaktere; die Gilde merkt sich den letzten Stand
-- (auch wenn jemand offline ist).
--   CRF: ver, berufe        berufe = "Name~Stufe~Max;Name~Stufe~Max"
--   CRR: ver, beruf, ids    ids = Rezept-IDs (Zauber-IDs) zur Basis 36, mit Komma getrennt
--   CRQ: jemand öffnet den Reiter -> alle antworten per Flüstern mit CRF (klein)
--   CRRQ: Rezepte eines Spielers anfragen (nur wenn sein Stand neuer ist)
-- Nur der Spieler selbst darf über seinen Charakter berichten (keine Weiterleitung).
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP

local MAX_PROFS, MAX_RECIPES, MAX_PEOPLE = 6, 600, 1000
local Crafts = {}
ns.Crafts = Crafts

local function DB() return ns.GuildTable("crafts") end   -- [Name] = { v, profs = { {n, l, m} }, rec = { [Beruf] = { id, … } } }
local function Me() return ns.Me() end
local function Now() return GetServerTime() end
-- Trennzeichen der Nachricht (~ ; ,) und Codes aus fremden Texten entfernen
local function Clean(s, max) return (tostring(s or ""):gsub("[%c|~;,]", "")):sub(1, max) end

local function B36(n)
    local chars, out = "0123456789abcdefghijklmnopqrstuvwxyz", ""
    n = math.floor(n)
    repeat
        local r = n % 36
        out = chars:sub(r + 1, r + 1) .. out
        n = math.floor(n / 36)
    until n == 0
    return out
end

---------------------------------------------------------------------
-- Eigene Berufe und Rezepte lesen
---------------------------------------------------------------------
local function ReadProfessions()
    local out = {}
    if not (GetProfessions and GetProfessionInfo) then return out end
    local list = { pcall(GetProfessions) }
    if not table.remove(list, 1) then return out end
    for i = 1, 5 do
        local idx = list[i]
        if idx then
            local ok, name, _, level, max = pcall(GetProfessionInfo, idx)
            if ok and type(name) == "string" and name ~= "" then
                out[#out + 1] = { n = Clean(name, 30), l = tonumber(level) or 0, m = tonumber(max) or 0 }
            end
        end
    end
    return out
end

-- Rezepte aus dem gerade offenen Berufsfenster (nur das eigene, nicht verlinkte)
local function ReadOpenRecipes()
    local T = C_TradeSkillUI
    if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo) then return end
    if (T.IsTradeSkillLinked and T.IsTradeSkillLinked()) or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
       or (T.IsNPCCrafting and T.IsNPCCrafting()) then return end
    local prof
    local info = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
    if type(info) == "table" then prof = info.professionName end
    if (not prof or prof == "") and T.GetTradeSkillLine then
        local _, name = T.GetTradeSkillLine()
        prof = name
    end
    if type(prof) ~= "string" or prof == "" then return end
    local ids = {}
    for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
        local r = T.GetRecipeInfo(id)
        if r and r.learned and type(id) == "number" then ids[#ids + 1] = id end
        if #ids >= MAX_RECIPES then break end
    end
    if #ids == 0 then return end
    table.sort(ids)
    return Clean(prof, 30), ids
end

---------------------------------------------------------------------
-- Senden
---------------------------------------------------------------------
local function ProfString(e)
    local parts = {}
    for i, p in ipairs(e.profs or {}) do
        if i > MAX_PROFS then break end
        parts[#parts + 1] = ("%s~%d~%d"):format(p.n, p.l or 0, p.m or 0)
    end
    return table.concat(parts, ";")
end

local function SendProfs(target)
    local e = DB()[Me()]
    if e and e.profs and #e.profs > 0 then ns.Queue("CRF", target, e.v, ProfString(e)) end
end

local function SendRecipes(target)
    local e = DB()[Me()]
    if not (e and e.rec) then return end
    for prof, ids in pairs(e.rec) do
        local parts = {}
        for i, id in ipairs(ids) do parts[i] = B36(id) end
        ns.Queue("CRR", target, e.v, prof, table.concat(parts, ","))
    end
end

-- Eigenen Stand aktualisieren; geändert (oder 3 Tage nicht gemeldet) -> an die Gilde
local function UpdateMine(prof, ids)
    if not IsInGuild() or not GuildPrideDB then return end
    local me = Me()
    local e = DB()[me] or { v = 0, profs = {}, rec = {} }
    local before = ProfString(e) .. "#" .. (prof and table.concat(e.rec[prof] or {}, ",") or "")
    local profs = ReadProfessions()
    if #profs > 0 then e.profs = profs end
    if prof then e.rec[prof] = ids end
    -- Rezepte von Berufen, die man nicht mehr hat, verwerfen
    local have = {}
    for _, p in ipairs(e.profs) do have[p.n] = true end
    for p in pairs(e.rec) do if not have[p] and #e.profs > 0 then e.rec[p] = nil end end
    local after = ProfString(e) .. "#" .. (prof and table.concat(e.rec[prof] or {}, ",") or "")
    DB()[me] = e
    if before == after and e.v > 0 and Now() - (e.sent or 0) < 3 * 86400 then return end
    if before ~= after or e.v == 0 then e.v = math.max(Now(), e.v + 1) end
    if #e.profs == 0 then return end
    e.sent = Now()
    SendProfs()
    if prof and before ~= after then
        local parts = {}
        for i, id in ipairs(ids) do parts[i] = B36(id) end
        ns.Queue("CRR", nil, e.v, prof, table.concat(parts, ","))
    end
    if ns.RefreshUI then ns.RefreshUI() end
end
Crafts.UpdateMine = UpdateMine

---------------------------------------------------------------------
-- Empfangen
---------------------------------------------------------------------
local function Count()
    local n = 0
    for _ in pairs(DB()) do n = n + 1 end
    return n
end

-- Nur über den eigenen Charakter, direkt (nicht weitergeleitet), nur Gildenmitglieder
local function Accept(sender)
    return sender ~= Me() and ns.IsDirect(sender, sender) and ns.IsGuildMember(sender)
end

local askedRecipes = {}   -- [Name] = Version, die wir schon angefragt haben
ns.On("CRF", function(payload, sender)
    if not Accept(sender) then return end
    local ver, list = strsplit(SEP, payload)
    ver = ns.Stamp(ver)
    if ver == 0 then return end
    local e = DB()[sender]
    if e and ver <= (e.v or 0) then return end
    if not e and Count() >= MAX_PEOPLE then return end
    local profs = {}
    for item in tostring(list or ""):gmatch("[^;]+") do
        local n, l, m = item:match("^([^~]+)~(%d+)~(%d+)$")
        n = Clean(n, 30)
        if n ~= "" and #profs < MAX_PROFS then
            profs[#profs + 1] = { n = n, l = ns.Num(l, 0, 1000) or 0, m = ns.Num(m, 0, 1000) or 0 }
        end
    end
    if #profs == 0 then return end
    local old = e and e.rec or {}
    -- Rezepte nur behalten, solange der Beruf noch da ist
    local rec = {}
    for _, p in ipairs(profs) do rec[p.n] = old[p.n] end
    DB()[sender] = { v = ver, profs = profs, rec = rec }
    -- Neuerer Stand: Rezepte gezielt nachfragen (einmal je Version), außer sie
    -- kommen ohnehin gleich hinterher (Rundsendung nach einer Änderung)
    if askedRecipes[sender] ~= ver then
        askedRecipes[sender] = ver
        C_Timer.After(15 + math.random() * 15, function()
            local x = DB()[sender]
            if x and x.v == ver and not x.got then ns.Queue("CRRQ", sender, "1") end
        end)
    end
    if ns.RefreshUI then ns.RefreshUI() end
end)

ns.On("CRR", function(payload, sender)
    if not Accept(sender) then return end
    local ver, prof, list = strsplit(SEP, payload)
    ver, prof = ns.Stamp(ver), Clean(prof, 30)
    local e = DB()[sender]
    -- Nur zu einem bekannten Stand und einem seiner Berufe
    if not e or ver ~= e.v or prof == "" then return end
    local known = false
    for _, p in ipairs(e.profs) do if p.n == prof then known = true end end
    if not known then return end
    local ids = {}
    for code in tostring(list or ""):gmatch("[0-9a-z]+") do
        local id = tonumber(code, 36)
        if id and id > 0 and id < 2 ^ 31 then ids[#ids + 1] = id end
        if #ids >= MAX_RECIPES then break end
    end
    e.rec[prof] = ids
    e.got = true
    if ns.RefreshUI then ns.RefreshUI() end
end)

-- Anfragen: höchstens alle 30 Minuten je Fragendem antworten
local answered = {}
ns.On("CRQ", function(_, sender)
    if sender == Me() then return end
    local now = GetTime()
    if answered[sender] and now - answered[sender] < 1800 then return end
    answered[sender] = now
    C_Timer.After(math.random() * 5, function() SendProfs(sender) end)
end)
ns.On("CRRQ", function(_, sender)
    if sender == Me() or not ns.IsGuildMember(sender) then return end
    C_Timer.After(math.random() * 2, function() SendRecipes(sender) end)
end)

---------------------------------------------------------------------
-- Suche
---------------------------------------------------------------------
local spellNames = {}
local function RecipeName(id)
    local n = spellNames[id]
    if n == nil then
        if C_Spell and C_Spell.GetSpellName then n = C_Spell.GetSpellName(id)
        elseif GetSpellInfo then n = GetSpellInfo(id) end
        if type(n) ~= "string" then n = false end
        spellNames[id] = n
    end
    return n or nil
end
Crafts.RecipeName = RecipeName

-- Zeilen: { name, prof, level, max, recipe = Rezeptname oder nil }
function Crafts.Search(text)
    text = strtrim(text or ""):lower()
    local rows = {}
    for name, e in pairs(DB()) do
        if ns.IsGuildMember(name) then
            for _, p in ipairs(e.profs or {}) do
                local profHit = text == "" or p.n:lower():find(text, 1, true) or name:lower():find(text, 1, true)
                if profHit then
                    rows[#rows + 1] = { name = name, prof = p.n, level = p.l, max = p.m,
                                        recipes = e.rec[p.n] and #e.rec[p.n] or 0 }
                elseif #text >= 3 then
                    for _, id in ipairs(e.rec[p.n] or {}) do
                        local rn = RecipeName(id)
                        if rn and rn:lower():find(text, 1, true) then
                            rows[#rows + 1] = { name = name, prof = p.n, level = p.l, max = p.m, recipe = rn, id = id }
                        end
                    end
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        if (a.recipe or "") ~= (b.recipe or "") then return (a.recipe or "") < (b.recipe or "") end
        if a.prof ~= b.prof then return a.prof < b.prof end
        if a.level ~= b.level then return a.level > b.level end
        return a.name < b.name
    end)
    return rows
end

---------------------------------------------------------------------
-- Ereignisse: beim Einloggen Berufe melden, beim Öffnen des Berufsfensters Rezepte
---------------------------------------------------------------------
local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_SHOW")
local started, pending = false, false
ev:SetScript("OnEvent", function(_, event)
    if not GuildPrideDB or not IsInGuild() then return end
    if event == "PLAYER_ENTERING_WORLD" then
        if started then return end
        started = true
        C_Timer.After(50, function() pcall(UpdateMine) end)
    elseif event == "SKILL_LINES_CHANGED" then
        if not started or pending then return end
        pending = true
        C_Timer.After(10, function() pending = false; pcall(UpdateMine) end)
    else
        -- Berufsfenster: kurz warten, bis die Liste vollständig ist
        C_Timer.After(1, function()
            local ok, prof, ids = pcall(ReadOpenRecipes)
            if ok and prof then pcall(UpdateMine, prof, ids) end
        end)
    end
end)

---------------------------------------------------------------------
-- Reiter "Berufe"
---------------------------------------------------------------------
if not ns.AddTab then return end
local page = ns.AddTab(L["Berufe"], 75)
ns.CraftsPage = page

local search = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
search:SetSize(260, 22); search:SetPoint("TOPLEFT", 8, -6)
search:SetAutoFocus(false); search:SetMaxLetters(40)
local ph = search:CreateFontString(nil, "OVERLAY", "GPFont_Muted")
ph:SetPoint("LEFT", 4, 0); ph:SetText(L["Name, Beruf oder Rezept suchen …"])
local info = page:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
info:SetPoint("LEFT", search, "RIGHT", 12, 0); info:SetWidth(330); info:SetJustifyH("LEFT")
info:SetText(L["Öffne dein Berufsfenster einmal, dann stehen auch deine Rezepte hier. Klick auf eine Zeile = anflüstern."])

local holder = CreateFrame("Frame", nil, page)
holder:SetPoint("TOPLEFT", 0, -36); holder:SetPoint("BOTTOMRIGHT")
local list = ns.CreateList(holder, 24)
local empty = holder:CreateFontString(nil, "OVERLAY", "GPFont_Muted")
empty:SetPoint("TOP", 0, -60); empty:SetWidth(560)

local function Online(full)
    for i = 1, GetNumGuildMembers() do
        local n, _, _, _, _, _, _, _, on = GetGuildRosterInfo(i)
        if n and (ns.FullName and ns.FullName(n) or n) == full then return on end
    end
end

function page:Refresh()
    local text = search:GetText() or ""
    ph:SetShown(text == "" and not search:HasFocus())
    local rows = Crafts.Search(text)
    for i, r in ipairs(rows) do
        local row = list:GetRow(i)
        local main = ns.MainOf and ns.MainOf(r.name)
        local who = Ambiguate(r.name, "guild") .. ((main and main ~= r.name) and (" |cff999999(" .. Ambiguate(main, "guild") .. ")|r") or "")
        row.left:SetText((Online(r.name) and "|cff40ff40•|r " or "|cff666666•|r ") .. who)
        if r.recipe then
            row.mid:SetText(("|cffffd100%s|r  |cff999999%s|r"):format(r.recipe, r.prof))
        else
            row.mid:SetText(("%s  |cffffd18c%d|r|cff999999/%d|r"):format(r.prof, r.level or 0, r.max or 0))
        end
        row.right:SetText(r.recipe and "" or (r.recipes > 0 and (L["%d Rezepte"]):format(r.recipes) or ""))
        row:EnableMouse(true)
        row:SetScript("OnMouseUp", function()
            if ChatFrame_SendTell then ChatFrame_SendTell(Ambiguate(r.name, "none")) end
        end)
    end
    list:Finish(#rows)
    empty:SetShown(#rows == 0)
    empty:SetText(text ~= "" and L["Nichts gefunden."]
        or L["Noch keine Berufe bekannt. Mitglieder mit GuildPride melden ihre Berufe automatisch."])
end

search:SetScript("OnTextChanged", function() page:Refresh() end)
search:SetScript("OnEditFocusGained", function() ph:Hide() end)
search:SetScript("OnEditFocusLost", function() page:Refresh() end)
search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)

-- Beim Öffnen die Berufe der anderen anfragen (höchstens alle 10 Minuten)
local lastAsk = -600
page:HookScript("OnShow", function()
    if GetTime() - lastAsk < 600 then return end
    lastAsk = GetTime()
    ns.Queue("CRQ", nil, "1")
end)
