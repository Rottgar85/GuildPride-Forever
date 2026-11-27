-- GuildPride: Stufen Light, Medium und Max (früher „Pakete“, /gp paket bleibt)
--
--   light   nur Gilde: Gildenfenster, Chat, Events, Raid-Werkzeuge, Messenger, Hinweise
--   medium  dazu alles für unterwegs allein: Handwerk, Buffs, Leveln, Komfort, Reisen, Zettel, Rares, Item-Vergleich
--   max     alles, dazu Auktionshaus und Verkaufs-Berater
--
-- Was die Stufe nicht enthält, ist nicht nur aus, sondern auch aus den Menüs verschwunden:
-- Reiter (ns.TabHidden), Abschnitte der Einstellungen (tier an der Überschrift), Werkzeuge,
-- Suche, /gp-Befehle, Rare-Knopf auf der Karte und Scales-Knöpfe. Ohne Wahl (nil) gilt Max:
-- für alle, die vor 2.46 schon spielten, ändert sich nichts, bis sie wählen.
-- Nie angefasst werden Zustimmungen (errorShare, usageShare), Discord, Größen und Schriften.
local ADDON, ns = ...
local L = ns.L

local RANK = { light = 1, medium = 2, max = 3 }
local NEED = { solo = 2, max = 3 }
ns.TIER_LIST = { "light", "medium", "max" }
ns.TIER_NAMES = { light = "Light", medium = "Medium", max = "Max" }

-- Wörter für /gp stufe und die alten Paket-Namen
local ALIAS = { light = "light", leicht = "light", gilde = "light", guild = "light", raid = "light",
                medium = "medium", mittel = "medium", solo = "medium",
                max = "max", alles = "max", all = "max", voll = "max" }
function ns.PresetKey(word)
    if type(word) ~= "string" then return nil end
    return ALIAS[strtrim(word):lower()]
end

-- Gewählte Stufe; ohne Wahl Max
function ns.Tier()
    local p = type(GuildPrideDB) == "table" and ns.PresetKey(GuildPrideDB.preset) or nil
    return p or "max"
end
function ns.TierChosen() return type(GuildPrideDB) == "table" and ns.PresetKey(GuildPrideDB.preset) ~= nil end
-- need: nil (immer), "solo" (ab Medium), "max"
function ns.TierAllows(need)
    if not need then return true end
    return RANK[ns.Tier()] >= (NEED[need] or 3)
end

---------------------------------------------------------------------
-- Schalter je Stufe
---------------------------------------------------------------------
local GUILD = { "memberAlerts", "popup", "shareMilestones", "welcomePack", "mapShow", "guildQuests",
    "raidReady", "readyWindow", "bossNotes", "cooldownShare", "wishTooltip", "wishDropHint", "plateColors", "whisperWindow", "whisperEnabled" }
local SOLO = { "buffFood", "buffFoodReady", "restReminder", "levelInfo", "levelBar", "repTrack", "supplyWarn", "bagWarn",
    "hearthInfo", "chatLinks", "mapNotes", "craftCard", "craftHints", "craftTooltip", "craftBank", "craftNPCMap", "craftTips",
    "craftNodes", "craftFish", "transitUI", "flightTimes", "flightUI" }
local MAX = { "ahTab", "ahTooltip", "ahSellHint", "ahMailSummary", "craftTrade", "craftSell" }
local GROUPS = { light = { GUILD }, medium = { GUILD, SOLO }, max = { GUILD, SOLO, MAX } }
ns.TIER_KEYS = { guild = GUILD, solo = SOLO, max = MAX }
-- Reiter im Gildenfenster, die erst ab einer Stufe da sind (Schlüssel = Ordnung aus ns.AddTab)
ns.TIER_TABS = { ["55"] = "solo" }

-- Rare-Scanner und Item-Vergleich haben eigene Daten: ab Medium an
local function ApplyModules(solo)
    local R = ns.Rares
    if R and R.SetEnabled and R.DB then ns.Try(R.SetEnabled, solo)
    elseif type(GuildPrideRaresDB) == "table" and type(GuildPrideRaresDB.opts) == "table" then GuildPrideRaresDB.opts.enabled = solo end
    if R and R.UpdateMapToggle then ns.Try(R.UpdateMapToggle) end
    if R and R.UpdateToggleShown then ns.Try(R.UpdateToggleShown) end
    if type(ScalesDB) == "table" then
        ScalesDB.tooltip, ScalesDB.bagArrows, ScalesDB.bagDown, ScalesDB.bagOther = solo, solo, solo, solo
        ScalesDB.charButtonHide = not solo
        local S = ns.Scales
        if S and S.Minimap and S.Minimap.Apply then ns.Try(S.Minimap.Apply) end
        if S and S.Bags and S.Bags.QueueRefresh then ns.Try(S.Bags.QueueRefresh) end
    end
end

function ns.ApplyPreset(word)
    local key = ns.PresetKey(word)
    if not key or type(GuildPrideDB) ~= "table" then return false end
    local want = {}
    for _, list in ipairs({ GUILD, SOLO, MAX }) do for _, k in ipairs(list) do want[k] = false end end
    for _, list in ipairs(GROUPS[key]) do for _, k in ipairs(list) do want[k] = true end end
    local changed = {}
    for _, o in ipairs(ns.SettingOptions or {}) do
        if o.key then changed[o.key] = o.changed end
        -- alles in Abschnitten, die in dieser Stufe fehlen, ist aus (sonst liefe es unsichtbar weiter)
        if o.key and o.tierNeed and RANK[key] < (NEED[o.tierNeed] or 3) and type(GuildPrideDB[o.key]) == "boolean" then want[o.key] = false end
    end
    GuildPrideDB.preset = key
    for k, v in pairs(want) do
        if GuildPrideDB[k] ~= v then
            GuildPrideDB[k] = v
            if changed[k] then ns.Try(changed[k]) end
        end
    end
    ApplyModules(key ~= "light")
    if ns.MenuChanged then ns.Try(ns.MenuChanged) end
    if ns.RefreshUI then ns.RefreshUI() end
    return true
end

-- Brandneu und die Tour ohne Wahl geschlossen: das schlanke Medium (mit Buff-Food und Erholung,
-- die ab Werk aus sind, aber die meisten selbst einschalten). Umsteiger und wer schon gewählt hat:
-- nie anfassen. Rückgabe: wurde Medium gesetzt?
function ns.ApplyDefaultTier(fresh)
    if not fresh or type(GuildPrideDB) ~= "table" or ns.TierChosen() then return false end
    return ns.ApplyPreset("medium")
end

---------------------------------------------------------------------
-- /gp-Befehle, die zu einer höheren Stufe gehören
---------------------------------------------------------------------
local CMDS = {}
for w in ([[handwerk crafting guide track tracker luecken lücken gaps comfort komfort qol ep xp level leveln link links
    buff essen food lagerfeuer rast rest schlafsack rares scales zettel]]):gmatch("%S+") do CMDS[w] = "solo" end
CMDS.ah = "max"
ns.TIER_CMDS = CMDS

-- Darf der Befehl (erstes Wort) in dieser Stufe laufen?
function ns.TierCommandOK(word)
    local need = type(word) == "string" and CMDS[word:lower()] or nil
    return ns.TierAllows(need), need
end

local function Blocked(need)
    ns.Print((L["Das gehört zu GuildPride %s. Stufe ändern: /gp stufe"]):format(need == "max" and "Max" or "Medium"))
end

local function Wrap(name, need)
    local orig = SlashCmdList[name]
    if type(orig) ~= "function" then return end
    SlashCmdList[name] = function(arg, ...)
        if not ns.TierAllows(need) then return Blocked(need) end
        return orig(arg, ...)
    end
end

-- /gp stufe [light|medium|max], /gp paket (alt)
function ns.TierSlash(arg)
    local cmd, rest = strtrim(arg or ""):match("^(%S*)%s*(.*)$")
    cmd = (cmd or ""):lower()
    if cmd ~= "stufe" and cmd ~= "tier" and cmd ~= "paket" and cmd ~= "preset" then
        local ok, need = ns.TierCommandOK(cmd)
        if not ok then Blocked(need); return true end
        return false
    end
    if rest == "" and ns.ShowTierChoice then ns.ShowTierChoice()
    elseif ns.ApplyPreset(rest) then
        ns.Print((L["GuildPride-Stufe: %s. Alles lässt sich weiter einzeln ändern."]):format(ns.TIER_NAMES[ns.Tier()]))
    else ns.Print(L["Stufen: /gp stufe light · medium · max"]) end
    return true
end

-- Erst beim Einloggen: dann sind alle anderen /gp-Teile geladen und dieser Teil läuft zuerst
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    local orig = SlashCmdList.GUILDPRIDE
    SlashCmdList.GUILDPRIDE = function(arg, ...)
        if ns.TierSlash(arg) then return end
        return orig(arg, ...)
    end
    Wrap("GPRARES", "solo")
    Wrap("SCALES", "solo")
    -- Rare-Knopf und Scales-Knöpfe nach der Stufe richten (ohne Wahl bleibt alles, wie es ist)
    if ns.TierChosen() and not ns.TierAllows("solo") then C_Timer.After(2, function() ApplyModules(false) end) end
end)
