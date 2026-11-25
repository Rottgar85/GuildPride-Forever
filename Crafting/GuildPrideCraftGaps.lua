-- GuildPride Handwerk: Rezept-Lücken der Gilde (/gp luecken, Werkzeuge, Knopf im Reiter Handwerk)
-- Welche Rezepte eines Berufs kann niemand? Alle Rezepte kommen aus dem Rezept-Verzeichnis
-- (GuildPrideCraftCatalog.lua), bekannte aus den in der Gilde geteilten Berufen und deinen Twinks.
-- „Das lerne ich“ (Rechtsklick): wer ein fehlendes Rezept übernimmt, sagt es der Gilde.
--   RLN  ver · Rezept-IDs mit Komma   die ganze eigene Liste, nur für sich selbst, nie weitergeleitet
--   RLQ  1                            Anfrage beim Öffnen des Fensters, nur wer etwas hat, antwortet
-- Gespeichert: GuildTable("learn")[Name] = { ver, ids }; gelernte Rezepte fallen von selbst weg.
local ADDON, ns = ...
local L = ns.L
local G, K = ns.CraftGuides, ns.CraftCatalog

local P = {}
ns.CraftGaps = P
-- Berufe mit Rezepten (Sammelberufe haben keine, Bergbau nur das Schmelzen)
P.ORDER = { 164, 165, 171, 197, 202, 333, 185, 129, 186 }

-- Beruf eines Eintrags: über die Nummer im geteilten Link, sonst über den Namen (deutsch oder englisch)
local function LineOf(e, prof)
    local link = e.links and e.links[prof]
    local line = tonumber(tostring(link or ""):match("^trade:.*:(%d+)$"))
    if line then return line end
    for id, n in pairs(G.NAMES) do
        if n.de == prof or n.en == prof then return id end
    end
end

-- { total, known, shared, list = { { id, name } }, crafters = { { name, level, shared } } }
function P.Report(line, text)
    local known, crafters, at = {}, {}, {}
    local function Crafter(name)
        local c = at[name]
        if not c then c = { name = name, level = 0, shared = false }; at[name] = c; crafters[#crafters + 1] = c end
        return c
    end
    local shared = 0
    for name, e in pairs(ns.GuildTable("crafts")) do
        for _, p in ipairs(e.profs or {}) do
            if LineOf(e, p.n) == line then
                local c = Crafter(name)
                c.level = p.l or 0
                local ids = e.rec and e.rec[p.n]
                if ids and #ids > 0 then
                    c.shared = true
                    shared = shared + 1
                    for _, id in ipairs(ids) do known[id] = true end
                end
            end
        end
    end
    for name, profs in pairs(ns.GuildTable("craftsRoster")) do
        for _, p in ipairs(profs) do if p.id == line then Crafter(name) end end
    end
    local chars = type(GuildPrideDB) == "table" and GuildPrideDB.craftChars
    for _, e in pairs(type(chars) == "table" and chars or {}) do
        local mine = type(e) == "table" and type(e.known) == "table" and e.known[line]
        for id in pairs(type(mine) == "table" and mine or {}) do known[id] = true end
    end
    table.sort(crafters, function(a, b)
        if a.shared ~= b.shared then return a.shared end
        if a.level ~= b.level then return a.level > b.level end
        return a.name < b.name
    end)
    local want = strtrim(text or ""):lower()
    local list, total, have = {}, 0, 0
    for _, id in ipairs(K.Ids(line)) do
        total = total + 1
        if known[id] then have = have + 1
        else
            local name = ns.Crafts.RecipeName(id)
            if name and (want == "" or name:lower():find(want, 1, true)) then list[#list + 1] = { id = id, name = name } end
        end
    end
    table.sort(list, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return { total = total, known = have, shared = shared, list = list, crafters = crafters }
end

---------------------------------------------------------------------
-- Das lerne ich
---------------------------------------------------------------------
local MAX_LEARN, LEARN_DAYS = 20, 60
local function Learn() return ns.GuildTable("learn") end
local function MyLearn()
    local e = Learn()[ns.Me()]
    if type(e) ~= "table" or type(e.ids) ~= "table" then e = { ver = 0, ids = {} }; Learn()[ns.Me()] = e end
    return e
end
local function SendLearn(target)
    local e = MyLearn()
    ns.Queue("RLN", target, e.ver, table.concat(e.ids, ","))
end
local function TouchLearn()
    local e = MyLearn()
    e.ver = math.max(GetServerTime(), (e.ver or 0) + 1)
    SendLearn()
end

-- Wer lernt das Rezept? (Namen, man selbst zuerst)
function P.Who(id)
    local out, me, now = {}, ns.Me(), GetServerTime()
    for name, e in pairs(Learn()) do
        if type(e) == "table" and (name == me or (ns.IsGuildMember(name) and now - (e.ver or 0) < LEARN_DAYS * 86400)) then
            for _, x in ipairs(type(e.ids) == "table" and e.ids or {}) do
                if x == id then out[#out + 1] = name; break end
            end
        end
    end
    table.sort(out, function(a, b)
        if (a == me) ~= (b == me) then return a == me end
        return a < b
    end)
    return out
end

-- Übernehmen (true) oder zurücknehmen (false); nil = schon 20 übernommen
function P.Toggle(id)
    local ids = MyLearn().ids
    for i, x in ipairs(ids) do
        if x == id then table.remove(ids, i); TouchLearn(); return false end
    end
    if #ids >= MAX_LEARN then return nil end
    ids[#ids + 1] = id
    TouchLearn()
    return true
end

-- Was einer meiner Charaktere inzwischen kann, von meiner Liste nehmen
function P.CleanMine()
    if type(Learn()[ns.Me()]) ~= "table" then return 0 end
    local ids, n = MyLearn().ids, 0
    local chars = type(GuildPrideDB) == "table" and GuildPrideDB.craftChars
    local function Known(id)
        for _, e in pairs(type(chars) == "table" and chars or {}) do
            for _, list in pairs(type(e) == "table" and type(e.known) == "table" and e.known or {}) do
                if type(list) == "table" and list[id] then return true end
            end
        end
        return false
    end
    for i = #ids, 1, -1 do
        if Known(ids[i]) then table.remove(ids, i); n = n + 1 end
    end
    if n > 0 then TouchLearn() end
    return n
end

ns.On("RLN", function(payload, sender)
    if sender == ns.Me() or not ns.IsGuildMember(sender) then return end
    local ver, text = strsplit(ns.SEP, payload)
    ver = ns.Stamp(ver)
    local e = Learn()[sender]
    if ver <= 0 or (type(e) == "table" and (e.ver or 0) >= ver) then return end
    local ids = {}
    for id in tostring(text or ""):gmatch("[^,]+") do
        id = id:match("^%d+$") and #id <= 8 and tonumber(id) or nil
        if id and id > 0 and #ids < MAX_LEARN then ids[#ids + 1] = id end
    end
    Learn()[sender] = { ver = ver, ids = ids }
    if P.Refresh then P.Refresh() end
end)
ns.On("RLQ", function(_, sender)
    local e = Learn()[ns.Me()]
    if sender == ns.Me() or type(e) ~= "table" or #(e.ids or {}) == 0 then return end
    ns.AnswerSoon("RLN", function() SendLearn("@CHANNEL") end)
end)

-- Zeilen für das Fenster: { text, id }
function P.Lines(line, text)
    local r = P.Report(line, text)
    local out = {}
    local who = {}
    for i, c in ipairs(r.crafters) do
        if i > 8 then who[#who + 1] = "…"; break end
        who[#who + 1] = (c.shared and "|cff40ff40" or "|cff999999") .. Ambiguate(c.name, "guild") .. "|r" .. (c.level > 0 and (" " .. c.level) or "")
    end
    out[1] = { text = #who > 0 and (L["Handwerker: %s"]):format(table.concat(who, ", ")) or ("|cffff6060" .. L["Niemand in der Gilde hat diesen Beruf."] .. "|r") }
    out[2] = { text = (L["Rezepte: %d bekannt von %d · geteilt haben %d von %d Handwerkern"]):format(r.known, r.total, r.shared, #r.crafters) }
    if K.Running() then out[#out + 1] = { text = "|cffffd100" .. L["Rezepte des Spiels werden gesammelt …"] .. "|r" } end
    for _, x in ipairs(r.list) do
        local names, me = P.Who(x.id), ns.Me()
        for i, n in ipairs(names) do names[i] = n == me and L["du lernst das"] or (L["%s lernt das"]):format(Ambiguate(n, "guild")) end
        out[#out + 1] = { text = "   " .. x.name .. (#names > 0 and ("  |cff40ff40" .. table.concat(names, ", ") .. "|r") or ""), id = x.id }
    end
    return out
end

---------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------
local win
local asked = -300
function P.Refresh()
    if not win or not win:IsShown() then return end
    win.list = P.Lines(win.line, win.search:GetText())
    local lines = {}
    for i, l in ipairs(win.list) do lines[i] = l.text end
    for _, b in ipairs(win.profs) do
        b.icon:SetDesaturated(b.line ~= win.line)
        b.icon:SetAlpha(b.line == win.line and 1 or 0.6)
    end
    win.title:SetText(L["Rezept-Lücken der Gilde"] .. ": " .. G.Name(win.line))
    win:SetLines(lines)
end

local function Build()
    win = ns.ListWindow({ name = "GuildPrideCraftGaps", title = L["Rezept-Lücken der Gilde"], rows = 18, width = 560, top = -92,
        sub = L["Rezepte, die niemand kann. Grün = hat seine Rezepte geteilt. Wer fehlt, öffnet sein Berufsfenster einmal mit GuildPride."] })
    win.profs = {}
    for i, line in ipairs(P.ORDER) do
        local b = CreateFrame("Button", nil, win)
        b:SetSize(28, 28); b:SetPoint("TOPLEFT", 16 + (i - 1) * 34, -58)
        b.line = line
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints(); b.icon:SetTexture(ns.CraftWindow and ns.CraftWindow.ICONS[line] or "Interface\\Icons\\INV_Misc_QuestionMark")
        b:SetScript("OnClick", function() win.line, win.offset = line, 0; P.Refresh() end)
        b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(G.Name(line)); GameTooltip:Show() end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        win.profs[i] = b
    end
    win.search = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    win.search:SetSize(180, 20); win.search:SetPoint("TOPRIGHT", -18, -62); win.search:SetAutoFocus(false); win.search:SetMaxLetters(40)
    win.search:SetScript("OnTextChanged", function() win.offset = 0; P.Refresh() end)
    win.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    for i, row in ipairs(win.rows) do
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            local r = win.list and win.list[i + win.offset]
            if not (r and r.id) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(r.id) else GameTooltip:SetText(r.text) end
            GameTooltip:AddLine(P.Who(r.id)[1] == ns.Me() and L["Rechtsklick: doch nicht lernen"] or L["Rechtsklick: Das lerne ich"], 0.25, 1, 0.25)
            GameTooltip:AddLine(L["Shift-Klick: in den Chat"], 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row:SetScript("OnMouseUp", function(_, button)
            local r = win.list and win.list[i + win.offset]
            if r and r.id and button == "RightButton" then
                if P.Toggle(r.id) == nil then ns.Print((L["Höchstens %d Rezepte auf einmal."]):format(MAX_LEARN)) end
                P.Refresh()
                return
            end
            if not (r and r.id and IsShiftKeyDown()) then return end
            local link = C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(r.id)
            if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
        end)
    end
    win.line = P.ORDER[1]
    win:SetScript("OnShow", function()
        win.offset = 0
        K.Scan(P.Refresh)
        P.CleanMine()
        if GetTime() - asked > 300 then asked = GetTime(); ns.Queue("RLQ", nil, "1") end
        P.Refresh()
    end)
end

function P.Open()
    if not win then
        Build()
        -- zuerst der eigene Beruf, wenn es einen mit Rezepten gibt
        for _, p in ipairs(ns.Craft and ns.Craft.MyProfessions and ns.Craft.MyProfessions() or {}) do
            for _, line in ipairs(P.ORDER) do
                if p.line == line then win.line = line end
            end
        end
    end
    win:SetShown(not win:IsShown())
end

ns.Command({ "luecken", "lücken", "gaps" }, function() P.Open() end)
