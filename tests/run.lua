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

print(("\n%d bestanden, %d fehlgeschlagen"):format(passed, failed))
if failed > 0 then os.exit(1) end
