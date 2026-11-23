-- GuildPride-Tests: lua5.1 tests/run.lua (aus dem Hauptordner)
-- Prüft vor allem die Sicherheitsregeln für Addon-Nachrichten.
package.path = "./tests/?.lua;" .. package.path
local W = require("wow")
local SEP = "\031"

W.roster = {
    { "Tester", 3 },   -- ich
    { "Gm", 0 },       -- Gildenleitung
    { "Offi", 1 },     -- Offizier (darf Gildennachricht ändern)
    { "Anna", 3 },
    { "Bert", 3 },
    { "Carl", 3 },
    { "Ohne", 3 },     -- ohne GuildPride
}

W.Load("GuildPride.lua")
W.Load("GuildPrideAusweis.lua")
W.Load("GuildPrideDKP.lua")
W.Load("GuildPrideHistory.lua")
W.Load("GuildPrideRoster.lua")
W.Load("GuildPrideRecruit.lua")
W.Load("GuildPrideCrafts.lua")
W.Load("GuildPrideGoals.lua")
W.Load("GuildPrideBoard.lua")
W.Load("GuildPrideWishlist.lua")
W.Load("GuildPrideInk.lua")
W.Start()
local ns = W.ns
ns.FormatDate = ns.FormatDate or function() return "" end
ns.FormatDay = ns.FormatDay or function() return "" end

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name)
    else failed = failed + 1; print("FEHLER " .. name .. ": " .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "") .. " erwartet " .. tostring(b) .. ", ist " .. tostring(a), 2) end end
local function msg(kind, ...) return kind .. ":" .. table.concat({ ... }, SEP) end

---------------------------------------------------------------------
test("Offiziere: Ränge mit Recht 'Gildennachricht ändern'", function()
    eq(ns.IsOfficerName("Gm"), true)
    eq(ns.IsOfficerName("Offi"), true)
    eq(ns.IsOfficerName("Anna"), false)
    eq(ns.IsOfficerName("Fremder"), false)
end)

---------------------------------------------------------------------
test("Ausweis: 14 Zeichen, gleich bleibend, ohne BattleTag", function()
    local a = ns.Ausweis()
    eq(#a, 14)
    eq(a, ns.Ausweis())
    eq(a:find("Tester", 1, true), nil)
    eq(a:match("^[0-9a-z]+$") ~= nil, true)
end)

test("Ausweis: andere Gilde ergibt anderen Code", function()
    local a = ns.Ausweis()
    local old = GetGuildInfo
    GetGuildInfo = function() return "Anderegilde", "Rang", 3, "Realm" end
    local b = ns.Ausweis()
    GetGuildInfo = old
    eq(a ~= b, true)
end)

local CODE_A = "aaaaaaaaaaaaaa"
local CODE_B = "bbbbbbbbbbbbbb"

test("Ausweis: zwei Charaktere mit gleichem Code werden ein Spieler", function()
    W.Receive("Anna", msg("AUS", CODE_A, "", 1))
    W.Receive("Bert", msg("AUS", CODE_A, "", 1))
    local groups = ns.AltGroups()
    local main = ns.MainOf("Bert")
    eq(ns.MainOf("Anna"), main)
    eq(#groups[main], 1)
end)

test("Ausweis: wer meinen Code benutzt, wird als umstritten markiert", function()
    W.sent = {}
    W.Receive("Carl", msg("AUS", ns.Ausweis(), "", 1))
    eq(ns.IsDisputed("Carl"), true)
    eq(ns.MainOf("Carl"), "Carl")
    local found = false
    for _, s in ipairs(W.sent) do if s.kind == "AUSX" then found = true end end
    eq(found, true, "AUSX gesendet")
end)

test("Ausweis: fremde Liste von einem Mitglied allein zählt nicht", function()
    W.Receive("Anna", msg("AUSL", "Ohne=" .. CODE_B .. "="), "WHISPER")
    eq(ns.MainOf("Ohne"), "Ohne")
    eq(ns.IsMyChar("Ohne"), false)
end)

test("Ausweis: fremde Liste zählt, wenn zwei Mitglieder sie gleich melden", function()
    W.Receive("Bert", msg("AUSL", "Ohne=" .. CODE_A .. "="), "WHISPER")
    W.Receive("Carl", msg("AUSL", "Ohne=" .. CODE_A .. "="), "WHISPER")
    eq(ns.MainOf("Ohne"), ns.MainOf("Anna"))
end)

test("Twink von Hand: nur Offiziere", function()
    W.Receive("Anna", msg("ALT", "Carl", "Gm", W.server))
    eq(ns.IsManualAlt("Carl"), false)
    W.Receive("Offi", msg("ALT", "Carl", "Gm", W.server))
    eq(ns.IsManualAlt("Carl"), true)
    eq(ns.MainOf("Carl"), "Gm")
    eq(ns.IsDisputed("Carl"), false, "Offizier löst Streit")
end)

---------------------------------------------------------------------
local T0 = W.server
local function dkp(id, d, by, names, void)
    return msg("DKP", id, d, "Test", by, T0, void and 1 or 0, names, "")
end

test("DKP: Nicht-Offizier allein kann nicht buchen", function()
    W.Receive("Anna", dkp("fake01", 500, "Anna", "Anna"))
    eq(ns.DKP.Of("Anna"), nil)
end)

test("DKP: Offizier bucht direkt", function()
    W.Receive("Offi", dkp("ok0001", 10, "Offi", "Bert"))
    eq(ns.DKP.Of("Bert"), 10)
end)

test("DKP: Abgleich über zwei verschiedene Mitglieder", function()
    W.Receive("Anna", dkp("sync01", 7, "Offi", "Carl"))
    eq(ns.DKP.Of("Carl"), nil, "erst nach zweiter Meldung")
    W.Receive("Bert", dkp("sync01", 7, "Offi", "Carl"))
    eq(ns.DKP.Of("Carl"), 7)
end)

test("DKP: Nicht-Offizier kann keine Buchung zurücknehmen", function()
    W.Receive("Anna", dkp("ok0001", 10, "Offi", "Bert", true))
    eq(ns.DKP.Of("Bert"), 10)
end)

---------------------------------------------------------------------
test("Weiterleitung: angeblich vom Offizier wird verworfen", function()
    local inner = dkp("fwd001", 99, "Offi", "Anna")
    W.Receive("Bert", msg("FWD", "Offi", "1", inner))
    eq(ns.DKP.Of("Anna"), nil)
end)

test("Weiterleitung: DKP auch von Nicht-Offizier-Absender verworfen", function()
    W.Receive("Bert", msg("FWD", "Carl", "2", dkp("fwd002", 5, "Carl", "Carl")))
    W.Receive("Anna", msg("FWD", "Carl", "3", dkp("fwd002", 5, "Carl", "Carl")))
    eq(ns.DKP.Of("Carl"), 7, "unverändert")
end)

test("Weiterleitung: zusammengesetzte (MP) DKP-Nachricht verworfen", function()
    local inner = dkp("fwd003", 50, "Offi", "Anna")
    local part = msg("MP", "77", 1, 1, inner)
    W.Receive("Bert", msg("FWD", "Carl", "4", part))
    eq(ns.DKP.Of("Anna"), nil)
end)

test("Weiterleitung: Ausweis-Meldung für fremden Charakter verworfen", function()
    W.Receive("Bert", msg("FWD", "Ohne", "5", msg("AUS", CODE_B, "", 1)))
    eq(ns.MainOf("Ohne"), ns.MainOf("Anna"), "Zuordnung unverändert")
end)

---------------------------------------------------------------------
test("Verlauf: Beitritt merken, erneuter Beitritt erkannt", function()
    local t0 = W.server - 100 * 86400
    ns.HistoryJoin("Anna", t0)
    ns.HistoryLeave("Anna", W.server - 50 * 86400)
    eq(ns.HistoryRejoinText("Anna") ~= nil, true)
    ns.HistoryJoin("Anna", W.server)
    eq(#ns.HistoryOf("Anna").joins, 2)
    eq(ns.HistoryOf("Anna").first, t0)
    eq(ns.HistoryOf("Anna").left, nil)
end)

test("Verlauf: fremde Liste nur von Offizieren", function()
    local fake = "Bert=" .. (W.server - 900 * 86400) .. "=0=" .. (W.server - 900 * 86400) .. "="
    W.Receive("Carl", msg("JHL", fake), "WHISPER")
    eq(ns.HistoryOf("Bert") == nil or ns.HistoryOf("Bert").first ~= W.server - 900 * 86400, true)
    local t = W.server - 10 * 86400
    local real = "Bert=" .. t .. "=0=" .. t .. "="
    W.Receive("Offi", msg("JHL", real), "WHISPER")
    eq(ns.HistoryOf("Bert").first, t)
end)

test("Raid-Aufstellung: nur von Offizieren angenommen", function()
    ns.GuildTable("events")["Offi-1-1"] = { id = "Offi-1-1", title = "Raid", signups = {} }
    W.Receive("Anna", msg("LAY", "Offi-1-1", "Anna=11;Bert=12"))
    eq(ns.GuildTable("events")["Offi-1-1"].layout, nil)
    W.Receive("Offi", msg("LAY", "Offi-1-1", "Anna=11;Bert=12;Boese=99"))
    local lay = ns.GuildTable("events")["Offi-1-1"].layout
    eq(lay.Anna, 11); eq(lay.Bert, 12); eq(lay.Boese, nil, "ungültiger Platz")
end)

---------------------------------------------------------------------
test("Bewerbung: geschlossen -> freundliche Absage, kein Gespräch", function()
    W.whispers = {}
    W.Whisper("Fremd", "!bewerben")
    eq(#W.whispers, 1)
    eq(W.whispers[1].to, "Fremd")
end)

test("Bewerbung: Steckbrief nur von Offizieren", function()
    W.Receive("Anna", msg("RCP", W.server + 1, 1, "Heiler", "Mi 20 Uhr", "Deutsch", "Nett"))
    eq(ns.RecruitOpen(), false)
    W.Receive("Offi", msg("RCP", W.server, 1, "Heiler", "Mi 20 Uhr", "Deutsch", "Nett"))
    eq(ns.RecruitOpen(), true)
end)

test("Werbung: mehrere Werbetexte speichern und wechseln", function()
    local old = { GuildPrideDB.recruitText, GuildPrideDB.recruitTexts, GuildPrideDB.recruitIndex }
    GuildPrideDB.recruitText, GuildPrideDB.recruitTexts, GuildPrideDB.recruitIndex = "Alter Text", nil, nil
    local list, i = ns.RecruitList()
    eq(#list, 1); eq(i, 1); eq(list[1], "Alter Text", "bisheriger Text wird Nr. 1")
    eq(ns.RecruitAdd(), true)
    ns.RecruitSetText("Zweiter Text")
    eq(GuildPrideDB.recruitIndex, 2); eq(GuildPrideDB.recruitText, "Zweiter Text")
    ns.RecruitSelect(1); eq(GuildPrideDB.recruitText, "Alter Text")
    ns.RecruitSelect(0); eq(GuildPrideDB.recruitIndex, 2, "vor dem ersten kommt der letzte")
    ns.RecruitSelect(3); eq(GuildPrideDB.recruitIndex, 1, "nach dem letzten kommt der erste")
    ns.RecruitRemove()
    list = ns.RecruitList()
    eq(#list, 1); eq(GuildPrideDB.recruitText, "Zweiter Text")
    ns.RecruitRemove()
    eq(#ns.RecruitList(), 1); eq(GuildPrideDB.recruitText, "", "letzter Text wird nur geleert")
    for _ = 1, 12 do ns.RecruitAdd() end
    eq(#ns.RecruitList(), 10, "höchstens 10")
    GuildPrideDB.recruitText, GuildPrideDB.recruitTexts, GuildPrideDB.recruitIndex = old[1], old[2], old[3]
end)

test("Bewerbung: Gespräch per Flüstern ohne Addon", function()
    W.whispers, W.sent = {}, {}
    W.Whisper("Fremd", "!bewerben")
    for i = 1, 4 do W.Whisper("Fremd", "Antwort " .. i .. " |cffff0000bunt|r") end
    local box = ns.GuildTable("appOutbox")
    local app
    for _, a in pairs(box) do app = a end
    eq(app ~= nil, true, "Bewerbung im Ausgang")
    eq(app.name, "Fremd")
    eq(app.a[4]:find("|", 1, true), nil, "Codes entfernt")
    eq(#W.whispers, 6, "Begrüßung + 4 Fragen + Dank")
end)

test("Bewerbung: zweite am selben Tag abgelehnt", function()
    W.whispers = {}
    W.Whisper("Fremd", "!bewerben")
    eq(#W.whispers, 1)
end)

test("Bewerbung: Gildenmitglieder werden ignoriert", function()
    W.whispers = {}
    W.Whisper("Anna", "!bewerben")
    eq(#W.whispers, 0)
end)

test("Bewerbung: Bestätigung nur von Offizieren", function()
    local box = ns.GuildTable("appOutbox")
    local id = next(box)
    W.Receive("Anna", msg("APK", id), "WHISPER")
    eq(box[id] ~= nil, true)
    W.Receive("Offi", msg("APK", id), "WHISPER")
    eq(box[id], nil)
end)

test("Bewerbung: Offizier empfängt und speichert", function()
    W.canMotd = true
    W.Receive("Bert", msg("APP", "Zweit-1", "Zweit", W.server, "Bert", "Magier 60", "DD", "abends", "Hallo"), "WHISPER")
    local app = ns.GuildTable("apps")["Zweit-1"]
    W.canMotd = false
    eq(app ~= nil, true)
    eq(app.a[1], "Magier 60")
end)


---------------------------------------------------------------------
test("Berufe: Mitglied meldet eigene Berufe und Rezepte", function()
    local v = W.server
    W.Receive("Anna", msg("CRF", v, "Schneiderei~285~300;Verzauberkunst~150~225"))
    local e = ns.GuildTable("crafts")["Anna"]
    eq(e ~= nil, true)
    eq(#e.profs, 2)
    eq(e.profs[1].n, "Schneiderei"); eq(e.profs[1].l, 285)
    W.Receive("Anna", msg("CRR", v, "Schneiderei", "2s,zz,1"))
    eq(#e.rec["Schneiderei"], 3)
    eq(e.rec["Schneiderei"][1], tonumber("2s", 36))
end)

test("Berufe: Symbole werden mitgeschickt, Ersatz nach Namen", function()
    W.Receive("Bert", msg("CRF", W.server + 5, "Bergbau~150~225;Alchemie~100~150", "136248;abc"))
    local e = ns.GuildTable("crafts")["Bert"]
    eq(e.profs[1].i, 136248)
    eq(e.profs[2].i, nil, "ungültiges Symbol verworfen")
    eq(ns.Crafts.Icon(e.profs[2]):find("Trade_Alchemy", 1, true) ~= nil, true, "Ersatz nach Name")
    ns.GuildTable("crafts")["Bert"] = nil
end)

test("Berufe: Berufs-Link wird geteilt, falsche verworfen", function()
    local e = ns.GuildTable("crafts")["Anna"]
    W.Receive("Anna", msg("CRR", e.v, "Schneiderei", "2s,zz,1", "trade:Player-6937-0016743F:197:300"))
    eq(e.links["Schneiderei"], "trade:Player-6937-0016743F:197:300")
    W.Receive("Anna", msg("CRR", e.v, "Schneiderei", "2s,zz,1", "item:123:0:0"))
    eq(e.links["Schneiderei"], nil, "kein Berufs-Link")
    eq(ns.Crafts.LinkData("|cffffd000|Htrade:Player-1-ABC:164:75|h[Schmiedekunst]|h|r"), "trade:Player-1-ABC:164:75")
end)

test("Berufe: Rezepte nur zum bekannten Stand und Beruf", function()
    local e = ns.GuildTable("crafts")["Anna"]
    W.Receive("Anna", msg("CRR", e.v + 5, "Schneiderei", "aa"))
    eq(#e.rec["Schneiderei"], 3, "falscher Stand")
    W.Receive("Anna", msg("CRR", e.v, "Alchemie", "aa"))
    eq(e.rec["Alchemie"], nil, "fremder Beruf")
end)

test("Berufe: weitergeleitet oder von Fremden verworfen", function()
    W.Receive("Bert", msg("FWD", "Carl", "9", msg("CRF", W.server, "Alchemie~300~300")))
    eq(ns.GuildTable("crafts")["Carl"], nil, "weitergeleitet")
    W.Receive("Fremd", msg("CRF", W.server, "Alchemie~300~300"), "WHISPER")
    eq(ns.GuildTable("crafts")["Fremd"], nil, "kein Mitglied")
end)

test("Berufe: offenes Berufsfenster wird erkannt", function()
    ProfessionsFrame, TradeSkillFrame = nil, nil
    eq(ns.Crafts.ProfessionShown(), false)
    ProfessionsFrame = CreateFrame(); ProfessionsFrame.shown = false
    eq(ns.Crafts.ProfessionShown(), false, "zu")
    ProfessionsFrame:Show()
    eq(ns.Crafts.ProfessionShown(), true)
    ProfessionsFrame = nil
end)

test("Tastendruck-Aktion: Tasten weiterreichen schon beim Laden, im Kampf versteckt", function()
    local work, hits, fight = false, 0, false
    local oldCombat, oldCreate = InCombatLockdown, CreateFrame
    local calls = {}
    CreateFrame = function(...)
        local fr = oldCreate(...)
        fr.SetPropagateKeyboardInput = function(_, v) calls[#calls + 1] = "propagate" .. tostring(v) end
        fr.EnableKeyboard = function(_, v) calls[#calls + 1] = "keyboard" .. tostring(v) end
        return fr
    end
    InCombatLockdown = function() return fight end
    local _, f = ns.KeyAction(function() return work end, function() hits = hits + 1 end)
    CreateFrame = oldCreate
    eq(calls[1], "propagatetrue", "Weiterreichen zuerst, sofort beim Anlegen")
    eq(calls[2], "keyboardtrue"); eq(#calls, 2, "danach nie wieder umgestellt")
    f.scripts.OnKeyDown(f)
    eq(hits, 0, "nichts wartet")
    work = true
    f.scripts.OnEvent(f, "PLAYER_REGEN_DISABLED")
    eq(f.IsListening(), false, "Kampfbeginn: versteckt")
    fight = true
    f.scripts.OnKeyDown(f)
    eq(hits, 0, "im Kampf nichts senden")
    fight = false
    f.scripts.OnEvent(f, "PLAYER_REGEN_ENABLED")
    eq(f.IsListening(), true, "nach dem Kampf")
    f.scripts.OnKeyDown(f)
    eq(hits, 1); eq(#calls, 2, "Tastatur-Einstellungen unverändert")
    InCombatLockdown = oldCombat
end)

test("Berufe: Suche nach Beruf und Name", function()
    eq(#ns.Crafts.Search("schnei"), 1)
    eq(#ns.Crafts.Search("anna"), 2)
    eq(#ns.Crafts.Search(""), 2)
    local tree = ns.Crafts.Tree("")
    eq(#tree, 1, "ein Charakter")
    eq(#tree[1].profs, 2)
    eq(tree[1].auto, false, "ohne Suche zugeklappt")
    tree = ns.Crafts.Tree("verzau")
    eq(#tree[1].profs, 1, "nur der passende Beruf")
    eq(tree[1].auto, true, "Treffer aufgeklappt")
end)

test("Berufe: auch Mitglieder ohne GuildPride aus der Gildenliste", function()
    local oldRoster = W.roster
    W.roster = { { "Anna", 2 }, { "Dora", 3 }, { "Emil", 3, 60, false } }
    for _, m in ipairs(oldRoster) do W.roster[#W.roster + 1] = m end
    local rows = {   -- id, zugeklappt, Symbol, Überschrift, …, Name, Name-Realm, …, Stufe
        { 164, true, 136241, "Schmiedekunst" },
        { 2933, true, nil, "Test Profession [DNT]" },
        { 197, true, 136249, "Schneiderei" },
    }
    local members = { [164] = { { "Dora", 280 }, { "Emil", 150 } }, [197] = { { "Anna", 285 } } }
    local open, offline, expanded, collapsed = {}, false, 0, 0
    local function list()
        local out = {}
        for _, h in ipairs(rows) do
            out[#out + 1] = { h[1], not open[h[1]], h[3], h[4] }
            if open[h[1]] then
                for _, m in ipairs(members[h[1]] or {}) do
                    if offline or m[1] ~= "Emil" then
                        out[#out + 1] = { h[1], nil, nil, nil, nil, nil, nil, m[1], m[1] .. "-Realm", "Krieger", true, "Zone", m[2] }
                    end
                end
            end
        end
        return out
    end
    GetNumGuildTradeSkill = function() return #list() end
    GetGuildTradeSkillInfo = function(i) local r = list()[i]; if r then return unpack(r, 1, 13) end end
    ExpandGuildTradeSkillHeader = function(id) open[id] = true; expanded = expanded + 1 end
    CollapseGuildTradeSkillHeader = function(id) open[id] = nil; collapsed = collapsed + 1 end
    GetGuildRosterShowOffline = function() return offline end
    SetGuildRosterShowOffline = function(v) offline = v end

    eq(ns.Crafts.ReadGuild(), true)
    eq(expanded, 3); eq(collapsed, 3, "danach wieder zugeklappt")
    eq(offline, false, "Offline-Anzeige zurückgesetzt")
    local db = ns.GuildTable("craftsRoster")
    eq(db["Emil"] ~= nil, true, "Offline-Mitglied gelesen")
    eq(db["Dora"][1].n, "Schmiedekunst"); eq(db["Dora"][1].l, 280); eq(db["Dora"][1].id, 164)

    W.Advance(6)   -- Gildenliste neu einlesen lassen
    local tree = ns.Crafts.Tree("")
    local byName = {}
    for _, c in ipairs(tree) do byName[c.name] = c end
    eq(byName["Anna"].roster, nil, "Addon-Nutzer behält seine Daten")
    eq(byName["Anna"].profs[1].skill, 197, "Berufs-ID aus der Gildenliste")
    eq(byName["Dora"].roster, true)
    eq(byName["Dora"].profs[1].count, 0)
    eq(#ns.Crafts.Tree("schmiede"), 2, "Suche findet Mitglieder ohne Addon")

    GetNumGuildTradeSkill, GetGuildTradeSkillInfo = nil, nil
    ExpandGuildTradeSkillHeader, CollapseGuildTradeSkillHeader, SetGuildRosterShowOffline = nil, nil, nil
    GetGuildRosterShowOffline = function() return true end
    eq(ns.Crafts.ReadGuild(), false, "ohne Spielfunktion nichts")
    wipe(db); W.roster = oldRoster; W.Advance(6)
end)

---------------------------------------------------------------------
local function goal(id, ver, title, progress)
    return msg("GOL", id, ver, "manual", 10, 0, progress or 0, 0, title)
end

test("Gildenziele: nur von Offizieren", function()
    W.Receive("Anna", goal("Anna-1-1", W.server, "Falsch"))
    eq(ns.GuildTable("goals")["Anna-1-1"], nil)
    W.Receive("Anna", goal("Offi-1-1", W.server, "Auch falsch"))
    eq(ns.GuildTable("goals")["Offi-1-1"], nil, "Mitglied allein")
    W.Receive("Offi", goal("Offi-1-1", W.server, "Onyxia"))
    eq(ns.GuildTable("goals")["Offi-1-1"].title, "Onyxia")
end)

test("Gildenziele: Ziel eines Nicht-Offiziers wird nie angenommen", function()
    W.Receive("Offi", goal("Anna-2-2", W.server, "Unterschoben"))
    eq(ns.GuildTable("goals")["Anna-2-2"], nil)
end)

test("Gildenziele: Fortschritt und Erreichen", function()
    local g = ns.GuildTable("goals")["Offi-1-1"]
    W.Receive("Offi", goal("Offi-1-1", W.server + 1, "Onyxia", 10))
    eq(ns.Goals.Progress(g), 10)
    eq(g.doneAt ~= nil, true)
end)

---------------------------------------------------------------------
local function board(id, author, text)
    return msg("BRD", id, W.server, author, W.server, 0, text)
end

test("Schwarzes Brett: nur Offiziere hängen aus", function()
    W.Receive("Anna", board("Anna-1-1", "Anna", "Freibier"))
    eq(ns.Board.Current(), nil)
    W.Receive("Offi", board("Anna-1-2", "Anna", "Freibier"))
    eq(ns.Board.Current(), nil, "Verfasser kein Offizier")
    W.Receive("Offi", board("Offi-1-1", "Offi", "Raid |cffff0000heute|r 20 Uhr"))
    local b = ns.Board.Current()
    eq(b ~= nil, true)
    eq(b.text:find("|", 1, true), nil, "Codes entfernt")
end)

test("Schwarzes Brett: älterer Stand überschreibt nicht", function()
    W.Receive("Offi", msg("BRD", "Offi-0-0", W.server - 500, "Offi", W.server - 500, 0, "Alt"))
    eq(ns.Board.Current().id, "Offi-1-1")
end)

---------------------------------------------------------------------
test("Beitrittsanfrage: Flüstern von Fremden nur an die Gruppensuche", function()
    local got
    ns.OnPublicJoin = function(m, s) got = { m = m, s = s } end
    W.Receive("Fremd", msg("LFJ", "T", "WARRIOR", 60), "WHISPER")
    eq(got and got.s, "Fremd")
    got = nil
    W.Receive("Fremd", goal("Offi-9-9", W.server, "Fremd"), "WHISPER")
    eq(ns.GuildTable("goals")["Offi-9-9"], nil, "andere Arten von Fremden verworfen")
    eq(got, nil)
end)

test("Beitrittsanfrage: weitergeleitet verworfen", function()
    local got = false
    ns.Handlers["LFJ"] = { function() got = true end }
    W.Receive("Bert", msg("FWD", "Carl", "10", msg("LFJ", "T", "WARRIOR", 60)))
    eq(got, false)
end)

---------------------------------------------------------------------
test("Wunschliste: kodieren und begrenzen", function()
    local W2 = ns.Wish
    local s = W2.Encode({ [19019] = 3, [16309] = 1 })
    eq(s, "cl1:1,eob:3")
    local d = W2.Decode(s .. ",zz:9,abc,0:2")
    eq(d[19019], 3); eq(d[16309], 1)
    eq(W2.Count(d), 2, "kaputte Einträge verworfen")
    eq(W2.ItemID("|cffa335ee|Hitem:19019::::::::60:::::|h[Donnerzorn]|h|r"), 19019)
    eq(W2.ItemID("abc"), nil)
end)

test("Wunschliste: eigene Liste ändern und senden", function()
    local W2 = ns.Wish
    W.sent = {}
    eq(W2.Set(19019, 2), true)
    eq(W2.Set(19019, 2), false, "unverändert")
    eq(W2.Mine().i[19019], 2)
    W2.Cycle(19019); eq(W2.Mine().i[19019], 3)
    W2.Cycle(19019); eq(W2.Mine().i[19019], 1)
    W.Advance(5)
    local found
    for _, m in ipairs(W.sent) do if m.kind == "WSH" then found = m end end
    eq(found ~= nil, true, "Liste an die Gilde")
    eq(found.target, nil)
    eq(W2.Set(19019, 0), true)
    eq(W2.Mine().i[19019], nil, "entfernt")
end)

test("Wunschliste: nur die eigene Liste, direkt und von Mitgliedern", function()
    local db = ns.GuildTable("wish")
    W.Receive("Anna", msg("WSH", W.server, "eob:3,cl1:1"))
    eq(db["Anna"].i[19019], 3)
    W.Receive("Anna", msg("WSH", W.server - 100, "eob:1"))
    eq(db["Anna"].i[19019], 3, "älterer Stand überschreibt nicht")
    W.Receive("Bert", msg("FWD", "Carl", "9", msg("WSH", W.server, "eob:3")))
    eq(db["Carl"], nil, "weitergeleitet")
    W.Receive("Fremd", msg("WSH", W.server, "eob:3"), "WHISPER")
    eq(db["Fremd"], nil, "kein Mitglied")
    W.Receive("Bert", msg("WSH", W.server, "eob:1"))
    local who = ns.Wish.Who(19019)
    eq(#who, 2); eq(who[1].name, "Anna", "BiS zuerst"); eq(who[2].name, "Bert")
    local items = ns.Wish.GuildItems()
    eq(items[1].id, 19019); eq(items[1].count, 2); eq(items[1].top, 3)
end)

test("Wunschliste: Tooltip und Drop-Hinweis", function()
    local lines = {}
    local tip = { AddLine = function(_, t) lines[#lines + 1] = t end,
                  AddDoubleLine = function(_, a, b) lines[#lines + 1] = a .. "|" .. b end }
    ns.Wish.AddTooltipLines(tip, 19019)
    eq(#lines, 3, "Kopfzeile + zwei Namen")
    eq(lines[2]:find("Anna", 1, true) ~= nil, true)
    lines = {}
    ns.Wish.AddTooltipLines(tip, 4711)
    eq(#lines, 0, "niemand sucht es")
    -- Drop: nur wer in der Gruppe ist
    local old = ns.DKP.GroupNames
    ns.DKP.GroupNames = function() return { "Bert" } end
    local text = ns.Wish.DropText("|Hitem:19019|h")
    eq(text:find("Bert", 1, true) ~= nil, true)
    eq(text:find("Anna", 1, true), nil, "nicht in der Gruppe")
    ns.DKP.GroupNames = function() return {} end
    eq(ns.Wish.DropText("|Hitem:19019|h"), nil)
    ns.DKP.GroupNames = old
    ns.GuildTable("wish")["Anna"], ns.GuildTable("wish")["Bert"] = nil, nil
end)

test("Tinte: helle Farben werden dunkel, dunkle bleiben", function()
    local Ink = ns.Ink
    Ink.on = true
    local r, g, b = Ink.Color(0.92, 0.90, 0.88)
    eq(r < 0.3 and g < 0.3 and b < 0.3, true, "heller Text -> dunkle Tinte")
    eq((Ink.Color(0.1, 0.2, 0.1)), 0.1, "dunkel bleibt")
    local t = Ink.Text("|cffffd100Gold|r und |cff40ff40grün|r")
    eq(t:find("ffd100", 1, true), nil, "Gold umgerechnet")
    eq(t:find("|r und ", 1, true) ~= nil, true, "Text bleibt")
    Ink.on = false
    eq(Ink.Text("|cffffd100Gold|r"), "|cffffd100Gold|r", "aus = unverändert")
end)
test("Tinte: dunkle Flächen werden im Buch hell", function()
    local Ink = ns.Ink
    local got
    local panel = { SetBackdropColor = function(_, r, g, b, a) got = { r, g, b, a } end }
    Ink.Set(false)
    ns.DarkPanel(panel, 0.07, 0.05, 0.04, 0.97)
    eq(got[1], 0.07, "aus: Originalfarbe")
    Ink.Set(true)
    eq(got[1] > 0.8 and got[2] > 0.8, true, "an: helles Papier")
    local box = { SetBackdropColor = function(_, r) got = { r } end }
    ns.DarkPanel(box, 0, 0, 0, 0.35)
    eq(got[1] > 0.3 and got[1] < 0.6, true, "halbdurchsichtig: Braunton")
    Ink.Set(false)
    eq(got[1], 0, "wieder dunkel")
end)
---------------------------------------------------------------------
-- Kanal-Nachricht so, wie WoW sie meldet: 7. Wert Kanalnummer, 8. Kanalname
local function chan(sender, localID, name, m)
    W.Advance(31)
    W.Fire("CHAT_MSG_ADDON", "GuildPride", m, "CHANNEL", sender, "", 0, localID, name)
end

test("Kanal: nur unser Datenkanal und nur Mitglieder (Fehler aus 2.2.4)", function()
    local db, old = ns.GuildTable("wish"), ns.DataChannelId
    ns.DataChannelId = function() return 5, "GPsabc" end
    chan("Anna", 9, "Fremdkanal", msg("WSH", W.server, "eob:1"))
    eq(db["Anna"], nil, "fremder Kanal")
    chan("Fremd", 5, "GPsabc", msg("WSH", W.server, "eob:1"))
    eq(db["Fremd"], nil, "kein Mitglied")
    chan("Anna", 7, "7. GPsabc", msg("WSH", W.server, "eob:1"))
    eq(db["Anna"] and db["Anna"].i[19019], 1, "Name passt, andere Nummer")
    chan("Bert", 5, "", msg("WSH", W.server, "eob:2"))
    eq(db["Bert"] and db["Bert"].i[19019], 2, "Nummer passt")
    db["Anna"], db["Bert"] = nil, nil
    ns.DataChannelId = nil
    chan("Carl", 5, "GPsabc", msg("WSH", W.server, "eob:1"))
    eq(db["Carl"], nil, "ohne Kanal-Schlüssel nichts")
    ns.DataChannelId = old
end)

test("Mehrteilig (MP): Teile werden zusammengesetzt, auch durcheinander", function()
    local db = ns.GuildTable("wish")
    local full = msg("WSH", W.server, "eob:2")
    W.Receive("Bert", msg("MP", "4242", 2, 2, full:sub(7)))
    eq(db["Bert"], nil, "erst wenn alle Teile da sind")
    W.Receive("Bert", msg("MP", "4242", 1, 2, full:sub(1, 6)))
    eq(db["Bert"] and db["Bert"].i[19019], 2)
    W.Receive("Carl", msg("MP", "4343", 1, 2, full:sub(1, 6)))
    W.Receive("Carl", msg("MP", "4343", 2, 3, full:sub(7)))
    eq(db["Carl"], nil, "Teil mit anderer Anzahl verworfen")
    db["Bert"] = nil
end)

test("Empfang: ein Fehler in einem Modul stoppt die anderen nicht", function()
    local db, list = ns.GuildTable("wish"), ns.Handlers["WSH"]
    table.insert(list, 1, function() error("kaputt") end)
    local oldEH, caught = geterrorhandler, 0
    geterrorhandler = function() return function() caught = caught + 1 end end
    local ok, err = pcall(W.Receive, "Anna", msg("WSH", W.server, "eob:1"))
    geterrorhandler = oldEH
    table.remove(list, 1)
    eq(ok, true, tostring(err))
    eq(caught, 1, "Fehler gemeldet")
    eq(db["Anna"] and db["Anna"].i[19019], 1, "Wunschliste trotzdem übernommen")
    db["Anna"] = nil
end)

---------------------------------------------------------------------
test("Datensicherung: sichern und Daten bleiben", function()
    W.Load("GuildPrideBackup.lua")
    GuildPrideDB.testWert = 42
    eq(ns.BackupNow("Hand"), true)
    eq(#GuildPrideBackupDB.snaps, 1)
    eq(GuildPrideBackupDB.snaps[1].data.testWert, 42)
    GuildPrideDB.testWert = 1
    eq(GuildPrideBackupDB.snaps[1].data.testWert, 42, "Kopie, keine Referenz")
end)

---------------------------------------------------------------------
test("Discord: schnelles Umentscheiden ergibt nur eine Zeile", function()
    SlashCmdList.GUILDPRIDE = SlashCmdList.GUILDPRIDE or function() end
    W.Load("GuildPrideDiscord.lua")
    local D = ns.Discord
    GuildPrideDB.discordBridge, GuildPrideDB.discordLinked = true, true
    local out, old = {}, C_ChatInfo.SendChatMessage
    C_ChatInfo.SendChatMessage = function(text, kind) if kind == "GUILD" then out[#out + 1] = text end end
    D.Post("Tester: Zusage #abcde Kara (Tank)", true)
    D.Post("Tester: Vielleicht #abcde Kara", true)
    D.Post("Tester: Absage #abcde Kara", true)
    D.Flush()
    eq(#out, 0, "Anmeldung wird kurz zurückgehalten")
    W.Advance(11)
    D.Flush()
    eq(#out, 1, "nur die letzte Anmeldung")
    eq(out[1], "[GP] Tester: Absage #abcde Kara")
    D.Post("Neues Event #fghij: Ony – 20.11. 20:00 (t=1)", true)
    eq(#out, 2, "andere Zeilen sofort")
    C_ChatInfo.SendChatMessage = old
    GuildPrideDB.discordBridge, GuildPrideDB.discordLinked = nil, nil
end)

test("Discord: Ersteller gibt fremde Anmeldung weiter, außer sie ist schon in Discord", function()
    local D = ns.Discord
    GuildPrideDB.discordBridge, GuildPrideDB.discordLinked = true, true
    local oldNames = LOCALIZED_CLASS_NAMES_MALE
    LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Krieger" }
    local oldRoster = W.roster
    W.roster = { { W.me, 3 }, { "Anna", 2 } }
    local out, old = {}, C_ChatInfo.SendChatMessage
    C_ChatInfo.SendChatMessage = function(text, kind) if kind == "GUILD" then out[#out + 1] = text end end
    local e = { id = "Tester-1-2", title = "Kara", signups = { Anna = { s = "yes", v = 1, r = "DAMAGER" } } }
    D.RelaySign(e, "Anna", e.signups.Anna)
    W.Advance(11); D.Flush()
    eq(#out, 1, "weitergegeben")
    eq(out[1], ("[GP] Anna: %s #%s Kara (%s, Krieger)"):format(D.DE and "Zusage" or "Attending", D.ShortId(e.id), D.DE and "DD" or "DPS"))
    -- schon im Kanal gesehen (Anna hat selbst gesendet): nichts doppelt
    D._SignSeen[out[1]] = GetTime()
    D.RelaySign(e, "Anna", e.signups.Anna)
    W.Advance(11); D.Flush()
    eq(#out, 1, "nicht doppelt")
    -- eigene Anmeldung wird nie weitergegeben, ohne Anbindung nichts
    D.RelaySign(e, ns.Me(), { s = "yes", v = 1 })
    GuildPrideDB.discordBridge = false
    D._SignSeen[out[1]] = nil
    D.RelaySign(e, "Anna", e.signups.Anna)
    GuildPrideDB.discordBridge = true
    W.Advance(11); D.Flush()
    eq(#out, 1, "nichts weiter")
    C_ChatInfo.SendChatMessage = old
    LOCALIZED_CLASS_NAMES_MALE = oldNames
    W.roster = oldRoster
    GuildPrideDB.discordBridge, GuildPrideDB.discordLinked = nil, nil
end)

---------------------------------------------------------------------
test("Discord: getrennter Kanal ohne Ausweichen in /g, Offiziers-Zeilen nur von Offizieren weitergeben", function()
    local D = ns.Discord
    GuildPrideDB.discordBridge, GuildPrideDB.discordLinked = true, true
    -- Getrennter Discord-Kanal, der Zeilen annimmt, aber nie zurückliefert
    local streamSent, guildSent = {}, {}
    C_GuildInfo = { IsDiscordStreamSeparate = function() return true end }
    Enum = { ClubStreamType = { Discord = 5 } }
    C_Club = { GetGuildClubId = function() return 1 end, GetStreams = function() return { { streamType = 5, streamId = 9 } } end,
        SendMessage = function(_, _, text) streamSent[#streamSent + 1] = text end }
    local old = C_ChatInfo.SendChatMessage
    C_ChatInfo.SendChatMessage = function(text, kind) if kind == "GUILD" then guildSent[#guildSent + 1] = text end end
    local timers = {}
    local oldAfter = C_Timer.After
    C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
    ns.VERSION = "2.20.0"
    D.Post("Offi: Test 1", true)
    D.Post("Offi: Test 2", true)
    eq(#streamSent, 3, "zuerst über den Discord-Kanal, dazu einmal die Version")
    eq(streamSent[2], "[GP] V 2.20.0")
    eq(GuildPrideDB.discord.verSent, "2.20.0")
    eq(#guildSent, 0)
    for _, fn in ipairs(timers) do fn() end
    D.Flush()
    eq(#guildSent, 0, "getrennter Discord-Chat: nie in den Gildenchat ausweichen")
    -- Kanal nicht erreichbar: auch dann nicht in den Gildenchat
    local sendOk = C_Club.SendMessage
    C_Club.SendMessage = function() error("blockiert") end
    D.Post("Offi: Test 3", true)
    eq(#guildSent, 0, "kein Ausweichen bei Fehler")
    C_Club.SendMessage = sendOk
    -- Nicht getrennt: Gildenchat ist der normale Weg
    C_GuildInfo.IsDiscordStreamSeparate = function() return false end
    -- Weitergabe: DKP eines Offiziers nur, wenn ich selbst Offizier bin (Tester ist keiner)
    local before = #guildSent
    W.Receive("Offi", "DRL:[GP] DKP #abc123 +10 Test: Anna", "GUILD")
    for _, fn in ipairs(timers) do fn() end
    D.Flush()
    eq(#guildSent, before, "Nicht-Offizier gibt DKP nicht weiter")
    W.Receive("Anna", "DRL:[GP] Anna: Test 3", "GUILD")
    for _, fn in ipairs(timers) do fn() end
    D.Flush()
    eq(guildSent[#guildSent], "[GP] Anna: Test 3", "normale Zeilen werden weitergegeben")
    eq(D.OfficerLine("[GP] Umfrage #abcde: Frage – a | b"), true)
    eq(D.OfficerLine("[GP] Anna: Zusage #abcde Kara"), false)
    C_ChatInfo.SendChatMessage, C_Timer.After = old, oldAfter
    C_Club, C_GuildInfo, Enum = nil, nil, nil
    GuildPrideDB.discordBridge, GuildPrideDB.discordLinked = nil, nil
end)

---------------------------------------------------------------------
test("Discord: Blizzard-Meldung nach eigener Zeile -> nicht verknüpft, Zeile über Mitglied", function()
    local D = ns.Discord
    GuildPrideDB.discordBridge, GuildPrideDB.discordLinked, GuildPrideDB.discordViaGuild = true, true, true
    local old, oldAddon = C_ChatInfo.SendChatMessage, ns.SendAddonMsg
    local relayed
    C_ChatInfo.SendChatMessage = function() end
    ns.SendAddonMsg = function(_, msg) relayed = msg end
    D.Post("Neues Event #zzzzz: X – 1.1. 20:00 (t=1)", true)
    W.Fire("CHAT_MSG_SYSTEM", "Irgendwas anderes")
    eq(GuildPrideDB.discordLinked, true, "fremde Meldung ändert nichts")
    W.Fire("CHAT_MSG_SYSTEM", "Verknüpfe dein Discord-Konto, um im Discord-Kanal zu schreiben.")
    eq(GuildPrideDB.discordLinked, false)
    eq(relayed, "DRL:[GP] Neues Event #zzzzz: X – 1.1. 20:00 (t=1)", "Zeile über ein Mitglied nachgeholt")
    -- Später kommt keine Meldung mehr durch (Zeitfenster vorbei)
    GuildPrideDB.discordLinked = true
    W.Advance(5)
    W.Fire("CHAT_MSG_SYSTEM", "Discord …")
    eq(GuildPrideDB.discordLinked, true, "nur direkt nach dem Senden")
    C_ChatInfo.SendChatMessage, ns.SendAddonMsg = old, oldAddon
    GuildPrideDB.discordBridge, GuildPrideDB.discordLinked, GuildPrideDB.discordViaGuild = nil, nil, nil
end)

test("Discord: wartende Zeilen überleben das Ausloggen, alte verfallen", function()
    local D = ns.Discord
    GuildPrideDB.discordBridge, GuildPrideDB.discordLinked = true, true
    D.Post("Tester: Zusage #qqqqq Ony (Tank)", true)   -- wird zurückgehalten
    eq(#D.Pending(), 1)
    W.Fire("PLAYER_LOGOUT")
    eq(#GuildPrideDB.discord.pending, 1, "gespeichert")
    table.insert(GuildPrideDB.discord.pending, { t = time() - 7 * 3600, text = "[GP] alt" })
    for i = #D.Pending(), 1, -1 do table.remove(D.Pending(), i) end
    W.Fire("PLAYER_LOGIN")
    eq(#D.Pending(), 1, "nur die junge Zeile kommt zurück")
    eq(D.Pending()[1], "[GP] Tester: Zusage #qqqqq Ony (Tank)")
    eq(GuildPrideDB.discord.pending, nil)
    for i = #D.Pending(), 1, -1 do table.remove(D.Pending(), i) end
    GuildPrideDB.discordBridge, GuildPrideDB.discordLinked = nil, nil
end)

test("Discord: alte Einstellungen werden zu Schaltern", function()
    GuildPrideDB.discord = { via = "guild", showRaw = true }
    GuildPrideDB.discordViaGuild, GuildPrideDB.discordShowRaw = nil, nil
    W.Fire("PLAYER_LOGIN")
    eq(GuildPrideDB.discordViaGuild, true)
    eq(GuildPrideDB.discordShowRaw, true)
    eq(GuildPrideDB.discord.via, nil)
    GuildPrideDB.discordViaGuild, GuildPrideDB.discordShowRaw = nil, nil
end)

test("Dungeon/Raid: Liste, Rollen und Discord-Zeile für den Bot", function()
    W.Load("GuildPrideInstances.lua")
    local I = ns.Instances
    eq(I.Find("raid", "ony").size, 40)
    eq(I.Find("dungeon", "dm").size, 5)
    eq(I.Find("raid", "dm"), nil, "Schlüssel nur in der passenden Art")
    eq(I.Find("raid", "naxx"), nil)
    eq(#I.list.dungeon, 33); eq(#I.list.raid, 3)
    local n = I.Need(40)
    eq(n.TANK, 4); eq(n.HEALER, 10); eq(n.DAMAGER, 26)
    local D = ns.Discord
    local lines, old = {}, D.Post
    D.Post = function(text) lines[#lines + 1] = text end
    D.EventCreated({ id = "Ich-1-1", title = "Raid: Onyxia", t = 1795000000, rep = 7, kind = "raid", inst = "ony", desc = "" })
    D.EventCreated({ id = "Ich-1-2", title = "Kara", t = 1795000000 })
    D.EventCreated({ id = "Ich-1-3", title = "X", t = 1795000000, kind = "raid", inst = "naxx" })
    D.Post = old
    assert(lines[1]:find(") – [raid=ony]", 1, true), lines[1])
    assert(lines[1]:sub(-10) == "[raid=ony]", "ohne Beschreibung endet die Zeile mit dem Zusatz")
    assert(not lines[2]:find("raid=", 1, true) and not lines[2]:find("dungeon=", 1, true), "normales Event ohne Zusatz")
    assert(not lines[3]:find("naxx", 1, true), "unbekannte Instanz wird nicht gemeldet")
end)

require("ah")(test, eq, W, ns)
require("transit")(test, eq, W, ns)
require("flight")(test, eq, W, ns)
require("invite")(test, eq, W, ns)
require("board")(test, eq, W, ns)
require("itemid")(test, eq, W, ns)
require("players")(test, eq, W, ns)
require("more")(test, eq, W, ns)
require("buffs")(test, eq, W, ns)
require("zettel")(test, eq, W, ns)

test("Gruppensuche: Dungeon-Auswahl filtert Gruppen aus dem Dungeonbrowser", function()
    local match = ns.BrowserDungeonMatch
    eq(match({ "Die Todesminen" }, nil), true, "nichts gewählt = alle")
    eq(match({ "Die Todesminen" }, { ["Die Todesminen"] = true }), true)
    eq(match({ "Das Verlies", "Die Todesminen" }, { ["Die Todesminen"] = true, ["Scholomance"] = true }), true,
        "eine von mehreren Aktivitäten reicht")
    eq(match({ "Das Verlies" }, { ["Die Todesminen"] = true }), false)
    eq(match(nil, { ["Die Todesminen"] = true }), false, "ohne Dungeon nicht zeigen, wenn gefiltert")
end)

test("Blockliste: Offiziere sperren, alle gleichen ab, Fremde dürfen nichts ändern", function()
    W.Load("GuildPrideBlock.lua")
    local B = ns.Block
    local oldMotd, oldIsOff = W.canMotd, ns.IsOfficerName
    ns.IsOfficerName = function(n) return n == "Offi" end   -- Rangrechte hier fest vorgeben
    W.canMotd = false
    eq(select(2, B.Add("Böse", "Spam")), "recht", "kein Offizier: nicht erlaubt")
    W.canMotd = true
    W.sent = {}
    eq(B.Add("Böse", "Spam im Chat"), true)
    eq(B.IsBlocked("Böse") ~= nil, true); eq(B.IsBlocked("böse") ~= nil, true, "ohne Groß/klein")
    eq(B.IsBlocked("Böse").reason, "Spam im Chat")
    local sent = false
    for _, m in ipairs(W.sent) do if m.kind == "BLK" then sent = true end end
    eq(sent, true, "an die Gilde geschickt")
    eq(B.Refuse("Böse"), true, "Einladen wird abgelehnt"); eq(B.Refuse("Anna"), false)
    -- Eintrag von einem Offizier wird übernommen, von einem normalen Mitglied nicht
    W.Receive("Offi", "BLK:Troll\031" .. (GetServerTime() + 5) .. "\031Offi\0310\031Beleidigungen")
    eq(B.IsBlocked("Troll") ~= nil, true, "vom Offizier übernommen")
    W.Receive("Anna", "BLK:Unschuldig\031" .. (GetServerTime() + 5) .. "\031Anna\0310\031")
    eq(B.IsBlocked("Unschuldig"), nil, "von Nicht-Offizier ignoriert")
    -- entfernen
    eq(B.Remove("Böse"), true); eq(B.IsBlocked("Böse"), nil)
    eq(#B.List(), 1)
    -- Namen mit Leerzeichen in Anführungszeichen
    local n, r = B.ParseArgs('"Vor Nachname" weil Spam'); eq(n, "Vor Nachname"); eq(r, "weil Spam")
    n, r = B.ParseArgs("Einzel Grund"); eq(n, "Einzel"); eq(r, "Grund")
    -- Zeichen am Namen: rotes X für gesperrt (überall, wo GuildPride Namen zeigt)
    eq(B.Marks("Troll"):find("UI-GroupLoot-Pass-Up", 1, true) ~= nil, true, "gesperrt: Zeichen")
    eq(B.Marks("Anna"), "", "nicht gesperrt: nichts")
    eq(ns.NameMark("Troll"):find("UI-GroupLoot-Pass-Up", 1, true) ~= nil, true, "über ns.NameMark")
    B.Remove("Troll")
    W.canMotd, ns.IsOfficerName = oldMotd, oldIsOff
end)

test("Chat: Symbol steht vor dem Namen, die Nachricht bleibt unverändert", function()
    local oldGCN, oldUtil, oldMarked = GetColoredName, ChatFrameUtil, ns.IsMarked
    ChatFrameUtil = nil
    GetColoredName = function(_, _, author) return author end
    local filters = {}
    local oldAdd = ChatFrame_AddMessageEventFilter
    ChatFrame_AddMessageEventFilter = function(e, fn) filters[#filters + 1] = e end
    W.Load("GuildPrideMarks.lua")
    ns.IsMarked = function(a) return a == "Gm" end
    eq(#filters, 0, "kein Chat-Filter mehr, der den Text umschreibt")
    eq(GetColoredName("CHAT_MSG_GUILD", "hallo", "Gm"):find("^|T") ~= nil, true, "Symbol vor dem Namen")
    eq(GetColoredName("CHAT_MSG_GUILD", "hallo", "Anna"), "Anna", "andere unverändert")
    eq(GetColoredName("CHAT_MSG_SYSTEM", "x", "Gm"), "Gm", "nur Chat-Nachrichten von Spielern")
    GetColoredName, ChatFrameUtil, ns.IsMarked, ChatFrame_AddMessageEventFilter = oldGCN, oldUtil, oldMarked, oldAdd
end)

test("Notizen zu Spielern: speichern, lesen, löschen – nur lokal", function()
    W.Load("GuildPrideNotes.lua")
    W.sent = {}
    eq(ns.SetPlayerNote("Anna", "guter Heiler"), true)
    eq(ns.PlayerNote("Anna"), "guter Heiler")
    eq(ns.SetPlayerNote("Anna", "  "), true); eq(ns.PlayerNote("Anna"), nil, "leer löscht")
    eq(ns.SetPlayerNote("Bert", "x|cffff0000rot"), true); eq(ns.PlayerNote("Bert"):find("|", 1, true), nil, "keine Farbcodes")
    eq(#W.sent, 0, "nichts verschickt")
    ns.SetPlayerNote("Bert", "")
end)

test("Übersetzungen: jeder Text im Code hat eine englische Fassung", function()
    local function read(p)
        local f = io.open(p, "rb")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end
    local loc = read("Core/GuildPrideLocale.lua")
    local keys = {}
    for k in loc:gmatch('%["(.-)"%]%s*=') do keys[k] = true end
    local missing = {}
    for line in io.lines("GuildPrideForever.toc") do
        local path = line:gsub("\r", ""):gsub("\\", "/")
        if path:match("%.lua$") and not path:find("^#") and not path:find("GuildPrideLocale") then
            local s = read(path)
            for k in (s or ""):gmatch('%f[%w_]L%["(.-)"%]') do
                -- zusammengesetzte Schlüssel (L["ROLE_" .. x]) kann der Test nicht prüfen
                if not keys[k] and not k:find("\"", 1, true) then missing[#missing + 1] = path .. ": " .. k end
            end
        end
    end
    eq(#missing, 0, "ohne Übersetzung: " .. table.concat(missing, " | "))
end)

test("AH-Tooltip: historischer Preis aus den letzten Tagen", function()
    local AH = ns.AH
    local now = math.floor(W.server)
    for d = 1, 3 do AH.RecordOwn("40001", 100 * d, 1, now - (4 - d) * 86400) end   -- 100c, 200c, 300c
    local h = AH.TooltipHistory("|Hitem:40001:0:0:0:0:0:0:0|h")
    eq(h ~= nil, true, "Verlauf ab zwei Tagen")
    eq(h:find("Verlauf (3 Tage)", 1, true) ~= nil, true)
    eq(h:find("Tief " .. AH.Money(100), 1, true) ~= nil, true); eq(h:find("Hoch " .. AH.Money(300), 1, true) ~= nil, true)
    eq(h:find(AH.Money(200), 1, true) ~= nil, true, "Durchschnitt")
    eq(AH.TooltipHistory("|Hitem:40002:0:0:0:0:0:0:0|h"), nil, "ohne Verlauf keine Zeile")
end)

test("AH-Verlauf: Tagespreise anderer Spieler füllen nur fehlende Tage", function()
    local AH = ns.AH
    local today = math.floor(W.server / 86400)
    AH.RecordOwn("40010", 500, 1, today * 86400 + 100)                  -- heute selbst gesehen: 500c
    local msg = AH.EncodeH("A", "40010", { { d = today - 2, p = 300 }, { d = today - 1, p = 400 }, { d = today, p = 1 } })
    eq(msg:sub(1, 2), "H:"); eq(#msg <= 250, true, "passt in eine Nachricht")
    local side, key, list = AH.DecodeH(msg)
    eq(side, "A"); eq(key, "40010"); eq(#list, 3)
    eq(AH.MergeHistory(key, list), 2, "zwei fremde Tage neu")
    local h = AH.History("40010")
    eq(#h, 3); eq(h[3].p, 500, "eigener Tag bleibt (nicht durch fremde 1c ersetzt)")
    eq(h[1].d, today - 2, "nach Tag sortiert")
    eq(select(3, AH.DecodeH("H:A:40010:1,5")) and #select(3, AH.DecodeH("H:A:40010:1,5")), 0, "uralte Tage verworfen")
end)

test("AH-Tooltip: Händlerpreis, Herstellkosten und einzeln abschaltbare Zeilen", function()
    local AH = ns.AH
    local now = math.floor(W.server)
    W.itemInfo[40020] = { quality = 1, bindType = 0, classID = 7, sellPrice = 50 }
    AH.RecordOwn("40020", 40, 1, now)   -- 40c im AH, nach 5 % Gebühr 38c < 50c beim Händler
    local v = AH.TooltipVendor("|Hitem:40020:0:0:0:0:0:0:0|h", 1)
    eq(v ~= nil and v:find("Händler", 1, true) ~= nil, true)
    eq(v:find("lieber beim Händler", 1, true) ~= nil, true, "Händler zahlt mehr")
    GuildPrideDB.ahCraft = { [40021] = { made = 1, r = { { 40020, 2 } } } }
    AH.RecordOwn("40021", 200, 1, now)
    local info = AH.CraftInfo(40021)
    eq(info.cost, 80); eq(info.profit, 110, "200 × 0,95 − 80")
    eq(AH.TooltipCraft("|Hitem:40021:0:0:0:0:0:0:0|h"):find("Gewinn", 1, true) ~= nil, true)
    GuildPrideDB.ahTipVendor, GuildPrideDB.ahTipCraft = false, false
    eq(AH.TooltipVendor("|Hitem:40020:0:0:0:0:0:0:0|h", 1), nil, "Händler-Zeile abgeschaltet")
    eq(AH.TooltipCraft("|Hitem:40021:0:0:0:0:0:0:0|h"), nil, "Herstell-Zeile abgeschaltet")
    GuildPrideDB.ahTipVendor, GuildPrideDB.ahTipCraft, GuildPrideDB.ahCraft = nil, nil, nil
end)

test("Gilde unterwegs: Zonen aus der Gildenliste als Dungeon oder Raid erkennen", function()
    local I = ns.Instances
    eq(I.ByZone("Die Todesminen").key, "dm"); eq(I.ByZone("The Deadmines").key, "dm", "auch englisch")
    eq(I.ByZone("Onyxias Hort").kind, "raid")
    eq(I.ByZone("Scharlachrotes Kloster") ~= nil, true, "Flügel über den Oberbegriff")
    eq(I.ByZone("Sturmwind"), nil, "Stadt ist keine Instanz")
    local oldInfo, oldRoster = GetGuildRosterInfo, W.roster
    W.roster = { { "Anna", 3 }, { "Bert", 3 }, { "Carl", 3 }, { "Dora", 3, 60, false } }
    local zones = { "Die Todesminen", "Die Todesminen", "Sturmwind", "Die Todesminen" }
    GetGuildRosterInfo = function(i)
        local m = W.roster[i]
        if not m then return nil end
        return m[1], "", m[2], 60, "Krieger", zones[i], "", "", m[4] ~= false
    end
    local road = I.GuildInInstances()
    eq(#road, 1); eq(road[1].inst.key, "dm"); eq(#road[1].names, 2, "offline zählt nicht")
    GetGuildRosterInfo, W.roster = oldInfo, oldRoster
end)

test("Preisalarm: auch mit Preisen anderer GuildPride-Spieler", function()
    local AH = ns.AH
    local printed, oldPrint, oldOpen = {}, AH.Print, AH.IsOpen
    AH.Print = function(t) printed[#printed + 1] = t end
    AH.IsOpen = function() return false end
    AH.SetAlert(13468, 20000)
    AH.RecordServer("13468", 15000, 1, GetServerTime(), "Anna")
    local hit = false
    for _, t in ipairs(printed) do if t:find("von anderen GuildPride", 1, true) then hit = true end end
    eq(hit, true, "geteilter Preis unter dem Alarm meldet sich")
    printed = {}
    AH.SetAlert(13469, 10000)
    AH.RecordServer("13469", 15000, 1, GetServerTime(), "Anna")
    eq(#printed, 0, "teurer als der Alarm: still")
    -- Übersicht: Treffer zuerst, mit zuletzt bekanntem Preis
    local ov = AH.AlertOverview()
    eq(#ov, 2); eq(ov[1].id, 13468, "Treffer zuerst"); eq(ov[1].hit, true); eq(ov[1].price, 15000)
    eq(ov[2].hit, false, "teurer: kein Treffer")
    AH.SetAlert(13468, nil); AH.SetAlert(13469, nil)
    AH.Print, AH.IsOpen = oldPrint, oldOpen
end)

test("/gp preis: Gegenstand und Preis aus dem Chat-Text", function()
    local P = ns.AH.ParsePriceArgs
    local item, copper, off = P("Schwarzer Lotus 1g 50s")
    eq(item, "Schwarzer Lotus"); eq(copper, 15000); eq(off, false)
    item, copper = P("13467 2,5"); eq(item, "13467"); eq(copper, 25000)
    item, copper, off = P("Schwarzer Lotus aus"); eq(item, "Schwarzer Lotus"); eq(copper, nil); eq(off, true)
    item, copper = P("|cff1eff00|Hitem:13467::::|h[Schwarzer Lotus]|h|r 75s")
    eq(item:find("Hitem:13467", 1, true) ~= nil, true); eq(copper, 7500)
    item, copper = P("Schwarzer Lotus"); eq(item, "Schwarzer Lotus"); eq(copper, nil, "ohne Preis: nur nachsehen")
    eq(P(""), nil, "leer: Liste")
end)

test("Meilensteine: Filter nach Art und Spielername", function()
    local m = ns.MilestoneMatch
    local lvl = { kind = "LEVEL", who = "Anna", value = 60 }
    local boss = { kind = "BOSS", who = "Bert", value = 1 }
    local join = { kind = "JOIN", who = "Cora" }
    eq(m(lvl, "all", ""), true); eq(m(boss, "all", ""), true)
    eq(m(lvl, "level", ""), true); eq(m(boss, "level", ""), false)
    eq(m(boss, "boss", ""), true); eq(m(join, "guild", ""), true); eq(m(join, "ach", ""), false)
    eq(m(lvl, "all", "an"), true, "Teil des Namens, ohne Groß/klein")
    eq(m(boss, "all", "an"), false)
end)

test("/gp diag: Bericht entsteht ohne Fehler und nennt den Realm", function()
    W.Load("GuildPrideDiag.lua")
    local text = ns.DiagReport()
    eq(type(text), "string")
    eq(text:find("GetRealmName", 1, true) ~= nil, true)
    eq(text:find("== Dungeonbrowser ==", 1, true) ~= nil, true)
    eq(text:find("== Andere Addons ==", 1, true) ~= nil, true, "Abschnitt andere Addons")
end)

test("Meilensteine: Abgleich fragt auch nach älteren Einträgen (MHO)", function()
    local log = ns.GuildLog()
    local saved = {}
    for i, e in ipairs(log) do saved[i] = e end
    for i = #log, 1, -1 do log[i] = nil end
    local now = math.floor(W.server)
    log[1] = { kind = "LEVEL", who = "Anna", value = 60, t = now - 100 }
    log[2] = { kind = "LEVEL", who = "Anna", value = 50, t = now - 5000 }
    W.sent = {}
    ns.RequestHistory()
    local mho
    for _, m in ipairs(W.sent) do if m.kind == "MHO" then mho = m end end
    eq(mho ~= nil, true, "fragt nach Älterem")
    eq(mho.msg:match("^MHO:(%d+)"), tostring(now - 5000), "vor dem eigenen ältesten")
    for i = #log, 1, -1 do log[i] = nil end
    for i, e in ipairs(saved) do log[i] = e end
end)

test("Hotfix 20.11.2026: ohne Realm-Namen bleiben die Gildendaten beim alten Realm", function()
    local oldGI, oldRN, oldNRN = GetGuildInfo, GetRealmName, GetNormalizedRealmName
    local oldName, oldNorm, oldGuilds = GuildPrideDB.realmName, GuildPrideDB.realmNorm, GuildPrideDB.guilds
    GetGuildInfo = function() return "Testgilde", "Rang", 3, nil end
    GetRealmName = function() return "" end
    GetNormalizedRealmName = function() return "" end
    GuildPrideDB.realmName, GuildPrideDB.realmNorm = nil, nil
    -- alter Stand unter dem echten Realm, seit dem Hotfix ein zweiter unter „Testgilde@“
    GuildPrideDB.guilds = {
        ["Testgilde@CAMWOWEU4Realm7PvE"] = { log = {
            { kind = "LEVEL", who = "Anna", value = 60, t = 100 },
            { kind = "JOIN", who = "Bert", t = 50 },
        }, events = { a = { title = "Alt" } } },
        ["Testgilde@"] = { log = {
            { kind = "LEVEL", who = "Cora", value = 40, t = 300 },
            { kind = "LEVEL", who = "Anna", value = 60, t = 200 },   -- neu abgeglichen, später gesehen
        }, events = { a = { title = "Neu" }, b = { title = "Zweites" } } },
    }
    eq(ns.GuildId(), "Testgilde@CAMWOWEU4Realm7PvE", "Realm aus den gespeicherten Daten")
    eq(GuildPrideDB.guilds["Testgilde@"], nil, "Daten ohne Realm zusammengeführt")
    local g = GuildPrideDB.guilds["Testgilde@CAMWOWEU4Realm7PvE"]
    eq(#g.log, 3, "doppelter Meilenstein nur einmal")
    eq(g.log[1].who, "Cora", "neueste zuerst")
    for _, e in ipairs(g.log) do if e.who == "Anna" then eq(e.t, 100, "frühester Zeitpunkt bleibt") end end
    eq(g.events.a.title, "Neu", "neuerer Stand gewinnt"); eq(g.events.b.title, "Zweites")
    eq(GuildPrideDB.realmNorm, "CAMWOWEU4Realm7PvE", "Realm gemerkt")
    -- liefert das Spiel den Realm wieder, wird er gemerkt
    GetRealmName = function() return "CAMWOW EU4 Realm 7 PvE" end
    eq(ns.RealmName(), "CAMWOW EU4 Realm 7 PvE"); eq(ns.RealmName(true), "CAMWOWEU4Realm7PvE")
    GetGuildInfo, GetRealmName, GetNormalizedRealmName = oldGI, oldRN, oldNRN
    GuildPrideDB.realmName, GuildPrideDB.realmNorm, GuildPrideDB.guilds = oldName, oldNorm, oldGuilds
end)

print(("\n%d bestanden, %d fehlgeschlagen"):format(passed, failed))
if failed > 0 then os.exit(1) end
