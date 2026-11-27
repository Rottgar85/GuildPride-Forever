-- GuildPride: Buff-Food- und Erholungs-Erinnerung
-- * Buff-Food (buffFood): 2 Min. bevor „Satt“ (Well Fed) ausläuft oder wenn es
--   fehlt, öffnet sich ein kleines Fenster mit dem Buff-Food aus deinen Taschen –
--   das beste für deine Klasse steht vorne. Ein Klick isst es, das Fenster verschwindet.
--   Nichts dabei: es nennt, was du kochen kannst und was deine Twinks haben.
--   buffFoodGroupOnly: nur in Instanzen und Gruppen. buffFoodReady: beim
--   Bereitschaftscheck erinnern, wenn „Satt“ fehlt oder unter 5 Min. hat.
-- * Erholung (restReminder, nur unter der Höchststufe): läuft „Lagervorteile“
--   vom Lagerfeuer aus (oder wird der Gemütliche Schlafsack wieder bereit),
--   öffnet sich das Fenster mit Schlafsack und bestem Lagerfeuer. Ein Klick
--   benutzt es, das Fenster verschwindet.
-- Werte und Stufe kommen aus dem Tooltip des Gegenstands (Forever-Daten gehen
-- vor), die Gewichte je Klasse aus Buffs.WEIGHTS. Die Knöpfe sind sichere
-- Aktionsknöpfe: Fenster nur außerhalb des Kampfes, bei Kampfbeginn zu
-- (kommt vor der Kampfsperre), danach wieder auf, wenn noch nötig.
-- X schließt bis zum nächsten Auslaufen. Von Hand: /gp buff, /gp rast.
-- Daten: Boosted Rest 1229451 und Schlafsack 211527 wie Polestar (QoL/Rest.lua),
-- Lagerfeuer-Bausätze aus den Forever-Itemdaten.
local ADDON, ns = ...
local L = ns.L

local Buffs = {}
ns.Buffs = Buffs

Buffs.REST_SPELL = 1229451          -- Lagervorteile / Boosted Rest (am Lagerfeuer sitzen)
-- Buff des Lagerfeuers am Namen (deutscher und englischer Client)
Buffs.FIRE_BUFF_NAMES = { ["Lagervorteile"] = true, ["Boosted Rest"] = true }
Buffs.BAG_ITEM = 211527             -- Gemütlicher Schlafsack (Cozy Sleeping Bag)
-- Lagerfeuer, das beste zuerst: Bausätze, danach Kochen-Zauber „Einfaches Lagerfeuer“
Buffs.CAMPFIRES = {
    { item = 279974 },              -- Expert Campfire Kit
    { item = 279961 },              -- Journeyman Campfire Kit
    { item = 279981 },              -- Basic Campfire Kit
    { spell = 818 },                -- Basic Campfire (Kochen)
}
local WELL_FED_SPELL = 19705        -- „Satt“, nur für den Namen in der Client-Sprache
local GCD = 1.5

-- Wie viel ein Punkt je Werteart für die Klasse wert ist (Classic-Faustregeln:
-- Mana alle 5 Sek. ≈ 2 Willenskraft).
Buffs.WEIGHTS = {
    WARRIOR = { str = 1.0, sta = 0.9, agi = 0.7, hp5 = 1.0, spi = 0.1 },
    ROGUE   = { agi = 1.0, str = 0.5, sta = 0.6, hp5 = 0.6, spi = 0.05 },
    HUNTER  = { agi = 1.0, sta = 0.5, int = 0.3, mp5 = 1.0, spi = 0.2, str = 0.1 },
    PALADIN = { str = 0.9, sta = 0.7, int = 0.5, mp5 = 1.5, spi = 0.3, agi = 0.4, hp5 = 0.5 },
    SHAMAN  = { str = 0.6, agi = 0.5, int = 0.7, mp5 = 2.0, sta = 0.5, spi = 0.3, hp5 = 0.3 },
    DRUID   = { str = 0.6, agi = 0.6, int = 0.6, sta = 0.6, spi = 0.5, mp5 = 1.5, hp5 = 0.4 },
    PRIEST  = { int = 0.8, spi = 0.9, mp5 = 2.0, sta = 0.5, hp5 = 0.2 },
    MAGE    = { int = 0.9, spi = 0.7, mp5 = 2.0, sta = 0.5, hp5 = 0.2 },
    WARLOCK = { int = 0.6, sta = 1.0, spi = 0.4, mp5 = 2.0, hp5 = 0.3 },
}
local DEFAULT_WEIGHTS = { sta = 0.7, spi = 0.5, str = 0.6, agi = 0.6, int = 0.6, mp5 = 1.5, hp5 = 0.5 }

-- Wörter im Tooltip (Englisch und Deutsch) -> Werteart
local STAT_WORDS = {
    stamina = "sta", ausdauer = "sta",
    spirit = "spi", willenskraft = "spi",
    strength = "str", ["stärke"] = "str",
    agility = "agi", beweglichkeit = "agi",
    intellect = "int", intelligenz = "int",
    mana = "mp5",
    health = "hp5", gesundheit = "hp5",
}

---------------------------------------------------------------------
-- Tooltip lesen (rein, getestet): Zeilen -> { sta = 12, spi = 12 } oder nil
---------------------------------------------------------------------
-- Nur der Teil hinter „well fed“ / „satt“ zählt (davor steht die Heilung).
function Buffs.ParseFood(lines)
    if type(lines) ~= "table" then return nil end
    for _, line in ipairs(lines) do
        if type(line) == "string" then
            local low = line:lower() .. " "
            local e
            -- nur die erste „Benutzen:“-Zeile; „satt“ als ganzes Wort (nicht „Sattel“).
            -- Bei Rezepten lehrt die erste Zeile das Kochen, „satt“ steht erst
            -- im angehängten Tooltip des fertigen Essens: kein Essen.
            if low:find("use:", 1, true) or low:find("benutzen:", 1, true) then
                e = select(2, low:find("well fed", 1, true))
                if not e then
                    -- danach kein Buchstabe: \195 beginnt ä/ö/ü/ß, Anführungszeichen („Satt“) sind erlaubt
                    local s = low:find("satt[^%a\195]")
                    e = s and s + 3
                end
                if not e then return nil end
            end
            if e then
                local rest = low:sub(e + 1)
                local stats, value = {}, nil
                -- erste Zahl direkt vor einem Wertewort ist der Wert
                for num, word in rest:gmatch("(%d+)%s+([%a\128-\255]+)") do
                    if STAT_WORDS[word] then value = tonumber(num); break end
                end
                if value then
                    for word in rest:gmatch("[%a\128-\255]+") do
                        local k = STAT_WORDS[word]
                        if k and not stats[k] then stats[k] = value end
                    end
                end
                return stats   -- leer = Buff-Food ohne lesbaren Wert
            end
        end
    end
    return nil
end

-- Punkte eines Essens für eine Klasse
function Buffs.Score(stats, class)
    local w = Buffs.WEIGHTS[class or ""] or DEFAULT_WEIGHTS
    local sum = 0
    for k, v in pairs(stats or {}) do sum = sum + (w[k] or 0) * v end
    if sum <= 0 then sum = 0.01 end   -- Buff-Food ohne lesbaren Wert: ganz hinten
    return sum
end

-- Kandidaten sortieren: Punkte, dann Anzahl, dann ID (fest)
function Buffs.Sort(list)
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if (a.count or 0) ~= (b.count or 0) then return (a.count or 0) > (b.count or 0) end
        return (a.id or 0) < (b.id or 0)
    end)
    return list
end

-- Text wie „+12 Ausdauer, +12 Willenskraft“
local STAT_LABEL = { sta = "Ausdauer", spi = "Willenskraft", str = "Stärke", agi = "Beweglichkeit",
                     int = "Intelligenz", mp5 = "Mana/5 Sek.", hp5 = "Leben/5 Sek." }
local STAT_ORDER = { "str", "agi", "sta", "int", "spi", "mp5", "hp5" }
function Buffs.StatText(stats)
    local out = {}
    for _, k in ipairs(STAT_ORDER) do
        if stats and stats[k] then out[#out + 1] = ("+%d %s"):format(stats[k], L[STAT_LABEL[k]]) end
    end
    return table.concat(out, ", ")
end

---------------------------------------------------------------------
-- Client lesen (mit Rückfall auf ältere Funktionen)
---------------------------------------------------------------------
local Secret = ns.IsSecret
local function Opt(key) return type(GuildPrideDB) == "table" and GuildPrideDB[key] ~= false end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end
local function SpellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    if GetSpellTexture then return GetSpellTexture(id) end
end
local function SpellKnown(id)
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    return IsSpellKnown and IsSpellKnown(id) or false
end
local function SpellUsable(id)
    if C_Spell and C_Spell.IsSpellUsable then return (C_Spell.IsSpellUsable(id)) end
    if IsUsableSpell then return (IsUsableSpell(id)) end
    return true
end
local function SpellReady(id)
    local start, dur
    if C_Spell and C_Spell.GetSpellCooldown then
        local c = C_Spell.GetSpellCooldown(id)
        if type(c) == "table" then start, dur = c.startTime, c.duration end
    elseif GetSpellCooldown then
        start, dur = GetSpellCooldown(id)
    end
    if Secret(start) or Secret(dur) then return false end
    return not dur or dur <= GCD or (start or 0) + dur <= GetTime()
end

local function ItemInfo(id)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not f then return nil end
    local name, _, _, _, minLevel, _, _, _, _, icon, _, classID = f(id)
    return name, minLevel, icon, classID
end
-- Gegenstandsklasse 9 = Rezept (Enum.ItemClass.Recipe)
function Buffs.IsRecipe(classID) return classID == 9 end
local function ItemCount(id)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    return f and f(id) or 0
end
local function ItemReady(id)
    local f = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not f then return true end
    local start, dur = f(id)
    if Secret(start) or Secret(dur) then return false end
    return not dur or dur <= GCD or (start or 0) + dur <= GetTime()
end

local function NumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end
local function SlotItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if type(info) == "table" then return info.itemID end
        return nil
    end
    if GetContainerItemID then return GetContainerItemID(bag, slot) end
end

local scanTip
local function ScanTip()
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "GuildPrideBuffScanTip", nil, "GameTooltipTemplate")
        scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    scanTip:ClearLines()
    return scanTip
end
local function ScanTipLines()
    local out = {}
    for i = 1, scanTip:NumLines() do
        local fs = _G["GuildPrideBuffScanTipTextLeft" .. i]
        local t = fs and fs:GetText()
        if type(t) == "string" and not Secret(t) then out[#out + 1] = t end
    end
    return out
end
local function DataLines(data)
    local out = {}
    for _, line in ipairs(type(data) == "table" and data.lines or {}) do
        if type(line.leftText) == "string" and not Secret(line.leftText) then out[#out + 1] = line.leftText end
    end
    return out
end

-- Tooltip eines Gegenstands nach ID (auch für Dinge, die nicht in deinen Taschen sind)
local function ItemTooltipLines(id)
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        local ok, data = pcall(C_TooltipInfo.GetItemByID, id)
        return DataLines(ok and data)
    end
    ScanTip():SetItemByID(id)
    return ScanTipLines()
end

local function TooltipLines(bag, slot)
    if C_TooltipInfo and C_TooltipInfo.GetBagItem then
        return DataLines(C_TooltipInfo.GetBagItem(bag, slot))
    end
    ScanTip():SetBagItem(bag, slot)
    return ScanTipLines()
end

-- Tooltip-Ergebnis je Gegenstand: false = kein Buff-Food
local foodCache = {}

local function BuffFoodInBags()
    local class = select(2, UnitClass("player"))
    local level = UnitLevel("player") or 1
    local seen, list = {}, {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, NumSlots(bag) do
            local id = SlotItem(bag, slot)
            if id and not seen[id] then
                seen[id] = true
                if foodCache[id] == nil then
                    local stats = Buffs.ParseFood(TooltipLines(bag, slot))
                    foodCache[id] = stats or false
                end
                local stats = foodCache[id]
                local name, minLevel, icon, classID = ItemInfo(id)
                if stats and name and not Buffs.IsRecipe(classID) and (minLevel or 0) <= level and ItemReady(id) then
                    list[#list + 1] = { kind = "item", id = id, name = name, icon = icon, count = ItemCount(id),
                                        score = Buffs.Score(stats, class), note = Buffs.StatText(stats) }
                end
            end
        end
    end
    return Buffs.Sort(list)
end
Buffs.FoodInBags = BuffFoodInBags

---------------------------------------------------------------------
-- Buff-Food nach Gegenstands-ID: für Kochrezepte und die Taschen der Twinks
---------------------------------------------------------------------
local COOKING = 185          -- Berufslinie Kochkunst
local CONSUMABLE = 0         -- Gegenstandsklasse Verbrauchsgut (Essen gehört dazu)

local function ItemClass(id)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not f then return nil end
    local ok, _, _, _, _, _, classID = pcall(f, id)
    if ok then return classID end
end

-- Tooltip-Ergebnis je ID; ändert sich nicht, darum nie geleert. false = kein Buff-Food
local idFood = {}
function Buffs.FoodStatsByID(id)
    id = tonumber(id)
    if not id then return nil end
    if idFood[id] == nil then
        if ItemClass(id) ~= CONSUMABLE then
            idFood[id] = false
        else
            local lines = ItemTooltipLines(id)
            if #lines == 0 then return nil end   -- Spiel kennt das Item noch nicht: später noch mal
            idFood[id] = Buffs.ParseFood(lines) or false
        end
    end
    return idFood[id] or nil
end

-- Bestes Satt-Essen, das du mit deinen Rezepten und den Zutaten in den Taschen kochen kannst
-- → { recipe, id, n, score, note } oder nil. Rezepte kennt das Addon erst, wenn du das
-- Kochkunst-Fenster einmal geöffnet hast.
function Buffs.BestCookable(class, level)
    local Craft = ns.Craft
    if not (Craft and Craft.MyEntry and Craft.CanCraft and Craft.OutputItem) then return nil end
    local ok, e = pcall(Craft.MyEntry)
    local known = ok and type(e) == "table" and type(e.known) == "table" and e.known[COOKING]
    if type(known) ~= "table" then return nil end
    local best
    for rid in pairs(known) do
        local n = tonumber(Craft.CanCraft(rid)) or 0
        local out = n > 0 and Craft.OutputItem(rid)
        local stats = out and Buffs.FoodStatsByID(out)
        local minLevel = stats and level and select(2, ItemInfo(out))
        if stats and (not minLevel or minLevel <= level) then
            local s = Buffs.Score(stats, class)
            if not best or s > best.score or (s == best.score and rid < best.recipe) then
                best = { recipe = rid, id = out, n = n, score = s, note = Buffs.StatText(stats) }
            end
        end
    end
    return best
end

-- Buff-Food deiner anderen Charaktere (zuletzt gesehene Taschen/Bank):
-- je Twink das beste → { { name, id, n, score } }, bestes zuerst
function Buffs.AltFood(class)
    local Craft = ns.Craft
    local out = {}
    if not (Craft and Craft.Chars) then return out end
    local me = Craft.Me and Craft.Me()
    for name, e in pairs(Craft.Chars()) do
        if name ~= me and type(e) == "table" and type(e.items) == "table" then
            local best
            for id, n in pairs(e.items) do
                n = tonumber(n)
                local stats = n and n > 0 and Buffs.FoodStatsByID(id)
                if stats then
                    local s = Buffs.Score(stats, class)
                    if not best or s > best.score or (s == best.score and n > best.n) then
                        best = { name = name, id = tonumber(id), n = n, score = s }
                    end
                end
            end
            if best then out[#out + 1] = best end
        end
    end
    table.sort(out, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.n ~= b.n then return a.n > b.n end
        return a.name < b.name
    end)
    return out
end

local function RestChoices()
    local list = {}
    if ItemCount(Buffs.BAG_ITEM) > 0 and ItemReady(Buffs.BAG_ITEM) then
        local name, _, icon = ItemInfo(Buffs.BAG_ITEM)
        list[#list + 1] = { kind = "item", id = Buffs.BAG_ITEM, name = name or L["Gemütlicher Schlafsack"], icon = icon,
                            note = L["Schlafsack ausrollen"], place = true }
    end
    for _, c in ipairs(Buffs.CAMPFIRES) do
        if c.item and ItemCount(c.item) > 0 and ItemReady(c.item) then
            local name, _, icon = ItemInfo(c.item)
            if name then
                list[#list + 1] = { kind = "item", id = c.item, name = name, icon = icon, count = ItemCount(c.item),
                                    note = L["Lagerfeuer aufstellen"], place = true }
                break
            end
        elseif c.spell and SpellKnown(c.spell) and SpellUsable(c.spell) and SpellReady(c.spell) then
            list[#list + 1] = { kind = "spell", id = c.spell, name = SpellName(c.spell), icon = SpellIcon(c.spell),
                                note = L["Lagerfeuer anzünden"], place = true }
            break
        end
    end
    return list
end
Buffs.RestChoices = RestChoices

-- Buff des Schlafsacks: „Gut erholt“ / „Well Rested“, dazu der Zauber, den der
-- Schlafsack selbst auslöst (Name und Nummer aus dem Client)
Buffs.BAG_BUFF_NAMES = { ["Gut erholt"] = true, ["Well Rested"] = true }
local function BagSpell()
    local f = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not f then return nil, nil end
    return f(Buffs.BAG_ITEM)
end

-- Aktive Buffs: satt? Lagervorteile (Lagerfeuer)? Gut erholt (Schlafsack)?
-- Geheime Werte im Kampf -> nil = unbekannt. Vierter Wert: Sekunden, bis „Satt“ ausläuft.
local function ReadAuras()
    local fedName, restName = SpellName(WELL_FED_SPELL), SpellName(Buffs.REST_SPELL)
    local bagName, bagSpell = BagSpell()
    local fed, rest, rested, fedLeft = false, false, false, nil
    local function Check(name, icon, spellId, expires)
        if Secret(name) or Secret(spellId) or Secret(icon) then error("secret") end
        if spellId == Buffs.REST_SPELL or Buffs.FIRE_BUFF_NAMES[name] or (restName and name == restName) then
            rest = true
        end
        if Buffs.BAG_BUFF_NAMES[name] or (bagSpell and spellId == bagSpell) or (bagName and name == bagName) then
            rested = true
        end
        -- nur der Buff „Satt“ selbst; das Symbol teilen sich viele andere Buffs (z. B. „Essen“)
        if (fedName and name == fedName) or name == "Well Fed" or name == "Satt" then
            fed = true
            if not Secret(expires) and type(expires) == "number" and expires > 0 then
                fedLeft = math.max(0, expires - GetTime())
            end
        end
    end
    local ok = pcall(function()
        for i = 1, 40 do
            if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
                local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
                if not a then break end
                Check(a.name, a.icon, a.spellId, a.expirationTime)
            elseif UnitBuff then
                local name, icon, _, _, _, expires, _, _, _, spellId = UnitBuff("player", i)
                if not name then break end
                Check(name, icon, spellId, expires)
            else
                break
            end
        end
    end)
    if not ok then return nil, nil, nil, nil end
    return fed, rest, rested, fedLeft
end
Buffs.ReadAuras = ReadAuras

-- Vorwarnung: so viele Sekunden vor dem Ablauf von „Satt“ kommt das Fenster schon
Buffs.WARN = 120
Buffs.READY_WARN = 300       -- beim Bereitschaftscheck: weniger als 5 Min. übrig

-- Essen nötig? fed = nil (unbekannt, Kampf) heißt nein
function Buffs.NeedFood(fed, left, warn)
    if fed == nil then return false end
    if not fed then return true end
    return left ~= nil and left <= (warn or Buffs.WARN)
end

-- Schalter „nur in Instanzen und Gruppen“ (aus = überall erinnern)
function Buffs.FoodHere()
    if not (type(GuildPrideDB) == "table" and GuildPrideDB.buffFoodGroupOnly == true) then return true end
    if IsInInstance then
        local inInst, kind = IsInInstance()
        if inInst and (kind == "party" or kind == "raid") then return true end
    end
    return IsInGroup and IsInGroup() and true or false
end

-- Bereitschaftscheck: fehlt „Satt“ oder läuft es in den nächsten 5 Min. aus?
function Buffs.ReadyCheckNeedsFood()
    if not (Opt("buffFood") and Opt("buffFoodReady")) then return false end
    local fed, _, _, left = ReadAuras()
    return Buffs.NeedFood(fed, left, Buffs.READY_WARN)
end

local function Leveling()
    local max = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or MAX_PLAYER_LEVEL or 60
    return (UnitLevel("player") or 1) < max
end

---------------------------------------------------------------------
-- Ein Fenster, drei Symbole: Buff-Food · Schlafsack · Lagerfeuer.
-- Buff-Food zeigt sich, wenn „Satt“ fehlt; Schlafsack und Lagerfeuer, wenn
-- „Lagervorteile“ fehlt. Was du nicht benutzen kannst, ist grau und sagt
-- darunter, warum (keins dabei, Abklingzeit …). Klick benutzt es.
---------------------------------------------------------------------
local SLOT_W, ICON = 84, 44
local ICON_FOOD = "Interface\\Icons\\INV_Misc_Food_14"
local ICON_FIRE = "Interface\\Icons\\Spell_Fire_Fire"
local ICON_BAG = "Interface\\Icons\\INV_Misc_Bag_08"
local win, slots
local SNOOZE = 30 * 60
local snoozeFood, snoozeBag, snoozeFire = 0, 0, 0 -- GetTime(), bis wann nicht gefragt wird
local warnLeft    -- Sekunden bis „Satt“ ausläuft, solange das Fenster vorwarnt
-- Von Hand (/gp buff, Bereitschaftscheck) geöffnet: bleibt offen, bis X, Benutzen,
-- Kampf oder Tod – die Prüfung frischt es dann nur auf, statt es zu schließen
local manual = false
local Check

local function SavePos(f)
    if type(GuildPrideDB) ~= "table" then return end
    local point, _, _, x, y = f:GetPoint(1)
    GuildPrideDB.buffWinPos = { point = point, x = x, y = y }
end

local function BagLeft()
    local f = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not f then return 0 end
    local start, dur = f(Buffs.BAG_ITEM)
    if Secret(start) or Secret(dur) or not dur or dur <= GCD then return 0 end
    return math.max(0, (start or 0) + dur - GetTime())
end

local function ItemIcon(id)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    return GetItemIcon and GetItemIcon(id)
end

local function MakeSlot(i, label)
    local b = CreateFrame("Button", "GuildPrideBuffSlot" .. i, win, "SecureActionButtonTemplate")
    b:SetSize(ICON, ICON)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetPoint("TOPLEFT", -3, 3); b.glow:SetPoint("BOTTOMRIGHT", 3, -3)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b.label = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.label:SetPoint("TOP", b, "BOTTOM", 0, -4); b.label:SetWidth(SLOT_W - 4)
    b.label:SetText(label)
    b.status = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.status:SetPoint("TOP", b.label, "BOTTOM", 0, -2); b.status:SetWidth(SLOT_W - 4)
    b.status:SetWordWrap(true)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local c = self.choice
        if c and c.kind == "item" then GameTooltip:SetItemByID(c.id)
        elseif c then GameTooltip:SetSpellByID(c.id)
        else GameTooltip:SetText(label); GameTooltip:AddLine(self.why or "", 1, 0.4, 0.4, true) end
        if c then GameTooltip:AddLine(L["Klick benutzt es"], 0.4, 1, 0.4) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- Symbol belegen: c = benutzbare Wahl oder nil (dann grau mit Grund)
local function SetSlot(b, c, icon, status, why)
    b.choice, b.why = c, why
    if c then
        if c.place then
            -- Schlafsack und Lagerfeuer werden auf den Boden gelegt:
            -- [@player] legt sie gleich neben dich, ohne Zielkreis
            b:SetAttribute("type", "macro")
            if c.kind == "spell" then
                b:SetAttribute("macrotext", "/cast [@player] " .. (c.name or SpellName(c.id) or ""))
            else
                b:SetAttribute("macrotext", "/use [@player] item:" .. c.id)
            end
        else
            b:SetAttribute("macrotext", nil)
            b:SetAttribute("type", c.kind)
            b:SetAttribute(c.kind, c.kind == "item" and ("item:" .. c.id) or c.id)
        end
        b.icon:SetTexture(c.icon or icon)
        b.icon:SetDesaturated(false)
        b.glow:SetColorTexture(1, 0.82, 0.2, 0.5)
        b.count:SetText((c.count or 0) > 1 and c.count or "")
        b.status:SetText("|cff80ff80" .. status .. "|r")
    else
        b:SetAttribute("type", nil)
        b.icon:SetTexture(icon)
        b.icon:SetDesaturated(true)
        b.glow:SetColorTexture(1, 0.2, 0.2, 0.35)
        b.count:SetText("")
        b.status:SetText("|cffff6060" .. status .. "|r")
    end
end

local function Clicked(kind)
    -- Essen/Benutzen kann abbrechen (aufgestanden): nach 45 Sek. noch einmal schauen
    local t = GetTime() + 45
    manual = false
    if kind == "food" then snoozeFood = t elseif kind == "bag" then snoozeBag = t else snoozeFire = t end
    if C_Timer then C_Timer.After(0.2, function() Check() end); C_Timer.After(46, function() Check() end) end
end

local function Build()
    if win then return end
    win = CreateFrame("Frame", "GuildPrideBuffFrame", UIParent, "BackdropTemplate")
    win:SetSize(SLOT_W * 3 + 20, 140)
    local p = type(GuildPrideDB) == "table" and GuildPrideDB.buffWinPos
    if type(p) == "table" and p.point then win:SetPoint(p.point, UIParent, p.point, p.x or 0, p.y or 0)
    else win:SetPoint("CENTER", UIParent, "CENTER", 0, 120) end
    if ns.SkinDialog then ns.SkinDialog(win) end   -- Goldrahmen wie das Gildenfenster
    win:SetFrameStrata("DIALOG")
    win:SetClampedToScreen(true)
    win:SetMovable(true); win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function() win:StopMovingOrSizing(); SavePos(win) end)
    win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    win.title:SetPoint("TOPLEFT", 14, -12); win.title:SetText(L["GuildPride – Buffs"])
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetSize(22, 22); close:SetPoint("TOPRIGHT", -4, -6)
    if ns.SkinClose then ns.SkinClose(close) end
    close:SetScript("OnClick", function() Buffs.Close() end)
    function Buffs.Close()
        local now = GetTime()
        manual = false
        -- Vorwarnung weggeklickt: Ruhe, bis „Satt“ wirklich ausgelaufen ist
        if slots.food:IsShown() then snoozeFood = now + (warnLeft and warnLeft + 2 or SNOOZE) end
        if slots.bag:IsShown() then snoozeBag = now + SNOOZE end
        if slots.fire:IsShown() then snoozeFire = now + SNOOZE end
        win:Hide()
        Check()
    end
    -- Zahnrad: Erinnerungen direkt hier abschalten (dieselben Schalter wie in den Einstellungen)
    local gear = CreateFrame("Button", nil, win)
    gear:SetSize(16, 16); gear:SetPoint("RIGHT", close, "LEFT", -2, 0)
    gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    gear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    gear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(L["Erinnerungen abschalten"]); GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", GameTooltip_Hide)
    local menu = CreateFrame("Frame", nil, win, "BackdropTemplate")
    menu:SetPoint("TOPRIGHT", win, "BOTTOMRIGHT", 0, -2); menu:SetSize(250, 116)
    if ns.SkinDialog then ns.SkinDialog(menu) end
    menu:SetFrameStrata("DIALOG"); menu:SetFrameLevel(win:GetFrameLevel() + 10)
    menu:EnableMouse(true); menu:Hide()
    -- quiet: Schalter, der nichts abschaltet (nur einschränkt) – ohne Hinweis im Chat
    local function Toggle(y, key, text, quiet)
        local cb = CreateFrame("CheckButton", nil, menu, "UICheckButtonTemplate")
        cb:SetSize(22, 22); cb:SetPoint("TOPLEFT", 8, y)
        local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", cb, "RIGHT", 2, 0); fs:SetText(text)
        cb:SetScript("OnShow", function(self)
            self:SetChecked(quiet and GuildPrideDB[key] == true or (not quiet and Opt(key)))
        end)
        cb:SetScript("OnClick", function(self)
            if type(GuildPrideDB) ~= "table" then return end
            GuildPrideDB[key] = self:GetChecked() and true or false
            if not quiet and not GuildPrideDB[key] then
                ns.Print(L["Abgeschaltet – wieder an in den Einstellungen oder über das Zahnrad (/gp buff)."])
            end
            Check()
        end)
    end
    Toggle(-8, "buffFood", L["Buff-Food-Erinnerung"])
    Toggle(-34, "buffFoodGroupOnly", L["… nur in Instanzen und Gruppen"], true)
    Toggle(-60, "buffFoodReady", L["… beim Bereitschaftscheck"])
    Toggle(-86, "restReminder", L["Schlafsack-/Lagerfeuer-Erinnerung"])
    gear:SetScript("OnClick", function() menu:SetShown(not menu:IsShown()) end)
    win:HookScript("OnHide", function() menu:Hide() end)
    slots = { food = MakeSlot(1, L["Buff-Food"]), bag = MakeSlot(2, L["Schlafsack"]), fire = MakeSlot(3, L["Lagerfeuer"]) }
    -- Der Knopf hört auf Drücken und Loslassen, benutzt wird nur bei einem von
    -- beiden (Spiel-Einstellung „Aktion beim Drücken“). Erst danach umbauen,
    -- sonst ist der Knopf beim Loslassen schon weg und nichts wird benutzt.
    local function Hook(b, kind)
        b:HookScript("PostClick", function(self, _, down)
            local onDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown") or false
            if self.choice and (down and true or false) == onDown then Clicked(kind) end
        end)
    end
    Hook(slots.food, "food"); Hook(slots.bag, "bag"); Hook(slots.fire, "fire")
    win:Hide()
end

-- Kein Buff-Food in den Taschen: was kannst du kochen, was haben deine Twinks?
-- → Text unter dem Symbol, Tooltip-Text
local function FoodMissing()
    local class = select(2, UnitClass("player"))
    local status = L["keins dabei"]
    local why = { L["Kein Buff-Food in deinen Taschen – kauf oder koch dir welches."] }
    local cook = Buffs.BestCookable(class, UnitLevel("player"))
    if cook then
        status = (L["kochbar (%d×)"]):format(cook.n)
        why[#why + 1] = (L["Du kannst %s %d-mal kochen (Kochkunst öffnen)."]):format(
            ItemInfo(cook.id) or ("item:" .. cook.id), cook.n)
    end
    local alts = Buffs.AltFood(class)
    if #alts > 0 then
        if not cook then status = L["bei Twinks"] end
        why[#why + 1] = L["Bei deinen Twinks:"]
        for i = 1, math.min(3, #alts) do
            local a = alts[i]
            why[#why + 1] = ("%s: %d× %s"):format(a.name, a.n, ItemInfo(a.id) or ("item:" .. a.id))
        end
    end
    return status, table.concat(why, "\n")
end

-- Symbole füllen und nebeneinander setzen; ohne Symbol zu.
-- fedLeft: „Satt“ läuft noch, aber bald aus (Vorwarnung)
local function Show(needFood, needBag, needFire, fedLeft)
    if InCombatLockdown() then return end
    local order = {}
    if needFood then
        local best = BuffFoodInBags()[1]
        if best then
            local status = best.note ~= "" and best.note or L["bereit"]
            if fedLeft then status = (L["Satt noch %d Min."]):format(math.max(1, math.ceil(fedLeft / 60))) end
            SetSlot(slots.food, best, ICON_FOOD, status)
        else
            SetSlot(slots.food, nil, ICON_FOOD, FoodMissing())
        end
        order[#order + 1] = slots.food
    end
    if needBag then
        local bagIcon = ItemIcon(Buffs.BAG_ITEM) or ICON_BAG
        if ItemCount(Buffs.BAG_ITEM) <= 0 then
            SetSlot(slots.bag, nil, bagIcon, L["nicht dabei"], L["Du hast den Gemütlichen Schlafsack nicht in den Taschen."])
        elseif BagLeft() > 0 then
            SetSlot(slots.bag, nil, bagIcon, (L["noch %d Min."]):format(math.ceil(BagLeft() / 60)),
                L["Der Schlafsack hat noch Abklingzeit."])
        else
            local name = ItemInfo(Buffs.BAG_ITEM)
            SetSlot(slots.bag, { kind = "item", id = Buffs.BAG_ITEM, name = name, icon = bagIcon, place = true },
                bagIcon, L["ausrollen"])
        end
        order[#order + 1] = slots.bag
    end
    if needFire then
        local fire
        for _, c in ipairs(RestChoices()) do if c.id ~= Buffs.BAG_ITEM then fire = c end end
        if fire then SetSlot(slots.fire, fire, ICON_FIRE, fire.kind == "item" and L["aufstellen"] or L["anzünden"])
        else SetSlot(slots.fire, nil, ICON_FIRE, L["keins dabei"],
            L["Kein Lagerfeuer-Bausatz dabei und kein Lagerfeuer zum Anzünden – setz dich an ein Lagerfeuer."]) end
        order[#order + 1] = slots.fire
    end
    for _, b in pairs(slots) do b:Hide(); b.label:Hide(); b.status:Hide() end
    if #order == 0 then win:Hide(); return end
    for i, b in ipairs(order) do
        b:ClearAllPoints()
        b:SetPoint("TOP", win, "TOPLEFT", 10 + (i - 0.5) * SLOT_W, -36)
        b:Show(); b.label:Show(); b.status:Show()
    end
    win:SetSize(math.max(SLOT_W * #order + 20, 180), 36 + ICON + 52)
    win:Show()
end

---------------------------------------------------------------------
-- Ablauf: fehlt der Buff (auch schon beim Einloggen), kommt das Fenster.
-- X: 30 Min. Ruhe, oder bis der Buff wieder da war.
---------------------------------------------------------------------
local function Blocked()
    return InCombatLockdown() or UnitIsDeadOrGhost("player") or (UnitOnTaxi and UnitOnTaxi("player"))
end

Check = function()
    if not win or InCombatLockdown() then return end
    local fed, rest, rested, fedLeft = ReadAuras()
    if fed == nil then return end
    local now = GetTime()
    local needFood = Buffs.NeedFood(fed, fedLeft)
    warnLeft = fed and needFood and fedLeft or nil
    -- frisch satt: X-Ruhe vorbei (nicht während der Vorwarnung, sonst käme sie gleich wieder)
    if fed and not needFood then snoozeFood = 0 end
    if rested then snoozeBag = 0 end
    if rest then snoozeFire = 0 end
    if Blocked() then manual = false; win:Hide(); return end
    -- von Hand geöffnet: nur auffrischen (z. B. neues Essen in den Taschen), nicht schließen
    if manual and win:IsShown() then
        Show(true, not rested, not rest, fed and fedLeft or nil)
        return
    end
    manual = false
    local resting = Opt("restReminder") and Leveling()
    -- Schlafsack weg, sobald „Gut erholt“ aktiv ist; Lagerfeuer weg bei „Lagervorteile“
    Show(needFood and Opt("buffFood") and Buffs.FoodHere() and now >= snoozeFood,
         not rested and resting and now >= snoozeBag,
         not rest and resting and now >= snoozeFire, warnLeft)
end
Buffs.Check = function() Check() end

-- Von Hand öffnen (/gp buff, /gp rast)
function Buffs.Open(kind)
    Build()
    if InCombatLockdown() then ns.Print(L["Im Kampf nicht möglich."]); return end
    local fed, rest, rested, fedLeft = ReadAuras()
    manual = true
    Show(true, not rested, not rest, fed and fedLeft or nil)
end
Buffs.Window = function() return win end

-- Bereitschaftscheck: Hinweis im Chat und das Essen-Fenster (auch wenn X Ruhe gegeben hat)
local function OnReadyCheck()
    if not win or InCombatLockdown() or not Buffs.ReadyCheckNeedsFood() then return end
    ns.Print(L["Bereitschaftscheck: „Satt“ fehlt oder läuft bald aus – iss noch etwas!"])
    local fed, _, _, fedLeft = ReadAuras()
    warnLeft = fed and fedLeft or nil
    manual = true
    Show(true, false, false, warnLeft)
end

-- /gp rast info: warum (k)ein Fenster aufgeht
function Buffs.Info()
    local fed, rest, rested = ReadAuras()
    local function yn(v) return v == nil and "?" or (v and L["ja"] or L["nein"]) end
    local max = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or MAX_PLAYER_LEVEL or 60
    ns.Print((L["Satt: %s · Lagervorteile: %s · Stufe %d/%d · Schalter Essen %s, Erholung %s"]):format(
        yn(fed), yn(rest), UnitLevel("player") or 0, max, yn(Opt("buffFood")), yn(Opt("restReminder"))))
    ns.Print((L["Schlafsack: %d dabei, bereit: %s · Gut erholt: %s"]):format(ItemCount(Buffs.BAG_ITEM),
        yn(ItemReady(Buffs.BAG_ITEM)), yn(rested)))
    for _, c in ipairs(Buffs.CAMPFIRES) do
        if c.item then
            ns.Print((L["Lagerfeuer %s (%d): %d dabei"]):format(ItemInfo(c.item) or "?", c.item, ItemCount(c.item)))
        else
            ns.Print((L["Lagerfeuer-Zauber %s: bekannt %s, benutzbar %s"]):format(SpellName(c.spell) or "?",
                yn(SpellKnown(c.spell)), yn(SpellUsable(c.spell))))
        end
    end
    local list = RestChoices()
    ns.Print((L["Im Erholungs-Fenster: %d Knopf/Knöpfe"]):format(#list))
end

local pending = false
local function Soon()
    if pending or not C_Timer then return end
    pending = true
    C_Timer.After(0.5, function() pending = false; Check() end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        Build()
        ev:RegisterEvent("UNIT_AURA")
        ev:RegisterEvent("PLAYER_REGEN_DISABLED")
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
        ev:RegisterEvent("BAG_UPDATE_DELAYED")
        ev:RegisterEvent("BAG_UPDATE_COOLDOWN")
        ev:RegisterEvent("PLAYER_UNGHOST")
        ev:RegisterEvent("PLAYER_CONTROL_GAINED")
        ev:RegisterEvent("READY_CHECK")
        ev:RegisterEvent("GROUP_ROSTER_UPDATE")      -- Schalter „nur in Gruppen“
        ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")    -- Schalter „nur in Instanzen“
        if C_Timer then
            C_Timer.After(5, Check)
            -- Abklingzeiten (Schlafsack) enden ohne Ereignis: jede Minute nachsehen
            if C_Timer.NewTicker then C_Timer.NewTicker(60, function() Check() end) end
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Kampfbeginn kommt vor der Kampfsperre: jetzt noch zumachen
        manual = false
        if win then win:Hide() end
    elseif event == "READY_CHECK" then
        OnReadyCheck()
    elseif event == "UNIT_AURA" then
        if arg1 == "player" then Soon() end
    elseif event == "BAG_UPDATE_DELAYED" then
        wipe(foodCache)
        Soon()
    else
        Soon()
    end
end)

-- /gp buff · /gp rast
local origSlash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd = strtrim(arg or ""):lower()
    if cmd == "buff" or cmd == "food" or cmd == "essen" then Buffs.Open("food")
    elseif cmd == "rast info" or cmd == "rest info" then Buffs.Info()
    elseif cmd == "rast" or cmd == "rest" or cmd == "lagerfeuer" or cmd == "schlafsack" then Buffs.Open("rest")
    elseif origSlash then origSlash(arg) end
end
