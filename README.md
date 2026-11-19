<p align="center"><img src="docs/logo.png" alt="GuildPride" width="200"></p>

[English](#english) · [Deutsch](#deutsch) · [Screenshots](#screenshots)

World of Warcraft addon for WoW Forever only · Version 2.27.1 · Author: Rottgar85 · CurseForge project 1788777. For Retail and Classic, use [GuildPride](https://github.com/Rottgar85/GuildPride)

---

## English

**Your guild, front and center.** GuildPride replaces the default guild window with a fully styled guild hub – and adds what WoW Forever is missing: ship and zeppelin timers per layer, a rare scanner, a full auction house, layer switching with one click, a crafting directory, Discord sync and DKP. Works for any guild and is made **only for WoW Forever**. For Retail and Classic, use the regular GuildPride addon.

### NEW in 2.26

- **Dungeons and raids for guild events** – the **New event** window has a button each for **dungeon** and **raid**: every WoW Forever dungeon and raid with level and player count, the name becomes the title. The event list gets its own column (e.g. *Raid · 40*), the lineup follows the group size, and Discord gets the choice so the bot builds the matching group.
- **Sharing without exception** – ship and zeppelin times, rares and auction house prices are always shared with everyone using GuildPride, even with the server-wide group finder off.
- **Ship timer** – times confirmed by several players (*confirmed 3×*), a reminder 1 minute before departure, automatic layer detection and last week's time as a guess after the reset.

### Guild window

- **New guild window** – opens with **J** or the guild button. Guild name and faction logo or guild crest at the top. Pick a look on first start (Guild book, Classic, Icon bar); everything uses the dark **"Guild hall"** design with a gold accent. Window size (60–200 %), opacity and chat font are adjustable, and the sidebar can be hidden, renamed and reordered. Prefer Blizzard's window? `/gp blizzard` switches back.
- **Overview** – members online, the next event, the message of the day, the latest milestones and a **This week** recap (level-ups, raid kills, achievements, mounts, joins, departures, busiest member).
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

### Crafting & auction house

- **Crafting directory** (*Professions* tab) – who has which profession at which skill and which recipes, searchable by name, profession or recipe.
- **Guild orders** – post an item and a quantity; crafters accept or give back, the requester gets a notice. New and accepted orders also go to Discord.
- **Auction house** – optional GuildPride window with search by category, buy view with all offers, **price history** of 7 days and who in the guild can craft the item, selling with a price suggestion (cheapest current offer), **My auctions**, favourites, **shopping lists** (quantity, stock, price alert, export/import incl. Auctionator lists, temporary list for one shopping trip, *Buy list*) and *Orders*. Prices show in the item tooltip.
- **Prices for everyone** – prices are shared server-wide (own faction, goblin auction houses separate) and only count as confirmed when at least two players report them. Works alongside Auctionator.
- **Profession window** – *AH: Reagents* searches only the reagents of a recipe, *To shopping list*, and shows reagent cost, sale value and profit.

### Travel, rares & layers

- **Ship timer** – stand at a dock (ship, zeppelin, airship) and a small window shows a countdown per connection: whether it is **at the dock and when it leaves**, when the next one arrives and the one after. Times are measured when someone rides along and are **shared with everyone using GuildPride**.
- **Per layer** – every layer runs its ships offset; the window shows the times of **your** layer and switches with you. Times confirmed by several players show *confirmed 3×*; a single differing report does not replace them.
- **Reminder** – click the clock icon on a connection: raid warning and sound 1 minute before departure, even when you have left the dock.
- **After the weekly reset** – until someone measures again, last week's time shows as *guessed*. Experimental: when the layer start time matches on two measured layers, unmeasured layers get an *estimated* time.
- **Rare scanner & world bosses** (`/gp rares`) – rares are detected via target, mouse and nameplates and shared with everyone on the server using GuildPride, with alert, sound and the sighting's layer. The world map shows known spawn points of over 300 rares.
- **Switch layers with one click** – button in the guild window, in the group finder or `/gp layer`: a player on another layer in your zone invites you, the invite is accepted and you leave the group by yourself. Your layer shows below the minimap. The layer list shows everyone with GuildPride on the server with zone and layer; **Go here** switches to a specific player's layer, **To layer** in the rare alert takes you to the sighting.

### Scales

- **Scales built in** (`/scales`) – simulates your character (DPS, HPS, mitigation) and shows on every item whether it is an upgrade, with arrows in your bags and a line in the tooltip, plus a weapon comparison.

### Discord & DKP

- **Discord sync** – uses Blizzard's own guild chat Discord link. Events (with dungeon/raid and group size), sign-ups with role and class, declines, DKP, polls, milestones, guild orders and prices show up in your Discord – no extra program. Sign-ups of players without a linked Discord are relayed by the event creator.
- **DKP** – `/gp dkp`: officers award points to the raid, a group or a target with one click, deduct loot and undo any entry in the log. Everyone sees DKP in the player tooltip.
- **Setup:** the guild leader links the guild to a Discord channel (Guild & Communities → Guild Settings → Discord Settings, ideally with *Separate Discord chat*) and invites **GameBot** (dashboard: https://gamerbot.duckdns.org – log in with Discord, add the bot, open *WoW Bridge*, pick an event channel). Everyone with a linked Discord types `/gp discord linked` once in game and `/wow link Name` in Discord.

### Security & sharing

- **Guild data** (milestones, events, polls, DKP, chat, alts) is only exchanged with members of **your** guild, over a hidden channel protected by a random key of the guild leadership. A new key is created when someone leaves.
- **Shared with everyone on the server using GuildPride, always:** ship timetables (with layer), rare sightings and auction house prices – no guild names, own faction only.
- **Only with the server-wide group finder switched on:** group finder listings and layer switching.
- Everything that arrives is checked and limited – no injected colour or link codes, no flooding. Guild data is stored per guild.
- **One-click backup** (`/gp backup`): keeps the last 5 states, automatically once a week.

### Commands

| Command | What it does |
|---|---|
| `/gp` | open the window (`/gp help` lists all commands) |
| `/gp sound` · `/gp popup` | sounds or pop-ups on/off |
| `/gp blizzard` | switch between GuildPride and Blizzard's guild window |
| `/gp invite First Last` | invite a player to the guild |
| `/gp layer` | switch layer (`list`, `display`, `on`/`off`, `leave`) |
| `/gp rares` · `/gpr` | rare scanner |
| `/scales` | Scales |
| `/gp ah` | auction house (`on`/`off`, `status`, `scan`, `window`) |
| `/gp dkp` | DKP window with log |
| `/gp wish` | wishlist |
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
| `/gp report` · `/gp errors` | bug report to copy |
| `/gp options` | GuildPride page in the WoW options |

### Feedback

Bug reports and ideas are very welcome in the comments or on the GuildPride Discord (logo button in the guild window). `/gp report` creates a report to copy.

---

## Deutsch

**Deine Gilde im Mittelpunkt.** GuildPride ersetzt das normale Gildenfenster durch einen komplett gestalteten Gilden-Treffpunkt – und bringt mit, was WoW Forever fehlt: Schiffs- und Zeppelinzeiten je Layer, einen Rare-Scanner, ein vollständiges Auktionshaus, Layer-Wechsel mit einem Klick, ein Handwerker-Verzeichnis, Discord-Anbindung und DKP. Funktioniert für jede Gilde und ist **nur für WoW Forever** gemacht. Für Retail und Classic gibt es das normale GuildPride.

*Version 2.27.1*

### NEU in 2.26

- **Dungeons und Raids bei Gildenevents** – im Fenster **Neues Event** je ein Knopf für **Dungeon** und **Raid**: alle Dungeons und Raids von WoW Forever mit Stufe und Spielerzahl, der Name wird als Titel übernommen. Die Event-Liste bekommt eine eigene Spalte (z. B. *Raid · 40*), die Aufstellung richtet sich nach der Gruppengröße, und Discord bekommt die Auswahl mit, damit der Bot die passende Gruppe anlegt.
- **Teilen ohne Ausnahme** – Schiffs- und Zeppelinzeiten, Rares und Auktionshauspreise werden immer mit allen GuildPride-Spielern geteilt, auch wenn die serverweite Gruppensuche aus ist.
- **Schiffs-Zähler** – von mehreren Spielern bestätigte Zeiten (*3× bestätigt*), Erinnerung 1 Minute vor der Abfahrt, Layer automatisch erkannt und nach dem Reset die Zeit der letzten Woche als Vermutung.

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

### Berufe & Auktionshaus

- **Handwerker-Verzeichnis** (Reiter *Berufe*) – wer welchen Beruf auf welcher Stufe hat und welche Rezepte er kann, durchsuchbar nach Name, Beruf oder Rezept.
- **Gildenaufträge** – Item und Menge einstellen; Hersteller nehmen an oder geben ab, der Auftraggeber bekommt einen Hinweis. Neue und angenommene Aufträge gehen auch an Discord.
- **Auktionshaus** – wahlweise GuildPride-Fenster mit Suche nach Kategorien, Kaufansicht mit allen Angeboten, **Preisverlauf** über 7 Tage und wer in der Gilde das Item herstellen kann, Verkaufen mit Preisvorschlag (günstigstes aktuelles Angebot), **Meine Auktionen**, Favoriten, **Einkaufslisten** (Menge, Bestand, Preisalarm, Export/Import auch von Auctionator-Listen, temporäre Liste für einen Einkauf, *Liste kaufen*) und *Aufträge*. Preise stehen im Item-Tooltip.
- **Preise für alle** – Preise werden serverweit geteilt (eigene Fraktion, Goblin-Auktionshäuser getrennt) und gelten erst als bestätigt, wenn mindestens zwei Spieler sie melden. Läuft auch zusammen mit Auctionator.
- **Berufsfenster** – *AH: Zutaten* sucht nur die Zutaten eines Rezepts, *Zur Einkaufsliste*, dazu Kosten der Zutaten, Verkaufswert und Gewinn.

### Reisen, Rares & Layer

- **Schiffs-Zähler** – stehst du an einem Anleger (Schiff, Zeppelin, Luftschiff), zeigt ein kleines Fenster je Verbindung einen Countdown: ob es **am Steg liegt und wann es ablegt**, wann das nächste kommt und das danach. Gemessen wird, wenn jemand mitfährt – und **mit allen GuildPride-Spielern geteilt**.
- **Je Layer** – jeder Layer fährt seine Schiffe versetzt; das Fenster zeigt die Zeiten **deines** Layers und wechselt mit. Von mehreren Spielern gemessene Zeiten stehen mit *3× bestätigt* da; eine einzelne abweichende Meldung verdrängt sie nicht.
- **Erinnerung** – Uhr-Symbol an einer Verbindung anklicken: Raid-Warnung und Ton 1 Minute vor der Abfahrt, auch wenn du nicht mehr am Anleger bist.
- **Nach dem wöchentlichen Reset** – bis wieder jemand misst, steht die Zeit der letzten Woche als *vermutet* da. Versuch: Passt der Layer-Start bei zwei gemessenen Layern zusammen, bekommen auch ungemessene Layer eine *geschätzte* Zeit.
- **Rare-Scanner & Weltbosse** (`/gp rares`) – Rares werden über Ziel, Maus und Namensplaketten erkannt und mit allen GuildPride-Spielern auf dem Server geteilt, mit Alarm, Ton und dem Layer der Sichtung. Die Weltkarte zeigt bekannte Fundorte von über 300 Rares.
- **Layer wechseln mit einem Klick** – Knopf im Gildenfenster, in der Gruppensuche oder `/gp layer`: Ein Spieler auf einem anderen Layer in deiner Zone lädt dich ein, die Einladung wird angenommen und du verlässt die Gruppe von selbst. Dein Layer steht unter der Minimap. Die Layer-Liste zeigt alle mit GuildPride auf dem Server mit Zone und Layer; **Hierhin** wechselt gezielt auf den Layer eines Spielers, **Zum Layer** im Rare-Alarm bringt dich zur Sichtung.

### Scales

- **Scales eingebaut** (`/scales`) – simuliert deinen Charakter (DPS, HPS, Mitigation) und zeigt an jedem Item, ob es ein Upgrade ist, mit Pfeilen in den Taschen und einer Zeile im Tooltip, dazu ein Waffenvergleich.

### Discord & DKP

- **Discord-Anbindung** – nutzt Blizzards eigene Gildenchat-Discord-Verknüpfung. Events (mit Dungeon/Raid und Gruppengröße), Anmeldungen mit Rolle und Klasse, Absagen, DKP, Umfragen, Meilensteine, Gildenaufträge und Preise erscheinen in eurem Discord – ohne Zusatzprogramm. Anmeldungen von Spielern ohne verknüpftes Discord gibt der Event-Ersteller weiter.
- **DKP** – `/gp dkp`: Offiziere buchen Punkte mit einem Klick an den Raid, die Gruppe oder ein Ziel, ziehen Loot ab und nehmen jede Buchung im Protokoll zurück. Alle sehen die DKP im Spieler-Tooltip.
- **Einrichtung:** Die Gildenleitung verknüpft die Gilde mit einem Discord-Kanal (Gilde & Communitys → Gildeneinstellungen → Discord-Einstellungen, am besten mit *Discord-Chat getrennt*) und lädt **GameBot** ein (Dashboard: https://gamerbot.duckdns.org – mit Discord anmelden, Bot hinzufügen, *WoW-Brücke* öffnen, Event-Kanal wählen). Wer Discord verknüpft hat, gibt im Spiel einmal `/gp discord verknuepft` und in Discord `/wow link Name` ein.

### Sicherheit & Teilen

- **Gildendaten** (Meilensteine, Events, Umfragen, DKP, Chat, Twinks) gehen nur an Mitglieder **eurer** Gilde, über einen versteckten Kanal, geschützt durch einen zufälligen Schlüssel der Gildenleitung. Verlässt jemand die Gilde, wird ein neuer Schlüssel erzeugt.
- **Immer mit allen GuildPride-Spielern auf dem Server geteilt:** Schiffs-Fahrpläne (mit Layer), Rare-Sichtungen und Auktionshauspreise – ohne Gildennamen, nur eigene Fraktion.
- **Nur mit eingeschalteter serverweiter Gruppensuche:** Gruppensuche-Einträge und Layer-Wechsel.
- Alles, was ankommt, wird geprüft und begrenzt – keine eingeschleusten Farb- oder Link-Codes, kein Fluten. Gildendaten werden je Gilde getrennt gespeichert.
- **Datensicherung per Knopfdruck** (`/gp sicherung`): die letzten 5 Stände, einmal pro Woche automatisch.

### Befehle

| Befehl | Funktion |
|---|---|
| `/gp` | Fenster öffnen (`/gp hilfe` zeigt alle Befehle) |
| `/gp sound` · `/gp popup` | Sounds oder Popups an/aus |
| `/gp blizzard` | zwischen GuildPride und dem Blizzard-Gildenfenster wechseln |
| `/gp einladen Vorname Nachname` | Spieler in die Gilde einladen |
| `/gp layer` | Layer wechseln (`liste`, `anzeige`, `an`/`aus`, `raus`) |
| `/gp rares` · `/gpr` | Rare-Scanner |
| `/scales` | Scales |
| `/gp ah` | Auktionshaus (`an`/`aus`, `status`, `scan`, `fenster`) |
| `/gp dkp` | DKP-Fenster mit Protokoll |
| `/gp wunsch` | Wunschliste |
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
| `/gp melden` · `/gp fehler` | Fehlerbericht zum Kopieren |
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
