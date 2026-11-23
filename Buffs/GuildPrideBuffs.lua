-- GuildPride: Buff-Food- und Erholungs-Erinnerung
-- * Buff-Food (buffFood): läuft „Satt“ (Well Fed) aus, öffnet sich ein kleines
--   Fenster mit dem Buff-Food aus deinen Taschen – das beste für deine Klasse
--   steht vorne. Ein Klick isst es, das Fenster verschwindet.
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
local WELL_FED_ICON = 136000        -- Spell_Misc_Food
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
            -- nur die „Benutzen:“-Zeile; „satt“ als ganzes Wort (nicht „Sattel“)
            if low:find("use:", 1, true) or low:find("benutzen:", 1, true) then
                e = select(2, low:find("well fed", 1, true))
                if not e then
                    -- danach kein Buchstabe: \195 beginnt ä/ö/ü/ß, Anführungszeichen („Satt“) sind erlaubt
                    local s = low:find("satt[^%a\195]")
                    e = s and s + 3
                end
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
local function Secret(v) return issecretvalue and issecretvalue(v) or false end
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
    local name, _, _, _, minLevel, _, _, _, _, icon = f(id)
    return name, minLevel, icon
end
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
local function TooltipLines(bag, slot)
    local out = {}
    if C_TooltipInfo and C_TooltipInfo.GetBagItem then
        local data = C_TooltipInfo.GetBagItem(bag, slot)
        for _, line in ipairs(data and data.lines or {}) do
            if type(line.leftText) == "string" and not Secret(line.leftText) then out[#out + 1] = line.leftText end
        end
        return out
    end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "GuildPrideBuffScanTip", nil, "GameTooltipTemplate")
        scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    scanTip:ClearLines()
    scanTip:SetBagItem(bag, slot)
    for i = 1, scanTip:NumLines() do
        local fs = _G["GuildPrideBuffScanTipTextLeft" .. i]
        local t = fs and fs:GetText()
        if type(t) == "string" and not Secret(t) then out[#out + 1] = t end
    end
    return out
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
                local name, minLevel, icon = ItemInfo(id)
                if stats and name and (minLevel or 0) <= level and ItemReady(id) then
                    list[#list + 1] = { kind = "item", id = id, name = name, icon = icon, count = ItemCount(id),
                                        score = Buffs.Score(stats, class), note = Buffs.StatText(stats) }
                end
            end
        end
    end
    return Buffs.Sort(list)
end
Buffs.FoodInBags = BuffFoodInBags

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
-- Geheime Werte im Kampf -> nil = unbekannt
local function ReadAuras()
    local fedName, restName = SpellName(WELL_FED_SPELL), SpellName(Buffs.REST_SPELL)
    local bagName, bagSpell = BagSpell()
    local fed, rest, rested = false, false, false
    local function Check(name, icon, spellId)
        if Secret(name) or Secret(spellId) or Secret(icon) then error("secret") end
        if spellId == Buffs.REST_SPELL or Buffs.FIRE_BUFF_NAMES[name] or (restName and name == restName) then
            rest = true
        end
        if Buffs.BAG_BUFF_NAMES[name] or (bagSpell and spellId == bagSpell) or (bagName and name == bagName) then
            rested = true
        end
        if (fedName and name == fedName) or name == "Well Fed" or name == "Satt" or icon == WELL_FED_ICON then fed = true end
    end
    local ok = pcall(function()
        for i = 1, 40 do
            if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
                local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
                if not a then break end
                Check(a.name, a.icon, a.spellId)
            elseif UnitBuff then
                local name, icon, _, _, _, _, _, _, _, spellId = UnitBuff("player", i)
                if not name then break end
                Check(name, icon, spellId)
            else
                break
            end
        end
    end)
    if not ok then return nil, nil, nil end
    return fed, rest, rested
end
Buffs.ReadAuras = ReadAuras

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
    close:SetScript("OnClick", function()
        local now = GetTime()
        if slots.food:IsShown() then snoozeFood = now + SNOOZE end
        if slots.bag:IsShown() then snoozeBag = now + SNOOZE end
        if slots.fire:IsShown() then snoozeFire = now + SNOOZE end
        Check()
    end)
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

-- Symbole füllen und nebeneinander setzen; ohne Symbol zu
local function Show(needFood, needBag, needFire)
    if InCombatLockdown() then return end
    local order = {}
    if needFood then
        local best = BuffFoodInBags()[1]
        if best then SetSlot(slots.food, best, ICON_FOOD, best.note ~= "" and best.note or L["bereit"])
        else SetSlot(slots.food, nil, ICON_FOOD, L["keins dabei"],
            L["Kein Buff-Food in deinen Taschen – kauf oder koch dir welches."]) end
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
    local fed, rest, rested = ReadAuras()
    if fed == nil then return end
    local now = GetTime()
    if fed then snoozeFood = 0 end
    if rested then snoozeBag = 0 end
    if rest then snoozeFire = 0 end
    if Blocked() then win:Hide(); return end
    local resting = Opt("restReminder") and Leveling()
    -- Schlafsack weg, sobald „Gut erholt“ aktiv ist; Lagerfeuer weg bei „Lagervorteile“
    Show(not fed and Opt("buffFood") and now >= snoozeFood,
         not rested and resting and now >= snoozeBag,
         not rest and resting and now >= snoozeFire)
end
Buffs.Check = function() Check() end

-- Von Hand öffnen (/gp buff, /gp rast)
function Buffs.Open(kind)
    Build()
    if InCombatLockdown() then ns.Print(L["Im Kampf nicht möglich."]); return end
    local _, rest, rested = ReadAuras()
    Show(true, not rested, not rest)
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
        if C_Timer then
            C_Timer.After(5, Check)
            -- Abklingzeiten (Schlafsack) enden ohne Ereignis: jede Minute nachsehen
            if C_Timer.NewTicker then C_Timer.NewTicker(60, function() Check() end) end
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Kampfbeginn kommt vor der Kampfsperre: jetzt noch zumachen
        if win then win:Hide() end
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
