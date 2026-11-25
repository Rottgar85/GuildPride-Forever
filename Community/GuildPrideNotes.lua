-- GuildPride: eigene Notizen zu Spielern („guter Tank“, „verlässt Gruppen“).
-- Nur für dich: gespeichert in GuildPrideDB.playerNotes[Name], nie verschickt.
-- Zu sehen im Tooltip über Spielern und in der Liste der GuildPride-Spieler (dort Strg+Klick: bearbeiten).
-- /gp notiz Name Text · /gp notiz Name (löschen) – Namen mit Leerzeichen in Anführungszeichen
local ADDON, ns = ...
local L = ns.L

local MAX = 120

local function Notes()
    if type(GuildPrideDB) ~= "table" then return {} end
    if type(GuildPrideDB.playerNotes) ~= "table" then GuildPrideDB.playerNotes = {} end
    return GuildPrideDB.playerNotes
end

local function Key(name)
    if type(name) ~= "string" then return nil end
    name = strtrim((name:gsub("[%c|]", "")))
    if name == "" then return nil end
    return ns.Normalize and ns.Normalize(name) or name
end

function ns.PlayerNote(name)
    local k = Key(name)
    return k and Notes()[k] or nil
end

-- Leerer Text löscht die Notiz; true, wenn gespeichert oder gelöscht
function ns.SetPlayerNote(name, text)
    local k = Key(name)
    if not k then return false end
    text = strtrim((tostring(text or ""):gsub("[%c|]", " "))):sub(1, MAX)
    Notes()[k] = text ~= "" and text or nil
    if ns.Players and ns.Players.Refresh then ns.Players.Refresh() end
    return true
end

-- Kleines Eingabefenster (StaticPopup mit Eingabefeld, nur für GuildPride selbst)
StaticPopupDialogs["GUILDPRIDE_PLAYER_NOTE"] = {
    text = L["Notiz zu %s (nur für dich, leer = löschen):"],
    button1 = OKAY or "OK", button2 = CANCEL,
    hasEditBox = true, editBoxWidth = 260, maxLetters = MAX,
    OnShow = function(self, data)
        local eb = self.editBox or self.EditBox
        eb:SetText(ns.PlayerNote(data) or ""); eb:SetFocus(); eb:HighlightText()
    end,
    OnAccept = function(self, data)
        local eb = self.editBox or self.EditBox
        ns.SetPlayerNote(data, eb:GetText())
    end,
    EditBoxOnEnterPressed = function(eb)
        local p = eb:GetParent()
        ns.SetPlayerNote(p.data, eb:GetText()); p:Hide()
    end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
function ns.EditPlayerNote(name)
    local k = Key(name)
    if not k then return end
    StaticPopup_Show("GUILDPRIDE_PLAYER_NOTE", Ambiguate(k, "none"), nil, k)
end

-- Notiz im Tooltip über Spielern (Welt, Gruppe …)
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if tooltip ~= GameTooltip or not tooltip.GetUnit then return end
        local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
        -- in Instanzen ist die Einheit geschützt: schon die Abfrage damit wirft einen Fehler
        local function Secret(v) return issecretvalue and issecretvalue(v) or false end
        if not ok or Secret(unit) or not unit then return end
        local okP, player = pcall(UnitIsPlayer, unit)
        if not okP or Secret(player) or not player then return end
        local name, realm = UnitName(unit)
        if Secret(name) or Secret(realm) or not name then return end
        local note = ns.PlayerNote(realm and realm ~= "" and (name .. "-" .. realm) or name)
        if note then tooltip:AddLine(L["Notiz: "] .. note, 1, 0.82, 0.4, true) end
    end)
end

-- /gp notiz Name Text · /gp notiz Name (löschen)
local origSlash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local raw = strtrim(arg or "")
    local cmd, rest = raw:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower()
    if cmd ~= "notiz" and cmd ~= "note" then return origSlash and origSlash(arg) end
    local name, text = rest:match('^"([^"]+)"%s*(.*)$')
    if not name then name, text = rest:match("^(%S+)%s*(.*)$") end
    if not name then
        ns.Print(L["/gp notiz Name Text – Name mit Leerzeichen in Anführungszeichen; ohne Text: löschen"])
        return
    end
    ns.SetPlayerNote(name, text)
    ns.Print(text ~= "" and (L["Notiz zu %s gespeichert."]):format(name) or (L["Notiz zu %s gelöscht."]):format(name))
end
