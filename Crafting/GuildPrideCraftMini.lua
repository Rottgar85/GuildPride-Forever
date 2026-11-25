-- GuildPride Handwerk: Kompaktansicht, Skill-Ups pro Stunde, Abklingzeiten
--   Kompakt (/gp handwerk mini): schmales Fenster, das beim Spielen offen bleiben kann –
--     je Beruf Stufe, nächster Guide-Schritt und wie oft du ihn gerade herstellen kannst,
--     dazu heute gewonnene Punkte (~ pro Stunde), Abklingzeiten und der Tracker.
--   Statistik: GuildPrideDB.craftLog[Charakter] = { day, [Skill-Line] = Punkte heute }
--   Abklingzeiten (Transmutieren, Mondstoff, Salzstreuer) aller Charaktere:
--     craftChars[Name].cd = { [Art] = bereit-ab (Serverzeit) }; Hinweis, sobald eine bereit ist
local ADDON, ns = ...
local L = ns.L
local Craft, G = ns.Craft, ns.CraftGuides

local Mini = {}
ns.CraftMini = Mini

---------------------------------------------------------------------
-- Statistik
---------------------------------------------------------------------
local session = {}   -- [Skill-Line] = { gain, since }
local lastSkill = {}

local function Today() return date and date("%Y-%m-%d") or "?" end
local function Log()
    if type(GuildPrideDB) ~= "table" then return {} end
    GuildPrideDB.craftLog = type(GuildPrideDB.craftLog) == "table" and GuildPrideDB.craftLog or {}
    local me = Craft.Me()
    local l = GuildPrideDB.craftLog[me]
    if type(l) ~= "table" or l.day ~= Today() then l = { day = Today() }; GuildPrideDB.craftLog[me] = l end
    return l
end

function Mini.Record(line, old, new)
    if not (old and new and new > old) then return end
    local gain = new - old
    local l = Log()
    l[line] = (l[line] or 0) + gain
    local s = session[line]
    if not s then s = { gain = 0, since = GetTime() }; session[line] = s end
    s.gain = s.gain + gain
end

-- Punkte pro Stunde in dieser Sitzung (erst ab 5 Minuten sinnvoll)
function Mini.PerHour(line)
    local s = session[line]
    if not s or s.gain == 0 then return nil end
    local hours = math.max(5 / 60, (GetTime() - s.since) / 3600)
    return math.floor(s.gain / hours + 0.5)
end

function Mini.TodayGain(line) return Log()[line] or 0 end

Craft.OnChanged(function()
    for _, p in ipairs(Craft.MyProfessions()) do
        if lastSkill[p.line] then Mini.Record(p.line, lastSkill[p.line], p.skill) end
        lastSkill[p.line] = p.skill
    end
end)

---------------------------------------------------------------------
-- Abklingzeiten
---------------------------------------------------------------------
Mini.COOLDOWNS = {
    { key = "transmute", spells = { 17187, 11479, 11480, 17559, 17560, 17561, 17562, 17563, 17564, 17565, 17566 },
      de = "Transmutieren", en = "Transmute" },
    { key = "mooncloth", spells = { 18560 }, de = "Mondstoff", en = "Mooncloth" },
    { key = "salt", item = 15846, de = "Salzstreuer", en = "Salt Shaker" },
}

local function Known(spell)
    if IsPlayerSpell then local ok, r = pcall(IsPlayerSpell, spell); if ok and r then return true end end
    if IsSpellKnown then local ok, r = pcall(IsSpellKnown, spell); if ok and r then return true end end
    return false
end

local function SpellRemaining(spell)
    local start, dur
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spell)
        if ok and type(info) == "table" then start, dur = info.startTime, info.duration end
    elseif GetSpellCooldown then
        local ok, s, d = pcall(GetSpellCooldown, spell)
        if ok then start, dur = s, d end
    end
    if not (start and dur) or dur <= 1.5 or start == 0 then return 0 end
    return math.max(0, start + dur - GetTime())
end

local function ItemRemaining(id)
    local f = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not f then return 0 end
    local ok, start, dur = pcall(f, id)
    if not ok or not (start and dur) or dur <= 1.5 or start == 0 then return 0 end
    return math.max(0, start + dur - GetTime())
end

-- Eigene Abklingzeiten lesen und merken
function Mini.ReadCooldowns()
    local e = Craft.MyEntry()
    e.cd = {}
    for _, c in ipairs(Mini.COOLDOWNS) do
        local rem
        if c.item then
            if Craft.Count(c.item) > 0 then rem = ItemRemaining(c.item) end
        else
            for _, sp in ipairs(c.spells) do
                if Known(sp) then rem = SpellRemaining(sp); break end
            end
        end
        if rem then e.cd[c.key] = GetServerTime() + math.floor(rem) end
    end
end

-- Alle Abklingzeiten: { { name, what, readyAt, ready } }
function Mini.CooldownList()
    local out, now = {}, GetServerTime()
    for name, e in pairs(Craft.Chars()) do
        if type(e) == "table" and type(e.cd) == "table" then
            for _, c in ipairs(Mini.COOLDOWNS) do
                local at = e.cd[c.key]
                if at then out[#out + 1] = { name = name, what = G.Lang(c), readyAt = at, ready = at <= now } end
            end
        end
    end
    table.sort(out, function(a, b) return a.readyAt < b.readyAt end)
    return out
end

local alerted = {}
local function CheckCooldowns()
    ns.Try(Mini.ReadCooldowns)
    for _, c in ipairs(Mini.CooldownList()) do
        local k = c.name .. c.what
        if c.ready and not alerted[k] then
            alerted[k] = true
            if c.name == Craft.Me() then ns.Print((L["%s ist wieder bereit."]):format(c.what))
            else ns.Print((L["%s: %s ist wieder bereit."]):format(c.name, c.what)) end
        elseif not c.ready then
            alerted[k] = nil
        end
    end
end

local function Left(sec)
    if sec <= 0 then return L["bereit"] end
    if sec < 3600 then return (L["%d Min."]):format(math.ceil(sec / 60)) end
    return (L["%d Std."]):format(math.ceil(sec / 3600))
end
Mini.Left = Left

---------------------------------------------------------------------
-- Inhalt der Kompaktansicht: { text, line }
---------------------------------------------------------------------
function Mini.Lines()
    local out = {}
    for _, p in ipairs(Craft.MyProfessions()) do
        local head = ("|cffffd100%s|r %d/%d"):format(G.Name(p.line), p.skill or 0, p.max or 0)
        local gain = Mini.TodayGain(p.line)
        if gain > 0 then
            local ph = Mini.PerHour(p.line)
            head = head .. "  |cff40ff40+" .. gain .. "|r" .. (ph and ("  |cffaaaaaa~" .. (L["%d/Std."]):format(ph) .. "|r") or "")
        end
        out[#out + 1] = { text = head, line = p.line }
        local step = Craft.CurrentStep(p.line, p.skill)
        if step and step.spell then
            local left = G.Remaining(step, p.skill) or 0
            local can = Craft.CanCraft(step.spell)
            out[#out + 1] = { line = p.line, text = ("   %d× %s  %s"):format(left, Craft.RecipeName(step.spell),
                can > 0 and ("|cff40ff40" .. (L["(kannst %d×)"]):format(can) .. "|r") or ("|cffff6060" .. L["(Zutaten fehlen)"] .. "|r")) }
        elseif step and step.text then
            out[#out + 1] = { line = p.line, text = "   |cffaaaaaa" .. step.text .. "|r" }
        end
    end
    local now = GetServerTime()
    for _, c in ipairs(Mini.CooldownList()) do
        out[#out + 1] = { text = ("|cff8899aa%s|r %s: %s"):format(c.name, c.what,
            c.ready and ("|cff40ff40" .. L["bereit"] .. "|r") or Left(c.readyAt - now)) }
    end
    local T = ns.CraftTrack
    if T and not T.IsEmpty() then
        local _, n = T.Missing()
        out[#out + 1] = { tracker = true, text = n > 0 and ("|cffffd100" .. L["Tracker"] .. "|r: " .. (L["%d Items fehlen"]):format(n))
                                                   or ("|cffffd100" .. L["Tracker"] .. "|r: |cff40ff40" .. L["alles da"] .. "|r") }
    end
    return out
end

---------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------
local win
local MAX = 16
local function Build()
    win = CreateFrame("Frame", "GuildPrideCraftMini", UIParent, "BackdropTemplate")
    win:SetSize(300, 40)
    win:SetFrameStrata("MEDIUM")
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        GuildPrideDB.craftMiniPos = { p, rp, x, y }
    end)
    if ns.SkinDialog then ns.SkinDialog(win) end
    local pos = type(GuildPrideDB) == "table" and GuildPrideDB.craftMiniPos
    if type(pos) == "table" then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else win:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -220) end
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScale(0.8)
    if ns.SkinClose then ns.SkinClose(close) end
    close:SetScript("OnClick", function() Mini.Toggle(false) end)
    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText(L["Handwerk"])
    win.rows = {}
    for i = 1, MAX do
        local r = CreateFrame("Button", nil, win)
        r:SetSize(280, 15)
        r:SetPoint("TOPLEFT", 10, -24 - (i - 1) * 15)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetAllPoints(); r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
        r:SetScript("OnClick", function(self)
            local d = self.data
            if d and d.tracker and ns.CraftTrack then ns.CraftTrack.Toggle()
            elseif d and d.line and ns.CraftWindow then ns.CraftWindow.Show(d.line, "prof") end
        end)
        win.rows[i] = r
    end
end

function Mini.Refresh()
    if not (win and win:IsShown()) then return end
    local lines = Mini.Lines()
    if #lines == 0 then lines = { { text = "|cff888888" .. L["Noch keine Berufe – einmal das Berufsfenster öffnen."] .. "|r" } } end
    for i, r in ipairs(win.rows) do
        local l = lines[i]
        r.data = l
        r:SetShown(l ~= nil)
        if l then r.text:SetText(l.text) end
    end
    win:SetHeight(32 + math.min(MAX, #lines) * 15)
end

function Mini.Toggle(on)
    if not win then Build() end
    if on == nil then on = not win:IsShown() end
    win:SetShown(on)
    if type(GuildPrideDB) == "table" then GuildPrideDB.craftMiniShown = on and true or false end
    Mini.Refresh()
end

Craft.OnChanged(function() Mini.Refresh() end)
C_Timer.NewTicker(30, function() CheckCooldowns(); Mini.Refresh() end)

local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "TRADE_SKILL_ITEM_CRAFTED_RESULT", "SPELL_UPDATE_COOLDOWN")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(10, function()
            for _, p in ipairs(Craft.MyProfessions()) do lastSkill[p.line] = p.skill end
            CheckCooldowns()
            if type(GuildPrideDB) == "table" and GuildPrideDB.craftMiniShown then Mini.Toggle(true) end
        end)
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then
        ns.Try(Mini.ReadCooldowns)
    else
        Mini.Refresh()
    end
end)
