-- GuildPride: Handwerker-Verzeichnis
-- Wer in der Gilde welchen Beruf auf welcher Stufe hat und welche Rezepte er kann.
-- Jeder meldet nur seine eigenen Charaktere; die Gilde merkt sich den letzten Stand
-- (auch wenn jemand offline ist).
--   CRF: ver, berufe, symbole   berufe = "Name~Stufe~Max;…", symbole = Datei-IDs der
--                               Berufssymbole in derselben Reihenfolge ("123;456")
--   CRR: ver, beruf, ids, link   ids = Rezept-IDs (Zauber-IDs) zur Basis 36, mit Komma
--                                 getrennt; link = Daten des Berufs-Links ("trade:…"), mit
--                                 dem andere das Berufsfenster des Spielers öffnen können
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

-- Datenteil eines Berufs-Links ("trade:Player-…:…"); nur dieser wird geteilt
local function LinkData(link)
    local data = type(link) == "string" and link:match("|H(trade:[^|]+)|h") or link
    if type(data) ~= "string" or #data > 160 or not data:match("^trade:Player%-[%w%-]+:[%d:%-]+$") then return nil end
    return data
end
Crafts.LinkData = LinkData

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
            local ok, name, icon, level, max = pcall(GetProfessionInfo, idx)
            if ok and type(name) == "string" and name ~= "" then
                out[#out + 1] = { n = Clean(name, 30), l = tonumber(level) or 0, m = tonumber(max) or 0,
                                  i = tonumber(icon) }
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
    local link = T.GetTradeSkillListLink and LinkData(T.GetTradeSkillListLink())
    return Clean(prof, 30), ids, link
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

local function IconString(e)
    local parts = {}
    for i, p in ipairs(e.profs or {}) do
        if i > MAX_PROFS then break end
        parts[#parts + 1] = tostring(p.i or 0)
    end
    return table.concat(parts, ";")
end

local function SendProfs(target)
    local e = DB()[Me()]
    if e and e.profs and #e.profs > 0 then ns.Queue("CRF", target, e.v, ProfString(e), IconString(e)) end
end

local function SendRecipes(target)
    local e = DB()[Me()]
    if not (e and e.rec) then return end
    for prof, ids in pairs(e.rec) do
        local parts = {}
        for i, id in ipairs(ids) do parts[i] = B36(id) end
        ns.Queue("CRR", target, e.v, prof, table.concat(parts, ","), e.links and e.links[prof] or "")
    end
end

-- Eigenen Stand aktualisieren; geändert (oder 3 Tage nicht gemeldet) -> an die Gilde
local function UpdateMine(prof, ids, link)
    if not IsInGuild() or not GuildPrideDB then return end
    local me = Me()
    local e = DB()[me] or { v = 0, profs = {}, rec = {} }
    e.links = e.links or {}
    local function State() return ProfString(e) .. "#" .. (prof and (table.concat(e.rec[prof] or {}, ",") .. (e.links[prof] or "")) or "") end
    local before = State()
    local profs = ReadProfessions()
    if #profs > 0 then e.profs = profs end
    if prof then e.rec[prof] = ids; e.links[prof] = link or e.links[prof] end
    -- Rezepte von Berufen, die man nicht mehr hat, verwerfen
    local have = {}
    for _, p in ipairs(e.profs) do have[p.n] = true end
    for p in pairs(e.rec) do if not have[p] and #e.profs > 0 then e.rec[p] = nil; e.links[p] = nil end end
    local after = State()
    DB()[me] = e
    if before == after and e.v > 0 and Now() - (e.sent or 0) < 3 * 86400 then return end
    if before ~= after or e.v == 0 then e.v = math.max(Now(), e.v + 1) end
    if #e.profs == 0 then return end
    e.sent = Now()
    SendProfs()
    if prof and before ~= after then
        local parts = {}
        for i, id in ipairs(ids) do parts[i] = B36(id) end
        ns.Queue("CRR", nil, e.v, prof, table.concat(parts, ","), e.links[prof] or "")
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
    local ver, list, iconList = strsplit(SEP, payload)
    ver = ns.Stamp(ver)
    if ver == 0 then return end
    local icons = {}
    for id in tostring(iconList or ""):gmatch("[^;]+") do icons[#icons + 1] = ns.Num(id, 1, 99999999) end
    local e = DB()[sender]
    if e and ver <= (e.v or 0) then return end
    if not e and Count() >= MAX_PEOPLE then return end
    local profs = {}
    for item in tostring(list or ""):gmatch("[^;]+") do
        local n, l, m = item:match("^([^~]+)~(%d+)~(%d+)$")
        n = Clean(n, 30)
        if n ~= "" and #profs < MAX_PROFS then
            profs[#profs + 1] = { n = n, l = ns.Num(l, 0, 1000) or 0, m = ns.Num(m, 0, 1000) or 0, i = icons[#profs + 1] }
        end
    end
    if #profs == 0 then return end
    local old = e and e.rec or {}
    -- Rezepte nur behalten, solange der Beruf noch da ist
    local rec, links = {}, {}
    for _, p in ipairs(profs) do rec[p.n] = old[p.n]; links[p.n] = e and e.links and e.links[p.n] end
    DB()[sender] = { v = ver, profs = profs, rec = rec, links = links }
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
    local ver, prof, list, link = strsplit(SEP, payload)
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
    e.links = e.links or {}
    e.links[prof] = LinkData(link)   -- nur gültige Berufs-Links
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

-- Berufssymbol: mitgeschickt, sonst nach dem Namen (deutsch/englisch)
local ICON_BY_NAME = {
    schneiderei = "Trade_Tailoring", tailoring = "Trade_Tailoring",
    alchemie = "Trade_Alchemy", alchemy = "Trade_Alchemy",
    schmiedekunst = "Trade_BlackSmithing", blacksmithing = "Trade_BlackSmithing",
    verzauberkunst = "Trade_Engraving", enchanting = "Trade_Engraving",
    ingenieurskunst = "Trade_Engineering", engineering = "Trade_Engineering",
    ["kürschnerei"] = "INV_Misc_Pelt_Wolf_01", skinning = "INV_Misc_Pelt_Wolf_01",
    ["kräuterkunde"] = "Spell_Nature_NatureTouchGrow", herbalism = "Spell_Nature_NatureTouchGrow",
    bergbau = "Trade_Mining", mining = "Trade_Mining",
    lederverarbeitung = "INV_Misc_ArmorKit_17", leatherworking = "INV_Misc_ArmorKit_17",
    ["erste hilfe"] = "Spell_Holy_SealOfSacrifice", ["first aid"] = "Spell_Holy_SealOfSacrifice",
    kochkunst = "INV_Misc_Food_15", cooking = "INV_Misc_Food_15",
    angeln = "Trade_Fishing", fishing = "Trade_Fishing",
}
function Crafts.Icon(p, size)
    local tex = p.i or (ICON_BY_NAME[(p.n or ""):lower()] and ("Interface\\Icons\\" .. ICON_BY_NAME[p.n:lower()]))
        or "Interface\\Icons\\INV_Misc_QuestionMark"
    size = size or 16
    return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(tex, size, size)
end

-- Berufsfenster eines Spielers öffnen (über seinen geteilten Berufs-Link)
function Crafts.OpenProfession(data, prof)
    data = LinkData(data)
    if not data then return false end
    local link = ("|cffffd000|H%s|h[%s]|h|r"):format(data, prof or "")
    if SetItemRef then
        local ok = pcall(SetItemRef, data, link, "LeftButton")
        if ok then return true end
    end
    return false
end

-- Baumansicht: Charaktere mit ihren Berufen; bei einer Suche nur Treffer
-- (Name, Beruf oder Rezept) und automatisch aufgeklappt
function Crafts.Tree(text)
    text = strtrim(text or ""):lower()
    local chars = {}
    for name, e in pairs(DB()) do
        if ns.IsGuildMember(name) and e.profs and #e.profs > 0 then
            local nameHit = text == "" or name:lower():find(text, 1, true)
            local c = { name = name, profs = {}, auto = false }
            for _, p in ipairs(e.profs) do
                local all = e.rec[p.n] or {}
                local entry = { n = p.n, l = p.l, m = p.m, i = p.i, count = #all, ids = all, link = e.links and e.links[p.n] }
                if nameHit or p.n:lower():find(text, 1, true) then
                    c.profs[#c.profs + 1] = entry
                    if not nameHit then c.auto = true end
                elseif #text >= 3 then
                    local hits = {}
                    for _, id in ipairs(all) do
                        local rn = RecipeName(id)
                        if rn and rn:lower():find(text, 1, true) then hits[#hits + 1] = id end
                    end
                    if #hits > 0 then
                        entry.ids, entry.auto = hits, true
                        c.profs[#c.profs + 1] = entry
                        c.auto = true
                    end
                end
            end
            if #c.profs > 0 then chars[#chars + 1] = c end
        end
    end
    return chars
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
            local ok, prof, ids, link = pcall(ReadOpenRecipes)
            if ok and prof then pcall(UpdateMine, prof, ids, link) end
        end)
    end
end)

---------------------------------------------------------------------
-- Reiter "Berufe"
---------------------------------------------------------------------
if not ns.AddTab then return end
local page = ns.AddTab(L["Berufe"], 55)   -- eigener Platz unter "Planen"
ns.CraftsPage = page

local search = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
search:SetSize(260, 22); search:SetPoint("TOPLEFT", 8, -6)
search:SetAutoFocus(false); search:SetMaxLetters(40)
local ph = search:CreateFontString(nil, "OVERLAY", "GPFont_Muted")
ph:SetPoint("LEFT", 4, 0); ph:SetText(L["Name, Beruf oder Rezept suchen …"])
local info = page:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
info:SetPoint("LEFT", search, "RIGHT", 12, 0); info:SetWidth(330); info:SetJustifyH("LEFT")
info:SetText(L["Klick auf einen Namen zeigt die Berufe, Klick auf einen Beruf öffnet sein Berufsfenster. Dafür muss der Spieler seins einmal geöffnet haben."])

local holder = CreateFrame("Frame", nil, page)
holder:SetPoint("TOPLEFT", 0, -36); holder:SetPoint("BOTTOMRIGHT")
local list = ns.CreateList(holder, 24)
local empty = holder:CreateFontString(nil, "OVERLAY", "GPFont_Muted")
empty:SetPoint("TOP", 0, -60); empty:SetWidth(560)

local function OnlineMap()
    local on = {}
    for i = 1, GetNumGuildMembers() do
        local n, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if n and online then on[ns.FullName and ns.FullName(n) or n] = true end
    end
    return on
end

-- Aufgeklappt: Charakter -> Berufe, Beruf -> Rezepte
local openChar, openProf = {}, {}
local function ProfKey(name, prof) return name .. "\030" .. prof end

local CHAR_INDENT, PROF_INDENT, REC_INDENT = 8, 30, 54
local function Row(i, indent)
    local row = list:GetRow(i)
    row.left:ClearAllPoints(); row.left:SetPoint("LEFT", indent, 0)
    row:EnableMouse(true)
    row:SetScript("OnEnter", nil); row:SetScript("OnLeave", nil)
    return row
end

function page:Refresh()
    local text = search:GetText() or ""
    ph:SetShown(text == "" and not search:HasFocus())
    local chars = Crafts.Tree(text)
    local online = OnlineMap()
    table.sort(chars, function(a, b)
        local oa, ob = online[a.name] and true or false, online[b.name] and true or false
        if oa ~= ob then return oa end
        return a.name < b.name
    end)
    local n = 0
    for _, c in ipairs(chars) do
        local open = openChar[c.name]
        if open == nil then open = c.auto end
        n = n + 1
        local row = Row(n, CHAR_INDENT)
        local main = ns.MainOf and ns.MainOf(c.name)
        row.left:SetText(("%s %s%s%s"):format(open and "▾" or "▸", online[c.name] and "|cff40ff40•|r" or "|cff666666•|r",
            Ambiguate(c.name, "guild"), (main and main ~= c.name) and (" |cff999999(" .. Ambiguate(main, "guild") .. ")|r") or ""))
        -- nur Name, dahinter die Berufssymbole; Stufen im Tooltip und aufgeklappt
        local icons = {}
        for _, p in ipairs(c.profs) do icons[#icons + 1] = Crafts.Icon(p, 18) end
        row.mid:SetText(table.concat(icons, " "))
        row.right:SetText("")
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(Ambiguate(c.name, "guild"))
            for _, p in ipairs(c.profs) do
                GameTooltip:AddDoubleLine(Crafts.Icon(p, 14) .. " " .. p.n, ("%d / %d"):format(p.l or 0, p.m or 0), 1, 1, 1, 1, 0.82, 0.55)
            end
            GameTooltip:AddLine(L["Klick: aufklappen · Rechtsklick: anflüstern"], 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row:SetScript("OnMouseUp", function(_, button)
            if button == "RightButton" then
                if ChatFrame_SendTell then ChatFrame_SendTell(Ambiguate(c.name, "none")) end
                return
            end
            openChar[c.name] = not open
            page:Refresh()
        end)
        if open then
            for _, p in ipairs(c.profs) do
                local key = ProfKey(c.name, p.n)
                local popen = openProf[key]
                if popen == nil then popen = p.auto or false end
                n = n + 1
                local prow = Row(n, PROF_INDENT)
                prow.left:SetText((p.count > 0 and (popen and "▾ " or "▸ ") or "   ") .. Crafts.Icon(p, 16) .. " " .. p.n)
                prow.mid:SetText(("|cffffd18c%d|r|cff999999 / %d|r"):format(p.l or 0, p.m or 0))
                -- Klick: Berufsfenster des Spielers (geteilter Link); sonst bzw.
                -- Rechtsklick: Rezeptliste hier aufklappen
                local countText = p.count > 0 and (L["%d Rezepte"]):format(p.count) or L["Rezepte unbekannt"]
                prow.right:SetText(p.link and ("|cffffd100" .. L["Berufsfenster öffnen"] .. "|r  ·  " .. countText) or countText)
                prow:SetScript("OnMouseUp", function(_, button)
                    if button ~= "RightButton" and p.link and Crafts.OpenProfession(p.link, p.n) then return end
                    if p.count == 0 then return end
                    openProf[key] = not popen
                    page:Refresh()
                end)
                prow:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(("%s – %s"):format(Ambiguate(c.name, "guild"), p.n))
                    if p.link then
                        GameTooltip:AddLine(L["Klick: sein Berufsfenster mit allen Rezepten öffnen"], 1, 1, 1, true)
                        if p.count > 0 then GameTooltip:AddLine(L["Rechtsklick: Rezeptliste hier aufklappen"], 0.7, 0.7, 0.7, true) end
                    else
                        GameTooltip:AddLine(L["Das Berufsfenster ist erst verfügbar, wenn der Spieler seins einmal mit dem neuen GuildPride geöffnet hat."], 0.7, 0.7, 0.7, true)
                    end
                    GameTooltip:Show()
                end)
                prow:SetScript("OnLeave", GameTooltip_Hide)
                if popen then
                    local recs = {}
                    for _, id in ipairs(p.ids) do recs[#recs + 1] = { id = id, name = RecipeName(id) or ("#" .. id) } end
                    table.sort(recs, function(a, b) return a.name < b.name end)
                    for _, r in ipairs(recs) do
                        n = n + 1
                        local rrow = Row(n, REC_INDENT)
                        rrow.left:SetText("|cffe6e0da" .. r.name .. "|r")
                        rrow.mid:SetText("")
                        rrow.right:SetText("")
                        rrow:SetScript("OnEnter", function(self)
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(r.id) else GameTooltip:SetText(r.name) end
                            GameTooltip:AddLine(L["Shift-Klick: in den Chat"], 0.6, 0.6, 0.6)
                            GameTooltip:Show()
                        end)
                        rrow:SetScript("OnLeave", GameTooltip_Hide)
                        rrow:SetScript("OnMouseUp", function()
                            if not IsShiftKeyDown() then return end
                            local link = (C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(r.id))
                                or (GetSpellLink and GetSpellLink(r.id))
                            if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
                        end)
                    end
                end
            end
        end
    end
    list:Finish(n)
    empty:SetShown(n == 0)
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
