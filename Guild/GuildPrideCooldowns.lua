-- GuildPride: gemeinsame Abklingzeiten wichtiger Zauber in der Gruppe
-- Jeder mit GuildPride meldet nur seine eigenen Zauber, sobald er sie benutzt (abschaltbar:
-- cooldownShare). Während eines Bosskampfs kann Forever Addon-Nachrichten sperren; dann kommt
-- die Meldung danach. Angezeigt wird nur, wer in deiner Gruppe ist (/gp abklingzeiten).
--   CDN  zauber (erste Rang-ID) · Restzeit in Sekunden
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP

local C = {}
ns.Cooldowns = C
C.data = {}   -- [Name] = { [zauber] = GetTime() des Endes }

-- Erste Rang-ID -> Abklingzeit in Sekunden (Classic-Werte; höchstens so lang wird geglaubt)
C.SPELLS = {
    [20484] = 1800,   -- Wiedergeburt
    [29166] = 360,    -- Anregen
    [740]   = 300,    -- Gelassenheit
    [633]   = 3600,   -- Handauflegung
    [642]   = 300,    -- Gottesschild
    [1022]  = 300,    -- Segen des Schutzes
    [19752] = 3600,   -- Göttliche Intervention
    [20608] = 3600,   -- Reinkarnation
    [16190] = 300,    -- Totem der Manaflut
    [871]   = 1800,   -- Schildwall
    [12975] = 600,    -- Letztes Gefecht
    [10060] = 180,    -- Seele der Macht
    [724]   = 600,    -- Brunnen des Lichts
    [2825]  = 600,    -- Kampfrausch
    [32182] = 600,    -- Heldentum
    [20707] = 1800,   -- Seelenstein
}

local function Enabled() return not (type(GuildPrideDB) == "table" and GuildPrideDB.cooldownShare == false) end
local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and (GetSpellInfo(id)) or nil
end

function C.Set(name, spell, left)
    local max = C.SPELLS[spell]
    if not max or left <= 0 then return false end
    C.data[name] = C.data[name] or {}
    C.data[name][spell] = GetTime() + math.min(left, max)
    if C.Refresh then C.Refresh() end
    return true
end
function C.Left(name, spell)
    local t = C.data[name] and C.data[name][spell]
    return t and math.max(0, t - GetTime()) or 0
end

ns.On("CDN", function(payload, sender)
    if sender == ns.Me() or not ns.IsGuildMember(sender) then return end
    local spell, left = strsplit(SEP, payload)
    spell, left = tonumber(spell), tonumber(left)
    if not spell or not left or left ~= left then return end
    C.Set(sender, spell, left)
end)

---------------------------------------------------------------------
-- Eigene Zauber erkennen (alle Ränge am Namen)
---------------------------------------------------------------------
local byName
local function FirstRank(spellID)
    if C.SPELLS[spellID] then return spellID end
    if not byName then
        byName = {}
        for id in pairs(C.SPELLS) do
            local n = SpellName(id)
            if type(n) == "string" then byName[n] = id end
        end
    end
    local n = SpellName(spellID)
    return type(n) == "string" and byName[n] or nil
end

-- Dauer aus dem Spiel (Talente), wenn lesbar; sonst Tabelle. Unter 10 s ist es die globale Abklingzeit.
function C.Duration(first, spellID)
    local max = C.SPELLS[first]
    local ok, d = pcall(function()
        if C_Spell and C_Spell.GetSpellCooldown then
            local i = C_Spell.GetSpellCooldown(spellID)
            return type(i) == "table" and i.duration or nil
        end
        if GetSpellCooldown then return (select(2, GetSpellCooldown(spellID))) end
    end)
    if not ok or type(d) ~= "number" or (issecretvalue and issecretvalue(d)) or d < 10 then return max end
    return math.min(math.floor(d + 0.5), max)
end

local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "UNIT_SPELLCAST_SUCCEEDED")
ev:SetScript("OnEvent", function(_, _, unit, _, spellID)
    if unit ~= "player" or not Enabled() or not IsInGroup() or not IsInGuild() then return end
    if type(spellID) ~= "number" or (issecretvalue and issecretvalue(spellID)) then return end
    local first = FirstRank(spellID)
    if not first then return end
    C_Timer.After(0.5, function()
        local d = C.Duration(first, spellID)
        C.Set(ns.Me(), first, d)
        ns.Queue("CDN", "@CHANNEL", first, d)
    end)
end)

---------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------
local function InGroup()
    local out = {}
    local realm = GetNormalizedRealmName() or ""
    local n = IsInGroup() and GetNumGroupMembers() or 0
    for i = 1, n do
        local unit = IsInRaid() and ("raid" .. i) or (i == n and "player" or ("party" .. i))
        local name, r = (ns.IS_FOREVER and UnitFullName or UnitName)(unit)
        if name and not (issecretvalue and issecretvalue(name)) then
            out[ns.Normalize(name .. "-" .. ((r and r ~= "") and r or realm))] = true
        end
    end
    out[ns.Me()] = true
    return out
end

local function Time(s)
    if s >= 60 then return ("%d:%02d"):format(math.floor(s / 60), s % 60) end
    return ("%d s"):format(s)
end

local win
function C.Refresh()
    if not win or not win:IsShown() then return end
    local group, rows = InGroup(), {}
    for name, t in pairs(C.data) do
        if group[name] then
            for spell in pairs(t) do rows[#rows + 1] = { name = name, spell = spell, left = C.Left(name, spell) } end
        end
    end
    table.sort(rows, function(a, b)
        if a.left ~= b.left then return a.left < b.left end
        if a.name ~= b.name then return a.name < b.name end
        return a.spell < b.spell
    end)
    local lines = {}
    for _, r in ipairs(rows) do
        lines[#lines + 1] = ("%s  %s  %s"):format(Ambiguate(r.name, "guild"), SpellName(r.spell) or ("#" .. r.spell),
            r.left > 0 and ("|cffff6060" .. Time(r.left) .. "|r") or ("|cff40ff40" .. L["bereit"] .. "|r"))
    end
    win:SetLines(lines)
end

function C.Open()
    if not win then
        win = ns.ListWindow({ name = "GuildPrideCooldowns", title = L["Abklingzeiten der Gruppe"], rows = 12, width = 400,
            sub = L["Nur Gildenmitglieder mit GuildPride; ein Zauber erscheint, sobald er einmal benutzt wurde."],
            empty = L["Noch nichts gemeldet."] })
        win:SetScript("OnShow", function() win.offset = 0; C.Refresh() end)
        ns.Every(1, function() if win:IsShown() then C.Refresh() end end)
    end
    win:SetShown(not win:IsShown())
end

ns.Command({ "abklingzeiten", "cooldowns", "cd" }, function() C.Open() end)
