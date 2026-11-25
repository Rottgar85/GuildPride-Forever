<p align="center"><img src="docs/logo.png" alt="GuildPride" width="200"></p>

[English](#english) · [Deutsch](#deutsch) · [Screenshots](#screenshots)

World of Warcraft addon for WoW Forever only · Version 2.45.0 · Author: Rottgar85 · CurseForge project 1788777. For Retail and Classic, use [GuildPride](https://github.com/Rottgar85/GuildPride)

---

## English

**Your guild, front and center.** GuildPride replaces the default guild window with a fully styled guild hub – and adds what WoW Forever is missing: ship, zeppelin and Deeprun Tram timers, a rare scanner, a full auction house, a crafting window, raid tools, Discord sync and DKP. Works for any guild and is made **only for WoW Forever**. For Retail and Classic, use the regular GuildPride addon.

### NEW in 2.42 and 2.43

- **2.43:** tools as tiles, `/gp help` with all commands, jump bar in the settings, multi-line boss notes, material list by name with guild bank stock, fewer messages at login.
- **Tools page** under *Plan*: raid readiness, guild quests, boss notes, material list, loot history, group cooldowns, mentors, quiz, album and event statistics – see *Tools* below.
- **Search everything** – magnifier at the top of the guild window or `/gp search`: members, events, settings, commands, boss notes and recipes.
- **Presets** – `/gp preset guild`, `raid` or `all` turns on only what you need. Plus a larger font and colours for colour blindness.
- **Error reports only with your yes**, an error report that only counts GuildPride errors, and much less memory for auction prices.

### Guild window

- **New guild window** – opens with **J** or the guild button. Guild name and faction logo or guild crest at the top. Pick a look on first start (Guild book, Classic, Icon bar); everything uses the dark **"Guild hall"** design with a gold accent. Window size (60–200 %), opacity and chat font are adjustable, and the sidebar can be hidden, renamed and reordered. Prefer Blizzard's window? `/gp blizzard` switches back.
- **Overview** – members online, the next event, the message of the day, the latest milestones and a **This week** recap (level-ups, raid kills, achievements, mounts, joins, departures, busiest member). **Today** lists what is coming up: events with your answer, your auctions, mail, ready cooldowns, open guild orders.
- **Milestones with badges** – animated pop-up when a guildmate reaches level 10, 20, 30 …, plus achievements, first raid boss kills and new mounts. Missed milestones are fetched at login. Joins and departures show a clear notice.
- **Guild goals** – shared goals with a progress bar (member count, players at a level or your own goals officers count up by hand). Reached goals are celebrated and can be posted to Discord.
- **Notice board** – officers pin a message; every member sees it once as a window, then on the overview (`/gp board`).
- **Guild & Chat** – guild chat, officer chat and your communities with server history, the members right next to the chat. Unread counts, highlighted mentions and a Discord filter.
- **Member list** – search by name, rank, note or zone, sortable columns, "member since …" with joins, leaves and rank changes. Click a member to set a rank, remove them or transfer leadership. **Invite** opens Blizzard's invite dialog.
- **Alts detected automatically** – everyone with GuildPride reports one player ID for all their characters; alts collapse under the main. **Your BattleTag stays private**: the guild only sees a code derived from it.
- **For officers** – *Management* tab (applications, recruiting text, DKP, note templates, guild channel), *Activity* tab (who has been offline how long, event sign-ups, attendance), **Inactive** filter with removal in a few clicks, **promotion by time** ("Recruit → Member after 14 days"), automatic welcome.
- **Applications, even without the addon** – applicants whisper **!apply** to any member with GuildPride and answer four questions; **!info** sends your guild profile.
- **Guild on the world map** – guild members with GuildPride as a dot in their class colour (only your guild sees it, can be turned off).

### Plan

- **Event planner** – date, time, description, officer note, **dungeon or raid** from the list, weekly repeat, templates and editing. Members sign up as *Attending / Maybe / Declined* with their role. New events show a notice with sound, a reminder comes before the start (0–60 min), plus lineup check, **raid roster** (8 groups, auto-assign, invite everyone assigned, arrange the raid) and **attendance** per player.
- **Group finder & quest help** – sign up as *Looking for group*, *Looking for members* or *Needs quest help* with a quest or dungeon and the roles you need. **Join** sends role, class and level, the leader invites with one click. Blizzard's Dungeon Finder groups can be pulled into the list.
- **Server-wide group finder** – optionally show your listing to everyone on the server with GuildPride (own faction, no guild name). `/gp server` turns it off.
- **Polls** – up to 6 answers and an optional duration.
- **Wishlist** – mark items as normal, high or BiS; the item tooltip shows who in the guild wants it (with DKP), and an epic drop shows who in the group wants it.

### Tools (under *Plan*)

- **Raid readiness** (`/gp ready`) – leader and assistants see durability, well fed, potions and elixirs of the group, problems first. On a ready check everyone with GuildPride answers by itself.
- **Guild quests** (`/gp quests`) – who is online and has the same quest, your zone first; a click invites up to four.
- **Boss notes** (`/gp boss`) – officers write short tactics per boss; the window opens once when you enter the instance.
- **Material list** (`/gp mats`) – officers set what is needed (by name, link or ID), everyone pledges a share, the guild bank counts too; right click puts the rest into your tracker.
- **Loot history** (`/gp loot`) – who got what in dungeons and raids (rare or better), with a filter; opening the window fetches newer entries from officers.
- **Group cooldowns** (`/gp cooldowns`) – Rebirth, Shield Wall and other important spells of guild members in your group.
- **Event statistics** (`/gp stats`, officers) – reliability, streaks, weekdays and months from the recorded attendance.
- **Mentors** (`/gp mentor`) – members who like to help new ones; a click whispers them.
- **Guild quiz** (`/gp quiz`) and **treasure hunt** (`/gp hunt`) – officers ask questions or hide stations, with a leaderboard.
- **Guild album** (`/gp album`) – your first boss kills with date, with a screenshot if you like. **Anniversaries** show on the overview.

### Crafting & auction house

- **Crafting window** (`/gp handwerk`, own **Crafting** entry in the guild window) – levelling path from 1 to 300 for every profession with "Next up", reagents, stock and cost to your goal. Under **"More …"**: recipes, profit, guild & alts, tracker and compact view.
- **Tracker** (`/gp tracker`) – counts what you gather, buys what is missing at a vendor or searches it at the auction house, and crafts tracked recipes one click at a time (intermediates first).
- **Recipe card, trainers on the map, gathering spots, fishing bar** with one key for fishing, **sell advisor** in the tooltip – everything can be turned off one by one under "Crafting".
- **Crafting directory** (*Crafting* entry) – who has which profession at which skill and which recipes, searchable by name, profession or recipe.
- **Recipe gaps** (`/gp gaps`) – which recipes of a profession nobody in the guild knows, and who has the profession. Right click: “I will learn this” – the guild sees it.
- **Guild orders** – post an item and a quantity; crafters accept or give back, the requester gets a notice. New and accepted orders also go to Discord.
- **Auction house** – optional GuildPride window with search by category, buy view with all offers, **price history** of 30 days and who in the guild can craft the item, selling with a price suggestion (cheapest current offer), **My auctions**, favourites, **shopping lists** (quantity, stock, price alert, export/import incl. Auctionator lists, temporary list for one shopping trip, *Buy list*) and *Orders*. Prices show in the item tooltip.
- **Prices for everyone** – prices are shared server-wide (own faction, goblin auction houses separate) and only count as confirmed when at least two players report them. Works alongside Auctionator.
- **Profession window** – *AH: Reagents* searches only the reagents of a recipe, *To shopping list*, and shows reagent cost, sale value and profit.

### Travel, notes, buffs & rares

- **Notes on the map** (`/gp zettel`) – pin a note where you stand, for the guild or for everyone; it opens when someone comes close.
- **Buff reminder** – best buff food from your bags, sleeping bag and campfire while levelling; off by default, turn them on under Settings › Buffs.
- **Departures** – stand at a dock (ship, zeppelin, airship) or a Deeprun Tram platform and a small window shows a countdown per connection: whether it is **at the dock and when it leaves**, when the next one arrives and the one after. Times are measured when someone rides along and are **shared with everyone using GuildPride**.
- **Your own time first** – your own measurement wins; otherwise the time most players measured themselves (*confirmed 3×*). A single differing report does not replace it. Since Blizzard's hotfix of 2026-11-20 layers can no longer be detected, so no layer numbers are shown.
- **Reminder** – click the clock icon on a connection: raid warning and sound 1 minute before departure, even when you have left the dock.
- **After the weekly reset** – until someone measures again, last week's time shows as *guessed*.
- **Rare scanner & world bosses** (`/gp rares`) – rares are detected via target, mouse and nameplates and shared with everyone on the server using GuildPride, with alert and sound. The world map shows known spawn points of over 300 rares.

### Scales

- **Scales built in** (`/scales`) – simulates your character (DPS, HPS, mitigation) and shows on every item whether it is an upgrade, with arrows in your bags and a line in the tooltip, plus a weapon comparison.

### Discord & DKP

- **Discord sync** – uses Blizzard's own guild chat Discord link. Events (with dungeon/raid and group size), sign-ups with role and class, declines, DKP, polls, milestones, guild orders and prices show up in your Discord – no extra program. Sign-ups of players without a linked Discord are relayed by the event creator.
- **DKP** – `/gp dkp`: officers award points to the raid, a group or a target with one click, deduct loot and undo any entry in the log. Everyone sees DKP in the player tooltip.
- **Setup:** the guild leader links the guild to a Discord channel (Guild & Communities → Guild Settings → Discord Settings, ideally with *Separate Discord chat*) and invites **GameBot** (dashboard: https://gamerbot.duckdns.org – log in with Discord, add the bot, open *WoW Bridge*, pick an event channel). Everyone with a linked Discord types `/gp discord linked` once in game and `/wow link Name` in Discord.

### Security & sharing

- **Guild data** (milestones, events, polls, DKP, chat, alts) is only exchanged with members of **your** guild, over a hidden channel protected by a random key of the guild leadership. A new key is created when someone leaves.
- **Shared with everyone on the server using GuildPride, always:** ship timetables, rare sightings and auction house prices – no guild names, own faction only.
- **Only with the server-wide group finder switched on:** group finder listings.
- **Can be turned off:** guild quests share only the numbers of your quests with your guild; raid readiness (durability, well fed, number of potions) goes only to the leader and assistants of your own group who are in your guild; cooldowns share when you used an important spell in a group, only with your guild (Settings › Sharing).
- **Error reports only with your yes:** if GuildPride runs into a Lua error, you are asked once whether such errors may go to the developer inside the game. Sent are only the error text (may rarely contain a player name), the place in the code, versions, game language and circumstances (combat, instance type, open GuildPride windows) – never chat, notes, gold or your addon list. The developer does not store character names, only a counting code. Without a yes nothing is sent; you can change it at any time under Settings › Sharing.
- **Testers only with their yes:** the developer can invite players to see new features earlier. After your yes your GuildPride tells the developer, when they are online, that you are testing, your version and the name of the character you are playing; only the invited name is stored, and your error reports (if allowed) are marked “tester”. `/gp tester off` or Settings › Sharing ends it.
- **Usage counters only with your yes:** you are asked once whether the developer may learn which features you use. Counted are only opened tabs, GuildPride windows and /gp commands plus changed switches – never contents, chat, gold or names. At most once a day; only a counting code is stored. Without a yes nothing is counted; you can change it at any time under Settings › Sharing.
- Everything that arrives is checked and limited – no injected colour or link codes, no flooding. Guild data is stored per guild.
- **One-click backup** (`/gp backup`): keeps the last 5 states, automatically once a week.

### Commands

| Command | What it does |
|---|---|
| `/gp` | open the window |
| `/gp help` | all commands with explanations, a click runs one |
| `/gp sound` · `/gp popup` | sounds or pop-ups on/off |
| `/gp blizzard` | switch between GuildPride and Blizzard's guild window |
| `/gp invite First Last` | invite a player to the guild |
| `/gp rares` · `/gpr` | rare scanner |
| `/scales` | Scales |
| `/gp ah` | auction house (`on`/`off`, `status`, `scan`, `window`) |
| `/gp dkp` | DKP window with log |
| `/gp wish` | wishlist |
| `/gp search [text]` | search members, events, settings, commands, boss notes and recipes |
| `/gp preset guild` · `raid` · `all` | turn on only what you need |
| `/gp ready` · `/gp cooldowns` | raid readiness · group cooldowns |
| `/gp quests` · `/gp boss` · `/gp mats` | guild quests · boss notes · material list |
| `/gp loot` · `/gp stats` | loot history · event statistics (officers) |
| `/gp mentor` · `/gp quiz` · `/gp hunt` · `/gp album` | mentors · guild quiz · treasure hunt · guild album |
| `/gp board` | show the notice board |
| `/gp discord` | Discord link (`info`, `test`, `linked`) |
| `/gp server` | server-wide group finder on/off (`status`, `unblock`) |
| `/gp applications` | applications (officers) |
| `/gp backup` | backup window |
| `/gp recruit` | put the recruiting text into the chat input |
| `/gp version` | who in the guild uses which version |
| `/gp channel` | guild channel status (officers: `/gp channel new`) |
| `/gp id` | your player ID code (never your BattleTag) |
| `/gp news` · `/gp changelog` | what's new |
| `/gp report` · `/gp errors` · `/gp errortest` | bug report to copy · throw a harmless test error |
| `/gp diag` | diagnostics to copy (realm, guild, Dungeon Finder, community, memory and CPU) |
| `/gp note <name> <text>` | your own note on a player, shown in their tooltip (only for you; without text: delete) |
| `/gp blocklist` · `/gp block <name> [reason]` · `/gp unblock <name>` | block list: these players are not invited to the guild (officers change it; names with spaces in quotes) |
| `/gp bank` | guild bank log: who deposited or withdrew what, name filter and weekly totals (read when you open the guild bank) |
| `/gp welcome` | welcome window with message of the day, guild info, Discord and community link, question to the officers |
| `/gp export` · `/gp import` | copy your GuildPride settings as text and paste them on another PC or character |
| `/gp buff` · `/gp rest` | buff food window (best food for your class from your bags) · sleeping bag and campfire window while levelling; the gear in the window turns the reminders off |
| `/gp messages [name]` · `/gp message <name> <text>` | messenger: messages to guild members with GuildPride, even when they are offline; whispers open the window too, like WIM (other members keep them until delivery; to the main, so all their characters get it) |
| `/gp handwerk` · `/gp handwerk mini` | crafting window (levelling guide, recipes, profit, guild & alts) · compact view |
| `/gp tracker` | gathering and crafting tracker |
| `/gp gaps` | recipes nobody in the guild knows |
| `/gp zettel` | notes on the map (`write`, `on`/`off`, `clear`) |
| `/gp price <item> <price>` | price alert without the auction house window (`off` removes it, without arguments: list) |
| `/gp options` | GuildPride page in the WoW options |

### Feedback

Bug reports and ideas are very welcome in the comments or on the GuildPride Discord (logo button in the guild window). `/gp report` creates a report to copy.

---

## Deutsch

**Deine Gilde im Mittelpunkt.** GuildPride ersetzt das normale Gildenfenster durch einen komplett gestalteten Gilden-Treffpunkt – und bringt mit, was WoW Forever fehlt: Schiffs-, Zeppelin- und Tiefenbahnzeiten, einen Rare-Scanner, ein vollständiges Auktionshaus, ein Handwerk-Fenster, Raid-Werkzeuge, Discord-Anbindung und DKP. Funktioniert für jede Gilde und ist **nur für WoW Forever** gemacht. Für Retail und Classic gibt es das normale GuildPride.

*Version 2.45.0*

### NEU in 2.42 und 2.43

- **2.43:** Werkzeuge als Kacheln, `/gp hilfe` mit allen Befehlen, Sprungleiste in den Einstellungen, mehrzeilige Boss-Notizen, Materialliste nach Namen mit Bestand der Gildenbank, weniger Nachrichten beim Einloggen.
- **Seite „Werkzeuge“** unter *Planen*: Raid-Bereitschaft, Quests der Gilde, Boss-Notizen, Materialliste, Loot-Verlauf, Abklingzeiten, Paten, Quiz, Album und Event-Auswertung – siehe *Werkzeuge* weiter unten.
- **Suche über alles** – Lupe oben im Gildenfenster oder `/gp suche`: Mitglieder, Events, Einstellungen, Befehle, Boss-Notizen und Rezepte.
- **Pakete** – `/gp paket gilde`, `raid` oder `alles` schaltet nur an, was du brauchst. Dazu größere Schrift und Farben für Farbenblinde.
- **Fehlerberichte nur mit deinem Ja**, ein Fehlerbericht, der nur noch GuildPride-Fehler zählt, und viel weniger Speicher für Auktionspreise.

### Gildenfenster

- **Neues Gildenfenster** – öffnet sich mit **J** oder über den Gildenknopf. Oben Gildenname und Fraktionslogo oder Gildenwappen. Beim ersten Start wählst du das Aussehen (Gildenbuch, Klassisch, Icon-Leiste); alles im dunklen Design **„Gildenhalle“** mit Gold-Akzent. Fenstergröße (60–200 %), Deckkraft und Chat-Schrift sind einstellbar, die Reiter der Seitenleiste lassen sich ausblenden, umbenennen und umsortieren. Lieber das Blizzard-Fenster? `/gp blizzard` schaltet zurück.
- **Übersicht** – wer online ist, das nächste Event, die Nachricht des Tages, die letzten Meilensteine und ein **Wochenrückblick** (Stufenaufstiege, Raid-Siege, Erfolge, Reittiere, Beitritte, Abgänge, fleißigstes Mitglied).
- **Meilensteine mit Abzeichen** – animiertes Popup, wenn jemand Level 10, 20, 30 … erreicht, dazu Erfolge, erste Raidboss-Siege und neue Reittiere. Verpasste Meilensteine werden beim Einloggen nachgeladen. Beitritte und Austritte erscheinen als deutlicher Hinweis.
- **Gildenziele** – gemeinsame Ziele mit Fortschrittsbalken (Mitgliederzahl, Spieler auf einer Stufe oder eigene Ziele, die Offiziere von Hand weiterzählen). Erreichte Ziele werden gefeiert und auf Wunsch an Discord gemeldet.
- **Schwarzes Brett** – Offiziere hängen eine Mitteilung aus; jedes Mitglied sieht sie einmal als Fenster, danach in der Übersicht (`/gp brett`).
- **Gilde & Chat** – Gildenchat, Offizierschat und eure Communities mit Verlauf vom Server, die Mitglieder direkt daneben. Ungelesen-Zähler, hervorgehobene Erwähnungen und ein Discord-Filter.
- **Mitgliederliste** – Suche nach Name, Rang, Notiz oder Zone, sortierbare Spalten, „Mitglied seit …“ mit Beitritten, Austritten und Rangwechseln. Klick auf ein Mitglied: Rang setzen, entfernen oder Gildenleitung übergeben. **Einladen** öffnet Blizzards Einladedialog.
- **Twinks automatisch erkannt** – jeder mit GuildPride meldet für alle seine Charaktere denselben Ausweis; Twinks klappen unter dem Main zusammen. **Dein BattleTag bleibt privat**: Die Gilde sieht nur einen daraus berechneten Code.
- **Für Offiziere** – Reiter *Verwaltung* (Bewerbungen, Werbetext, DKP, Notiz-Vorlagen, Gildenkanal), Reiter *Aktivität* (wer wie lange offline ist, Event-Anmeldungen, Anwesenheit), Filter **Inaktive** mit Entfernen in wenigen Klicks, **Beförderung nach Zeit** („Rekrut → Mitglied nach 14 Tagen“), automatische Begrüßung.
- **Bewerbungen, auch ohne Addon** – Bewerber flüstern einem Mitglied mit GuildPride **!bewerben** und beantworten vier Fragen; **!info** schickt euren Steckbrief.
- **Gilde auf der Weltkarte** – Gildenmitglieder mit GuildPride als Punkt in ihrer Klassenfarbe (sieht nur eure Gilde, abschaltbar).

### Planen

- **Event-Planer** – Datum, Uhrzeit, Beschreibung, Offiziers-Notiz, **Dungeon oder Raid** aus der Liste, wöchentliche Wiederholung, Vorlagen und Bearbeiten. Mitglieder melden sich mit *Zusagen / Vielleicht / Absagen* und ihrer Rolle an. Neue Events kommen mit Hinweisfenster und Ton, vor Beginn eine Erinnerung (0–60 Min.), dazu Rollen-Check, **Raid-Aufstellung** (8 Gruppen, automatisch einteilen, alle Eingeteilten einladen, Raid ordnen) und **Anwesenheit** je Spieler.
- **Gruppensuche & Quest-Hilfe** – als *Sucht Gruppe*, *Sucht Mitspieler* oder *Braucht Quest-Hilfe* eintragen, mit Quest oder Dungeon und den fehlenden Rollen. **Beitreten** schickt Rolle, Klasse und Stufe, der Gruppenleiter lädt mit einem Klick ein. Gruppen aus Blizzards Dungeonbrowser lassen sich in die Liste holen.
- **Serverweite Gruppensuche** – auf Wunsch sehen alle auf dem Server mit GuildPride deinen Eintrag (eigene Fraktion, ohne Gildennamen). `/gp server` schaltet es ab.
- **Umfragen** – bis zu 6 Antworten und wahlweise Laufzeit.
- **Wunschliste** – Items als normal, hoch oder BiS markieren; im Item-Tooltip steht, wer in der Gilde es sucht (mit DKP), bei einem epischen Drop, wer in der Gruppe es sich wünscht.

### Werkzeuge (unter *Planen*)

- **Raid-Bereitschaft** (`/gp bereit`) – Leiter und Assistenten sehen Haltbarkeit, „Satt“, Tränke und Elixiere der Gruppe, Probleme zuerst. Beim Bereitschaftscheck antworten alle mit GuildPride von selbst.
- **Quests der Gilde** (`/gp quests`) – wer online ist und dieselbe Quest hat, deine Zone zuerst; ein Klick lädt bis zu vier ein.
- **Boss-Notizen** (`/gp boss`) – Offiziere schreiben je Boss eine kurze Taktik; das Fenster geht beim Betreten der Instanz einmal auf.
- **Materialliste** (`/gp material`) – Offiziere legen fest, was gebraucht wird (Name, Link oder ID), jeder sagt seinen Anteil zu, die Gildenbank zählt mit; Rechtsklick legt den Rest in deinen Tracker.
- **Loot-Verlauf** (`/gp loot`) – wer in Dungeons und Raids was bekommen hat (ab selten), mit Filter; beim Öffnen kommen neuere Einträge von Offizieren dazu.
- **Abklingzeiten der Gruppe** (`/gp abklingzeiten`) – Wiedergeburt, Schildwall und andere wichtige Zauber der Gildenmitglieder in deiner Gruppe.
- **Event-Auswertung** (`/gp auswertung`, Offiziere) – Verlässlichkeit, Serien, Wochentage und Monate aus der erfassten Anwesenheit.
- **Paten** (`/gp paten`) – Mitglieder, die Neuen gern helfen; ein Klick flüstert sie an.
- **Gildenquiz** (`/gp quiz`) und **Schnitzeljagd** (`/gp jagd`) – Offiziere stellen Fragen oder verstecken Stationen, mit Rangliste.
- **Gildenalbum** (`/gp album`) – eure ersten Bosskills mit Datum, auf Wunsch mit Screenshot. **Jubiläen** stehen in der Übersicht.

### Handwerk & Auktionshaus

- **Handwerk-Fenster** (`/gp handwerk`, eigener Eintrag **Handwerk** im Gildenfenster) – Weg von 1 bis 300 für jeden Beruf mit „Als Nächstes“, Zutaten, Bestand und Kosten bis zum Ziel. Unter **„Mehr …“**: Rezepte, Gewinn, Gilde & Twinks, Tracker und Kompaktansicht.
- **Tracker** (`/gp tracker`) – zählt, was du sammelst, kauft Fehlendes beim Händler oder sucht es im Auktionshaus und stellt getrackte Rezepte Klick für Klick her (Zwischenprodukte zuerst).
- **Rezeptkarte, Lehrer auf der Karte, Sammel-Fundorte, Angel-Leiste** mit einer Taste fürs Angeln, **Verkaufs-Berater** im Tooltip – alles einzeln abschaltbar unter „Handwerk“.
- **Handwerker-Verzeichnis** (Eintrag *Handwerk*) – wer welchen Beruf auf welcher Stufe hat und welche Rezepte er kann, durchsuchbar nach Name, Beruf oder Rezept.
- **Rezept-Lücken** (`/gp luecken`) – welche Rezepte eines Berufs niemand in der Gilde kann und wer den Beruf hat. Rechtsklick: „Das lerne ich“, die Gilde sieht es.
- **Gildenaufträge** – Item und Menge einstellen; Hersteller nehmen an oder geben ab, der Auftraggeber bekommt einen Hinweis. Neue und angenommene Aufträge gehen auch an Discord.
- **Auktionshaus** – wahlweise GuildPride-Fenster mit Suche nach Kategorien, Kaufansicht mit allen Angeboten, **Preisverlauf** über 30 Tage und wer in der Gilde das Item herstellen kann, Verkaufen mit Preisvorschlag (günstigstes aktuelles Angebot), **Meine Auktionen**, Favoriten, **Einkaufslisten** (Menge, Bestand, Preisalarm, Export/Import auch von Auctionator-Listen, temporäre Liste für einen Einkauf, *Liste kaufen*) und *Aufträge*. Preise stehen im Item-Tooltip.
- **Preise für alle** – Preise werden serverweit geteilt (eigene Fraktion, Goblin-Auktionshäuser getrennt) und gelten erst als bestätigt, wenn mindestens zwei Spieler sie melden. Läuft auch zusammen mit Auctionator.
- **Berufsfenster** – *AH: Zutaten* sucht nur die Zutaten eines Rezepts, *Zur Einkaufsliste*, dazu Kosten der Zutaten, Verkaufswert und Gewinn.

### Reisen, Zettel, Buffs & Rares

- **Notizzettel auf der Karte** (`/gp zettel`) – Zettel dort aufhängen, wo du stehst, für die Gilde oder für alle; er geht auf, wenn jemand nahe kommt.
- **Buff-Erinnerung** – bestes Buff-Food aus den Taschen, beim Leveln Schlafsack und Lagerfeuer; ab Werk aus, einschalten unter Einstellungen › Buffs & Erholung.
- **Abfahrten** – stehst du an einem Anleger (Schiff, Zeppelin, Luftschiff) oder am Bahnsteig der Tiefenbahn, zeigt ein kleines Fenster je Verbindung einen Countdown: ob es **am Steg liegt und wann es ablegt**, wann das nächste kommt und das danach. Gemessen wird, wenn jemand mitfährt – und **mit allen GuildPride-Spielern geteilt**.
- **Deine Zeit zuerst** – deine eigene Messung gilt; sonst die Zeit, die die meisten selbst gemessen haben (*3× bestätigt*). Eine einzelne abweichende Meldung verdrängt sie nicht. Seit Blizzards Hotfix vom 20.11.2026 lassen sich Layer nicht mehr erkennen, darum gibt es keine Layer-Nummern.
- **Erinnerung** – Uhr-Symbol an einer Verbindung anklicken: Raid-Warnung und Ton 1 Minute vor der Abfahrt, auch wenn du nicht mehr am Anleger bist.
- **Nach dem wöchentlichen Reset** – bis wieder jemand misst, steht die Zeit der letzten Woche als *vermutet* da.
- **Rare-Scanner & Weltbosse** (`/gp rares`) – Rares werden über Ziel, Maus und Namensplaketten erkannt und mit allen GuildPride-Spielern auf dem Server geteilt, mit Alarm und Ton. Die Weltkarte zeigt bekannte Fundorte von über 300 Rares.

### Scales

- **Scales eingebaut** (`/scales`) – simuliert deinen Charakter (DPS, HPS, Mitigation) und zeigt an jedem Item, ob es ein Upgrade ist, mit Pfeilen in den Taschen und einer Zeile im Tooltip, dazu ein Waffenvergleich.

### Discord & DKP

- **Discord-Anbindung** – nutzt Blizzards eigene Gildenchat-Discord-Verknüpfung. Events (mit Dungeon/Raid und Gruppengröße), Anmeldungen mit Rolle und Klasse, Absagen, DKP, Umfragen, Meilensteine, Gildenaufträge und Preise erscheinen in eurem Discord – ohne Zusatzprogramm. Anmeldungen von Spielern ohne verknüpftes Discord gibt der Event-Ersteller weiter.
- **DKP** – `/gp dkp`: Offiziere buchen Punkte mit einem Klick an den Raid, die Gruppe oder ein Ziel, ziehen Loot ab und nehmen jede Buchung im Protokoll zurück. Alle sehen die DKP im Spieler-Tooltip.
- **Einrichtung:** Die Gildenleitung verknüpft die Gilde mit einem Discord-Kanal (Gilde & Communitys → Gildeneinstellungen → Discord-Einstellungen, am besten mit *Discord-Chat getrennt*) und lädt **GameBot** ein (Dashboard: https://gamerbot.duckdns.org – mit Discord anmelden, Bot hinzufügen, *WoW-Brücke* öffnen, Event-Kanal wählen). Wer Discord verknüpft hat, gibt im Spiel einmal `/gp discord verknuepft` und in Discord `/wow link Name` ein.

### Sicherheit & Teilen

- **Gildendaten** (Meilensteine, Events, Umfragen, DKP, Chat, Twinks) gehen nur an Mitglieder **eurer** Gilde, über einen versteckten Kanal, geschützt durch einen zufälligen Schlüssel der Gildenleitung. Verlässt jemand die Gilde, wird ein neuer Schlüssel erzeugt.
- **Immer mit allen GuildPride-Spielern auf dem Server geteilt:** Schiffs-Fahrpläne, Rare-Sichtungen und Auktionshauspreise – ohne Gildennamen, nur eigene Fraktion.
- **Nur mit eingeschalteter serverweiter Gruppensuche:** Gruppensuche-Einträge.
- **Abschaltbar:** „Quests der Gilde“ teilt nur die Nummern deiner Quests mit deiner Gilde; die Raid-Bereitschaft (Haltbarkeit, satt, Zahl der Tränke) geht nur an Leiter und Assistenten deiner eigenen Gruppe, die in deiner Gilde sind; Abklingzeiten melden in einer Gruppe nur der Gilde, wann du einen wichtigen Zauber benutzt hast (Einstellungen › Teilen).
- **Fehlerberichte nur mit deinem Ja:** Hat GuildPride einen Lua-Fehler, wirst du einmal gefragt, ob solche Fehler im Spiel an den Entwickler gehen dürfen. Gesendet werden nur Fehlertext (kann selten einen Spielernamen enthalten), Stelle im Code, Versionen, Spielsprache und Umstände (Kampf, Instanzart, offene GuildPride-Fenster) – nie Chat, Notizen, Gold oder deine Addon-Liste. Der Entwickler speichert keine Charakternamen, nur einen Zählcode. Ohne Ja wird nichts gesendet; ändern kannst du das jederzeit unter Einstellungen › Teilen.
- **Tester nur mit ihrem Ja:** Der Entwickler kann Spieler einladen, neue Funktionen früher zu sehen. Nach deinem Ja meldet dein GuildPride dem Entwickler, wenn er online ist, dass du mittestest, deine Version und den Namen des Charakters, der gerade spielt; gespeichert wird nur der eingeladene Name, und deine Fehlerberichte (falls erlaubt) bekommen den Vermerk „Tester“. `/gp tester aus` oder Einstellungen › Teilen beendet es.
- **Nutzungszähler nur mit deinem Ja:** du wirst einmal gefragt, ob der Entwickler erfahren darf, welche Funktionen du benutzt. Gezählt werden nur geöffnete Reiter, GuildPride-Fenster und /gp-Befehle sowie geänderte Schalter – nie Inhalte, Chat, Gold oder Namen. Höchstens einmal am Tag; gespeichert wird nur ein Zählcode. Ohne Ja wird nichts gezählt; ändern kannst du das jederzeit unter Einstellungen › Teilen.
- Alles, was ankommt, wird geprüft und begrenzt – keine eingeschleusten Farb- oder Link-Codes, kein Fluten. Gildendaten werden je Gilde getrennt gespeichert.
- **Datensicherung per Knopfdruck** (`/gp sicherung`): die letzten 5 Stände, einmal pro Woche automatisch.

### Befehle

| Befehl | Funktion |
|---|---|
| `/gp` | Fenster öffnen |
| `/gp hilfe` | alle Befehle mit Erklärung, ein Klick führt einen aus |
| `/gp sound` · `/gp popup` | Sounds oder Popups an/aus |
| `/gp blizzard` | zwischen GuildPride und dem Blizzard-Gildenfenster wechseln |
| `/gp einladen Vorname Nachname` | Spieler in die Gilde einladen |
| `/gp rares` · `/gpr` | Rare-Scanner |
| `/scales` | Scales |
| `/gp ah` | Auktionshaus (`an`/`aus`, `status`, `scan`, `fenster`) |
| `/gp dkp` | DKP-Fenster mit Protokoll |
| `/gp wunsch` | Wunschliste |
| `/gp suche [Text]` | Mitglieder, Events, Einstellungen, Befehle, Boss-Notizen und Rezepte suchen |
| `/gp paket gilde` · `raid` · `alles` | nur anschalten, was du brauchst |
| `/gp bereit` · `/gp abklingzeiten` | Raid-Bereitschaft · Abklingzeiten der Gruppe |
| `/gp quests` · `/gp boss` · `/gp material` | Quests der Gilde · Boss-Notizen · Materialliste |
| `/gp loot` · `/gp auswertung` | Loot-Verlauf · Event-Auswertung (Offiziere) |
| `/gp paten` · `/gp quiz` · `/gp jagd` · `/gp album` | Paten · Gildenquiz · Schnitzeljagd · Gildenalbum |
| `/gp brett` | Schwarzes Brett zeigen |
| `/gp discord` | Discord-Anbindung (`info`, `test`, `verknuepft`) |
| `/gp server` | serverweite Gruppensuche an/aus (`status`, `entsperren`) |
| `/gp bewerbungen` | Bewerbungen (Offiziere) |
| `/gp sicherung` | Fenster Datensicherung |
| `/gp werben` | Werbetext in die Chat-Eingabe legen |
| `/gp version` | wer in der Gilde welche Version nutzt |
| `/gp kanal` | Stand des Gildenkanals (Offiziere: `/gp kanal neu`) |
| `/gp ausweis` | deinen Ausweis-Code zeigen (nie den BattleTag) |
| `/gp neu` · `/gp changelog` | Neuerungen anzeigen |
| `/gp melden` · `/gp fehler` · `/gp fehlertest` | Fehlerbericht zum Kopieren · harmlosen Testfehler auslösen |
| `/gp diag` | Diagnose zum Kopieren (Realm, Gilde, Dungeonbrowser, Community, Speicher und CPU) |
| `/gp notiz <Name> <Text>` | eigene Notiz zu einem Spieler, steht in seinem Tooltip (nur für dich; ohne Text: löschen) |
| `/gp blockliste` · `/gp block <Name> [Grund]` · `/gp unblock <Name>` | Blockliste: diese Spieler werden nicht in die Gilde eingeladen (ändern nur Offiziere; Namen mit Leerzeichen in Anführungszeichen) |
| `/gp bank` | Gildenbank-Verlauf: wer was eingezahlt oder genommen hat, mit Namensfilter und Wochensumme (gelesen beim Öffnen der Gildenbank) |
| `/gp willkommen` | Willkommensfenster mit Nachricht des Tages, Gildeninfo, Discord- und Community-Link und Frage an die Offiziere |
| `/gp export` · `/gp import` | GuildPride-Einstellungen als Text kopieren und auf einem anderen PC oder Charakter einfügen |
| `/gp buff` · `/gp rast` | Buff-Food-Fenster (bestes Essen für deine Klasse aus den Taschen) · Schlafsack- und Lagerfeuer-Fenster beim Leveln; das Zahnrad im Fenster schaltet die Erinnerungen ab |
| `/gp nachrichten [Name]` · `/gp nachricht <Name> <Text>` | Messenger: Nachrichten an Gildenmitglieder mit GuildPride, auch wenn sie offline sind; auch Flüstern öffnet das Fenster, wie bei WIM (andere Mitglieder heben sie bis zur Zustellung auf; an den Main, also an alle seine Charaktere) |
| `/gp handwerk` · `/gp handwerk mini` | Handwerk-Fenster (Leveln, Rezepte, Gewinn, Gilde & Twinks) · Kompaktansicht |
| `/gp tracker` | Sammel- und Herstell-Tracker |
| `/gp luecken` | Rezepte, die niemand in der Gilde kann |
| `/gp zettel` | Notizzettel auf der Karte (`schreiben`, `an`/`aus`, `weg`) |
| `/gp preis <Gegenstand> <Preis>` | Preisalarm ohne Auktionshaus-Fenster (`aus` entfernt ihn, ohne Angaben: Liste) |
| `/gp optionen` | GuildPride-Seite in den WoW-Optionen |

### Feedback

Fehlermeldungen und Ideen sind hier in den Kommentaren oder im GuildPride-Discord (Logo-Knopf im Gildenfenster) sehr willkommen. `/gp melden` erstellt einen Bericht zum Kopieren.

### Installation / Installieren

Copy the `GuildPrideForever` folder to `World of Warcraft/_forever_/Interface/AddOns`, or install it with the CurseForge or Wago app. Works in WoW Forever only.
Den Ordner `GuildPrideForever` nach `World of Warcraft/_forever_/Interface/AddOns` kopieren oder über die CurseForge- bzw. Wago-App installieren. Läuft nur in WoW Forever.

---

## Screenshots

*In-game screenshots (German client) · Spiel-Screenshots*

![Overview / Übersicht](docs/screenshots/1_uebersicht.jpg)

![Group finder – dungeon picker / Gruppensuche – Dungeon-Auswahl](docs/screenshots/3_gruppensuche_dungeon.jpg)

![Milestone pop-up / Meilenstein-Popup](docs/screenshots/4_meilenstein_popup.jpg)

![Settings / Einstellungen](docs/screenshots/5_einstellungen.jpg)

---

## Lizenz und Quellen / License and credits

GuildPride steht unter der **GNU General Public License v3.0** (siehe `LICENSE.txt`).
GuildPride is licensed under the **GNU General Public License v3.0** (see `LICENSE.txt`).

- Flugzeiten und Flugsymbol / flight times and flight icon: aus / from Polestar (GPL-3.0-only), Flugdaten dort nach / flight data there after Shortest Path Forever von / by Cillian Berragan (GPL-3.0-or-later, mit Erlaubnis / with permission)
- Schiffs-Fahrpläne / ship timetables: aus / from Polestar (GPL-3.0-only), dort aus / based on Shortest Path Forever von / by Cillian Berragan (GPL-3.0-or-later, mit Erlaubnis / with permission)
- Rare-Fundorte / rare spawn points: aus / from [ForeverMapNotes](https://www.curseforge.com/wow/addons/forevermapnotes-bysiberiano12) (GPL-3.0), dort aus / based on QuestieDB Forever data ([github.com/Questie/QuestieDB](https://github.com/Questie/QuestieDB)) – danke an das Questie-Team / thanks to the Questie team – und / and CMaNGOS classic-db ([github.com/cmangos/classic-db](https://github.com/cmangos/classic-db), GPL-3.0)
- Schriften / fonts: DejaVu (`Media/Fonts/LICENSE-DejaVu.txt`), Inter (SIL OFL 1.1, `Media/Fonts/LICENSE-Inter.txt`)
