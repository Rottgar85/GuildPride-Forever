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

local function Store()
    GuildPrideDB = GuildPrideDB or {}
    GuildPrideDB.errors = GuildPrideDB.errors or {}
    return GuildPrideDB.errors
end

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

function ns.ClearErrors()
    wipe(Store())
    ns.Print(L["Gespeicherte Fehler gelöscht."])
end
