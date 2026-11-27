-- GuildPride: Vorrat, Taschenplatz und Reparatur
-- * Vorrat (supplyWarn): Reagenzien und Munition deiner Klasse. Beim Händler steht im
--   Chat, was knapp ist (und ob dieser Händler es hat); geht etwas zur Neige, kommt
--   höchstens einmal pro Stunde ein Hinweis.
-- * Taschen (bagWarn): Sind nur noch wenige Plätze frei, kommt einmal ein Hinweis mit
--   Vorschlägen, was du am ehesten verkaufen kannst (Graues zuerst, dann das Billigste).
-- * Reparatur (autoRepair, ab Werk aus): beim Händler automatisch reparieren, auf Wunsch
--   aus der Gildenbank (autoRepairGuild), wenn dein Rang das darf.
-- Kein eigenes Händler-Fenster und kein Knopf: alles über den Chat.
local ADDON, ns = ...
local L = ns.L

local S = {}
ns.Supplies = S

local function Opt(key) return type(GuildPrideDB) == "table" and GuildPrideDB[key] ~= false end
local function On(key) return type(GuildPrideDB) == "table" and GuildPrideDB[key] == true end

---------------------------------------------------------------------
-- Vorrat: { Klasse, Zauber (einer davon bekannt), Gegenstand, Mindestmenge, Gruppe }
-- Gruppe: Ränge eines Zaubers – nur der höchste bekannte zählt.
---------------------------------------------------------------------
local TELEPORTS = { 3561, 3562, 3563, 3565, 3566, 3567 }
local PORTALS = { 10059, 11416, 11417, 11418, 11419, 11420 }
S.RULES = {
    { class = "MAGE", spells = TELEPORTS, item = 17031, min = 5 },        -- Rune der Teleportation
    { class = "MAGE", spells = PORTALS, item = 17032, min = 3 },          -- Rune der Portale
    { class = "MAGE", spells = { 23028 }, item = 17020, min = 10 },       -- Arkanes Pulver (Arkane Brillanz)
    { class = "MAGE", spells = { 130 }, item = 17056, min = 5 },          -- Leichte Feder (Langsamer Fall)
    { class = "PRIEST", spells = { 1706 }, item = 17056, min = 5 },       -- Leichte Feder (Levitieren)
    { class = "PRIEST", spells = { 21562 }, item = 17028, min = 5, group = "pof" },   -- Heilige Kerze
    { class = "PRIEST", spells = { 21564 }, item = 17029, min = 5, group = "pof" },   -- Geweihte Kerze
    { class = "DRUID", spells = { 21849 }, item = 17021, min = 5, group = "gotw" },   -- Wildbeeren
    { class = "DRUID", spells = { 21850 }, item = 17026, min = 5, group = "gotw" },   -- Wilder Dornwurz
    { class = "DRUID", spells = { 20484 }, item = 17034, min = 2, group = "rebirth" },
    { class = "DRUID", spells = { 20739 }, item = 17035, min = 2, group = "rebirth" },
    { class = "DRUID", spells = { 20742 }, item = 17036, min = 2, group = "rebirth" },
    { class = "DRUID", spells = { 20747 }, item = 17037, min = 2, group = "rebirth" },
    { class = "DRUID", spells = { 20748 }, item = 17038, min = 2, group = "rebirth" },
    { class = "PALADIN", spells = { 25898 }, item = 21177, min = 10 },    -- Symbol der Könige
    { class = "PALADIN", spells = { 19752 }, item = 17033, min = 1 },     -- Symbol der Göttlichkeit
    { class = "SHAMAN", spells = { 20608 }, item = 17030, min = 1 },      -- Ankh (Reinkarnation)
    { class = "WARLOCK", item = 6265, min = 3 },                          -- Seelensplitter
    { class = "ROGUE", spells = { 1856 }, item = 5140, min = 3 },         -- Blitzstrahlpulver (Verschwinden)
    { class = "ROGUE", spells = { 2094 }, item = 5530, min = 3 },         -- Blendungspulver (Blenden)
    { class = "HUNTER", ammo = true, min = 200 },                         -- Munition im Munitionsplatz
}

-- Was ist knapp? known(spell) → bool, count(item) → Anzahl, ammo = Munition im Platz (nil: keine)
-- → { { item, have, min } | { ammo = true, have, min } }
function S.Needs(class, known, count, ammo)
    local out, best = {}, {}
    local function Knows(r)
        if not r.spells then return true end
        for _, sp in ipairs(r.spells) do if known(sp) then return true end end
        return false
    end
    for _, r in ipairs(S.RULES) do
        if r.class == class and r.group and Knows(r) then best[r.group] = r end   -- später = höherer Rang
    end
    for _, r in ipairs(S.RULES) do
        if r.class == class and (not r.group or best[r.group] == r) then
            if r.ammo then
                if ammo and ammo < r.min then out[#out + 1] = { ammo = true, have = ammo, min = r.min } end
            elseif Knows(r) then
                local have = count(r.item) or 0
                if have < r.min then out[#out + 1] = { item = r.item, have = have, min = r.min } end
            end
        end
    end
    return out
end

---------------------------------------------------------------------
-- Taschen
---------------------------------------------------------------------
S.BAG_LOW = 3
-- Warnen? Nur beim Unterschreiten (last = freie Plätze beim letzten Blick, nil = erster Blick)
function S.BagCheck(free, last)
    return free <= S.BAG_LOW and (last == nil or last > S.BAG_LOW)
end

-- Vorschläge: Graues zuerst (billigstes zuerst), dann alles mit Händlerpreis, billigstes zuerst.
-- Dinge ohne Händlerpreis (Quest, Ruhestein …) nie.
function S.Suggest(items, max)
    local list = {}
    for _, it in ipairs(items) do
        if (it.price or 0) > 0 then list[#list + 1] = it end
    end
    table.sort(list, function(a, b)
        local ga, gb = a.quality == 0, b.quality == 0
        if ga ~= gb then return ga end
        local va, vb = a.price * (a.count or 1), b.price * (b.count or 1)
        if va ~= vb then return va < vb end
        return a.id < b.id
    end)
    local out = {}
    for i = 1, math.min(max or 3, #list) do out[i] = list[i] end
    return out
end

---------------------------------------------------------------------
-- Reparatur → "guild", "own", "poor" (zu wenig Gold) oder nil (nichts zu tun)
---------------------------------------------------------------------
function S.RepairChoice(cost, money, guildOK, wantGuild)
    if not cost or cost <= 0 then return nil end
    if wantGuild and guildOK then return "guild" end
    if money >= cost then return "own" end
    return "poor"
end

---------------------------------------------------------------------
-- Spiel
---------------------------------------------------------------------
local Secret = ns.IsSecret
local function Money(c) return ns.AH and ns.AH.Money and ns.AH.Money(c) or (("%dg"):format(math.floor(c / 10000))) end
local function ItemName(id)
    local f = C_Item and C_Item.GetItemNameByID
    local n = f and f(id)
    if not n and C_Item and C_Item.GetItemInfo then n = C_Item.GetItemInfo(id) end
    return n or ("item:" .. id)
end
local function Count(id)
    local f = C_Item and C_Item.GetItemCount
    return f and (f(id) or 0) or 0
end
local function Known(spell)
    if IsPlayerSpell then local ok, r = pcall(IsPlayerSpell, spell); if ok and r then return true end end
    if IsSpellKnown then local ok, r = pcall(IsSpellKnown, spell); if ok and r then return true end end
    return false
end
local function Ammo()
    if not GetInventoryItemID then return nil end
    local slot = (INVSLOT_AMMO or 0)
    local id = GetInventoryItemID("player", slot)
    if not id or Secret(id) then return nil end
    local n = GetInventoryItemCount and GetInventoryItemCount("player", slot) or 0
    if Secret(n) then return nil end
    return n
end
local function MyNeeds()
    local class = select(2, UnitClass("player"))
    return S.Needs(class, Known, Count, Ammo())
end
local function NeedText(n)
    local name = n.ammo and L["Munition"] or ItemName(n.item)
    return ("%s %d/%d"):format(name, n.have, n.min)
end

-- Was verkauft der offene Händler? { [itemID] = true }
local function MerchantItems()
    local out = {}
    local num = GetMerchantNumItems and GetMerchantNumItems() or 0
    for i = 1, num do
        local id = GetMerchantItemID and GetMerchantItemID(i)
        if id then out[id] = true end
    end
    return out
end

local function AtMerchant()
    local list = MyNeeds()
    if #list == 0 then return end
    local sells, parts, here = MerchantItems(), {}, {}
    for _, n in ipairs(list) do
        parts[#parts + 1] = NeedText(n)
        if n.item and sells[n.item] then here[#here + 1] = ItemName(n.item) end
    end
    local text = L["Vorrat knapp: "] .. table.concat(parts, " · ")
    if #here > 0 then text = text .. " – " .. (L["dieser Händler hat: %s"]):format(table.concat(here, ", ")) end
    ns.Print(text)
end

-- Unterwegs: neu knapp gewordenes höchstens einmal pro Stunde melden
local warnedAt = {}
local function CheckSupplies()
    if not Opt("supplyWarn") or InCombatLockdown() then return end
    local now = GetTime()
    for _, n in ipairs(MyNeeds()) do
        local key = n.ammo and "ammo" or n.item
        if now - (warnedAt[key] or -math.huge) > 3600 then
            warnedAt[key] = now
            ns.Print(L["Vorrat knapp: "] .. NeedText(n))
        end
    end
end

-- Taschen
local lastFree
local function BagItems()
    local out, C = {}, C_Container
    if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then return out end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C.GetContainerNumSlots(bag) or 0 do
            local info = C.GetContainerItemInfo(bag, slot)
            if type(info) == "table" and info.itemID then
                local price = 0
                if C_Item and C_Item.GetItemInfo then price = select(11, C_Item.GetItemInfo(info.itemID)) or 0 end
                out[#out + 1] = { id = info.itemID, name = ItemName(info.itemID), quality = info.quality or 1,
                                  price = price, count = info.stackCount or 1 }
            end
        end
    end
    return out
end
local function FreeSlots()
    local C, free = C_Container, 0
    if not (C and C.GetContainerNumFreeSlots) then return nil end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local n, family = C.GetContainerNumFreeSlots(bag)
        if (family or 0) == 0 then free = free + (n or 0) end   -- nur normale Taschen (keine Köcher, Seelentaschen …)
    end
    return free
end
local function CheckBags()
    if not Opt("bagWarn") then return end
    local free = FreeSlots()
    if not free then return end
    if S.BagCheck(free, lastFree) then
        local names = {}
        for _, it in ipairs(S.Suggest(BagItems())) do names[#names + 1] = it.name end
        local text = (L["Nur noch %d Taschenplätze frei."]):format(free)
        if #names > 0 then text = text .. " " .. (L["Am ehesten verzichtbar: %s"]):format(table.concat(names, ", ")) end
        ns.Print(text)
    end
    lastFree = free
end

-- Reparatur
local function Repair()
    if not On("autoRepair") or not (CanMerchantRepair and CanMerchantRepair()) then return end
    local cost = GetRepairAllCost and GetRepairAllCost()
    if Secret(cost) then return end
    local guildOK = CanGuildBankRepair and CanGuildBankRepair() or false
    local choice = S.RepairChoice(cost, GetMoney and GetMoney() or 0, guildOK, On("autoRepairGuild"))
    if not choice then return end
    if choice == "poor" then ns.Print((L["Reparatur: %s nötig, so viel Gold hast du nicht."]):format(Money(cost))); return end
    local ok = pcall(RepairAllItems, choice == "guild")
    if ok then
        ns.Print((choice == "guild" and L["Repariert für %s (aus der Gildenbank)."] or L["Repariert für %s."]):format(Money(cost)))
    end
end

local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "MERCHANT_SHOW", "BAG_UPDATE_DELAYED", "PLAYER_LOGIN", "UNIT_INVENTORY_CHANGED")
ev:SetScript("OnEvent", function(_, event, unit)
    if event == "MERCHANT_SHOW" then
        ns.Try(Repair)
        if Opt("supplyWarn") then ns.Try(AtMerchant) end
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if unit == "player" then ns.Debounce("supplies", 3, function() ns.Try(CheckSupplies) end) end
    elseif event == "PLAYER_LOGIN" then
        C_Timer.After(20, function() ns.Try(CheckSupplies); ns.Try(CheckBags) end)
    else
        ns.Debounce("supplies", 3, function() ns.Try(CheckSupplies) end)
        ns.Debounce("bags", 1, function() ns.Try(CheckBags) end)
    end
end)
