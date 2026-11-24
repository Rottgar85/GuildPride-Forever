-- GuildPride: Event-Auswertung (nur Offiziere) aus der erfassten Anwesenheit
-- Verlässlichkeit je Spieler, Serie, gute und schwache Wochentage, Verlauf über die Monate.
-- Nur lokale Daten (GuildTable("attendance")), nichts wird verschickt.
local ADDON, ns = ...
local L = ns.L

local E = {}
ns.EventStats = E

local function Valid(rec)
    return type(rec) == "table" and type(rec.t) == "number" and type(rec.yes) == "table" and type(rec.present) == "table"
end

function E.Compute(records)
    local list = {}
    for _, rec in pairs(records or {}) do if Valid(rec) then list[#list + 1] = rec end end
    table.sort(list, function(a, b) return a.t < b.t end)
    local players, weekdays, months, monthAt = {}, {}, {}, {}
    local function P(name)
        local p = players[name]
        if not p then p = { name = name, yes = 0, came = 0, present = 0, streak = 0 }; players[name] = p end
        return p
    end
    for _, rec in ipairs(list) do
        local here, said = {}, {}
        for _, n in ipairs(rec.present) do here[n] = true; P(n).present = P(n).present + 1 end
        for _, n in ipairs(rec.yes) do
            if not said[n] then
                said[n] = true
                local p = P(n)
                p.yes = p.yes + 1
                if here[n] then p.came, p.streak = p.came + 1, p.streak + 1 else p.streak = 0 end
            end
        end
        local d = date("*t", rec.t)
        local w = weekdays[d.wday] or { n = 0, sum = 0 }
        w.n, w.sum = w.n + 1, w.sum + #rec.present
        w.avg = w.sum / w.n
        weekdays[d.wday] = w
        local key = ("%04d-%02d"):format(d.year, d.month)
        local m = monthAt[key]
        if not m then m = { key = key, n = 0, sum = 0 }; monthAt[key] = m; months[#months + 1] = m end
        m.n, m.sum = m.n + 1, m.sum + #rec.present
        m.avg = m.sum / m.n
    end
    local out = {}
    for _, p in pairs(players) do
        p.quote = p.yes > 0 and p.came / p.yes or -1
        out[#out + 1] = p
    end
    table.sort(out, function(a, b)
        if a.quote ~= b.quote then return a.quote > b.quote end
        if a.came ~= b.came then return a.came > b.came end
        if a.present ~= b.present then return a.present > b.present end
        return a.name < b.name
    end)
    return { events = #list, players = out, weekdays = weekdays, months = months }
end

local DAYS = { L["Sonntag"], L["Montag"], L["Dienstag"], L["Mittwoch"], L["Donnerstag"], L["Freitag"], L["Samstag"] }

function E.Lines(records)
    local s = E.Compute(records)
    if s.events == 0 then
        return { L["Noch keine Anwesenheit erfasst. Das passiert 10 Min. nach Beginn eines Events von selbst."] }
    end
    local lines = { "|cffffd100" .. L["Wochentage (Spieler im Schnitt)"] .. "|r" }
    -- Montag zuerst
    for _, i in ipairs({ 2, 3, 4, 5, 6, 7, 1 }) do
        local w = s.weekdays[i]
        if w then lines[#lines + 1] = ("   %s: %.1f  |cff888888(%s)|r"):format(DAYS[i], w.avg, (L["%d Events"]):format(w.n)) end
    end
    lines[#lines + 1] = "|cffffd100" .. L["Monate (Spieler im Schnitt)"] .. "|r"
    for i = #s.months, math.max(1, #s.months - 5), -1 do
        local m = s.months[i]
        lines[#lines + 1] = ("   %s: %.1f  |cff888888(%s)|r"):format(m.key, m.avg, (L["%d Events"]):format(m.n))
    end
    lines[#lines + 1] = "|cffffd100" .. L["Spieler (da / zugesagt, Serie)"] .. "|r"
    for _, p in ipairs(s.players) do
        local who = Ambiguate(p.name, "guild")
        if p.yes > 0 then
            local q = math.floor(p.quote * 100 + 0.5)
            local col = q >= 75 and "|cff40ff40" or (q >= 50 and "|cffffd100" or "|cffff6060")
            lines[#lines + 1] = ("   %s  %s%d/%d (%d %%)|r%s"):format(who, col, p.came, p.yes, q,
                p.streak >= 3 and ("  |cff8cc8ff" .. (L["%d in Folge"]):format(p.streak) .. "|r") or "")
        else
            lines[#lines + 1] = ("   |cff999999%s  %s|r"):format(who, (L["%d× ohne Zusage da"]):format(p.present))
        end
    end
    return lines
end

local win
function E.Open()
    if not (CanEditMOTD and CanEditMOTD()) then ns.Print(L["Die Event-Auswertung sehen nur Offiziere."]); return end
    if not win then
        win = ns.ListWindow({ name = "GuildPrideEventStats", title = L["Event-Auswertung"], rows = 18, width = 480,
            sub = L["Aus der erfassten Anwesenheit auf diesem PC. Mausrad blättert."] })
        win:SetScript("OnShow", function() win.offset = 0; win:SetLines(E.Lines(ns.GuildTable("attendance"))) end)
    end
    win:SetShown(not win:IsShown())
end

ns.Command({ "auswertung", "stats" }, function() E.Open() end)
