-- GuildPride Handwerk: Fundament
-- Liest live aus dem Spiel und merkt sich (nur lokal, für Twinks):
--   GuildPrideDB.craftChars[Charakter] = { t, level, profs = { [Skill-Line] = { skill, max, name } },
--                                         known = { [Skill-Line] = { [Rezept] = true } },
--                                         items = { [itemID] = Anzahl (Taschen + Bank) } }
--   GuildPrideDB.craftReagents[Rezept] = { made, out, r = { { itemID, Menge }, … } }   (Zutaten-Cache)
-- Dazu: wer in der Gilde ein Rezept kann (Handwerker-Verzeichnis), „Bestes jetzt“ fürs
-- nächste Skill-Up und der aktuelle Guide-Schritt.
local ADDON, ns = ...
local L = ns.L

local Craft = {}
ns.Craft = Craft
local G = ns.CraftGuides

local MAX_ITEMS = 1500   -- je Charakter gemerkte Item-Arten

local function Saved(key)
    if type(GuildPrideDB) ~= "table" then return {} end
    if type(GuildPrideDB[key]) ~= "table" then GuildPrideDB[key] = {} end
    return GuildPrideDB[key]
end
function Craft.Chars() return Saved("craftChars") end
local function Reagents() return Saved("craftReagents") end

local function Me() return ns.Me and ns.Me() or UnitName("player") end
Craft.Me = Me

local function MyEntry()
    local chars, me = Craft.Chars(), Me()
    local e = chars[me]
    if type(e) ~= "table" then e = { profs = {}, known = {}, items = {} }; chars[me] = e end
    e.profs, e.known, e.items = e.profs or {}, e.known or {}, e.items or {}
    return e
end
Craft.MyEntry = MyEntry

---------------------------------------------------------------------
-- Berufe lesen (Stufe und Höchststufe)
---------------------------------------------------------------------
function Craft.ReadProfessions()
    local e = MyEntry()
    local found = {}
    if GetProfessions and GetProfessionInfo then
        for _, idx in ipairs({ GetProfessions() }) do
            if idx then
                local ok, name, _, rank, max, _, _, line = pcall(GetProfessionInfo, idx)
                if ok and line and G.NAMES[line] then
                    found[line] = { skill = tonumber(rank) or 0, max = tonumber(max) or 0, name = name }
                end
            end
        end
    end
    -- Ersatz: Fertigkeiten-Liste nach Namen (deutsch/englisch)
    if not next(found) and GetNumSkillLines and GetSkillLineInfo then
        local byName = {}
        for line, n in pairs(G.NAMES) do byName[n.de:lower()] = line; byName[n.en:lower()] = line end
        for i = 1, GetNumSkillLines() do
            local name, header, _, rank, _, _, max = GetSkillLineInfo(i)
            local line = not header and type(name) == "string" and byName[name:lower()]
            if line then found[line] = { skill = tonumber(rank) or 0, max = tonumber(max) or 0, name = name } end
        end
    end
    if next(found) then e.profs = found end
    e.level = UnitLevel and UnitLevel("player") or e.level
    e.mailName = UnitName and UnitName("player") or e.mailName   -- Name fürs Postfach (ohne Nachnamen)
    e.t = GetServerTime()
    return e.profs
end

-- Stufe eines Berufs (eigener Charakter): skill, max oder nil
function Craft.Skill(line, char)
    local e = char and Craft.Chars()[char] or MyEntry()
    local p = e and e.profs and e.profs[line]
    if not p then return nil end
    return p.skill, p.max, p.name
end

-- Deine Berufe in fester Reihenfolge: { line, skill, max, name }
function Craft.MyProfessions(char)
    local e = char and Craft.Chars()[char] or MyEntry()
    local out = {}
    for _, line in ipairs(G.ORDER) do
        local p = e and e.profs and e.profs[line]
        if p then out[#out + 1] = { line = line, skill = p.skill, max = p.max, name = p.name or G.Name(line) } end
    end
    return out
end

---------------------------------------------------------------------
-- Offenes Berufsfenster: Rezepte, Zutaten, Farben
---------------------------------------------------------------------
local function T() return C_TradeSkillUI end

-- Welcher Beruf ist im Fenster offen? (Skill-Line-ID)
function Craft.OpenLine()
    local t = T()
    if not t then return nil end
    if t.GetBaseProfessionInfo then
        local ok, info = pcall(t.GetBaseProfessionInfo)
        if ok and type(info) == "table" then
            local id = tonumber(info.professionID) or tonumber(info.parentProfessionID)
            if id and G.NAMES[id] then return id, info end
        end
    end
    if t.GetTradeSkillLine then
        local ok, _, name = pcall(t.GetTradeSkillLine)
        if ok and type(name) == "string" then
            for line, n in pairs(G.NAMES) do
                if n.de == name or n.en == name then return line end
            end
        end
    end
    return nil
end

function Craft.RecipeInfo(id)
    local t = T()
    if not (t and t.GetRecipeInfo and id) then return nil end
    local ok, info = pcall(t.GetRecipeInfo, id)
    return ok and type(info) == "table" and info or nil
end

-- Zutaten eines Rezepts: live (Berufsfenster), sonst aus dem Cache
function Craft.Reagents(id)
    local c = Reagents()[id]
    if ns.AH and ns.AH.RecipeReagents then
        local r = ns.AH.RecipeReagents(id)
        if #r > 0 then
            local made, out = 1, nil
            local t = T()
            if t and t.GetRecipeSchematic then
                local ok, sch = pcall(t.GetRecipeSchematic, id, false)
                if ok and type(sch) == "table" then made, out = tonumber(sch.quantityMin) or 1, tonumber(sch.outputItemID) end
            end
            c = { made = made, out = out, r = r }
            Reagents()[id] = c
        end
    end
    -- noch nie im Berufsfenster gesehen: Zutaten aus den Guide-Daten
    if not c and G.REAGENTS[id] then c = { made = 1, r = G.REAGENTS[id], guide = true } end
    return c and c.r or nil, c
end

-- Was stellt das Rezept her? itemID, Stückzahl (nil, wenn das Spiel es noch nicht verrät)
function Craft.OutputItem(id)
    if not id then return nil end
    local _, c = Craft.Reagents(id)
    if c and c.out then return c.out, c.made or 1 end
    local t = T()
    if t and t.GetRecipeSchematic then
        local ok, sch = pcall(t.GetRecipeSchematic, id, false)
        local out = ok and type(sch) == "table" and tonumber(sch.outputItemID)
        if out then
            local made = tonumber(sch.quantityMin) or 1
            local cache = Reagents()[id] or { r = Craft.KnownReagents(id) }
            cache.out, cache.made = out, made
            Reagents()[id] = cache
            return out, made
        end
    end
    return nil
end

-- Dünne goldene Scrollleiste für Listen mit eigener Blätter-Logik (offset).
-- onScroll(neuer offset) wird beim Ziehen gerufen; s:Update(offset, gesamt, sichtbar) zeigt sie
-- nur, wenn es mehr Zeilen gibt als Platz ist.
function Craft.ThinScroll(parent, onScroll, width)
    width = width or 5
    local s = CreateFrame("Slider", nil, parent)
    s:SetWidth(width)
    s:SetOrientation("VERTICAL")
    s:SetValueStep(1)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:SetMinMaxValues(0, 0); s:SetValue(0)
    local bg = s:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.35)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(0.79, 0.64, 0.36, 0.9)
    thumb:SetSize(width, 24)
    s:SetThumbTexture(thumb)
    s:SetScript("OnValueChanged", function(self, v)
        if self.updating then return end
        onScroll(math.floor((tonumber(v) or 0) + 0.5))
    end)
    s:Hide()
    function s.Update(self, offset, total, visible)
        local max = math.max(0, (total or 0) - (visible or 0))
        self:SetShown(max > 0)
        if max == 0 then return end
        self.updating = true
        self:SetMinMaxValues(0, max)
        self:SetValue(offset or 0)
        self.updating = false
        local h = tonumber(self:GetHeight()) or 0
        if h > 0 then thumb:SetHeight(math.max(14, h * visible / total)) end
    end
    return s
end

-- Bild eines Rezepts: das hergestellte Item, sonst das Zaubersymbol
function Craft.RecipeIcon(id)
    local out = Craft.OutputItem(id)
    if out then return Craft.ItemIcon(out) end
    local tex
    if C_Spell and C_Spell.GetSpellTexture then tex = C_Spell.GetSpellTexture(id)
    elseif GetSpellTexture then tex = GetSpellTexture(id) end
    local info = not tex and Craft.RecipeInfo(id)
    return tex or (info and info.icon) or 134400
end

-- Zutaten ohne Abfrage beim Spiel: Cache, sonst Guide-Daten
function Craft.KnownReagents(id)
    local c = Reagents()[id]
    if c and c.r then return c.r end
    return G.REAGENTS[id]
end

-- Alle Rezepte des offenen Berufs merken: bekannte Rezepte und Zutaten
function Craft.ReadOpenProfession()
    local t = T()
    local line = Craft.OpenLine()
    if not (t and line and t.GetAllRecipeIDs) then return end
    if t.IsTradeSkillLinked and t.IsTradeSkillLinked() then return end      -- Fenster eines anderen
    if t.IsTradeSkillGuild and t.IsTradeSkillGuild() then return end
    local ok, ids = pcall(t.GetAllRecipeIDs)
    if not ok or type(ids) ~= "table" then return end
    local e = MyEntry()
    local known, all = {}, {}
    for i, id in ipairs(ids) do
        if i > 800 then break end
        all[id] = true
        local info = Craft.RecipeInfo(id)
        if info and info.learned then
            known[id] = true
            Craft.Reagents(id)
        end
    end
    if next(known) then e.known[line] = known end
    -- Alle Rezepte, die dein Spiel für diesen Beruf kennt (Guide-Abgleich, für alle Charaktere gleich)
    if next(all) then Saved("craftAll")[line] = all end
    -- Zutaten der Guide-Rezepte merken, auch wenn du sie noch nicht kannst (Einkaufsliste)
    for _, s in ipairs(G.STEPS[line] or {}) do
        if not Reagents()[s[3]] then pcall(Craft.Reagents, s[3]) end
    end
    Craft.ReadProfessions()
    if Craft.Changed then Craft.Changed() end
end

-- Gibt es das Rezept in deinem Spiel? true/false, nil = noch unbekannt (Berufsfenster nie offen)
function Craft.InGame(line, id)
    local all = Saved("craftAll")[line]
    if type(all) ~= "table" or not next(all) then return nil end
    return all[id] == true
end

---------------------------------------------------------------------
-- Guide-Schritte von Hand abhaken (je Charakter)
---------------------------------------------------------------------
local function StepKey(s) return s.from .. "-" .. s.to .. "-" .. tostring(s.spell or s.text or "") end
local function Skips(line, create)
    local e = MyEntry()
    e.skip = e.skip or {}
    if create and not e.skip[line] then e.skip[line] = {} end
    return e.skip[line]
end
function Craft.IsSkipped(line, s)
    local sk = Skips(line)
    return sk and sk[StepKey(s)] and true or false
end
function Craft.ToggleSkip(line, s)
    local sk = Skips(line, true)
    local k = StepKey(s)
    sk[k] = not sk[k] or nil
    if Craft.Changed then Craft.Changed() end
    return sk[k] == true
end

-- Farbe eines Rezepts für dich gerade: "orange", "yellow", "green", "gray" oder nil
-- Je nach Spielversion steht sie in einem anderen Feld: relativeDifficulty (Zahl),
-- difficulty / skillType (Text wie "optimal"), sonst über die klassische Berufs-API nach Namen.
local DIFF = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "gray" }
local DIFF_TEXT = { optimal = "orange", orange = "orange", medium = "yellow", yellow = "yellow",
                    easy = "green", green = "green", trivial = "gray", gray = "gray", grey = "gray" }
local DIFF_RANK = { orange = 0, yellow = 1, green = 2, gray = 3 }
Craft.DIFF_RANK = DIFF_RANK

local function ClassicDifficulty(name)
    if not (name and GetNumTradeSkills and GetTradeSkillInfo) then return nil end
    local ok, n = pcall(GetNumTradeSkills)
    for i = 1, (ok and tonumber(n) or 0) do
        local ok2, sname, stype = pcall(GetTradeSkillInfo, i)
        if ok2 and sname == name and type(stype) == "string" then return DIFF_TEXT[stype:lower()] end
    end
    return nil
end

function Craft.DifficultyOf(info)
    if type(info) ~= "table" then return nil end
    local d = info.relativeDifficulty
    if type(d) == "number" and DIFF[d] then return DIFF[d] end
    for _, key in ipairs({ "difficulty", "skillType", "skillLineDifficulty" }) do
        local v = info[key]
        if type(v) == "string" and DIFF_TEXT[v:lower()] then return DIFF_TEXT[v:lower()] end
        if type(v) == "number" and DIFF[v] then return DIFF[v] end
    end
    return ClassicDifficulty(info.name)
end

function Craft.Difficulty(id)
    return Craft.DifficultyOf(Craft.RecipeInfo(id))
end
Craft.COLORS = { orange = "ff8040", yellow = "ffff00", green = "40c040", gray = "808080" }

-- „Bestes jetzt“: Rezept mit sicherem Punkt (orange vor gelb), das du herstellen kannst,
-- am günstigsten. Kennt das Spiel keine Farben, zählt der Guide-Schritt.
-- Rückgabe: Rezept-ID, Farbe, herstellbar (Anzahl)  ·  nil, Grund ("keine Farben" / "kein Punkt")
function Craft.BestNow()
    local t = T()
    if not (t and t.GetAllRecipeIDs) then return nil end
    local ok, ids = pcall(t.GetAllRecipeIDs)
    if not ok or type(ids) ~= "table" then return nil end
    local best, bestScore, bestDiff, anyColor = nil, nil, nil, false
    for i, id in ipairs(ids) do
        if i > 800 then break end
        local info = Craft.RecipeInfo(id)
        if info and info.learned then
            local diff = Craft.DifficultyOf(info)
            if diff then anyColor = true end
            local rank = diff and DIFF_RANK[diff]
            if rank == 0 or rank == 1 then
                local can = tonumber(info.numAvailable) or 0
                local cost = 0
                if ns.AH and ns.AH.RecipeValue then
                    local okv, v = pcall(ns.AH.RecipeValue, id)
                    if okv and v then cost = v.cost + v.missing * 10000 end
                end
                -- kleiner ist besser: orange vor gelb, herstellbar zuerst, dann billig
                local score = rank * 1e9 + (can > 0 and 0 or 5e8) + cost
                if not bestScore or score < bestScore then best, bestScore, bestDiff = id, score, diff end
            end
        end
    end
    if best then
        local info = Craft.RecipeInfo(best)
        return best, bestDiff, info and tonumber(info.numAvailable) or 0
    end
    if not anyColor then
        -- Spiel liefert keine Farben: Rezept des aktuellen Guide-Schritts
        local line = Craft.OpenLine()
        local step = line and Craft.CurrentStep(line)
        if step and step.spell then return step.spell, nil, 0 end
        return nil, "keine Farben"
    end
    return nil, "kein Punkt"
end

-- Rezept im Berufsfenster auswählen. Versucht nacheinander: Rezeptliste des Fensters,
-- OpenRecipe, und als Letztes den Namen ins Suchfeld (dann steht das Rezept ganz oben).
-- Rückgabe: true, wenn das Rezept danach gewählt ist; sonst false, "suche" oder nil
local function Selected()
    local AH = ns.AH
    local r = AH and AH.CurrentRecipe and AH.CurrentRecipe()
    return r and r.id
end

-- Das Berufsfenster übernimmt eine Auswahl erst einen Moment später: nach jedem Versuch
-- kurz warten und dann prüfen. done(ok, how) bekommt das Ergebnis (how = "suche", wenn nur
-- das Suchfeld half). Rückgabe sofort: true, wenn ein Versuch gestartet wurde.
function Craft.SelectRecipe(id, done)
    if not id then if done then done(false) end return false end
    done = done or function() end
    local t = T()
    local info = Craft.RecipeInfo(id)
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    local list = page and page.RecipeList
    local tries = {}
    -- 1. Rezeptliste des Berufsfensters (wie ein Klick auf das Rezept)
    if info and list and type(list.SelectRecipe) == "function" then
        tries[#tries + 1] = function() pcall(list.SelectRecipe, list, info, true) end
    end
    if info and page and type(page.SelectRecipe) == "function" then
        tries[#tries + 1] = function() pcall(page.SelectRecipe, page, info) end
    end
    -- 2. Blizzard-Funktion
    if t and t.OpenRecipe then tries[#tries + 1] = function() pcall(t.OpenRecipe, id) end end
    local function Search()
        -- 3. Suchfeld: Rezept steht dann ganz oben in der Liste, danach noch einmal wählen
        local box = list and (list.SearchBox or (list.FilterBar and list.FilterBar.SearchBox))
        local name = (info and info.name) or Craft.RecipeName(id)
        if not (box and type(box.SetText) == "function" and name) then return done(false) end
        pcall(box.SetText, box, name)
        C_Timer.After(0.3, function()
            if info and list and type(list.SelectRecipe) == "function" then pcall(list.SelectRecipe, list, info, true) end
            C_Timer.After(0.3, function() done(Selected() == id, "suche") end)
        end)
    end
    local i = 0
    local function Next()
        if Selected() == id then return done(true) end
        i = i + 1
        local try = tries[i]
        if not try then return Search() end
        try()
        C_Timer.After(0.25, Next)
    end
    Next()
    return true
end

-- Fehlersuche: welche Felder liefert das Spiel zum gewählten Rezept?
function Craft.Diag()
    local id = Selected()
    if not id then ns.Print(L["Handwerk: Kein Rezept gewählt – Berufsfenster öffnen und ein Rezept anklicken."]); return end
    local info = Craft.RecipeInfo(id) or {}
    local keys = {}
    for k, v in pairs(info) do
        if type(v) ~= "table" and type(v) ~= "function" then keys[#keys + 1] = k .. "=" .. tostring(v) end
    end
    table.sort(keys)
    ns.Print(("Handwerk diag: id=%s line=%s farbe=%s"):format(tostring(id), tostring(Craft.OpenLine()), tostring(Craft.Difficulty(id))))
    ns.Print(table.concat(keys, "  "))
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    local list = page and page.RecipeList
    ns.Print(("RecipeList=%s SelectRecipe=%s page.SelectRecipe=%s OpenRecipe=%s SearchBox=%s"):format(
        tostring(list ~= nil), tostring(list and type(list.SelectRecipe) == "function"),
        tostring(page and type(page.SelectRecipe) == "function"),
        tostring(C_TradeSkillUI and C_TradeSkillUI.OpenRecipe ~= nil),
        tostring(list and (list.SearchBox or (list.FilterBar and list.FilterBar.SearchBox)) ~= nil)))
end

---------------------------------------------------------------------
-- Bestände: Taschen + Bank (Bank zählt das Spiel mit, auch geschlossen)
---------------------------------------------------------------------
local function Count(id)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not (f and id) then return 0, 0 end
    local ok1, bags = pcall(f, id, false)
    local ok2, all = pcall(f, id, true)
    bags = ok1 and tonumber(bags) or 0
    all = ok2 and tonumber(all) or bags
    return bags, math.max(0, all - bags)
end
Craft.Count = Count

-- Alle Items in Taschen (und Bank, wenn offen) für die Twink-Übersicht merken
local function ScanItems()
    local e = MyEntry()
    local items = {}
    local n = 0
    local C = C_Container
    local GetSlots = C and C.GetContainerNumSlots or GetContainerNumSlots
    local GetID = C and C.GetContainerItemID or GetContainerItemID
    if not (GetSlots and GetID) then return end
    local function Bag(b)
        local ok, slots = pcall(GetSlots, b)
        for s = 1, (ok and slots or 0) do
            local ok2, id = pcall(GetID, b, s)
            if ok2 and id and not items[id] and n < MAX_ITEMS then
                items[id] = true; n = n + 1
            end
        end
    end
    for b = 0, (NUM_BAG_SLOTS or 4) do Bag(b) end
    -- Bank nur, wenn sie offen ist (sonst kennt das Spiel die Fächer nicht)
    if Craft.bankOpen then
        Bag(BANK_CONTAINER or -1)
        for b = (NUM_BAG_SLOTS or 4) + 1, (NUM_BAG_SLOTS or 4) + (NUM_BANKBAGSLOTS or 6) do Bag(b) end
    end
    -- Gemerkte Bank-Items behalten (sind ja weiter dort), Zahlen frisch über GetItemCount
    for id in pairs(e.items) do if not items[id] and n < MAX_ITEMS then items[id] = true; n = n + 1 end end
    local out = {}
    for id in pairs(items) do
        local bags, bank = Count(id)
        if bags + bank > 0 then out[id] = bags + bank end
    end
    e.items = out
end
Craft.ScanItems = ScanItems

-- Wie viele haben deine anderen Charaktere? { { name, n } }, Summe
function Craft.AltCounts(id)
    local me, out, sum = Me(), {}, 0
    for name, e in pairs(Craft.Chars()) do
        local n = name ~= me and type(e) == "table" and e.items and tonumber(e.items[id])
        if n and n > 0 then out[#out + 1] = { name = name, n = n }; sum = sum + n end
    end
    table.sort(out, function(a, b) return a.n > b.n end)
    return out, sum
end

-- Welche deiner Charaktere kennen das Rezept?
function Craft.AltsKnowing(id)
    local me, out = Me(), {}
    for name, e in pairs(Craft.Chars()) do
        if name ~= me and type(e) == "table" and e.known then
            for _, set in pairs(e.known) do
                if set[id] then out[#out + 1] = name; break end
            end
        end
    end
    table.sort(out)
    return out
end

---------------------------------------------------------------------
-- Gilde: wer kann dieses Rezept? (Handwerker-Verzeichnis, nur aktuelle Mitglieder)
---------------------------------------------------------------------
function Craft.GuildKnowing(id)
    local out = {}
    if not (ns.GuildTable and IsInGuild and IsInGuild()) then return out end
    local me = Me()
    for name, e in pairs(ns.GuildTable("crafts")) do
        if name ~= me and type(e) == "table" and type(e.rec) == "table"
           and (not ns.IsGuildMember or ns.IsGuildMember(name)) then
            for _, ids in pairs(e.rec) do
                local hit = false
                for _, x in ipairs(ids) do if tonumber(x) == id then hit = true; break end end
                if hit then out[#out + 1] = name; break end
            end
        end
    end
    table.sort(out)
    return out
end

---------------------------------------------------------------------
-- Guide: aktueller Schritt für deinen Beruf
---------------------------------------------------------------------
-- Erster Schritt, dessen Ende über deiner Stufe liegt und den du nicht abgehakt hast
function Craft.CurrentStep(line, skill)
    skill = skill or Craft.Skill(line) or 0
    local steps = G.Steps(line)
    for i, s in ipairs(steps) do
        if skill < s.to and not Craft.IsSkipped(line, s) then return s, i, steps end
    end
    return nil, nil, steps
end

-- Was brauchst du noch bis zur Stufe target? Rezepte { [Rezept] = Anzahl } und
-- Zutaten { { id, need, have, missing } } (have = alle deine Charaktere), Schritte ohne bekannte Zutaten
-- Wie oft kannst du ein Rezept mit dem herstellen, was in deinen Taschen ist?
function Craft.CanCraft(id)
    local r = Craft.KnownReagents(id)
    if not r or #r == 0 then return 0 end
    local n
    for _, x in ipairs(r) do
        local bags = Count(x[1])
        local k = math.floor(bags / math.max(1, x[2]))
        n = n and math.min(n, k) or k
    end
    return n or 0
end

-- Was kostet dich der Rest bis target noch? (GuildPride-Preise, abzüglich Bestand aller Charaktere)
-- Rückgabe: Kupfer, Anzahl Zutaten ohne Preis
-- Günstigster Weg zu einem Item: Händler (gemerkter Preis), Auktionshaus oder selbst herstellen
-- (wenn einer deiner Charaktere ein Rezept dafür kann, z. B. Erz schmelzen statt Barren kaufen).
-- Rückgabe: Kupfer je Stück oder nil, Weg ("vendor"/"ah"/"craft"), Rezept beim Herstellen
function Craft.CheapestPrice(itemID, depth)
    depth = depth or 0
    local AH = ns.AH
    local best, how, via
    local vendor = type(GuildPrideDB) == "table" and type(GuildPrideDB.craftVendor) == "table" and GuildPrideDB.craftVendor[itemID]
    if vendor and vendor.p then best, how = vendor.p, "vendor" end
    local ah = AH and AH.PriceFor and AH.Key and AH.PriceFor(AH.Key(itemID))
    if ah and (not best or ah < best) then best, how = ah, "ah" end
    if depth < 2 then
        for id, c in pairs(Reagents()) do
            if c.out == itemID and c.r and Craft.AnyoneKnows(id) then
                local sum, ok = 0, true
                for _, x in ipairs(c.r) do
                    local p = Craft.CheapestPrice(x[1], depth + 1)
                    if not p then ok = false; break end
                    sum = sum + p * x[2]
                end
                if ok then
                    local each = sum / math.max(1, c.made or 1)
                    if not best or each < best then best, how, via = each, "craft", id end
                end
            end
        end
    end
    return best and math.floor(best + 0.5) or nil, how, via
end

-- Kann einer deiner Charaktere das Rezept?
function Craft.AnyoneKnows(id)
    for _, e in pairs(Craft.Chars()) do
        if type(e) == "table" and e.known then
            for _, set in pairs(e.known) do if set[id] then return true end end
        end
    end
    return false
end

-- Was kostet dich der Rest bis target noch? (günstigster Weg je Zutat, abzüglich Bestand aller Charaktere)
-- Rückgabe: Kupfer, Anzahl Zutaten ohne Preis
function Craft.RouteCost(line, target, skill)
    local _, items = Craft.RouteNeeds(line, target, skill)
    local cost, unknown = 0, 0
    for _, it in ipairs(items) do
        if it.missing > 0 then
            local p = Craft.CheapestPrice(it.id)
            if p then cost = cost + p * it.missing else unknown = unknown + 1 end
        end
    end
    return cost, unknown
end

-- Kosten eines Schritts (n Herstellungen, ohne Bestand): Kupfer, Anzahl ohne Preis
function Craft.StepCost(id, n)
    local cost, unknown = 0, 0
    for _, x in ipairs(Craft.KnownReagents(id) or {}) do
        local p = Craft.CheapestPrice(x[1])
        if p then cost = cost + p * x[2] * (n or 1) else unknown = unknown + 1 end
    end
    return cost, unknown
end

function Craft.RouteNeeds(line, target, skill)
    skill = skill or Craft.Skill(line) or 0
    local recipes, items, unknown = {}, {}, 0
    for _, s in ipairs(G.Steps(line)) do
        if s.spell and s.to > skill and s.from < target and not Craft.IsSkipped(line, s) then
            local n = G.Remaining(s, skill) or 0
            -- Schritt geht über das Ziel hinaus: nur den Teil bis zum Ziel
            if s.to > target and s.to > s.from then
                n = math.ceil(n * (target - math.max(skill, s.from)) / (s.to - math.max(skill, s.from)))
            end
            if n > 0 then
                recipes[s.spell] = (recipes[s.spell] or 0) + n
                local r = Craft.KnownReagents(s.spell)
                if r then
                    for _, x in ipairs(r) do items[x[1]] = (items[x[1]] or 0) + x[2] * n end
                else
                    unknown = unknown + 1
                end
            end
        end
    end
    local list = {}
    for id, need in pairs(items) do
        local bags, bank = Count(id)
        local _, alts = Craft.AltCounts(id)
        local have = bags + bank + alts
        list[#list + 1] = { id = id, need = need, have = have, missing = math.max(0, need - have) }
    end
    table.sort(list, function(a, b) return a.missing > b.missing end)
    return recipes, list, unknown
end

function Craft.RecipeName(id)
    if not id then return "?" end
    local n
    if C_Spell and C_Spell.GetSpellName then n = C_Spell.GetSpellName(id)
    elseif GetSpellInfo then n = GetSpellInfo(id) end
    if type(n) ~= "string" or n == "" then
        local info = Craft.RecipeInfo(id)
        n = info and info.name
    end
    return type(n) == "string" and n or ("#" .. id)
end

function Craft.ItemName(id)
    local f = (C_Item and C_Item.GetItemNameByID) or (GetItemInfo and function(x) return (GetItemInfo(x)) end)
    local n = f and f(id)
    return type(n) == "string" and n or ("#" .. tostring(id))
end

function Craft.ItemIcon(id)
    local f = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    return f and f(id) or 134400
end

---------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------
local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "PLAYER_LOGIN", "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE",
    "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED")
local readPending, scanPending = false, false
local function ReadSoon()
    if readPending then return end
    readPending = true
    C_Timer.After(1.5, function() readPending = false; pcall(Craft.ReadOpenProfession) end)
end
local function ScanSoon()
    if scanPending then return end
    scanPending = true
    C_Timer.After(2, function()
        scanPending = false
        pcall(ScanItems)
        if Craft.Changed then Craft.Changed() end
    end)
end
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(5, function() pcall(Craft.ReadProfessions); ScanSoon() end)
    elseif event == "SKILL_LINES_CHANGED" then
        pcall(Craft.ReadProfessions)
        if Craft.Changed then Craft.Changed() end
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then
        ReadSoon()
    elseif event == "BANKFRAME_OPENED" then
        Craft.bankOpen = true; ScanSoon()
    elseif event == "BANKFRAME_CLOSED" then
        Craft.bankOpen = false
    else
        ScanSoon()
    end
end)

-- Andere Module melden sich hier an, wenn sich etwas ändert (Tracker, Fenster, Karte)
local listeners = {}
function Craft.OnChanged(fn) listeners[#listeners + 1] = fn end
function Craft.Changed()
    for _, fn in ipairs(listeners) do pcall(fn) end
end
