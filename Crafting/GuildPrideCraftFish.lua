-- GuildPride Handwerk: Angel-Helfer
-- Mit Angel in der Hand erscheint eine kleine Leiste: „Auswerfen“, „Köder“ (bester Köder aus
-- den Taschen), Angel-Fertigkeit, ob ein Köder drauf ist, und der Fang dieser Sitzung mit Wert.
-- Gezählt wird auch insgesamt: GuildPrideDB.craftFish = { total = { [itemID] = n }, casts }
-- Sichere Knöpfe (SecureActionButton): ein-/ausblenden nur außerhalb des Kampfes.
-- Schalter: craftFish
local ADDON, ns = ...
local L = ns.L
local Craft = ns.Craft

local F = {}
ns.CraftFish = F

local FISHING = 7620
-- Köder, bester zuerst: { itemID, Bonus }
F.LURES = { { 6533, 100 }, { 7307, 75 }, { 6532, 75 }, { 6811, 50 }, { 6530, 50 }, { 6529, 25 } }

local function Opt() return not (type(GuildPrideDB) == "table" and GuildPrideDB.craftFish == false) end
local function Stats()
    if type(GuildPrideDB) ~= "table" then return { total = {} } end
    GuildPrideDB.craftFish = type(GuildPrideDB.craftFish) == "table" and GuildPrideDB.craftFish or {}
    local s = GuildPrideDB.craftFish
    s.total = type(s.total) == "table" and s.total or {}
    return s
end
F.Stats = Stats
F.session = {}

-- Angel in der Waffenhand?
function F.HasPole()
    local id = GetInventoryItemID and GetInventoryItemID("player", 16)
    if not id then return false end
    local f = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if not f then return false end
    local _, _, _, _, _, classID, subID = f(id)
    return classID == 2 and subID == 20
end

function F.BestLure()
    for _, l in ipairs(F.LURES) do
        if Craft.Count(l[1]) > 0 then return l[1], l[2] end
    end
end

function F.HasLure()
    if not GetWeaponEnchantInfo then return nil end
    local has = GetWeaponEnchantInfo()
    return has and true or false
end

-- Was ein Stück Fang dir bringt: Händler-Verkaufspreis oder AH-Preis nach 5 % Gebühr, je nachdem was mehr ist
function F.ItemValue(id)
    local best = 0
    if GetItemInfo then
        local sell = select(11, GetItemInfo(id))
        best = tonumber(sell) or 0
    end
    local AH = ns.AH
    local ah = AH and AH.PriceFor and AH.Key and tonumber((AH.PriceFor(AH.Key(id))))
    if ah and ah * 0.95 > best then best = ah * 0.95 end
    return math.floor(best + 0.5)
end

-- Wert des Fangs dieser Sitzung
function F.SessionValue()
    local sum, n = 0, 0
    for id, k in pairs(F.session) do
        n = n + k
        sum = sum + F.ItemValue(id) * k
    end
    return sum, n
end

-- „Ihr erhaltet Beute: [X]x3.“ → itemID, Anzahl (nur eigene Beute; Muster aus den Spieltexten)
local function LootPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    fmt = fmt:gsub("%%%d%$", "%%")                          -- %1$s → %s
    fmt = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")    -- Sonderzeichen schützen
    fmt = fmt:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    return "^" .. fmt
end

function F.ParseLoot(msg)
    if type(msg) ~= "string" then return nil end
    for _, fmt in ipairs({ LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF_MULTIPLE, LOOT_ITEM_SELF, LOOT_ITEM_PUSHED_SELF }) do
        local pat = LootPattern(fmt)
        if pat then
            local link, qty = msg:match(pat)
            local id = link and tonumber(link:match("item:(%d+)"))
            if id then return id, tonumber(qty) or 1 end
        end
    end
    return nil
end

-- Kam die Beute gerade vom Angeln? (während der Angel draußen ist bzw. kurz danach)
F.fishUntil = 0
function F.FromFishing()
    return GetTime() <= F.fishUntil
end

function F.Record(id, count)
    count = count or 1
    F.session[id] = (F.session[id] or 0) + count
    local s = Stats()
    s.total[id] = (s.total[id] or 0) + count
end

-- Zaubername „Angeln“: aus deinem Beruf (sicher in deiner Sprache), sonst über die Zauber-ID
function F.SpellName()
    local _, _, name = Craft.Skill(356)
    if type(name) == "string" and name ~= "" then return name end
    local n = Craft.RecipeName(FISHING)
    if n and not n:find("^#") then return n end
    return ns.IS_GERMAN and "Angeln" or "Fishing"
end

---------------------------------------------------------------------
-- Eine Taste für alles: auswerfen und (während die Angel draußen ist) den Schwimmer einholen.
-- Gilt nur, solange die Angel in der Hand ist und kein Kampf läuft (Override-Binding),
-- danach hat die Taste wieder ihre normale Belegung. Einholen läuft über „Mit Ziel
-- interagieren“ (Soft-Target auf den Schwimmer) – dafür setzen wir die Soft-Interact-CVars
-- beim Angeln und stellen die alten Werte danach wieder her.
---------------------------------------------------------------------
F.FISHING_SPELLS = { [7620] = true, [7731] = true, [7732] = true, [18248] = true }
local MODS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true, UNKNOWN = true }
local MOUSE = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

-- Taste/Maustaste in Binding-Schreibweise („ALT-CTRL-SHIFT-F“); nil = nicht erlaubt,
-- false = abbrechen (Esc). Linke/rechte Maustaste sind tabu (sonst ginge nichts mehr).
function F.KeyName(key, shift, ctrl, alt)
    if type(key) ~= "string" or key == "" then return nil end
    if key == "ESCAPE" then return false end
    if MODS[key] or key == "LeftButton" or key == "RightButton" then return nil end
    key = MOUSE[key] or key
    return (alt and "ALT-" or "") .. (ctrl and "CTRL-" or "") .. (shift and "SHIFT-" or "") .. key
end

function F.Key()
    local k = type(GuildPrideDB) == "table" and GuildPrideDB.craftFishKey
    return type(k) == "string" and k ~= "" and k or nil
end

function F.IsFishing(spellID)
    if F.FISHING_SPELLS[spellID] then return true end
    local name = UnitChannelInfo and UnitChannelInfo("player")
    return name ~= nil and name == F.SpellName()
end

-- Soft-Interact für den Schwimmer (Reichweite ~20 m statt 10 m)
local SOFT = { SoftTargetInteract = "3", SoftTargetInteractRange = "30", SoftTargetInteractArc = "2" }
local softSaved
local function GetCV(k) return C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(k) or (GetCVar and GetCVar(k)) end
local function SetCV(k, v)
    if C_CVar and C_CVar.SetCVar then pcall(C_CVar.SetCVar, k, v) elseif SetCVar then pcall(SetCVar, k, v) end
end
function F.SoftOn()
    if softSaved or InCombatLockdown() then return end
    softSaved = {}
    for k, v in pairs(SOFT) do
        local old = GetCV(k)
        if old ~= nil then softSaved[k] = old; SetCV(k, v) end
    end
end
function F.SoftOff()
    if not softSaved or InCombatLockdown() then return end
    for k, v in pairs(softSaved) do SetCV(k, v) end
    softSaved = nil
end

---------------------------------------------------------------------
-- Leiste
---------------------------------------------------------------------
local bar
F.reeling = false

function F.ApplyKey()
    if not bar or InCombatLockdown() then return end
    ClearOverrideBindings(bar)
    local key = F.Key()
    if not (key and bar:IsShown()) then F.SoftOff(); return end
    F.SoftOn()
    if F.reeling then
        SetOverrideBinding(bar, true, key, "INTERACTTARGET")
    else
        SetOverrideBindingClick(bar, true, key, "GuildPrideFishCast", "LeftButton")
    end
end

local function KeyLabel()
    local k = F.Key()
    if not k then return L["Taste wählen"] end
    local short = GetBindingText and GetBindingText(k, "KEY_") or k
    return (L["Taste: %s"]):format(short)
end

local cap
function F.SetKey(key)
    if type(GuildPrideDB) ~= "table" then return end
    GuildPrideDB.craftFishKey = key
    if key then
        local used = GetBindingAction and GetBindingAction(key)
        if used and used ~= "" then
            local nice = GetBindingName and GetBindingName(used) or used
            ns.Print((L["Angel-Taste %s – solange du die Angel trägst, ersetzt sie: %s"]):format(key, nice))
        else
            ns.Print((L["Angel-Taste %s – einmal drücken: auswerfen, nochmal: einholen."]):format(key))
        end
    else
        ns.Print(L["Angel-Taste gelöscht."])
    end
    if bar and bar.key then bar.key:SetText(KeyLabel()) end
    F.ApplyKey()
end

local function Capture()
    if InCombatLockdown() then return end
    if not cap then
        cap = CreateFrame("Button", nil, UIParent)
        cap:SetAllPoints(UIParent)
        cap:SetFrameStrata("FULLSCREEN_DIALOG")
        cap:EnableMouse(true)
        cap:EnableKeyboard(true)
        cap:SetPropagateKeyboardInput(false)   -- einmal beim Erstellen, nie zur Laufzeit umschalten
        local bg = cap:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.45)
        local t = cap:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        t:SetPoint("CENTER"); t:SetText(L["Drück jetzt die Taste oder Maustaste fürs Angeln (Esc = abbrechen)"])
        local function Take(self, key)
            local k = F.KeyName(key, IsShiftKeyDown(), IsControlKeyDown(), IsAltKeyDown())
            if k == nil then return end
            self:Hide()
            if k then F.SetKey(k) end
        end
        cap:SetScript("OnKeyDown", Take)
        cap:SetScript("OnMouseDown", Take)
        cap:Hide()
    end
    cap:Show()
end
F.Capture = Capture

local function Build()
    if bar or InCombatLockdown() then return end
    bar = CreateFrame("Frame", "GuildPrideFishBar", UIParent, "BackdropTemplate")
    bar:SetSize(340, 58)
    bar:SetFrameStrata("MEDIUM")
    bar:SetClampedToScreen(true)
    bar:EnableMouse(true)
    bar:SetMovable(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", bar.StartMoving)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        GuildPrideDB.craftFishPos = { p, rp, x, y }
    end)
    if ns.SkinDialog then ns.SkinDialog(bar) end
    local pos = type(GuildPrideDB) == "table" and GuildPrideDB.craftFishPos
    if type(pos) == "table" then bar:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 180) end

    local cast = CreateFrame("Button", "GuildPrideFishCast", bar, "UIPanelButtonTemplate,SecureActionButtonTemplate")
    cast:SetSize(96, 22); cast:SetPoint("BOTTOMLEFT", 10, 8)
    cast:SetText(L["Auswerfen"])
    -- Neuere Clients lösen sichere Knöpfe nur in der Phase aus, die „Aktion beim Drücken der
    -- Taste“ vorgibt – ohne diese Angabe wurde ein Mausklick (Loslassen) verworfen
    cast:RegisterForClicks("AnyUp", "AnyDown")
    cast:SetAttribute("useOnKeyDown", false)
    cast:SetAttribute("type", "spell")
    cast:SetAttribute("spell", F.SpellName())
    bar.cast = cast

    local lure = CreateFrame("Button", "GuildPrideFishLure", bar, "UIPanelButtonTemplate,SecureActionButtonTemplate")
    lure:SetSize(96, 22); lure:SetPoint("LEFT", cast, "RIGHT", 6, 0)
    lure:SetText(L["Köder"])
    lure:RegisterForClicks("AnyUp", "AnyDown")
    lure:SetAttribute("useOnKeyDown", false)
    lure:SetAttribute("type", "item")
    lure:SetAttribute("target-slot", 16)
    bar.lure = lure

    local key = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    key:SetSize(110, 22); key:SetPoint("LEFT", lure, "RIGHT", 6, 0)
    key:SetText(KeyLabel())
    key:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    key:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then F.SetKey(nil) else Capture() end
    end)
    key:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Eine Taste fürs Angeln"])
        GameTooltip:AddLine(L["Linksklick: Taste oder Maustaste wählen. Damit wirfst du aus – und solange die Angel draußen ist, holst du mit derselben Taste den Schwimmer ein."], 1, 1, 1, true)
        GameTooltip:AddLine(L["Gilt nur mit Angel in der Hand und außerhalb des Kampfes. Rechtsklick: Taste löschen."], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    key:SetScript("OnLeave", GameTooltip_Hide)
    bar.key = key

    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("TOPLEFT", 10, -8); bar.text:SetPoint("RIGHT", -10, 0)
    bar.text:SetJustifyH("LEFT"); bar.text:SetWordWrap(false)
    bar:Hide()
end

function F.Refresh()
    if not bar then return end
    local skill, max = Craft.Skill(356)
    local lure = F.HasLure()
    local value, n = F.SessionValue()
    local money = ns.AH and ns.AH.Money or tostring
    bar.text:SetText(("|cffffd100%s|r %s  ·  %s  ·  %s"):format(L["Angeln"],
        skill and (skill .. "/" .. (max or 0)) or "?",
        lure and ("|cff40ff40" .. L["Köder drauf"] .. "|r") or ("|cffff8040" .. L["kein Köder"] .. "|r"),
        (L["Fang %d (≈ %s)"]):format(n, money(value))))
    if not InCombatLockdown() then
        bar.cast:SetAttribute("spell", F.SpellName())
        local id = F.BestLure()
        bar.lure:SetAttribute("item", id and ("item:" .. id) or nil)
        bar.lure:SetEnabled(id ~= nil)
    end
end

function F.Update()
    if InCombatLockdown() then return end
    local want = Opt() and F.HasPole()
    if want then Build() end
    if bar then bar:SetShown(want); F.Refresh() end
    F.reeling = false
    F.ApplyKey()
end

local stopToken = 0
local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "PLAYER_LOGIN", "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "PLAYER_REGEN_ENABLED",
    "PLAYER_REGEN_DISABLED", "CHAT_MSG_LOOT", "BAG_UPDATE_DELAYED", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP")
ev:SetScript("OnEvent", function(_, event, arg, _, spellID)
    -- Angel-Zeitfenster merken (unabhängig von Leiste und Taste)
    if arg == "player" and event == "UNIT_SPELLCAST_CHANNEL_START" and F.IsFishing(spellID) then
        F.fishUntil = GetTime() + 40
    elseif arg == "player" and event == "UNIT_SPELLCAST_CHANNEL_STOP" and F.fishUntil > GetTime() then
        F.fishUntil = GetTime() + 5
    end
    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        -- Angel ist draußen: dieselbe Taste holt jetzt ein
        if arg == "player" and bar and bar:IsShown() and F.IsFishing(spellID) then
            stopToken = stopToken + 1
            F.reeling = true
            F.ApplyKey()
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        -- kurz warten, damit das Loslassen der Einhol-Taste nicht gleich neu auswirft
        if arg == "player" and F.reeling then
            stopToken = stopToken + 1
            local my = stopToken
            C_Timer.After(0.4, function()
                if my ~= stopToken then return end
                F.reeling = false
                F.ApplyKey()
            end)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- letzte Gelegenheit vor der Kampfsperre: Taste wieder normal belegen
        if bar then ClearOverrideBindings(bar) end
        F.reeling = false
        F.SoftOff()
    elseif event == "CHAT_MSG_LOOT" then
        if F.FromFishing() then
            local id, qty = F.ParseLoot(arg)
            if id then F.Record(id, qty); F.Refresh() end
        end
    elseif event == "UNIT_INVENTORY_CHANGED" and arg ~= "player" then
        return
    elseif event == "BAG_UPDATE_DELAYED" then
        F.Refresh()
    else
        C_Timer.After(0.5, F.Update)
    end
end)
