# Plan: Spieler-Ausweis und automatische Twink-Erkennung (2.5.0)

Ziel: GuildPride erkennt automatisch, welche Charaktere in der Gilde demselben
Spieler gehören, egal mit welchem Charakter er der Gilde beitritt. In der
Mitgliederliste erscheint jeder Spieler einmal (Main), seine Twinks sind darunter
eingeklappt. Dazu wird die Bedienung einfacher: weniger Reiter, weniger Menüs,
mehr per Tooltip und Rechtsklick (Kritik an GRM: „zu viele Menüs“).

## Ist-Stand (kurz)

- Mitgliederliste: `GuildPrideUI.lua` (`GuildData`, `MemberData`,
  `members:Refresh`, kompakte Liste `roster:Refresh`), Verwaltung per Klick in
  `GuildPrideManage.lua`.
- Nachrichten: Präfix `GuildPride`, Format `ART:feld\031feld…`, Versand über die
  Warteschlange `ns.Queue` (`GuildPrideEvents.lua`), Empfang und Verteilung in
  `GuildPride.lua` (`Dispatch`, Handler per `ns.On("ART", fn)`), Anfragen mit
  Drossel über `ASKS`.
- Gildendaten je Gilde: `ns.GuildTable(feld)` → `GuildPrideDB.guilds["Gilde@Realm"]`.
- `GuildPrideDB` ist **accountweit** (`## SavedVariables`), gilt also für alle
  Charaktere auf diesem WoW-Account.
- Addons können keine Gildennotizen schreiben (siehe Kopf von
  `GuildPrideManage.lua`). Twink-Daten können daher nicht in der Offiziersnotiz
  landen, sondern nur in den Addon-Daten.
- Früher gab es „BattleTags in der Offiziersnotiz“ (1.3.0), in 1.4 entfernt.
  Grund vor dem Bau klären (siehe offene Fragen).
- Reiter heute (8): Übersicht, Gilde & Chat, Events, Gruppensuche, Umfragen,
  Meilensteine, Gildeninfo, Einstellungen. Ein- und Ausblenden und Reihenfolge
  gibt es schon.

## 1. Der Ausweis

**Quelle:** der eigene BattleTag (`BNGetInfo()` → 2. Rückgabewert, auf Forever
vor dem Bau prüfen). Er ist für alle Charaktere eines Spielers gleich, auch über
mehrere WoW-Accounts unter einem Battle.net-Konto. Fremde BattleTags kann ein
Addon nicht lesen (nur von Battle.net-Freunden), deshalb meldet jeder nur seinen
eigenen.

**Kein Klartext:** Der BattleTag wird nie gesendet. Gesendet wird ein Code:

```
ausweis = Hash(BattleTag .. "\031" .. GuildId())   -- 2 × 32-Bit, als 14 Zeichen Base36
```

- Pro Gilde ein anderer Code: Zwei Gilden können denselben Spieler nicht
  miteinander abgleichen.
- Hash in reinem Lua (z. B. FNV-1a zweimal mit verschiedenen Startwerten).
  Ehrlich: Das ist kein kryptografischer Schutz. Wer gezielt einen bestimmten
  BattleTag ausprobiert, kann ihn bestätigen. Es verhindert aber, dass
  BattleTags in der Gilde einfach lesbar herumgehen, und das ist das Ziel.
- Kein BattleTag verfügbar (Fehler, kein Battle.net): Ausweis = zufällige ID,
  einmal erzeugt und in `GuildPrideDB.ausweisFallback` gespeichert (gilt dann
  nur für diesen WoW-Account).

**Einstellung:** „Meine Charaktere automatisch verknüpfen“ (Standard an). Aus =
es wird kein Ausweis gesendet, der Spieler bleibt nur manuell zuordenbar.

## 2. Nachrichten

| Art     | Inhalt                                   | Ziel        | Wann |
|---------|------------------------------------------|-------------|------|
| `AUS`   | ausweis, main (Name oder leer), ver      | Gilde       | Login, Gildenbeitritt, Main geändert |
| `AUSQ`  | –                                        | Gilde       | einmal nach dem Login (Liste holen), in `ASKS` gedrosselt |
| `AUSL`  | Liste `Name=ausweis=main;…` (mehrteilig) | Flüstern    | Antwort auf `AUSQ`, zufällig 2–8 s verzögert, nur einer antwortet (wie bei `WEL`) |
| `ALT`   | twink, main, setzer                      | Gilde       | Offizier ordnet von Hand zu oder löst eine Zuordnung |

Annahmeregeln:
- `AUS` gilt nur für den **Absender selbst**: Ein Charakter kann nur sich selbst
  einem Ausweis zuordnen, nie jemand anderen.
- `ALT` wird nur angenommen, wenn der Absender laut Gildenliste einen Rang
  höchstens so hoch wie der eingestellte Offiziersrang hat (Rangnummer aus
  `GetGuildRosterInfo`): nur Rang 0 (Gildenleitung) und 1 (Offiziere).
- Eine von Hand gesetzte Offiziers-Zuordnung hat Vorrang vor `AUS`. Löst ein
  Offizier sie, gilt wieder der Ausweis.
- Nachrichten von Nicht-Mitgliedern verwirft schon `CHAT_MSG_ADDON`.

## 3. Speicher

```lua
-- ns.GuildTable("ausweis")
chars = { ["Name"] = { a = "ausweis", t = Zeit } },  -- wer meldet welchen Ausweis
mains = { ["ausweis"] = "Name" },                    -- vom Spieler gewählter Main
manual = { ["Twink"] = { main = "Name", by = "Offizier", t = Zeit } },
```

Aufräumen beim Gildenlisten-Update: Charaktere, die nicht mehr in der Gilde sind,
fliegen raus (auch aus `manual`). Keine Daten aus anderen Gilden mischen
(`GuildTable` trennt das schon).

Neue Datei `GuildPrideAusweis.lua` (in der `.toc` nach `GuildPrideEvents.lua`,
vor `GuildPrideUI.lua`) mit:
- `ns.Ausweis()` – eigener Code
- `ns.MainOf(name)` – Main zu einem Charakter (manuell > Ausweis > er selbst)
- `ns.AltsOf(main)` – Liste der Twinks
- `ns.SetMyMain(name)`, `ns.SetAltManual(twink, main)`, `ns.ClearAltManual(twink)`

## 4. Main bestimmen

Reihenfolge:
1. Der Spieler hat einen Main gewählt (`mains[ausweis]`).
2. Sonst: der Charakter mit dem höchsten Rang, bei Gleichstand höchstes Level,
   dann am längsten in der Gilde (`ns.RankSince`).

Main wählen: Rechtsklick auf einen eigenen Charakter → „Als Main festlegen“.
Beim ersten Start mit mehreren erkannten Charakteren einmal kurz fragen
(abschaltbar).

## 5. Oberfläche: Twinks in der Mitgliederliste

- Jeder Spieler eine Zeile (der Main). Rechts ein kleines Zeichen „+3“, wenn er
  Twinks hat. Klick auf das Zeichen klappt die Twinks darunter auf, eingerückt
  und etwas dunkler.
- **Online-Status:** Ist ein Twink online, ist die Zeile online und zeigt
  „spielt gerade Twinkname (Level)“ statt der Zone des Mains.
- Tooltip auf der Zeile: alle Charaktere mit Klasse, Level und „zuletzt online“.
- Zähler oben: „34 Spieler (81 Charaktere)“.
- Inaktiv-Filter zählt pro **Spieler**: Wer mit irgendeinem Charakter aktiv
  war, gilt nicht als inaktiv. Wichtig, damit Twinks aktiver Spieler nicht
  entfernt werden.
- Charaktere ohne GuildPride und ohne Zuordnung bleiben normale Einzelzeilen.
- Rechtsklick (Offiziere): „Twink von … festlegen“ (Namenssuche) und
  „Zuordnung lösen“. Neue automatische Zuordnungen erscheinen eine Woche lang
  mit kleinem Hinweis „neu verknüpft“, damit Offiziere sie prüfen können.
- Kompakte Liste neben dem Chat: nur Mains, Twink-Info im Tooltip.

Auch nutzen: Chat und Meilensteine zeigen beim Twink „(Main: Name)“ im Tooltip.

## 6. Einfacher machen (eigener Schritt, nach Absprache)

Vorschlag 8 → 5 Reiter, jeder Bereich hat **eine** Hauptaktion:

| Neu | enthält heute |
|-----|---------------|
| Übersicht | Übersicht + Meilensteine als Verlauf darunter |
| Gilde | Gilde & Chat (Chat ⇄ Mitglieder wie bisher) |
| Planen | Events, Umfragen, Gruppensuche als Umschalter oben |
| Gildeninfo | unverändert |
| Einstellungen | gruppiert: Allgemein, Hinweise, Gilde (Offiziere), Ausweis |

Grundsätze: Infos in Tooltips statt Untermenüs, Aktionen per Rechtsklick,
selten Genutztes in die Einstellungen. Die vorhandene Reiter-Verwaltung bleibt.

## 7. Später: Discord-Bot

- Der Spieler verknüpft im Discord seinen Account mit seinem Ausweis (Code im
  Spiel per `/gp ausweis` anzeigen, im Bot eingeben).
- Der Bot zeigt dann pro Discord-Nutzer alle seine Charaktere und kann Rollen
  vergeben. Braucht das Begleitprogramm (SavedVariables → Server), daher nicht
  Teil von 2.5.0.

## Offene Fragen

1. ~~Warum wurde „BattleTags in der Offiziersnotiz“ entfernt?~~ Geklärt: Nicht
   jeder in der Gilde soll jeden BattleTag kennen. Daher gilt streng: Der
   BattleTag verlässt nie den eigenen Client, gesendet und gespeichert wird nur
   der Hash. `/gp ausweis` zeigt nur den Code, nie den BattleTag.
2. ~~Liefert `BNGetInfo()` auf Forever den BattleTag?~~ Ja (im Spiel geprüft).
3. ~~DKP pro Spieler oder pro Charakter?~~ Pro Charakter: DKP bleiben unverändert.
4. ~~Wer darf von Hand zuordnen?~~ Nur Gildenleitung und Offiziere (Rang 0 und 1),
   keine eigene Einstellung nötig.
5. Umbau der Reiter (Abschnitt 6) gleich mit 2.5.0 oder getrennt danach?

## Schritte

1. ✅ `GuildPrideAusweis.lua`: Hash, eigener Ausweis, Speicher, `AUS`/`AUSQ`/`AUSL`.
2. ✅ `MainOf`/`AltsOf` und Aufräumen bei Gildenlisten-Update.
3. ✅ Mitgliederliste: Gruppieren, Aufklappen, Online-Status, Zähler, Tooltip.
4. ✅ Inaktiv-Filter pro Spieler.
5. ✅ Rechtsklick: Main festlegen, Offiziers-Zuordnung (`ALT`), Hinweis „neu verknüpft“.
6. ✅ Einstellungen: Auto-Verknüpfung an/aus, Offiziersrang, `/gp ausweis`.
7. ✅ Texte in `GuildPrideLocale.lua` (Deutsch und Englisch), Hilfe, `CHANGELOG.md`.
8. Test im Spiel: zwei Charaktere auf einem Account, ein zweiter WoW-Account
   unter demselben Battle.net, ein Mitglied ohne Addon, Offiziers-Zuordnung,
   Gildenaustritt, `/reload` mitten drin.
