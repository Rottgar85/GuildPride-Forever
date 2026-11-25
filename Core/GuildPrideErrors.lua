-- GuildPride: Fehlerbericht zum Kopieren
--
-- Lua-Fehler, die aus GuildPride stammen, werden mitgeschrieben (die letzten 20,
-- gespeichert bis zum nächsten Update). Beim ersten Fehler einer Sitzung kommt ein
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
    -- Fehler älterer Versionen sind nach einem Update erledigt
    for i = #list, 1, -1 do
        if list[i].v ~= ns.VERSION then table.remove(list, i) end
    end
    for i = #early, 1, -1 do
        early[i].v = ns.VERSION
        table.insert(list, 1, early[i])
    end
    while #list > MAX do table.remove(list) end
    early = nil
end)

-- Addon-Ordner aus einem Pfad, auch ohne „Interface/AddOns/“ (BugGrabber kürzt es weg)
-- und mit angehängter Version („Name-1.2“); nil bei gekürzten Pfaden („...“) und Code ohne Datei
local CLIENT = { Interface = true, FrameXML = true, SharedXML = true, AddOns = true }
local function AddonOf(path)
    path = path:gsub("\\", "/")
    local name = path:match("Interface/AddOns/([^/]+)/") or path:match("^([%w_!][%w_!%-%. ]*)/")
    name = name and name:gsub("%-v?%d.*$", "")
    return name ~= "" and not CLIENT[name or ""] and name or nil
end
local function Foreign(addon)
    return addon and addon ~= ADDON and not addon:find("^Blizzard_")
end

-- Aufrufstapel ohne diesen Fehlerbehandler selbst (er steht immer obenauf)
local function CleanStack(stack)
    local out, leading = {}, true
    for line in stack:gmatch("[^\r\n]+") do
        if not (leading and (line:find("GuildPrideErrors.lua]", 1, true) or line:find("^%[[^%]]*BugGrabber[^%]]*%]"))) then
            leading = false
            out[#out + 1] = line
        end
    end
    return table.concat(out, "\n")
end

-- Stammt der Fehler von uns? Zuerst zählt die Datei in der Meldung (vorn gekürzt, der
-- Dateiname bleibt), sonst das Addon, in dem er entstand. Fehler in Blizzards Code
-- zählen nur, wenn GuildPride ihn aufgerufen hat.
local function Ours(msg, stack)
    local file = msg:match("^([^\n]-%.%a+):%d+:")
    if file then
        if file:find("GuildPride%w*%.%a+$") then return true end
        if Foreign(AddonOf(file)) then return false end
    end
    local first
    for line in stack:gmatch("[^\n]+") do
        local path = line:match("^%[string \"@?([^\"]*)") or line:match("^%[([^%]]*)%]")
        local addon = path and AddonOf(path)
        if addon then
            first = first or addon
            if Foreign(first) then return false end
            if addon == ADDON then return true end
        end
    end
    return false
end

-- Umstände eines Fehlers, ohne Namen: Kampf, Instanzart, offene GuildPride-Fenster
local function Context()
    local _, kind = IsInInstance()
    local wins = {}
    for _, name in ipairs(UISpecialFrames) do
        local f = name:find("^GuildPride%w+$") and _G[name]
        if type(f) == "table" and #wins < 3 and f:IsShown() then wins[#wins + 1] = name end
    end
    if ns.GuildFrame and ns.GuildFrame:IsShown() and ns.CurrentTabKey then wins[#wins + 1] = "tab" .. tostring(ns.CurrentTabKey()) end
    return ("combat=%s inst=%s win=%s"):format(InCombatLockdown() and "yes" or "no",
        type(kind) == "string" and kind or "none", #wins > 0 and table.concat(wins, ",") or "none"):sub(1, 120)
end

-- rawStack und count nur von BugGrabber (PollBugGrabber); sonst eigener Aufrufstapel, einmal
local function Record(msg, rawStack, count)
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return end
    local stack = CleanStack(rawStack or (debugstack and debugstack(3)) or "")
    if not Ours(msg, stack) then return end
    msg = msg:sub(1, 500)
    local list = Store()
    -- gleicher Fehler mehrfach: nur zählen
    for _, e in ipairs(list) do
        if e.msg == msg then e.n = (e.n or 1) + (count or 1); e.t = time(); return end
    end
    local okCtx, ctx = pcall(Context)
    table.insert(list, 1, { msg = msg, stack = stack:sub(1, 1500), t = time(), n = count or 1, v = ns.VERSION, ctx = okCtx and ctx or nil })
    while #list > MAX do table.remove(list) end
    if ns.ErrorShare then ns.ErrorShare.Recorded() end
    if not hinted and ns.Print then
        hinted = true
        if type(GuildPrideDB) == "table" and GuildPrideDB.errorShare == true then
            ns.Print(L["Es ist ein GuildPride-Fehler aufgetreten. Er geht automatisch an den Entwickler, du musst nichts tun."])
        else
            ns.Print(L["Es ist ein Fehler aufgetreten. Mit |cffffd100/gp fehler|r kannst du ihn kopieren und melden."])
        end
    end
end

-- Eigenen Code absichern, ohne Fehler zu verschlucken: wie pcall, aber ein Fehler steht danach im
-- Bericht und geht (mit Zustimmung) an den Entwickler. Für Blizzard-Funktionen, die scheitern dürfen,
-- weiter pcall benutzen.
function ns.Try(fn, ...)
    local n, args = select("#", ...), { ... }
    return xpcall(function() return fn(unpack(args, 1, n)) end, function(err)
        pcall(Record, err, debugstack and debugstack(2) or "")
        return err
    end)
end

if seterrorhandler and geterrorhandler then
    local previous = geterrorhandler()
    seterrorhandler(function(msg, ...)
        pcall(Record, msg)
        if previous then return previous(msg, ...) end
    end)
end

-- BugGrabber lädt früher und macht seterrorhandler zur Leerfunktion: Dann sehen wir keinen
-- Fehler selbst und schauen in seine Liste. (Kein RegisterCallback: damit würde BugGrabber
-- seine eigenen Chat-Hinweise abstellen.)
local grabbed = setmetatable({}, { __mode = "k" })   -- [Eintrag] = schon übernommene Anzahl
local function ReadBugGrabber()
    local bg = BugGrabber
    if type(bg) ~= "table" or type(bg.GetDB) ~= "function" then return end
    local list = bg:GetDB()
    if type(list) ~= "table" then return end
    local session = type(bg.GetSessionId) == "function" and bg:GetSessionId() or nil
    for i = 1, #list do
        local e = list[i]
        if type(e) == "table" and type(e.message) == "string" and (session == nil or e.session == session) then
            local n, seen = tonumber(e.counter) or 1, grabbed[e] or 0
            if n > seen then
                grabbed[e] = n
                Record(e.message, type(e.stack) == "string" and e.stack or "", n - seen)
            end
        end
    end
end
function ns.PollBugGrabber() return pcall(ReadBugGrabber) end

local poll = CreateFrame("Frame")
poll:RegisterEvent("PLAYER_LOGIN")
poll:SetScript("OnEvent", function()
    if type(BugGrabber) ~= "table" then return end
    C_Timer.After(10, ns.PollBugGrabber)
    C_Timer.NewTicker(30, ns.PollBugGrabber)
end)

-- /gp fehlertest: harmloser echter Fehler, um Bericht und Versand auszuprobieren
-- (mit Uhrzeit: jeder Testfehler ist ein eigener Eintrag)
function ns.ThrowTestError()
    local at = date("%H:%M:%S", time())
    C_Timer.After(0, function() error("GuildPride-Testfehler " .. at .. " (harmlos)") end)
    ns.Print(L["Testfehler ausgelöst. Er ist harmlos und steht jetzt unter |cffffd100/gp fehler|r."])
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
