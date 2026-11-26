-- GuildPride: Suche über alles (/gp suche, Lupe oben im Gildenfenster) und Pakete (/gp paket)
-- Sucht Mitglieder, Events, Einstellungen, Befehle, Werkzeuge, Boss-Notizen und Rezepte der Gilde.
local ADDON, ns = ...
local L = ns.L

local S = {}
ns.Search = S
local MAX = 40

-- Befehle mit kurzer Erklärung (auch die Übersicht, wenn man nach „gp“ sucht)
local COMMANDS = {
    { "handwerk", L["Handwerk & Guides"] }, { "tracker", L["Tracker"] }, { "luecken", L["Rezept-Lücken der Gilde"] }, { "dkp", "DKP" }, { "bank", L["Gildenbank-Verlauf"] },
    { "bereit", L["Raid-Bereitschaft"] }, { "quests", L["Quests der Gilde"] }, { "boss", L["Boss-Notizen"] },
    { "material", L["Materialliste der Gilde"] }, { "auswertung", L["Event-Auswertung"] }, { "loot", L["Loot-Verlauf"] },
    { "abklingzeiten", L["Abklingzeiten der Gruppe"] }, { "paten", L["Paten für Neue"] }, { "quiz", L["Gildenquiz"] },
    { "jagd", L["Schnitzeljagd"] }, { "album", L["Gildenalbum"] }, { "nachrichten", L["Messenger"] }, { "rares", L["Rares"] },
    { "zettel", L["Notizzettel"] }, { "brett", L["Schwarzes Brett"] }, { "buff", L["Buff-Food"] }, { "ah", L["Auktionshaus"] },
    { "melden", L["Fehler melden"] }, { "sicherung", L["Datensicherung"] }, { "export", L["Einstellungen sichern"] },
    { "intro", L["Einführung"] }, { "paket guild", L["Paket: nur Gilde"] }, { "paket raid", L["Paket: Gilde und Raid"] },
    { "paket all", L["Paket: alles"] }, { "version", L["Versionen in der Gilde"] },
}
S.COMMANDS = COMMANDS   -- auch für die Nutzungs-Statistik
local KIND = { member = L["Mitglied"], event = L["Event"], setting = L["Einstellung"], command = L["Befehl"], note = L["Boss-Notizen"], recipe = L["Rezept"] }

local function OpenTabKey(key)
    if not ns.UIParts or not ns.UIParts.tabs then return end
    for id, t in pairs(ns.UIParts.tabs) do
        if t.key == key then ns.OpenTab({ tabId = id }) return end
    end
end

function S.Find(text)
    local q = strtrim(text or ""):lower()
    local out = {}
    if #q < 2 then return out end
    local function Hit(s) return type(s) == "string" and s:lower():find(q, 1, true) ~= nil end
    local function Add(kind, label, open)
        if #out < MAX then out[#out + 1] = { kind = kind, text = label, open = open } end
    end
    for _, c in ipairs(COMMANDS) do
        if Hit(c[1]) or Hit(c[2]) or Hit("/gp " .. c[1]) then
            Add("command", c[2] .. "  |cff888888/gp " .. c[1] .. "|r", function() SlashCmdList.GUILDPRIDE(c[1]) end)
        end
    end
    for i = 1, GetNumGuildMembers() or 0 do
        local name, rank, _, level, _, zone, note, _, online = GetGuildRosterInfo(i)
        if name and (Hit(name) or Hit(note)) then
            Add("member", ("%s  |cff888888%s · %s%s|r"):format(Ambiguate(name, "guild"), tostring(rank or ""), tostring(level or "?"),
                online and (" · " .. tostring(zone or "")) or ""), function()
                if ns.MembersPage then ns.OpenTab(ns.MembersPage) end
                if ns.ShowMemberPanel then ns.ShowMemberPanel({ full = ns.FullName and ns.FullName(name) or ns.Normalize(name), guild = true, name = name }) end
            end)
        end
    end
    local now = GetServerTime()
    for _, e in pairs(ns.GuildTable("events")) do
        if type(e) == "table" and not e.deleted and (e.t or 0) > now - 86400 and Hit(e.title) then
            Add("event", e.title .. "  |cff888888" .. ns.FormatDate(e.t, "short") .. "|r", function() OpenTabKey("30") end)
        end
    end
    for _, o in ipairs(ns.SettingOptions or {}) do
        if o.label and Hit(o.label) and (not o.show or o.show()) then
            Add("setting", o.label, function()
                if ns.SettingsPage then ns.OpenTab(ns.SettingsPage) end
                if ns.ShowSetting then ns.ShowSetting(o) end
            end)
        end
    end
    for _, n in pairs(ns.GuildTable("bossnotes")) do
        if type(n) == "table" and not n.deleted and (Hit(n.boss) or Hit(n.text)) then
            Add("note", n.boss .. "  |cff888888" .. tostring(n.text) .. "|r", function() if ns.BossNotes then ns.BossNotes.Open(n.inst) end end)
        end
    end
    if #q >= 3 and ns.Crafts and ns.Crafts.Search then
        local ok, rows = ns.Try(ns.Crafts.Search, q)
        for _, r in ipairs(ok and type(rows) == "table" and rows or {}) do
            if r.recipe then
                Add("recipe", r.recipe .. "  |cff888888" .. Ambiguate(r.name, "guild") .. "|r", function() OpenTabKey("55") end)
            end
        end
    end
    return out
end

---------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------
local win
local function Refresh()
    if not win or not win:IsShown() then return end
    win.list = S.Find(win.box:GetText())
    local lines = {}
    for _, r in ipairs(win.list) do lines[#lines + 1] = ("|cffffd100%s|r  %s"):format(KIND[r.kind] or r.kind, r.text) end
    win.empty:SetText(#strtrim(win.box:GetText()) < 2 and L["Mindestens zwei Zeichen eingeben."] or L["Nichts gefunden."])
    win:SetLines(lines)
end
function S.Open(text)
    if not win then
        win = ns.ListWindow({ name = "GuildPrideSearch", title = L["Suche über alles"], rows = 14, width = 560, top = -70,
            sub = L["Mitglieder, Events, Einstellungen, Befehle, Boss-Notizen, Rezepte der Gilde. Klick öffnet."] })
        local box = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
        box:SetSize(526, 22); box:SetPoint("TOPLEFT", 20, win.bottomY); box:SetAutoFocus(false); box:SetMaxLetters(60)
        if ns.SkinEditBox then ns.SkinEditBox(box) end
        box:SetScript("OnTextChanged", function() win.offset = 0; Refresh() end)
        box:SetScript("OnEscapePressed", function() win:Hide() end)
        box:SetScript("OnEnterPressed", function()
            local r = win.list and win.list[1]
            if r then win:Hide(); r.open() end
        end)
        win.box = box
        for i, row in ipairs(win.rows) do
            row:EnableMouse(true)
            row:SetScript("OnMouseUp", function()
                local r = win.list and win.list[i + win.offset]
                if r then win:Hide(); r.open() end
            end)
        end
        win:SetScript("OnShow", function() win.offset = 0; Refresh() end)
    end
    win:Show()
    win.box:SetText(text or "")
    win.box:SetFocus()
    Refresh()
end

-- /gp hilfe: alle Befehle mit Erklärung, Klick führt aus
local help
function S.Help()
    if not help then
        help = ns.ListWindow({ name = "GuildPrideCommands", title = L["Alle Befehle"], rows = 18, width = 460,
            sub = L["Klick führt den Befehl aus."] })
        local lines = {}
        for i, c in ipairs(COMMANDS) do lines[i] = ("|cffffd100/gp %s|r  %s"):format(c[1], c[2]) end
        for i, row in ipairs(help.rows) do
            row:EnableMouse(true)
            row:SetScript("OnMouseUp", function()
                local c = COMMANDS[i + help.offset]
                if c then help:Hide(); SlashCmdList.GUILDPRIDE(c[1]) end
            end)
        end
        help:SetScript("OnShow", function() help.offset = 0; help:SetLines(lines) end)
    end
    help:SetShown(not help:IsShown())
end
ns.Command({ "hilfe", "help", "befehle", "commands" }, function() S.Help() end)

-- Lupe oben im Gildenfenster, links neben Nachrichten-, Community- und Discord-Knopf.
-- Der Nachrichten-Knopf entsteht erst bei PLAYER_LOGIN und der Community-Knopf ist nicht
-- immer sichtbar: darum hängt die Lupe am äußersten sichtbaren Knopf und wird neu gesetzt.
local parts = ns.UIParts
if parts and parts.discord then
    local b = CreateFrame("Button", "GuildPrideSearchButton", parts.frame)
    b:SetSize(22, 22)
    local function Place()
        local anchor = parts.discord
        for _, n in ipairs({ "GuildPrideMessengerButton", "GuildPrideCommunityButton" }) do
            local o = _G[n]
            if o and o:IsShown() then anchor = o; break end
        end
        b:ClearAllPoints()
        b:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
    end
    Place()
    parts.frame:HookScript("OnShow", function() C_Timer.After(0, function() C_Timer.After(0, Place) end) end)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:SetScript("OnEvent", function() C_Timer.After(0, Place) end)
    b:SetFrameLevel(parts.frame:GetFrameLevel() + 20)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints(); t:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    b:SetScript("OnClick", function() S.Open() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText(L["Suche über alles"]); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
end

---------------------------------------------------------------------
-- Pakete: schalten passende Funktionen gemeinsam an und aus. Nie angefasst werden Zustimmungen
-- (errorShare), Discord, Größen, Schriften und alles, was hier nicht steht.
---------------------------------------------------------------------
local GUILD = { "memberAlerts", "popup", "shareMilestones", "welcomePack", "mapShow", "guildQuests" }
local RAID = { "raidReady", "bossNotes", "cooldownShare", "buffFood", "wishTooltip", "wishDropHint" }
local REST = { "ahTooltip", "ahSellHint", "ahMailSummary", "craftCard", "craftHints", "craftTooltip", "craftBank", "craftNPCMap", "craftTips",
    "craftTrade", "craftNodes", "craftFish", "craftSell", "transitUI", "flightTimes", "flightUI", "mapNotes", "restReminder", "plateColors", "whisperWindow" }
local PRESETS = { guild = { GUILD }, raid = { GUILD, RAID }, all = { GUILD, RAID, REST } }

function ns.ApplyPreset(key)
    local on = PRESETS[key]
    if not on or type(GuildPrideDB) ~= "table" then return false end
    local want = {}
    for _, list in ipairs({ GUILD, RAID, REST }) do for _, k in ipairs(list) do want[k] = false end end
    for _, list in ipairs(on) do for _, k in ipairs(list) do want[k] = true end end
    local changed = {}
    for _, o in ipairs(ns.SettingOptions or {}) do if o.key then changed[o.key] = o.changed end end
    for k, v in pairs(want) do
        if GuildPrideDB[k] ~= v then
            GuildPrideDB[k] = v
            if changed[k] then ns.Try(changed[k]) end
        end
    end
    GuildPrideDB.preset = key
    if ns.RefreshUI then ns.RefreshUI() end
    return true
end

local slash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd, rest = strtrim(arg or ""):match("^(%S*)%s*(.*)$")
    cmd = cmd:lower()
    if cmd == "suche" or cmd == "search" or cmd == "find" then return S.Open(rest) end
    if cmd == "paket" or cmd == "preset" then
        local key = ({ gilde = "guild", alles = "all" })[rest:lower()] or rest:lower()
        if ns.ApplyPreset(key) then ns.Print(L["Paket eingestellt. Alles lässt sich weiter einzeln ändern."])
        else ns.Print(L["Pakete: /gp paket gilde · raid · alles"]) end
        return
    end
    return slash(arg)
end
