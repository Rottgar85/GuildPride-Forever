-- GuildPride: Gildenalbum – die ersten Bosskills mit Datum; auf Wunsch mit Screenshot (albumShot,
-- ab Werk aus). Alles bleibt auf diesem PC, nichts wird verschickt.
local ADDON, ns = ...
local L = ns.L

local A = {}
ns.Album = A
local MAX = 300

local function DB() return ns.GuildTable("album") end

-- true, wenn es der erste Sieg ist (je Boss und Instanz)
function A.Add(boss, inst, t)
    if type(boss) ~= "string" or boss == "" then return false end
    local db = DB()
    for _, e in ipairs(db) do if e.boss == boss and e.inst == inst then return false end end
    db[#db + 1] = { t = t or GetServerTime(), boss = boss, inst = inst }
    while #db > MAX do table.remove(db, 1) end
    return true
end

function A.Lines()
    local lines, db = {}, DB()
    for i = #db, 1, -1 do
        local e = db[i]
        lines[#lines + 1] = ("|cff999999%s|r  |cffffd100%s|r  %s"):format(ns.FormatDay(e.t, true), e.boss, e.inst or "")
    end
    return lines
end

local win
function A.Open()
    if not win then
        win = ns.ListWindow({ name = "GuildPrideAlbum", title = L["Gildenalbum"], rows = 14, width = 460,
            sub = L["Eure ersten Bosskills. Screenshots (Einstellungen › Hinweise) liegen im Ordner „Screenshots“ von WoW."],
            empty = L["Noch kein Boss im Album."] })
        win:SetScript("OnShow", function() win.offset = 0; win:SetLines(A.Lines()) end)
    end
    win:SetShown(not win:IsShown())
end

local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "ENCOUNTER_END")
ev:SetScript("OnEvent", function(_, _, _, name, _, _, success)
    if success ~= 1 and success ~= true then return end
    if issecretvalue and issecretvalue(name) then return end
    if not IsInGuild() then return end
    local inst = GetInstanceInfo and GetInstanceInfo() or nil
    if issecretvalue and issecretvalue(inst) then inst = nil end
    if not A.Add(name, inst) then return end
    ns.Print((L["Neu im Gildenalbum: %s"]):format(name))
    if GuildPrideDB.albumShot == true and Screenshot then C_Timer.After(1, function() Screenshot() end) end
end)

local slash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    if strtrim(arg or ""):lower() == "album" then return A.Open() end
    return slash(arg)
end
