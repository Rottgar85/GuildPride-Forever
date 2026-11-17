-- GuildPride: Fehlerbericht zum Kopieren
--
-- Lua-Fehler, die aus GuildPride stammen, werden mitgeschrieben (die letzten 20,
-- nur diese Sitzung und gespeichert). Beim ersten Fehler einer Sitzung kommt ein
-- Hinweis im Chat; /gp fehler zeigt alles zum Kopieren (Version, Spielversion,
-- Zeit, Fehler mit Aufrufstapel), damit Nutzer ihn leicht melden können.
-- Der vorhandene Fehlerbehandler (Blizzard, BugGrabber …) läuft weiter wie bisher.
local ADDON, ns = ...
local L = ns.L

local MAX = 20
local hinted = false

-- Vor ADDON_LOADED gibt es GuildPrideDB noch nicht (WoW lädt sie erst danach);
-- frühe Fehler warten so lange hier und werden dann übernommen
local loaded, early = false, {}
local function Store()
    if not loaded then return early end
    GuildPrideDB = GuildPrideDB or {}
    GuildPrideDB.errors = GuildPrideDB.errors or {}
    return GuildPrideDB.errors
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    loaded = true
    local list = Store()
    for i = #early, 1, -1 do table.insert(list, 1, early[i]) end
    while #list > MAX do table.remove(list) end
    early = nil
end)

local function Record(msg)
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return end
    local stack = debugstack and debugstack(3) or ""
    if not (msg:find("GuildPride", 1, true) or stack:find("GuildPride", 1, true)) then return end
    local list = Store()
    -- gleicher Fehler mehrfach: nur zählen
    for _, e in ipairs(list) do
        if e.msg == msg then e.n = (e.n or 1) + 1; e.t = time(); return end
    end
    table.insert(list, 1, { msg = msg:sub(1, 500), stack = stack:sub(1, 1500), t = time(), n = 1 })
    while #list > MAX do table.remove(list) end
    if not hinted and ns.Print then
        hinted = true
        ns.Print(L["Es ist ein Fehler aufgetreten. Mit |cffffd100/gp fehler|r kannst du ihn kopieren und melden."])
    end
end

if seterrorhandler and geterrorhandler then
    local previous = geterrorhandler()
    seterrorhandler(function(msg, ...)
        pcall(Record, msg)
        if previous then return previous(msg, ...) end
    end)
end

function ns.ErrorReport()
    local list = Store()
    if #list == 0 then ns.Print(L["Keine GuildPride-Fehler gespeichert."]) return end
    local version, build, date_, toc = GetBuildInfo()
    local lines = {
        ("GuildPride %s · WoW %s (%s, %s) · %s"):format(ns.VERSION or "?", version or "?", build or "?",
            tostring(toc or "?"), GetLocale and GetLocale() or "?"),
        "",
    }
    for i, e in ipairs(list) do
        lines[#lines + 1] = ("#%d  %s  (%dx)"):format(i, date("%d.%m.%Y %H:%M", e.t or 0), e.n or 1)
        lines[#lines + 1] = e.msg or ""
        lines[#lines + 1] = e.stack or ""
        lines[#lines + 1] = ""
    end
    if ns.ShowCopy then
        ns.ShowCopy(L["Fehlerbericht – alles markieren, kopieren und uns schicken"], table.concat(lines, "\n"))
    end
end

-- Fehler melden (Knopf unter der Version): fertiger Bericht zum Kopieren mit Version,
-- Spielversion, Sprache, anderen Addons und gespeicherten Lua-Fehlern
ns.ISSUES_URL = "https://github.com/Rottgar85/GuildPride-Forever/issues/new"
function ns.BugReport()
    local version, build, _, toc = GetBuildInfo()
    local lines = {
        L["So meldest du einen Fehler:"],
        "1. " .. L["Alles markieren (Strg+A) und kopieren (Strg+C)"],
        "2. " .. L["Hier einfügen und kurz beschreiben, was passiert ist:"],
        "   " .. ns.ISSUES_URL,
        "   " .. L["(oder als Kommentar auf CurseForge)"],
        "",
        L["Was ist passiert? Was hast du gerade gemacht?"],
        "...",
        "",
        "----",
        ("GuildPride %s · WoW %s (%s, %s) · %s"):format(ns.VERSION or "?", version or "?", build or "?",
            tostring(toc or "?"), GetLocale and GetLocale() or "?"),
    }
    -- Andere geladene Addons (helfen bei Konflikten, z. B. Karten-Addons)
    local others = {}
    local num = (C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns)()
    for i = 1, num do
        local name = (C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo)(i)
        local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded)(i)
        if loaded and name ~= ADDON and not tostring(name):find("^Blizzard_") then others[#others + 1] = name end
    end
    lines[#lines + 1] = L["Andere Addons:"] .. " " .. (#others > 0 and table.concat(others, ", ") or "-")
    lines[#lines + 1] = ""
    local list = Store()
    if #list == 0 then
        lines[#lines + 1] = L["Keine GuildPride-Fehler gespeichert."]
    else
        for i, e in ipairs(list) do
            lines[#lines + 1] = ("#%d  %s  (%dx)"):format(i, date("%d.%m.%Y %H:%M", e.t or 0), e.n or 1)
            lines[#lines + 1] = e.msg or ""
            lines[#lines + 1] = e.stack or ""
            lines[#lines + 1] = ""
        end
    end
    if ns.ShowCopy then ns.ShowCopy(L["Fehler melden"], table.concat(lines, "\n")) end
end

function ns.ClearErrors()
    wipe(Store())
    ns.Print(L["Gespeicherte Fehler gelöscht."])
end
