# GuildPride Forever

**Your guild, front and center.** GuildPride replaces the default guild window with a fully styled guild hub: overview, guild & chat, events, group finder, polls, milestones and guild info in one place. Works for any guild and is made **only for WoW Forever**. For Retail and Classic, use the regular GuildPride addon.

*Deutsche Beschreibung weiter unten.*

---

## 🇬🇧 English

### NEW in 2.6: join dates, raid roster, applications, management tab

- **Join date & history** – every member shows "member since …" plus joins, leaves and rank changes; you are told when someone was in the guild before.
- **Raid roster** – for every event: 8 groups, drag or click, auto-assign (tanks first, healers spread), invite everyone assigned, arrange raid groups with one click, send the roster to the guild.
- **Applications – even without the addon** – applicants whisper **!apply** to any member with GuildPride and answer four short questions; **!info** sends your guild profile. Officers get a notice and decide in one window.
- **Management tab** – only visible to officers: applications, recruiting text, DKP, note templates and guild channel in one place. Settings now only hold personal options.
- **Resizable window** – drag the bottom-right corner (60–200 %).

### NEW in 2.5: automatic alts, leaner menu, backup

- **Alts detected automatically** – everyone with GuildPride reports the same player ID for all their characters, no matter which character joins the guild. The member list shows each player once, alts collapse under **+3**, and "playing *Alt* (level)" shows on the main. **Your BattleTag stays private:** it never leaves your PC, the guild only sees a code derived from it (different in every guild). Officers can link alts of players without the addon by hand.
- **Inactivity per player** – the "inactive" filter only lists players whose *every* character has been away.
- **Leaner menu** – 5 tabs instead of 8 (*Overview* + Milestones, *Plan* = Events, Group finder, Polls), settings in sections with a search box. The old layout is one checkbox away.
- **One-click backup** – saves all GuildPride data, keeps the last 5, automatic once a week, one-click restore.
- **DKP log** – every entry with who, when, how much and why; officers can undo any single entry.
- **Hardened sync** – only officers can book DKP, only creators or officers can change events and polls, forged relays are rejected. Covered by automated tests.
- **Error report** – `/gp errors` shows a report to copy and send.

### NEW in 2.3: Discord & DKP

- **Discord sync** – uses Blizzard's own guild chat Discord link. Events, sign-ups (with role and class) and declines from GuildPride show up in your Discord as raid events with a live roster – no extra program, no import strings. Players without a linked Discord are relayed by a linked guildmate.
- **DKP** – `/gp dkp`: officers award points to the whole raid, a group or a target with one click (attendance, boss kills), deduct loot at a fixed price and can undo their last booking. **Every player sees DKP in the tooltip** when hovering over a player. Bookings are also posted to Discord, with `/dkp` standings and a leaderboard.
- **Setup for Discord:** your guild leader links the guild to a Discord channel (Guild & Communities → Guild Settings → Discord Settings, ideally with *Separate Discord chat*) and invites **GameBot** (dashboard: https://gamerbot.duckdns.org – log in with Discord, add the bot, open *WoW Bridge*, pick an event channel). Everyone with a linked Discord types `/gp discord linked` once in game and `/wow link Name` in Discord.

### Features

- **New guild window** – opens with **J** or the guild button. Your guild name at the top, your faction logo in the sidebar. Tabs: Overview, Guild & Chat, Events, Group Finder, Polls, Milestones, Guild Info and Settings. Prefer Blizzard's window? `/gp blizzard` switches back.
- **Overview** – members online, the next event, the message of the day, the latest milestones and a **This week** recap (level-ups, raid kills, achievements, mounts, joins, departures and the busiest member).
- **Guild & Chat** – chat on the left, members on the right, like Blizzard's community window. Guild chat, officer chat and your communities with server history. Unread counts on every channel, messages that mention you are highlighted.
- **Member list** – crowns mark the guild master (filled) and officers (outlined). Search by name, rank, note or zone, sortable columns, online only or everyone with rank, notes and "last online". Officers get an **Inactive** filter (14 to 180 days or your own number, ranks can be excluded) and can **remove the inactive** members in a few clicks. **Promotion by time**: set rules like "Recruit → Member after 14 days in the rank", and the list shows who is due – one click promotes them.
- **Guild management** – click a member to set a rank (up or down), remove them or transfer leadership (depending on your rights). Right-click for whisper, group invite, friend or community invite. **Guild invites:** WoW Forever only accepts `/ginvite` when you type it yourself, so the invite button and **Invite to guild** – also on any player in the game, like target, group, chat name or friends list – show you the ready-made command in chat (needs invite rights). Note templates and a recruiting text are built in.
- **Milestones with badges** – animated pop-up with a badge when a guildmate reaches level 10, 20, 30 …, plus achievements, first raid boss kills and new mounts. Joins and departures show a clear on-screen notice. Missed milestones are fetched when you log in.
- **Event planner** – officers create events with date, time, description and officer note, optionally **repeating every week**. Members sign up as *Attending / Maybe / Declined* with their role. Reminder 15 minutes before the start, lineup check, "Invite all attendees" and **attendance tracking** per player.
- **Group finder & quest help** – **Sign up** lists you as *Looking for group*, *Looking for members* or (with a quest picked) *Needs quest help*, with the roles you still need; **Sign off** removes you, and a full group signs you off by itself. Link a quest from your quest log or pick a **dungeon**: searchable list with level ranges; the **Heroic** button only appears when your character can actually run heroics, and then only heroic dungeons are listed. **Join** sends a join request, **Invite** invites a solo player.
- **Server-wide group finder** – tick *Server-wide* and your listing is also shown to everyone on your server who uses GuildPride; switch the list between *Guild · Server · All*. Only your own faction is shown (Blizzard keeps chat channels separate per faction), no guild name is sent, only group finder listings are exchanged, and you can hide players. `/gp server` turns it off.
- **Dungeon Finder** – the **Dungeon Finder** button opens Blizzard's own Dungeon Finder, and **Search Dungeon Finder** brings its groups into your list, marked **[Dungeon Finder]**. The dots show which roles are already in the group (blue tank, green healer, red damage), the line below says if a tank or healer is still missing, and **Whisper** opens a whisper to the group leader.
- **Copy messages** – click `[GuildPride]` in front of a GuildPride chat message to open just that line, ready to copy with Ctrl+C.
- **Guild on the world map** – guild members with GuildPride show up on the world map as a dot in their class color, even when they are not in your group. Positions are only shared with your guild, and both showing and sharing can be turned off in the settings.
- **Customize the menu** – hide, rename and reorder the sidebar tabs and pick a start tab that opens every time. "Settings" always stays.
- **Polls** – officers create polls with up to 6 answers and an optional duration, everyone votes.
- **Guild info** – Blizzard's guild info text for everyone, with a notice when it changes and a copy button.
- **Six styles** – Forge, Frost, Emerald, Arcane, Night or your own colours; window size, opacity and chat font size are adjustable. Minimap button, optional automatic welcome for new members, version check.
- **English & German** – switches automatically to your game client's language.

### Security & sync

- Data is only exchanged with members of **your** guild. Everything that arrives is checked and limited – no injected colour or link codes, no flooding.
- Guild data runs over a **secured background channel**: its name and password come from a random secret key created by the guild leadership and shared only with guild members. A new key is created when someone leaves the guild.
- Milestones, events, polls, attendance and chat are **stored per guild** – characters in different guilds never mix their data.
- Blizzard blocks addon messages during *chat lockdown* in instances. GuildPride waits and sends afterwards.
- Syncing works between guild members who **have GuildPride installed**.

### Commands

| Command | What it does |
|---|---|
| `/gp` | open the window (`/gp help` lists all commands) |
| `/gp sound` · `/gp popup` | turn sounds or pop-ups on/off |
| `/gp blizzard` | switch between GuildPride and Blizzard's guild window |
| `/gp invite First Last` | show the `/ginvite` command for a player in chat |
| `/gp recruit` | put your saved recruiting text into the chat input |
| `/gp options` | open the GuildPride page in the WoW options |
| `/gp version` | who in the guild uses which version |
| `/gp channel` | status of the secured channel (officers: `/gp channel new` creates a new key) |
| `/gp server` | turn the server-wide group finder on/off (`/gp server unblock` shows hidden players again, `/gp server status` shows channel and messages) |
| `/gp id` | show your player ID code (never your BattleTag) |
| `/gp backup` | open the backup window |
| `/gp errors` | error report to copy |
| `/gp dkp` | DKP window (with *Log …*) |
| `/gp news` | show what's new |
| `/gp applications` | applications window (officers) |
| `/gp badge 30` | preview a milestone pop-up |

### Feedback

Bug reports and ideas are very welcome in the comments here. Please include the Lua error.

---

## 🇩🇪 Deutsch

**Deine Gilde im Mittelpunkt.** GuildPride ersetzt das normale Gildenfenster durch einen komplett gestalteten Gilden-Treffpunkt: Übersicht, Gilde & Chat, Events, Gruppensuche, Umfragen, Meilensteine und Gildeninfo an einem Ort. Funktioniert für jede Gilde und ist **nur für WoW Forever** gemacht. Für Retail und Classic gibt es das normale GuildPride.

### NEU in 2.6: Beitrittsdatum, Raid-Aufstellung, Bewerbungen, Verwaltung

- **Beitrittsdatum & Verlauf** – bei jedem Mitglied „Mitglied seit …“ und dazu Beitritte, Austritte und Rangwechsel; Hinweis, wenn jemand schon einmal in der Gilde war.
- **Raid-Aufstellung** – zu jedem Event: 8 Gruppen, Ziehen oder Anklicken, automatisch einteilen (Tanks zuerst, Heiler verteilt), alle Eingeteilten einladen, Gruppen im Raid mit einem Klick ordnen, Aufstellung an die Gilde senden.
- **Bewerbungen – auch ohne Addon** – Bewerber flüstern einem Mitglied mit GuildPride **!bewerben** und beantworten vier kurze Fragen; **!info** schickt euren Steckbrief. Offiziere bekommen einen Hinweis und entscheiden in einem Fenster.
- **Reiter „Verwaltung“** – nur für Offiziere sichtbar: Bewerbungen, Werbetext, DKP, Notiz-Vorlagen und Gildenkanal an einem Ort. Die Einstellungen enthalten nur noch persönliche Optionen.
- **Fenster vergrößern** – unten rechts an der Ecke ziehen (60–200 %).

### NEU in 2.5: Twinks automatisch, schlankeres Menü, Datensicherung

- **Twinks automatisch erkannt** – jeder mit GuildPride meldet für alle seine Charaktere denselben Ausweis, egal mit welchem Charakter er der Gilde beitritt. Die Mitgliederliste zeigt jeden Spieler einmal, Twinks klappen mit **+3** auf, beim Main steht „spielt *Twink* (Level)“. **Dein BattleTag bleibt privat:** Er verlässt nie deinen PC, die Gilde sieht nur einen daraus berechneten Code (in jeder Gilde ein anderer). Twinks von Spielern ohne Addon ordnen Offiziere von Hand zu.
- **Inaktiv je Spieler** – der Filter „Inaktive“ zeigt nur Spieler, deren *alle* Charaktere weg waren.
- **Schlankeres Menü** – 5 statt 8 Reiter (*Übersicht* + Meilensteine, *Planen* = Events, Gruppensuche, Umfragen), Einstellungen in Abschnitten mit Suchfeld. Das alte Menü ist einen Haken entfernt.
- **Datensicherung per Knopfdruck** – sichert alle GuildPride-Daten, die letzten 5 Stände, einmal pro Woche automatisch, Wiederherstellen mit einem Klick.
- **DKP-Protokoll** – jede Buchung mit Wer, Wann, Wie viel und Warum; Offiziere nehmen jede einzelne Buchung zurück.
- **Abgleich abgesichert** – DKP buchen nur Offiziere, Events und Umfragen ändern nur Ersteller oder Offiziere, gefälschte Weiterleitungen werden verworfen. Mit automatischen Tests geprüft.
- **Fehlerbericht** – `/gp fehler` zeigt einen Bericht zum Kopieren und Melden.

### NEU in 2.3: Discord & DKP

- **Discord-Anbindung** – nutzt Blizzards eigene Gildenchat-Discord-Verknüpfung. Events, Anmeldungen (mit Rolle und Klasse) und Absagen aus GuildPride erscheinen in eurem Discord als Raid-Events mit Live-Aufstellung – ohne Zusatzprogramm, ohne Import-Strings. Spieler ohne verknüpftes Discord leitet ein verknüpftes Gildenmitglied weiter.
- **DKP** – `/gp dkp`: Offiziere buchen Punkte mit einem Klick an den ganzen Raid, die Gruppe oder ein Ziel (Anwesenheit, Boss-Kills), ziehen Loot zum festen Preis ab und können die letzte Buchung zurücknehmen. **Alle sehen die DKP im Tooltip**, wenn sie mit der Maus über einen Spieler fahren. Buchungen landen zusätzlich in Discord, mit `/dkp`-Stand und Rangliste.
- **Einrichtung für Discord:** Die Gildenleitung verknüpft die Gilde mit einem Discord-Kanal (Gilde & Communitys → Gildeneinstellungen → Discord-Einstellungen, am besten mit *Discord-Chat getrennt*) und lädt **GameBot** ein (Dashboard: https://gamerbot.duckdns.org – mit Discord anmelden, Bot hinzufügen, *WoW-Brücke* öffnen, Event-Kanal wählen). Wer Discord verknüpft hat, gibt im Spiel einmal `/gp discord verknuepft` und in Discord `/wow link Name` ein.

### Funktionen

- **Neues Gildenfenster** – öffnet sich mit **J** oder über den Gildenknopf. Oben euer Gildenname, in der Seitenleiste euer Fraktionslogo. Reiter: Übersicht, Gilde & Chat, Events, Gruppensuche, Umfragen, Meilensteine, Gildeninfo und Einstellungen. Lieber das Blizzard-Fenster? `/gp blizzard` schaltet zurück.
- **Übersicht** – wer online ist, das nächste Event, die Nachricht des Tages, die letzten Meilensteine und ein **Wochenrückblick** (Stufenaufstiege, Raid-Siege, Erfolge, Reittiere, Beitritte, Austritte und das aktivste Mitglied).
- **Gilde & Chat** – links der Chat, rechts die Mitglieder, wie im Blizzard-Community-Fenster. Gildenchat, Offizierschat und eure Communities mit Verlauf vom Server. Ungelesen-Zähler an jedem Kanal, Nachrichten mit deinem Namen werden hervorgehoben.
- **Mitgliederliste** – Kronen zeigen Gildenmeister (gefüllt) und Offiziere (leer). Suche nach Name, Rang, Notiz oder Zone, sortierbare Spalten, nur online oder alle mit Rang, Notizen und „zuletzt online“. Offiziere bekommen einen **Inaktiv**-Filter (14 bis 180 Tage oder eigene Zahl, Ränge ausnehmbar) und können die **Inaktiven in wenigen Klicks entfernen**. **Beförderung nach Zeit**: Regeln wie „Rekrut → Mitglied nach 14 Tagen im Rang“ anlegen, die Liste zeigt, wer fällig ist – ein Klick befördert.
- **Gildenverwaltung** – Klick auf ein Mitglied zum Rang setzen (hoch oder runter), Entfernen oder Gildenleitung übergeben (je nach deinen Rechten). Rechtsklick zum Anflüstern, in Gruppe einladen, als Freund hinzufügen oder in eine Community einladen. **Gildeneinladung:** WoW Forever nimmt `/ginvite` nur an, wenn du es selbst eintippst. Der Einladen-Knopf und **In Gilde einladen** – auch bei jedem Spieler im Spiel, etwa Ziel, Gruppe, Chatname oder Freundesliste – zeigen dir deshalb den fertigen Befehl im Chat an (mit Einladerecht). Notiz-Vorlagen und Werbetext sind eingebaut.
- **Meilensteine mit Abzeichen** – animiertes Popup mit Abzeichen, wenn jemand Level 10, 20, 30 … erreicht, dazu Erfolge, erste Raidboss-Siege und neue Reittiere. Beitritte und Austritte erscheinen als deutlicher Hinweis. Verpasste Meilensteine werden beim Einloggen nachgeladen.
- **Event-Planer** – Offiziere legen Events mit Datum, Uhrzeit, Beschreibung und Offiziers-Notiz an, auf Wunsch **jede Woche wiederholt**. Mitglieder melden sich mit *Zusagen / Vielleicht / Absagen* und ihrer Rolle an. Erinnerung 15 Minuten vorher, Rollen-Check, „Alle Zugesagten einladen“ und **Anwesenheit** pro Spieler.
- **Gruppensuche & Quest-Hilfe** – **Anmelden** trägt dich als *Sucht Gruppe*, *Sucht Mitspieler* oder (mit gewählter Quest) *Braucht Quest-Hilfe* ein, mit den Rollen, die noch fehlen; **Abmelden** trägt dich aus, und bei voller Gruppe wirst du automatisch abgemeldet. Quest aus dem Questlog verlinken oder einen **Dungeon** wählen: durchsuchbare Liste mit Levelbereich; der Knopf **Heroisch** erscheint erst, wenn dein Charakter heroisch laufen kann, und zeigt dann nur heroische Dungeons. **Beitreten** schickt eine Beitrittsanfrage, **Einladen** lädt Einzelspieler ein.
- **Serverweite Gruppensuche** – *Serverweit* ankreuzen, dann sehen auch alle anderen auf dem Server mit GuildPride deinen Eintrag; die Liste lässt sich zwischen *Gilde · Server · Alle* umschalten. Nur die eigene Fraktion wird angezeigt (Blizzard trennt Chatkanäle nach Fraktion), kein Gildenname wird mitgeschickt, ausgetauscht werden nur Gruppensuche-Einträge, Spieler lassen sich ausblenden. `/gp server` schaltet es ab.
- **Dungeonbrowser** – Der Knopf **Dungeonbrowser** öffnet Blizzards eigenen Dungeonbrowser, **Browser durchsuchen** holt dessen Gruppen in deine Liste, markiert mit **[Dungeonbrowser]**. Die Punkte zeigen, welche Rollen schon dabei sind (blau Tank, grün Heiler, rot DD), darunter steht, ob noch Tank oder Heiler fehlt, und **Anflüstern** öffnet ein Flüstern an den Gruppenleiter.
- **Meldungen kopieren** – Klick auf `[GuildPride]` vor einer GuildPride-Meldung im Chat öffnet genau diese Zeile, fertig zum Kopieren mit Strg+C.
- **Gilde auf der Weltkarte** – Gildenmitglieder mit GuildPride erscheinen als Punkt in ihrer Klassenfarbe auf der Weltkarte, auch wenn sie nicht in deiner Gruppe sind. Die Position sieht nur deine Gilde, Anzeigen und Teilen lassen sich in den Einstellungen abschalten.
- **Menü anpassen** – Reiter der Seitenleiste ausblenden, umbenennen, umsortieren und einen Startreiter wählen, der bei jedem Öffnen kommt. „Einstellungen“ bleibt immer da.
- **Umfragen** – Offiziere legen Umfragen mit bis zu 6 Antworten und wahlweiser Laufzeit an, alle stimmen ab.
- **Gildeninfo** – der Info-Text aus dem Blizzard-Gildenfenster für alle, mit Hinweis bei Änderungen und Kopier-Knopf.
- **Sechs Styles** – Schmiede, Frost, Smaragd, Arkan, Nacht oder eigene Farben; Fenstergröße, Deckkraft und Chat-Schriftgröße einstellbar. Minimap-Knopf, wahlweise automatische Begrüßung neuer Mitglieder, Versionscheck.
- **Deutsch & Englisch** – stellt sich automatisch auf die Sprache deines Clients ein.

### Sicherheit & Abgleich

- Daten werden nur mit Mitgliedern **eurer** Gilde ausgetauscht. Alles, was ankommt, wird geprüft und begrenzt – keine eingeschleusten Farb- oder Link-Codes, kein Fluten.
- Gildendaten laufen über einen **abgesicherten Hintergrund-Kanal**: Name und Passwort entstehen aus einem zufälligen geheimen Schlüssel der Gildenleitung, der nur an Gildenmitglieder geht. Verlässt jemand die Gilde, wird ein neuer Schlüssel erzeugt.
- Meilensteine, Events, Umfragen, Anwesenheit und Chat werden **je Gilde getrennt** gespeichert – Charaktere in verschiedenen Gilden vermischen nichts.
- Während der *Chat-Sperre* in Instanzen blockiert Blizzard Addon-Nachrichten. GuildPride wartet und sendet danach.
- Abgeglichen wird zwischen Gildenmitgliedern, die **GuildPride installiert haben**.

### Befehle

| Befehl | Funktion |
|---|---|
| `/gp` | Fenster öffnen (`/gp hilfe` zeigt alle Befehle) |
| `/gp sound` · `/gp popup` | Sounds oder Popups an/aus |
| `/gp blizzard` | zwischen GuildPride und dem Blizzard-Gildenfenster wechseln |
| `/gp einladen Vorname Nachname` | `/ginvite`-Befehl für einen Spieler im Chat anzeigen |
| `/gp werben` | gespeicherten Werbetext in die Chat-Eingabe legen |
| `/gp optionen` | GuildPride-Seite in den WoW-Optionen öffnen |
| `/gp version` | wer in der Gilde welche Version nutzt |
| `/gp kanal` | Stand des abgesicherten Kanals (Offiziere: `/gp kanal neu` erzeugt einen neuen Schlüssel) |
| `/gp server` | serverweite Gruppensuche an/aus (`/gp server entsperren` zeigt ausgeblendete Spieler wieder, `/gp server status` zeigt Kanal und Nachrichten) |
| `/gp ausweis` | deinen Ausweis-Code zeigen (nie den BattleTag) |
| `/gp sicherung` | Fenster Datensicherung öffnen |
| `/gp fehler` | Fehlerbericht zum Kopieren |
| `/gp dkp` | DKP-Fenster (mit *Protokoll …*) |
| `/gp neu` | Neuerungen anzeigen |
| `/gp bewerbungen` | Bewerbungsfenster (Offiziere) |
| `/gp badge 30` | Meilenstein-Popup testen |

### Feedback

Fehlermeldungen und Ideen sind hier in den Kommentaren sehr willkommen. Am besten mit Lua-Fehlermeldung.

---

*Fonts: DejaVu (free license, included). Artwork created for GuildPride.*
