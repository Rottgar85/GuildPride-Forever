-- GuildPride Rares: feste Daten
local ADDON, GP = ...
-- Rare-Scanner läuft in einem eigenen Unter-Namensraum, damit sich nichts mit GuildPride beißt
GP.Rares = GP.Rares or {}
local ns = GP.Rares

-- Weltbosse (NPC-ID). Vanilla: Erscheinen zufällig nach Tagen – die Fenster
-- sind Schätzungen und lassen sich im Spiel nicht genau bestimmen.
-- min/max in Stunden nach dem letzten bekannten Tod.
ns.WORLD_BOSSES = {
    [6109]  = { name = "Azuregos",          min = 72, max = 168 },
    [12397] = { name = "Lord Kazzak",       min = 72, max = 168 },
    [14887] = { name = "Ysondre",           min = 72, max = 168 },
    [14888] = { name = "Lethon",            min = 72, max = 168 },
    [14889] = { name = "Emeriss",           min = 72, max = 168 },
    [14890] = { name = "Taerar",            min = 72, max = 168 },
}

ns.FRESH      = 300   -- s: so lange gilt eine Sichtung als aktuell (Kartenpunkt, Alarm)
ns.CONFIRM    = 2     -- so viele verschiedene Spieler = "bestätigt"
