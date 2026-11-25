-- GuildPride: Öffnet das Spiel das Berufsfenster eines anderen Spielers? (für den Reiter Handwerk)
-- Blizzards Fenster kommt nur, wenn der Server antwortet: bei gleichem Heimatserver (Zahl nach
-- „Player-“ in der Spieler-ID) nach 0,1 bis 0,3 s, bei anderem gar nicht, auch ganz ohne Addons
-- (geprüft 24.–25.11.2026). Klicks auf Links im Chat rührt GuildPride nicht an.
local ADDON, ns = ...

local X = {}
ns.CraftLink = X
X.broken = {}               -- [Spieler-ID] = true: öffnete in dieser Sitzung nicht
local WAIT = 1.5
local shows = 0             -- zählt geöffnete Berufsfenster

local function Guid(link)
    local data = ns.Crafts.LinkData(link)
    return data and data:match("^trade:(Player%-[%w%-]+):")
end
local function Linked()
    local T = C_TradeSkillUI
    return (T and T.IsTradeSkillLinked and T.IsTradeSkillLinked()) and true or false
end

-- done(true/false) genau einmal, nach WAIT Sekunden
function X.Watch(link, done)
    local guid = Guid(link)
    if not guid then return false end
    local before, linked = shows, Linked()
    C_Timer.After(WAIT, function()
        local ok = shows ~= before or (Linked() and not linked)
        X.broken[guid] = not ok or nil
        done(ok)
    end)
    return true
end
function X.IsBroken(link)
    local guid = Guid(link)
    return guid ~= nil and X.broken[guid] == true
end

local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "TRADE_SKILL_SHOW", "ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event, name)
    if event == "TRADE_SKILL_SHOW" then shows = shows + 1
    -- Messdaten einer Testfassung entfernen
    elseif name == ADDON and type(GuildPrideDB) == "table" then
        GuildPrideDB.linkLog = nil
    end
end)
