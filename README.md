<p align="center"><img src="docs/logo.png" alt="GuildPride" width="200"></p>

[English](#english) · [Deutsch](#deutsch) · [Screenshots](#screenshots)

World of Warcraft addon for WoW Forever only · Author: Rottgar85 · CurseForge project 1788777. For Retail and Classic, use [GuildPride](https://github.com/Rottgar85/GuildPride)

---

## English

**Your guild, front and center.** GuildPride replaces the default guild window with a fully styled guild hub: milestones, events, guild info, a group finder, guild chat and member management in one place. Works for any guild: the window automatically shows your guild name and your faction logo (Horde or Alliance). English and German.

### Features
- **New guild window**: opens with **J** or the guild button in the micro menu. Your guild name at the top, your faction logo on the left. `/gp blizzard` switches back to Blizzard's window
- **Milestones with badges**: when a member reaches level 10, 20, 30 … 90, every guildmate with GuildPride sees an animated pop-up with a badge. Missed milestones are fetched from other members at login
- **Join and leave alerts**: a clear notice when someone joins, leaves or is removed
- **Event planner**: officers create events with title, date and time (separate fields), description and officer note. Members of every rank sign up as Attending, Maybe or Declined with their role. Reminder 15 minutes before the start
- **Group finder and quest help**: pick a quest or dungeon and the roles you still need, then **Sign up** (**Sign off** removes you; a full group signs you off by itself). Everyone sees class, level, role, zone and how full the group is. **Join** sends a join request, **Invite** invites a solo player, right-click whispers. Open to every rank
- **Server-wide group finder**: optionally also see and reach everyone on your server with GuildPride – without guild names, only your own faction (Blizzard keeps chat channels separate per faction). Switch between Guild · Server · All, hide players, `/gp server` turns it off.
- **Guild info**: the info text from Blizzard's guild window, the same for everyone, with a notice when it changes. It is edited in Blizzard's guild window (Blizzard blocks addons from changing it)
- **Guild & Chat**: guild chat, officer chat and your Blizzard communities with the members right next to the chat, like Blizzard's community window. Server-side history plus a local copy so old messages keep their author names
- **Members list**: crowns mark the guild master (filled) and officers (outlined). one click from the chat to the full list of your guild or community, online only or everyone, with rank, notes and "last online"
- **Styles**: Forge, Frost, Emerald, Arcane, Night and Custom, switchable any time in the settings
- **Invite players**: community invites work directly. For guild invites, WoW Forever only accepts `/ginvite` when you type it yourself, so the name field and **Invite to guild** in the right-click menu (any player in the game, needs invite rights) show you the ready-made command in chat
- **Guild management**: click a member to see notes and to set a rank (up or down), remove or transfer leadership (depending on your rights)
- **Community management**: right-click a member to change their role, edit their note or remove them
- **Polls**: officers create polls with up to 6 answers and an optional duration, everyone votes
- **More milestones**: achievements, first raid boss kills and new mounts
- **Event lineup**: role check for group or raid and "Invite all attendees" for officers
- **Recruiting text and note templates**, plus a settings page in the WoW options (`/gp options`)
- **Version check**: a reminder when a newer version is in use in the guild
- **Search and sort members**: search by name, rank, note or zone; click a column header (name, level, rank, last online) to sort, click again to reverse
- **Unread counts and mentions**: guild, officer and community buttons, the community menu and the Guild & Chat tab show how many messages are unread. Lines with your name get a » and gold text
- **This week** on the overview: level-ups, raid kills, achievements, mounts, joins, departures and the busiest member
- **For officers**: "Inactive" filter (14 to 180 days or your own number, ranks can be excluded) with **remove inactive** in a few clicks, **promotion by time** (rule: rank A → rank B after N days in the rank), automatic welcome message, weekly recurring events and attendance tracking
- **Minimap button**, a custom style with your own color, and adjustable window size, opacity and chat font

### Commands
- `/gp` or `/guildpride` open the window, `/gp help` all commands
- `/gp sound`, `/gp popup` turn sounds and pop-ups on or off
- `/gp blizzard` switch between GuildPride and the Blizzard guild window
- `/gp invite First Last` show the `/ginvite` command for a player in chat
- `/gp server` server-wide group finder on or off, `/gp server unblock` shows hidden players again, `/gp server status` shows channel and messages
- `/gp badge 30` preview a milestone pop-up, `/gp version` who uses which version

### Good to know
- Milestones, events and the group finder sync between guild members who have GuildPride installed
- Data is shared only with your guild through addon messages; members who can't write in guild chat send through an online guildmate
- During Blizzard's chat lockdown in instances, addon messages wait and are sent afterwards
- Guild data also travels over a hidden, password-protected background channel of your guild, so syncing does not depend on guild chat rank rights.

### Installation
Copy the `GuildPrideForever` folder to `World of Warcraft/_forever_/Interface/AddOns`, or install it with the CurseForge app. Works in WoW Forever only.

---

## Deutsch

**Deine Gilde im Mittelpunkt.** GuildPride ersetzt das normale Gildenfenster durch einen komplett gestalteten Gilden-Treffpunkt: Meilensteine, Events, Gildeninfo, Gruppensuche, Gildenchat und Mitgliederverwaltung an einem Ort. Funktioniert für jede Gilde: Das Fenster zeigt automatisch euren Gildennamen und das Logo eurer Fraktion (Horde oder Allianz). Deutsch und Englisch.

### Funktionen
- **Neues Gildenfenster**: öffnet sich mit **J** oder über den Gildenknopf in der Mikroleiste. Oben euer Gildenname, links das Logo eurer Fraktion. `/gp blizzard` schaltet zurück zum Blizzard-Fenster
- **Meilensteine mit Abzeichen**: erreicht jemand Level 10, 20, 30 … 90, sehen alle mit GuildPride ein animiertes Popup mit Abzeichen. Verpasste Meilensteine werden beim Einloggen von anderen Mitgliedern nachgeladen
- **Hinweis bei Beitritt und Austritt**: eine deutliche Meldung, wenn jemand beitritt, geht oder entfernt wird
- **Event-Planer**: Offiziere legen Events mit Titel, Datum und Uhrzeit (getrennte Felder), Beschreibung und Offiziers-Notiz an. Mitglieder aller Ränge melden sich mit Zusagen, Vielleicht oder Absagen und ihrer Rolle an. Erinnerung 15 Minuten vor Beginn
- **Gruppensuche und Quest-Hilfe**: Quest oder Dungeon und fehlende Rollen wählen, dann **Anmelden** (**Abmelden** trägt dich aus; ist die Gruppe voll, wirst du automatisch abgemeldet). Alle sehen Klasse, Level, Rolle, Zone und wie voll die Gruppe ist. **Beitreten** schickt eine Beitrittsanfrage, **Einladen** lädt einen Einzelspieler ein, Rechtsklick flüstert an. Für alle Ränge
- **Serverweite Gruppensuche**: auf Wunsch auch alle auf dem Server mit GuildPride sehen und erreichen – ohne Gildennamen, nur die eigene Fraktion (Blizzard trennt Chatkanäle nach Fraktion). Umschaltbar zwischen Gilde · Server · Alle, Spieler ausblendbar, `/gp server` schaltet es ab.
- **Gildeninfo**: der Info-Text aus dem Blizzard-Gildenfenster, für alle gleich, mit Hinweis bei Änderungen. Bearbeitet wird er im Blizzard-Gildenfenster (Blizzard sperrt das Ändern für Addons)
- **Gilde & Chat**: Gildenchat, Offizierschat und eure Blizzard-Communities, die Mitglieder direkt neben dem Chat wie im Blizzard-Community-Fenster. Verlauf vom Server und lokale Kopie, damit alte Nachrichten ihren Namen behalten
- **Mitgliederliste**: Kronen zeigen Gildenmeister (gefüllt) und Offiziere (leer). ein Klick vom Chat zur großen Liste eurer Gilde oder Community, nur online oder alle, mit Rang, Notizen und „zuletzt online“
- **Styles**: Schmiede, Frost, Smaragd, Arkan, Nacht und Eigene, jederzeit in den Einstellungen umschaltbar
- **Spieler einladen**: Community-Einladungen gehen direkt. Für die Gilde nimmt WoW Forever `/ginvite` nur an, wenn du es selbst eintippst. Das Namensfeld und **In Gilde einladen** im Rechtsklick-Menü (bei jedem Spieler im Spiel, mit Einladerecht) zeigen dir deshalb den fertigen Befehl im Chat an
- **Gildenverwaltung**: Klick auf ein Mitglied zeigt die Notizen, dort Rang setzen (hoch oder runter), entfernen oder Gildenleitung übergeben (je nach deinen Rechten)
- **Community-Verwaltung**: Rechtsklick auf ein Mitglied, um die Rolle zu ändern, die Notiz zu bearbeiten oder es zu entfernen
- **Umfragen**: Offiziere legen Umfragen mit bis zu 6 Antworten und wahlweiser Laufzeit an, alle stimmen ab
- **Mehr Meilensteine**: Erfolge, erste Raidboss-Siege und neue Reittiere
- **Event-Aufstellung**: Rollen-Check für Gruppe oder Schlachtzug und „Alle Zugesagten einladen“ für Offiziere
- **Werbetext und Notiz-Vorlagen**, dazu eine Einstellungsseite in den WoW-Optionen (`/gp optionen`)
- **Versionscheck**: Erinnerung, wenn in der Gilde eine neuere Version genutzt wird
- **Mitglieder suchen und sortieren**: Suche nach Name, Rang, Notiz oder Zone; Klick auf einen Spaltenkopf (Name, Level, Rang, zuletzt online) sortiert, erneuter Klick dreht die Richtung
- **Ungelesen und Erwähnungen**: Gilde, Offiziere, Communities, das Community-Menü und der Reiter Gilde & Chat zeigen, wie viele Nachrichten ungelesen sind. Zeilen mit deinem Namen bekommen ein » und goldene Schrift
- **Diese Woche** auf der Übersicht: Level-Aufstiege, Raid-Siege, Erfolge, Reittiere, Beitritte, Abgänge und das fleißigste Mitglied
- **Für Offiziere**: Filter „Inaktive“ (14 bis 180 Tage oder eigene Zahl, Ränge ausnehmbar) mit **Inaktive entfernen** in wenigen Klicks, **Beförderung nach Zeit** (Regel: Rang A → Rang B nach N Tagen im Rang), automatische Begrüßung, wöchentlich wiederholte Events und Anwesenheit
- **Minimap-Knopf**, eigener Style mit selbst gewählter Farbe, dazu einstellbare Fenstergröße, Deckkraft und Chat-Schrift

### Befehle
- `/gp` oder `/guildpride` Fenster öffnen, `/gp hilfe` alle Befehle
- `/gp sound`, `/gp popup` Sounds und Popups an oder aus
- `/gp blizzard` zwischen GuildPride und dem Blizzard-Gildenfenster wechseln
- `/gp einladen Vorname Nachname` `/ginvite`-Befehl für einen Spieler im Chat anzeigen
- `/gp server` serverweite Gruppensuche an oder aus, `/gp server entsperren` zeigt ausgeblendete Spieler wieder, `/gp server status` zeigt Kanal und Nachrichten
- `/gp badge 30` Meilenstein-Popup testen, `/gp version` wer welche Version nutzt

### Gut zu wissen
- Meilensteine, Events und Gruppensuche werden zwischen Gildenmitgliedern abgeglichen, die GuildPride installiert haben
- Daten gehen nur an eure Gilde per Addon-Nachricht; wer nicht im Gildenchat schreiben darf, sendet über ein Mitglied, das online ist
- Während der Blizzard-Chat-Sperre in Instanzen warten Addon-Nachrichten und werden danach gesendet
- Gildendaten laufen zusätzlich über einen versteckten, passwortgeschützten Hintergrund-Kanal eurer Gilde, damit der Abgleich nicht von Rangrechten im Gildenchat abhängt.

### Installation
Den Ordner `GuildPrideForever` nach `World of Warcraft/_forever_/Interface/AddOns` kopieren oder über die CurseForge-App installieren. Läuft nur in WoW Forever.

---

## Screenshots

*In-game screenshots (German client) · Spiel-Screenshots*

![Overview / Übersicht](docs/screenshots/1_uebersicht.jpg)

![Group finder – dungeon picker / Gruppensuche – Dungeon-Auswahl](docs/screenshots/3_gruppensuche_dungeon.jpg)

![Milestone pop-up / Meilenstein-Popup](docs/screenshots/4_meilenstein_popup.jpg)

![Settings / Einstellungen](docs/screenshots/5_einstellungen.jpg)
