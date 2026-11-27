# GuildPride Changelog

## 2.48.0

**Deutsch**
- **Schlankerer Start für neue Spieler**: Wer die Einführung schließt, ohne eine Stufe zu wählen, startet mit Medium (mit Buff-Food- und Erholungs-Erinnerung) statt mit allem. Wer GuildPride schon nutzt oder eine Stufe gewählt hat, behält seine Einstellungen
- **Messenger**: Nachrichten gehen seltener verloren. Loggt der Absender später ein, schickt er noch nicht zugestellte Nachrichten an Empfänger nach, die dann gerade online sind (höchstens 20 je Empfänger)
- Stabiler: Die Sprungleiste in den Einstellungen ist abgesichert

**English**
- **Leaner start for new players**: closing the intro without choosing a tier now starts you on Medium (with buff food and rest reminders) instead of everything. If you already use GuildPride or have chosen a tier, your settings stay as they are
- **Messenger**: fewer lost messages. When the sender logs in later, they resend undelivered messages to recipients who are online at that moment (at most 20 per recipient)
- More stable: the jump bar in the settings is protected

## 2.47.1

**Deutsch**
- Behoben: Absturz, wenn man in der Einstellungs-Suche nach einer gerade ausgeblendeten Einstellung suchte

**English**
- Fixed: crash when searching the settings for an option that was currently hidden

## 2.47.0

**Deutsch**
- **Flüstern ganz abschaltbar**: Neuer Schalter „Flüster-Fenster von GuildPride benutzen" (Einstellungen › Gilde). Aus heißt, GuildPride fasst Flüstern nicht mehr an – alles bleibt in Blizzards Chat. Die bisherigen Flüster-Optionen sind jetzt Unterpunkte davon
- **Freundlichere Einführung für neue Spieler**: eine kürzere, fokussierte Tour mit der Übersichtsseite „Was GuildPride für dich kann", einer Empfehlung bei der Stufenwahl, einer kurzen Bestätigung nach der Wahl und einem warmen Abschluss. Die „Neu: …"-Seiten erscheinen nur noch Rückkehrern, wenn es wirklich etwas Neues gibt
- **„Sounds abspielen" schaltet jetzt wirklich alle Töne ab**: Preisalarm, Gruppensuche, Messenger, Blockliste, Gebots-Fenster, neue Bewerbungen, Abfahrts-Warnungen, Notizzettel und Handwerk hielten sich bisher nicht an den Schalter

**English**
- **Whispers fully optional**: new switch "Use GuildPride's whisper window" (Settings › Guild). Off means GuildPride no longer touches whispers – everything stays in Blizzard's chat. The previous whisper options are now sub-items of it
- **Friendlier intro for new players**: a shorter, focused tour with the overview page "What GuildPride can do for you", a recommendation at the tier choice, a short confirmation after choosing and a warm closing page. The "New: …" pages now only show to returning players when there is really something new
- **"Play sounds" now really turns off every sound**: price alerts, group finder, messenger, blocklist, bidding window, new applications, departure warnings, notes and crafting did not respect the switch before

## 2.46.0

**Deutsch**
- **Light, Medium oder Max**: Beim ersten Einloggen nach dem Update fragt GuildPride einmal, wie du es nutzen willst. **Light**: nur die Gilde (Gildenfenster, Chat, Events, Raid-Werkzeuge, Messenger). **Medium**: dazu alles für unterwegs allein (Handwerk, Buffs, Leveln, Komfort, Reisen, Zettel, Rares, Item-Vergleich). **Max**: alles, dazu Auktionshaus und Verkaufs-Berater. Was nicht dazugehört, ist aus und verschwindet auch aus Menü, Einstellungen, Suche und Befehlen. Ändern mit `/gp stufe` oder dem Knopf oben in den Einstellungen; ohne Wahl bleibt alles wie bisher
- **Komfort** (neuer Abschnitt in den Einstellungen, Übersicht mit `/gp qol`): Leveln mit EP pro Stunde, Zeit bis zum nächsten Level und Ausgeruht (`/gp leveln`, verschiebbarer EP-Balken), Ruf-Balken folgt von selbst, Warnung bei fehlenden Reagenzien oder Munition und vollen Taschen, Ruhestein-Info, Links aus dem Chat sammeln (`/gp links`)
- **Auf Wunsch, ab Werk aus**: automatisch reparieren (auch aus der Gildenbank), Graues verkaufen, Quests automatisch annehmen und abgeben, Einladungen von Gilde und Freunden annehmen, Duelle ablehnen
- **Buff-Food**: zählt nur noch „Satt“ und schlägt keine Rezepte mehr vor. Neu: Vorwarnung 2 Minuten vorher, auf Wunsch nur in Instanzen und Gruppen, zeigt, was du kochen kannst und welche Twinks Buff-Food haben, Erinnerung beim Bereitschaftscheck
- Daten von Gilden, in denen du seit 180 Tagen nicht warst, werden aufgeräumt
- Behoben: Fehler im kleinen Handwerk-Fenster während des Kampfes (Abklingzeiten)
- Stabiler bei geschützten Werten in Forever

**English**
- **Light, Medium or Max**: at the first login after the update GuildPride asks once how you want to use it. **Light**: guild only (guild window, chat, events, raid tools, messenger). **Medium**: plus everything for playing on your own (crafting, buffs, levelling, comfort, travel, notes, rares, item comparison). **Max**: everything, plus auction house and selling advisor. Whatever is not part of it is off and also disappears from the menu, settings, search and commands. Change it with `/gp tier` or the button at the top of the settings; without a choice everything stays as before
- **Comfort** (new settings section, overview with `/gp qol`): levelling with XP per hour, time to the next level and rested (`/gp leveln`, movable XP bar), reputation bar follows by itself, warning about missing reagents or ammo and full bags, hearthstone info, collect links from chat (`/gp links`)
- **If you like, off by default**: auto repair (also from the guild bank), sell grey items, accept and turn in quests automatically, accept invites from guild and friends, decline duels
- **Buff food**: only counts "Well Fed" and no longer suggests recipes. New: early warning 2 minutes before, optionally only in instances and groups, shows what you can cook and which alts have buff food, reminder on ready checks
- Data of guilds you have not visited for 180 days is cleaned up
- Fixed: error in the small crafting window during combat (cooldowns)
- More stable with protected values in Forever

## 2.45.1

**Deutsch**
- Behoben: Oben rechts im Gildenfenster lag die Lupe (Suche) über dem Nachrichten-Knopf; jetzt stehen alle Knöpfe sauber nebeneinander

**English**
- Fixed: at the top right of the guild window the magnifier (search) covered the messages button; all buttons now sit neatly side by side

## 2.45.0

**Deutsch**
- **Tester**: Der Entwickler kann einzelne Spieler einladen, neue Funktionen vor allen anderen zu testen. Nur mit deinem Ja, jederzeit abschaltbar (`/gp tester aus` oder Einstellungen › Teilen)

**English**
- **Testers**: the developer can invite individual players to try new features before everyone else. Only with your yes, can be turned off at any time (`/gp tester off` or Settings › Sharing)

## 2.44.0

**Deutsch**
- **„Heute“ auf der Übersicht**: Events der nächsten 24 Stunden mit deiner Antwort, deine Auktionen (verkauft, laufen ab), Post, fertige Abklingzeiten deiner Twinks, offene Gildenaufträge; Offiziere sehen offene Fragen und Bewerbungen
- **Rezept-Lücken: „Das lerne ich“** (Rechtsklick): alle in der Gilde sehen, wer ein fehlendes Rezept übernimmt; gelernt verschwindet es von selbst
- **Auktions-Tipps** (GuildPride-Auktionshaus › Verkaufen › „Tipps“): was in Taschen und Bank gerade klar über dem Schnitt liegt
- **Schneller**: die Gildenliste wird bei Änderungen nur noch einmal gelesen und höchstens einmal je Sekunde
- **Weniger Speicher**: keine englischen Texte auf deutschen Clients, Rezepte gepackt, Datensicherung kleiner (neu Lernbares bleibt draußen und geht beim Zurückspielen nicht verloren)
- Behoben: „\n“ im Fenster beim Abbrechen einer Auktion

**English**
- **“Today” on the overview**: events of the next 24 hours with your answer, your auctions (sold, expiring), mail, ready cooldowns of your alts, open guild orders; officers see open questions and applications
- **Recipe gaps: “I will learn this”** (right click): everyone in the guild sees who takes on a missing recipe; once learned it disappears by itself
- **Auction tips** (GuildPride auction house › Sell › “Tips”): what in your bags and bank is clearly above average right now
- **Faster**: the guild list is read only once per change and at most once per second
- **Less memory**: no English texts on German clients, packed recipes, smaller backups (what can be relearned stays out and is kept when restoring)
- Fixed: “\n” in the window when cancelling an auction

## 2.43.1

**Deutsch**
- **Rezept-Lücken** (`/gp luecken`, Werkzeuge und Reiter Handwerk): welche Rezepte eines Berufs niemand in der Gilde kann und wer den Beruf hat
- **Buff-Food- und Schlafsack-Fenster** sind für neue Spieler aus; wer sie schon nutzt, behält sie (Einstellungen › Buffs & Erholung)
- **Auktionspreise** brauchen rund ein Drittel weniger Platz; zufällig verzauberte Gegenstände werden nach 14 Tagen vergessen
- **Handwerk**: Öffnet das Spiel das Berufsfenster eines Mitglieds nicht, gilt das nur noch für diesen Spieler; fremde Berufsfenster zählen nie als eigene
- **Französisch, Spanisch, Russisch**: viel mehr Wörter und Knöpfe übersetzt
- **Spielerliste leer?** GuildPride merkt, wenn seine Chat-Kanäle tot sind, und tritt ihnen von selbst neu bei
- Behoben: Lua-Fehler in Instanzen beim Überfahren von Spielern (Notizen im Tooltip)
- Behoben: zu lange Flüsternachrichten im Messenger gaben einen Fehler; der Rest bleibt jetzt stehen und geht mit dem nächsten Enter raus
- **Verkaufs-Berater im Tooltip** geht wieder und ist klarer: BEHALTEN, HÄNDLER oder AUKTIONSHAUS, darunter Preise und Unterschied nach Gebühr
- **Item-Tooltip aufgeräumt**: ein Block „GuildPride“ mit der Empfehlung rechts oben; Einzelheiten mit Umschalt (Einstellungen › Allgemein: immer alles zeigen)
- **Farbmarken in den Taschen** für die Empfehlung: grün Auktionshaus, gelb Händler, orange behalten, blau nachsehen; ab Werk aus (Einstellungen › Auktionshaus)
- **Einstellungen kürzer**: je Abschnitt zuerst das Wichtige, der Rest mit einem Klick; die Suche findet weiterhin alles
- **Eigene Fehler gehen nicht mehr still verloren**, sie stehen im Fehlerbericht (`/gp fehler`)
- Behoben: Baupläne im Tooltip, Alt-Klick auf Links und der Wert beim Angeln gingen in Forever nicht

**English**
- **Recipe gaps** (`/gp gaps`, tools and Crafting tab): which recipes of a profession nobody in the guild knows and who has the profession
- **Buff food and sleeping bag windows** are off for new players; if you already use them, they stay on (Settings › Buffs)
- **Auction prices** need about a third less space; randomly enchanted items are forgotten after 14 days
- **Crafting**: if the game does not open a member's profession window, this now only applies to that player; other players' profession windows never count as yours
- **French, Spanish, Russian**: many more words and buttons translated
- **Player list empty?** GuildPride notices when its chat channels are dead and rejoins them by itself
- Fixed: Lua error in instances when hovering players (notes in the tooltip)
- Fixed: whispers that were too long caused an error in the messenger; the rest now stays and goes out with the next Enter
- **Sell advisor in the tooltip** works again and is clearer: KEEP, VENDOR or AUCTION HOUSE, below it prices and the difference after the fee
- **Item tooltip tidied up**: one “GuildPride” block with the advice at the top right; details with Shift (Settings › General: always show everything)
- **Colour marks in the bags** for the advice: green auction house, yellow vendor, orange keep, blue check; off by default (Settings › Auction house)
- **Shorter settings**: the important ones first in each section, the rest with one click; the search still finds everything
- **Own errors no longer get lost silently**, they appear in the error report (`/gp fehler`)
- Fixed: recipes in the tooltip, Alt-click on links and the fishing value did not work in Forever

## 2.43.0

**Deutsch**
- **Werkzeuge als Kacheln** mit Symbol; Rechtsklick blendet aus, was du nicht brauchst
- **Alle Befehle mit Erklärung**: `/gp hilfe`, ein Klick führt einen aus
- **Einstellungen**: Sprungleiste oben mit einem Knopf je Abschnitt
- **Raid-Bereitschaft** geht auf, wenn du einen Bereitschaftscheck startest; Mindestmenge Tränke einstellbar, Tränke werden an der Item-Art erkannt
- **Boss-Notizen** mit mehreren Zeilen und Vorlage
- **Materialliste**: Gegenstand über den Namen finden, Bestand der Gildenbank zählt mit
- **Schnitzeljagd** mit eigenem Fenster; **Loot-Verlauf** und **Quiz-Rangliste** gleichen sich über Offiziere ab
- **Paten** sehen, wenn ein neues Mitglied online ist; **Abklingzeiten** mit der echten Dauer, wo das Spiel sie nennt
- **Anwesenheit** bei Events: Nachzügler werden ergänzt; Hinweis, wenn nichts erfasst wird
- **Farben für Farbenblinde** gelten auch in den Reitern mit Listen
- **Nutzung mitteilen – nur mit deinem Ja**: eine Seite in der Einführung fragt einmal nach Fehlern und Nutzung (nur Zähler, nie Inhalte); ohne Haken wird nichts gesendet. Einstellungen › Teilen
- **Weniger Nachrichten** in der Gilde beim Einloggen; gelöschte Notizen und Ziele werden nach 60 Tagen vergessen
- Texte, Befehlsübersicht und Einführung auf den neuen Stand gebracht

**English**
- **Tools as tiles** with an icon; right click hides what you do not need
- **All commands with explanations**: `/gp help`, a click runs one
- **Settings**: jump bar at the top with one button per section
- **Raid readiness** opens when you start a ready check; minimum number of potions adjustable, potions are recognised by item type
- **Boss notes** with several lines and a template
- **Material list**: find items by name, the guild bank stock counts too
- **Treasure hunt** with its own window; **loot history** and **quiz leaderboard** sync through officers
- **Mentors** see when a new member is online; **cooldowns** with the real duration where the game tells it
- **Attendance** at events: latecomers are added; a hint when nothing is recorded
- **Colours for colour blindness** also apply in the tabs with lists
- **Share usage – only with your yes**: a page in the introduction asks once about errors and usage (only counters, never contents); without a check mark nothing is sent. Settings › Sharing
- **Fewer messages** in the guild at login; deleted notes and goals are forgotten after 60 days
- Texts, command overview and introduction brought up to date

## 2.42.0

**Deutsch**
- **Werkzeuge** (neue Seite unter „Planen“): alles Neue für Gilde und Raid mit einem Klick
- **Raid-Bereitschaft** (`/gp bereit`): Leiter und Assistenten sehen Haltbarkeit, „Satt“, Tränke und Elixiere der Gruppe, Probleme zuerst; beim Bereitschaftscheck antworten alle von selbst
- **Quests der Gilde** (`/gp quests`): wer online ist und dieselbe Quest hat, deine Zone zuerst; Klick lädt ein
- **Boss-Notizen** (`/gp boss`): Offiziere schreiben je Boss eine kurze Taktik; das Fenster geht beim Betreten der Instanz einmal auf
- **Materialliste der Gilde** (`/gp material`): was gebraucht wird und wer wie viel beisteuert; Rechtsklick legt den Rest in den Tracker
- **Loot-Verlauf** (`/gp loot`), **Abklingzeiten der Gruppe** (`/gp abklingzeiten`), **Event-Auswertung** für Offiziere (`/gp auswertung`)
- **Paten für Neue** (`/gp paten`), **Gildenquiz** (`/gp quiz`), **Schnitzeljagd** (`/gp jagd`), **Gildenalbum** mit den ersten Bosskills (`/gp album`)
- **Jubiläen** in der Übersicht: 30 und 100 Tage, ein halbes Jahr, jedes Jahr in der Gilde
- **Suche über alles** (Lupe oben im Gildenfenster, `/gp suche`): Mitglieder, Events, Einstellungen, Befehle, Boss-Notizen und Rezepte
- **Pakete** (`/gp paket gilde`, `raid` oder `alles`): schaltet nur an, was du brauchst; alles bleibt einzeln änderbar
- **Besser lesbar** und **Farben für Farbenblinde** (Einstellungen › Allgemein)
- **Fehler automatisch melden – nur mit deinem Ja**: hat GuildPride einen Fehler, wirst du einmal gefragt, ob er an den Entwickler gehen darf. Abschaltbar unter Einstellungen › Teilen
- **Fehlerbericht** zählt nur noch GuildPride-Fehler (bisher landeten Fehler anderer Addons darin) und ist nach einem Update leer; auch mit BugGrabber; `/gp fehlertest` zum Ausprobieren
- **Weniger Speicher**: Auktionspreise brauchen nur noch einen Bruchteil von Arbeitsspeicher und Dateigröße; Zettel und Schiffe rechnen seltener; `/gp diag` zeigt die Leistung
- **Einführung** mit neuen Seiten; erste Texte auf Französisch, Spanisch und Russisch

**English**
- **Tools** (new page under "Plan"): everything new for guild and raid with one click
- **Raid readiness** (`/gp ready`): leader and assistants see durability, well fed, potions and elixirs of the group, problems first; on a ready check everyone answers by itself
- **Guild quests** (`/gp quests`): who is online and has the same quest, your zone first; a click invites
- **Boss notes** (`/gp boss`): officers write short tactics per boss; the window opens once when you enter the instance
- **Guild material list** (`/gp mats`): what is needed and who contributes how much; right click puts the rest into your tracker
- **Loot history** (`/gp loot`), **group cooldowns** (`/gp cooldowns`), **event statistics** for officers (`/gp stats`)
- **Mentors for new members** (`/gp mentor`), **guild quiz** (`/gp quiz`), **treasure hunt** (`/gp hunt`), **guild album** with your first boss kills (`/gp album`)
- **Anniversaries** on the overview: 30 and 100 days, half a year, every year in the guild
- **Search everything** (magnifier at the top of the guild window, `/gp search`): members, events, settings, commands, boss notes and recipes
- **Presets** (`/gp preset guild`, `raid` or `all`): turns on only what you need; everything can still be changed one by one
- **Easier to read** and **colours for colour blindness** (Settings › General)
- **Report errors automatically – only with your yes**: if GuildPride has an error, you are asked once whether it may go to the developer. Can be turned off under Settings › Sharing
- **Error report** only counts GuildPride errors (errors of other addons ended up there before) and is empty after an update; also with BugGrabber; `/gp errortest` to try it
- **Less memory**: auction prices need only a fraction of the memory and file size; notes and ships calculate less often; `/gp diag` shows the performance
- **Introduction** with new pages; first texts in French, Spanish and Russian

## 2.41.3

**Deutsch**
- **Buff-Erinnerung abschalten**: oben im Buff-Fenster gibt es jetzt ein **Zahnrad** – dort lassen sich die Buff-Food- und die Schlafsack-/Lagerfeuer-Erinnerung direkt abschalten

**English**
- **Turn off the buff reminder**: the buff window now has a **gear** at the top – turn the buff food and the sleeping bag/campfire reminder off right there

## 2.41.2

**Deutsch**
- **Handwerk im Hauptmenü**: das Gildenfenster hat jetzt einen eigenen Eintrag „Handwerk“ (Berufe der Gilde, Knopf „Handwerk & Guides“). „Planen“ zeigt nur noch Events, Wünsche und Umfragen

**English**
- **Crafting in the main menu**: the guild window now has its own "Crafting" entry (guild professions, "Crafting & guides" button). "Plan" only shows events, wishes and polls

## 2.41.1

**Deutsch**
- **Handwerk einfacher**: das Fenster zeigt nur noch **Leveln**. Rezepte, Gewinn, Gilde & Twinks, Tracker und Kompaktansicht findest du unter **„Mehr …“**, zurück geht es mit **„‹ Leveln“**
- **Tracker stellt her**: Knopf **„Herstellen: X ×N“** – jeder Klick stellt das nächste getrackte Rezept her, so oft wie getrackt und Zutaten da sind. Zwischenprodukte (z. B. Barren) kommen zuerst, der Tracker zählt mit und streicht fertige Rezepte. Bei geschlossenem Berufsfenster steht „Erst Berufsfenster öffnen“ auf dem Knopf
- **Angeln**: der Fang wird jetzt richtig gezählt (auch mit Auto-Beute) und mit Gold bewertet – Händlerpreis oder Auktionshaus nach Gebühr, je nachdem was mehr bringt

**English**
- **Simpler crafting**: the window only shows **Leveling** now. Recipes, profit, guild & alts, tracker and compact view are under **"More …"**, **"‹ Leveling"** takes you back
- **Tracker crafts**: button **"Craft: X ×N"** – every click crafts the next tracked recipe, as often as tracked and reagents allow. Intermediates (e.g. bars) come first, the tracker counts down and removes finished recipes. With the profession window closed the button says "Open the profession window first"
- **Fishing**: your catch is now counted correctly (also with auto loot) and valued in gold – vendor price or auction house after the fee, whichever pays more

## 2.41.0

**Deutsch**
- **Handwerk – alles neu** (`/gp handwerk`, Knopf „Handwerk & Guides“ im Berufe-Reiter): ein Fenster mit vier Reitern
  - **Leveln**: Weg von 1 bis 300 für jeden Beruf – was du wie oft herstellst, Kasten „Als Nächstes“ mit Zutaten, Bestand und was fehlt, Fortschrittsbalken, nächster Rang beim Lehrer, Kosten bis zum Ziel. Klick wählt das Rezept im Berufsfenster, Umschalt+Klick trackt, Rechtsklick hakt einen Schritt ab
  - **Rezepte**: alle Rezepte eines Berufs und wer von deinen Charakteren sie kann; **Gewinn**: was sich lohnt; **Gilde & Twinks**: Berufe und Abklingzeiten deiner Charaktere, wer in der Gilde was kann, „Gilde fragen“
  - Tooltip über einem Rezept zeigt das hergestellte Item mit Werten und die Zutaten mit Bildern; dünne Scrollleisten, wo die Liste länger ist
- **Rezeptkarte** neben dem Berufsfenster (frei verschiebbar): Farbe, ab wann grau, Zutaten, Gewinn, „Guide-Rezept“ und „Bestes jetzt“
- **Tracker** (`/gp tracker`): zählt, was du sammelst; am Händler kauft ein Klick genau, was fehlt; im Auktionshaus sucht ein Klick die fehlenden Sachen
- **Lehrer auf der Karte**: Klick auf einen Beruf zeigt alle Lehrer deiner Fraktion auf der Weltkarte, mit Wegpunkt; Bauplan-Händler werden beim Besuch gemerkt
- **Hinweise**: Guide-Schritt geschafft, Rang-Limit erreicht, was du am Lehrer lernen solltest; Bank und Briefkasten: Mats holen, einlagern oder an den Twink schicken; Kompaktansicht mit Punkten pro Stunde (`/gp handwerk mini`)
- **Sammeln**: deine Erz- und Kräuterfundorte auf der Weltkarte, gefärbt nach deiner Fertigkeit; Hinweis, wenn ein Vorkommen keine Punkte mehr gibt
- **Angel-Leiste** mit Angel in der Hand: Auswerfen, bester Köder, Fang mit Wert. **Eine Taste fürs Angeln**: Taste wählen – einmal drücken wirft aus, nochmal holt ein
- **Tooltips**: Baupläne (wer es lernen kann), Bestand deiner Charaktere, was dein Guide noch braucht, Herkunft der Materialien, und **Verkaufs-Berater**: Händler, Auktionshaus oder behalten
- Hinweis, wenn im Handelschannel jemand sucht, was du herstellen kannst
- **Notizzettel**: Zettel kommen auch nach, wenn du offline warst; kleine Zettel auf der Minimap; Zettel ausblenden oder Schreiber stummschalten; schöneres Papier und Schrift; Zettel für alle lassen sich getrennt abschalten
- Alles einzeln abschaltbar in den Einstellungen unter „Handwerk“

**English**
- **Crafting – all new** (`/gp handwerk`, "Crafting & guides" button in the professions tab): one window with four tabs
  - **Leveling**: the way from 1 to 300 for every profession – what to craft and how often, "Up next" box with reagents, stock and what is missing, progress bar, next rank at the trainer, cost to the goal. Click selects the recipe in the profession window, shift-click tracks, right-click ticks off a step
  - **Recipes**: all recipes of a profession and which of your characters know them; **Profit**: what pays off; **Guild & alts**: professions and cooldowns of your characters, who in the guild can craft what, "Ask the guild"
  - The tooltip over a recipe shows the crafted item with its stats and the reagents with icons; thin scroll bars where a list is longer
- **Recipe card** next to the profession window (free to move): colour, when it turns gray, reagents, profit, "Guide recipe" and "Best now"
- **Tracker** (`/gp tracker`): counts what you gather; at a vendor one click buys exactly what is missing; at the auction house one click searches the missing items
- **Trainers on the map**: clicking a profession shows all trainers of your faction on the world map, with a waypoint; pattern vendors are remembered when you visit them
- **Hints**: guide step done, rank limit reached, what to learn at the trainer; bank and mailbox: fetch mats, deposit them or send them to an alt; compact view with points per hour (`/gp handwerk mini`)
- **Gathering**: your ore and herb spots on the world map, coloured by your skill; hint when a node no longer gives points
- **Fishing bar** while holding a fishing pole: cast, best lure, catch with value. **One key for fishing**: choose a key – press once to cast, again to reel in
- **Tooltips**: patterns (who can learn it), stock of your characters, what your guide still needs, where materials come from, and a **sell advisor**: vendor, auction house or keep
- Notice when someone in trade chat looks for something you can craft
- **Map notes**: notes arrive even if you were offline; small notes on the minimap; hide notes or mute a writer; nicer paper and font; public notes can be turned off separately
- Everything can be turned off one by one in the settings under "Crafting"

## 2.40.0

**Deutsch**
- **Notizzettel auf der Karte**: „Zettel schreiben“ (Knopf auf der Weltkarte, Kartenfilter oder `/gp zettel schreiben`) hängt einen Zettel genau dort auf, wo du stehst – für die Gilde (blau, über den abgesicherten Gildenkanal) oder für alle (weiß, über den offenen Kanal). Wer bis auf etwa 5 m herankommt, dem geht der Zettel auf: wie ein echter Zettel aus dem Ringbuch, mit Text und Vor- und Nachnamen als Unterschrift. Zettel halten 7 Tage, eigene kannst du abreißen. Abschaltbar wie die Rares: Rechtsklick auf den Knopf, Kartenfilter, Einstellungen oder `/gp zettel aus`
- **Buff-Erinnerung**: Lagerfeuer wird am deutschen Buff „Lagervorteile“ erkannt, „Satt“ in Anführungszeichen wird gefunden, das Lagerfeuer wird per Klick direkt neben dich gesetzt
- **Gildenbank-Verlauf**: liest das Protokoll jetzt auch in WoW Forever beim Öffnen der Gildenbank (Fächer nacheinander); leere Antworten überschreiben nichts mehr
- **Planen**: die Knöpfe oben passen ins Fenster („Offene Dungeons“ ragte heraus)

**English**
- **Notes on the map**: "Write a note" (button on the world map, map filter or `/gp zettel write`) pins a note right where you stand – for the guild (blue, through the secured guild channel) or for everyone (white, through the open channel). Whoever comes within about 5 m gets the note opened: like a real note torn from a ring binder, with the text and first and last name as signature. Notes last 7 days, you can tear off your own. Can be turned off like the rares: right-click the button, map filter, settings or `/gp zettel off`
- **Buff reminder**: the campfire is recognised by the German buff name too, "Well Fed" in quotes is found, a click puts the campfire right next to you
- **Guild bank log**: now reads the log in WoW Forever when you open the guild bank (one tab after another); empty answers no longer overwrite anything
- **Plan**: the buttons at the top fit into the window ("Open dungeons" stuck out)

## 2.39.0

**Deutsch**
- **Messenger**: Nachrichten an Gildenmitglieder mit GuildPride – auch, wenn sie offline sind. Andere Mitglieder heben die Nachricht bis zur Zustellung auf (bis 14 Tage), du siehst „zugestellt“. Geht an den Main, also an alle Charaktere. Fenster mit Unterhaltungen und Verlauf, in der Größe ziehbar; Sprechblase oben im Gildenfenster und Zahl am Minimap-Knopf bei Ungelesenem. `/gp nachrichten`, `/gp nachricht Name Text`
- **Flüstern im Messenger (wie WIM)**: Wer dich anflüstert, bekommt eine Unterhaltung und das Fenster geht auf; auch beim eigenen Flüstern (`/w`, R, Namensmenü). Antworten im Fenster sind normales Flüstern, Blizzards Chat bleibt unverändert. Einstellbar: im Kampf, nur Gilde/Freunde/Gruppe, eigenes Flüstern
- **Willkommensfenster** für neue Mitglieder: Nachricht des Tages, Gildeninfo, Discord- und Community-Link der Gilde, Frage an die Offiziere (`/gp willkommen`)
- **Fragen neuer Mitglieder**: gehen über den Messenger an alle Offiziere (auch offline); Verwaltung › „Fragen neuer Mitglieder“ zeigt offen/beantwortet, Antworten im Messenger
- **Links der Gilde**: Offiziere tragen unter Verwaltung den eigenen Discord- und Community-Link ein; gilt für alle Mitglieder, im Willkommensfenster und im Begrüßungstext als `{discord}` und `{community}`
- **Buff-Food- und Erholungs-Erinnerung**: läuft „Satt“ aus, zeigt ein kleines Fenster das beste Essen für deine Klasse aus deinen Taschen – ein Klick isst es. Beim Leveln genauso für Schlafsack und Lagerfeuer, wenn die Erholung ausläuft (`/gp buff`, `/gp rast`)
- **Offene Dungeons** (unter „Planen“): wer in der Gilde welchen Dungeon oder Raid noch braucht; Klick lädt alle ein, die online sind. Die Gruppensuche schlägt passende Mitspieler vor („Passend online“)
- **Auktionshaus**: Briefkasten fasst Verkäufe zusammen („3 verkauft, 34g nach Gebühr · 1 abgelaufen“); Goldmünze in den Taschen, wenn ein Preis gerade 25 % über dem Schnitt liegt
- **Gildenbank-Verlauf** lesbar mit Namensfilter und Wochensumme (`/gp bank`, wo es eine Gildenbank gibt)
- **Abwesenheit**: abgemeldete Mitglieder zeigen „abgemeldet bis …“ statt roter Offline-Zeit
- **Abfahrten**: Ankunftszeit am Ziel („Ankunft ~14:32“)
- **Einstellungen sichern**: `/gp export` und `/gp import` für anderen PC oder Twink
- Preistausch sparsamer: Antworten schicken nur die Tage, die fehlen

**English**
- **Messenger**: messages to guild members with GuildPride – even when they are offline. Other members keep the message until delivery (up to 14 days), you see "delivered". Goes to the main, so all their characters get it. Window with conversations and history, resizable; speech bubble at the top of the guild window and a count on the minimap button for unread messages. `/gp messages`, `/gp message name text`
- **Whispers in the messenger (like WIM)**: whoever whispers you gets a conversation and the window opens; also for your own whispers (`/w`, R, name menu). Replies in the window are normal whispers, Blizzard's chat stays unchanged. Options: in combat, only guild/friends/group, own whispers
- **Welcome window** for new members: message of the day, guild info, the guild's Discord and community link, question to the officers (`/gp welcome`)
- **Questions from new members**: go to all officers through the messenger (even offline); Management › "Questions from new members" shows open/answered, reply in the messenger
- **Guild links**: officers enter the guild's own Discord and community link under Management; applies to all members, in the welcome window and in the greeting text as `{discord}` and `{community}`
- **Buff food and rest reminder**: when "Well Fed" runs out, a small window shows the best food for your class from your bags – one click eats it. While levelling the same for sleeping bag and campfire when the rest bonus runs out (`/gp buff`, `/gp rest`)
- **Open dungeons** (under "Plan"): who in the guild still needs which dungeon or raid; a click invites everyone online. The group finder suggests fitting players ("Online and fitting")
- **Auction house**: the mailbox sums up sales ("3 sold, 34g after fee · 1 expired"); gold coin in your bags when a price is currently 25 % above average
- **Guild bank log** readable with name filter and weekly totals (`/gp bank`, where there is a guild bank)
- **Absence**: members who reported absence show "away until …" instead of a red offline time
- **Departures**: arrival time at the destination ("arrives ~14:32")
- **Back up settings**: `/gp export` and `/gp import` for another PC or character
- Leaner price exchange: answers only send the days that are missing

## 2.38.0

**Deutsch**
- **Auktionshaus-Tooltip mit eigenem Abschnitt**: GuildPride steht jetzt unter einer eigenen Überschrift, auch wenn Auctionator oder ein anderes Preis-Addon aktiv ist
- **Preisverlauf im Tooltip**: „Verlauf (N Tage): Ø · Tief · Hoch“ aus bis zu 30 Tagen. Die Tagespreise werden mit anderen GuildPride-Spielern geteilt, so gibt es auch einen Verlauf für Gegenstände, die du nie gesucht hast
- **Mehr im Tooltip**: wie viele Spieler den Preis gemeldet haben, Wochentrend (teurer/günstiger), Händlerpreis mit Hinweis „lieber beim Händler verkaufen“ und bei hergestellten Gegenständen Zutatenkosten und Gewinn (Berufsfenster einmal öffnen)
- Jede Tooltip-Zeile lässt sich in den Einstellungen (Auktionshaus) einzeln abschalten
- **Gruppensuche**: Rollen-Symbole für Tank, Heiler und Schaden, auch auf den „Fehlt noch“-Knöpfen
- **Übersicht › Diese Woche**: „Gilde unterwegs“ zeigt, welche Mitglieder gerade in welchem Dungeon oder Raid sind
- **Blockliste und Notizen**: gesperrte Spieler bekommen ein rotes X vor dem Namen, Spieler mit Notiz ein Zettel-Symbol
- `/gp diag` zeigt jetzt auch andere geladene Addons und bekannte Überschneidungen

**English**
- **Auction house tooltip with its own section**: GuildPride now has its own heading, also when Auctionator or another price addon is active
- **Price history in the tooltip**: "History (N days): avg · low · high" from up to 30 days. Daily prices are shared with other GuildPride players, so there is a history even for items you never searched
- **More in the tooltip**: how many players reported the price, weekly trend (pricier/cheaper), vendor price with a "better sell to a vendor" hint and, for crafted items, reagent cost and profit (open the profession window once)
- Every tooltip line can be switched off on its own in the settings (Auction house)
- **Group finder**: role icons for tank, healer and damage, also on the "still missing" buttons
- **Overview › This week**: "Guild out and about" shows which members are in which dungeon or raid right now
- **Block list and notes**: blocked players get a red X before their name, players with a note a note icon
- `/gp diag` now also lists other loaded addons and known overlaps

## 2.37.1

**Deutsch**
- **Behoben**: Chat-Nachrichten (Gilde, Flüstern, Gruppe) kamen bei manchen Spielern nicht an

**English**
- **Fixed**: chat messages (guild, whisper, group) did not reach some players

## 2.37.0

**Deutsch**
- **Blockliste**: Spieler, die nicht in die Gilde eingeladen werden sollen (Verwaltung › „Blockliste …“, `/gp blockliste`, `/gp block Name Grund`). Gilt für die ganze Gilde, nur Offiziere ändern sie. Einladen über GuildPride lehnt gesperrte Spieler ab, Blizzards Einladefenster zeigt beim Eintippen eine Warnung, und tritt ein gesperrter Spieler doch bei, werden Offiziere gewarnt
- **Notizen zu Spielern**: `/gp notiz Name Text` – die Notiz steht im Tooltip des Spielers, nur für dich
- **Abfahrten im Minimap-Tooltip**: gemessene Abfahrten in der Nähe (Schiffe, Zeppeline, Tiefenbahn) stehen im Tooltip des GuildPride-Knopfs
- **Preisalarm-Übersicht**: `/gp preis` zeigt alle Alarme mit dem zuletzt bekannten Preis; ein grüner Haken heißt: gerade günstiger als dein Alarm
- **Tiefenbahn**: eigenes Lokomotiven-Symbol und passende Texte („steht am Bahnsteig“, „fährt ab“) statt Schiffs-Wörtern
- „Schiffs-Zähler“ heißt jetzt **Abfahrten**, weil auch Zeppeline und die Bahn dazugehören

**English**
- **Block list**: players who must not be invited to the guild (Management › "Block list …", `/gp blocklist`, `/gp block name reason`). Applies to the whole guild, only officers change it. Inviting through GuildPride refuses blocked players, Blizzard's invite window shows a warning while typing, and officers are warned if a blocked player joins anyway
- **Notes on players**: `/gp note name text` – the note shows in the player's tooltip, only for you
- **Departures in the minimap tooltip**: measured departures nearby (ships, zeppelins, Deeprun Tram) show in the GuildPride button's tooltip
- **Price alert overview**: `/gp price` lists all alerts with the last known price; a green check means: currently below your alert
- **Deeprun Tram**: its own locomotive icon and fitting texts ("at the platform", "departs") instead of ship words
- "Ship timer" is now called **Departures**, since zeppelins and the tram belong to it too

## 2.36.0

**Deutsch**
- **Preisalarm aus dem Chat**: `/gp preis <Gegenstand> <Preis>` legt einen Preisalarm fürs Auktionshaus an, ohne dessen Fenster zu öffnen (z. B. `/gp preis Schwarzer Lotus 1g 50s`). Gegenstand per Shift-Klick, Item-ID oder Name; `/gp preis <Gegenstand> aus` entfernt ihn, `/gp preis` zeigt alle
- **Preisalarm mit geteilten Preisen**: Sieht ein anderer GuildPride-Spieler den Gegenstand unter deinem Wunschpreis, meldet sich der Alarm auch, wenn du nicht am Auktionshaus bist
- **Tiefenbahn-Erinnerung** kommt 15 Sekunden vor der Abfahrt statt 1 Minute – die Bahn fährt etwa alle 70 Sekunden

**English**
- **Price alert from the chat**: `/gp price <item> <price>` adds an auction house price alert without opening its window (e.g. `/gp price Black Lotus 1g 50s`). Item by Shift-click, item ID or name; `/gp price <item> off` removes it, `/gp price` lists all
- **Price alert with shared prices**: When another GuildPride player sees the item below your price, the alert also fires while you are away from the auction house
- **Deeprun Tram reminder** comes 15 seconds before departure instead of 1 minute – the tram runs about every 70 seconds

## 2.35.0

**Deutsch**
- **Community-Knopf für die Horde**: Horde-Spieler (EU, Server „Normal“) bekommen jetzt den Einladungslink der Horden-Community, Allianz-Spieler weiter ihren
- **Alarm auch für GuildPride-Einträge**: Trägt sich ein Gilden- oder Server-Spieler für einen Dungeon ein, den du im Dungeon-Filter angehakt hast, kommen Ton und Chatzeile
- **Schiffe: beide Zeiten**: Ist die Zeit unsicher, steht die zweite gemeldete Abfahrt gleich dabei („unsicher – oder ab in 3:10“)

**English**
- **Community button for the Horde**: Horde players (EU, "Normal" server) now get the Horde community's invite link, Alliance players keep theirs
- **Alert for GuildPride entries too**: When a guild or server player signs up for a dungeon ticked in your dungeon filter, you get a sound and a chat line
- **Ships: both times**: When the time is uncertain, the other reported departure is shown right away ("uncertain – or departs in 3:10")

## 2.34.0

**Deutsch**
- **Alarm bei passender Gruppe**: Sind im Dungeon-Filter Dungeons angehakt, melden sich neue passende Gruppen aus dem Dungeonbrowser mit Ton und Chatzeile. Abschaltbar im Filter-Fenster („Ton bei neuen passenden Gruppen“)
- **Schiffszeiten ehrlicher**: Hat kürzlich jemand eine andere Zeit gemeldet (z. B. von einem anderen Layer), steht „unsicher – andere Zeiten gemeldet“ statt einer scheinbar sicheren Zeit. Deine eigene Messung gilt weiter zuerst
- **Meilensteine filtern**: Leiste über der Liste mit Alle, Stufe, Erfolge, Bosse und Beitritte, dazu eine Suche nach Spielernamen
- **Update-Hinweis** kommt jetzt auch, wenn Spieler auf dem Server (nicht nur in der Gilde) eine neuere GuildPride-Version haben

**English**
- **Alert for matching groups**: With dungeons ticked in the dungeon filter, new matching Dungeon Finder groups announce themselves with a sound and a chat line. Can be turned off in the filter window ("Sound for new matching groups")
- **More honest ship times**: If someone recently reported a different time (e.g. from another layer), it says "uncertain – other times reported" instead of a seemingly certain time. Your own measurement still comes first
- **Filter milestones**: bar above the list with All, Level, Achievements, Bosses and Joins, plus a player name search
- **Update notice** now also appears when players on the server (not only in the guild) have a newer GuildPride version

## 2.33.1

**Deutsch**
- Kleine Verbesserungen und Aufräumarbeiten

**English**
- Small improvements and clean-up

## 2.33.0

**Deutsch**
- **Mehr Meilensteine**: GuildPride behält jetzt bis zu 500 statt 100 Einträge. Beim Öffnen der Meilensteine werden auch ältere Einträge bei anderen Mitgliedern nachgefragt, so füllt sich der Verlauf nach und nach wieder auf
- **Community-Knopf** verschwindet, sobald du in der Community bist
- **Dungeon-Filter** gilt jetzt auch für Einträge von GuildPride-Spielern mit Dungeon; Einträge ohne Dungeon (z. B. Quest-Hilfe) bleiben sichtbar
- **/gp diag** zeigt einen Diagnose-Bericht zum Kopieren (Realm, Gilde, Dungeonbrowser, Community, gespeicherte Daten) – hilft bei Blizzard-Änderungen

**English**
- **More milestones**: GuildPride now keeps up to 500 instead of 100 entries. Opening Milestones also asks other members for older entries, so the history fills up again over time
- **Community button** disappears once you are in the community
- **Dungeon filter** now also applies to GuildPride entries with a dungeon; entries without a dungeon (e.g. quest help) stay visible
- **/gp diag** shows a diagnostics report to copy (realm, guild, Dungeon Finder, community, saved data) – helps with Blizzard changes

## 2.32.0

**Deutsch**
- **Daten nach Blizzards Hotfix zurück**: Seit dem 20.11.2026 liefert Forever keinen Realm-Namen mehr. Meilensteine, Events und andere Gildendaten, Auktionshauspreise und Schiffszeiten landeten dadurch unter einem leeren Realm und die alten Daten schienen weg. GuildPride merkt sich jetzt den Realm und führt alte und neue Daten zusammen
- **Gruppensuche aufgeräumt**: oben dein Eintrag (Quest/Dungeon, fehlende Rollen, Anmelden/Abmelden mit Status), unter einer Trennlinie die Liste mit Gilde/Server/Alle, Filter, Browser durchsuchen und Aktualisieren. Die Gruppensuche hat wieder einen eigenen Menüpunkt, die Berufe sind dafür unter „Planen“
- **Dungeon-Filter**: Unter „Filter“ einen oder mehrere Dungeons anhaken – dann stehen nur deren Gruppen aus dem Dungeonbrowser in der Liste
- **Browser durchsuchen** öffnet Blizzards Dungeonbrowser selbst, wenn dort noch keine Kategorie gewählt ist; nach einmal „Dungeons“ sucht der Knopf bis zum Ausloggen direkt
- **Aktualisieren** statt Dungeonbrowser-Knopf: fragt die Einträge von Gilde und Server neu ab
- **Community-Knopf**: Blizzard erlaubt Addons keinen direkten Beitritt. Der Knopf zeigt jetzt den Einladungslink zum Kopieren mit kurzer Anleitung für „Gilde & Communitys“ › Community beitreten

**English**
- **Data back after Blizzard's hotfix**: Since 2026-11-20 Forever no longer reports the realm name. Milestones, events and other guild data, auction prices and ship times were saved under an empty realm and the old data seemed gone. GuildPride now remembers the realm and merges old and new data
- **Group finder tidied up**: your entry at the top (quest/dungeon, missing roles, sign up/off with status), below a divider the list with Guild/Server/All, Filter, Search Dungeon Finder and Refresh. The group finder has its own menu entry again, professions moved under "Plan"
- **Dungeon filter**: Tick one or more dungeons under "Filter" – only their Dungeon Finder groups show in the list
- **Search Dungeon Finder** opens Blizzard's Dungeon Finder itself when no category is picked there; after picking "Dungeons" once the button searches directly until you log out
- **Refresh** replaces the Dungeon Finder button: asks guild and server for their entries again
- **Community button**: Blizzard does not let addons join directly. The button now shows the invite link to copy with short steps for "Guild & Communities" › Join Community

## 2.31.0

**Deutsch**
- **Community-Knopf**: Im Gildenfenster steht links neben dem Discord-Logo ein Community-Knopf. Ein Klick tritt der Ingame-Community direkt bei (nur EU, Allianz, Server „Normal“)
- **Schiffszeiten ohne Layer**: Seit Blizzards Hotfix vom 20.11.2026 lassen sich Layer nicht mehr erkennen. Die Fenster an den Anlegern zeigen deshalb nur noch Abfahrt, Ankunft und nächste Fahrt – deine eigene Messung zuerst, sonst die Zeit, die die meisten gemessen haben. Gespeichert wird bei dir
- **Tiefenbahn**: Der Zähler läuft jetzt auch an den Bahnsteigen der Tiefenbahn zwischen Sturmwind und Eisenschmiede
- **Layer-Funktionen entfernt**: Layer-Anzeige, Layer-Wechsel und der „Zum Layer“-Knopf bei Rare-Alarmen sind weg, weil Blizzard den Layer nicht mehr verrät

**English**
- **Community button**: The guild window has a community button left of the Discord logo. One click joins the in-game community directly (EU, Alliance, "Normal" server only)
- **Ship times without layers**: Since Blizzard's hotfix of 2026-11-20 layers can no longer be detected. The dock windows now only show departure, arrival and next trip – your own measurement first, otherwise the time most players measured. Times are stored on your side
- **Deeprun Tram**: The timer now also runs on the Deeprun Tram platforms between Stormwind and Ironforge
- **Layer features removed**: Layer display, layer switching and the "To layer" button on rare alerts are gone, because Blizzard no longer reveals the layer

## 2.30.2

**Deutsch**
- **Gezielter Layer-Wechsel landet auf dem richtigen Layer**: Helfer prüfen ihren Layer vor Angebot und Einladung neu (nur wer ihn in der letzten Minute an einer Kreatur gesehen hat, hilft). Ist der Helfer nicht mehr auf dem angebotenen Layer, sagt er ab und der nächste Helfer kommt dran
- Beim gezielten Wechsel zählt der Wunsch-Layer; landet man trotzdem woanders, sagt GuildPride das deutlich („Gelandet auf Layer 12 statt 20“)
- Die Layer-Liste zeigt keine veralteten Zahlen mehr: Wer seit 5 Minuten keine Kreatur gesehen hat, meldet „?“

**English**
- **Targeted layer switch lands on the right layer**: helpers re-check their layer before offering and inviting (only those who saw it on a creature within the last minute help). If the helper is no longer on the offered layer, they decline and the next helper takes over
- For a targeted switch the wanted layer counts; if you still land elsewhere, GuildPride says so clearly ("landed on layer 12 instead of 20")
- The layer list no longer shows outdated numbers: anyone who has not seen a creature for 5 minutes reports "?"

## 2.30.1

**Deutsch**
- **Layer wechseln geht schneller**: Anfrage, Angebot und Einladung werden sofort verschickt statt im 2-Sekunden-Takt, der Helfer wird gleich nach dem ersten Angebot gewählt, und nach dem Wechsel geht es ohne Wartezeit aus der Gruppe
- **Layer-Wechsel wird geprüft**: Die Gruppe wird erst verlassen, wenn der neue Layer sicher erkannt ist (zwei Kreaturen oder eine über 1,5 s). Danach wird 10 s nachgeprüft, ob der Layer hält – erst dann gibt es Dank und Zähler, sonst kommt der Hinweis „hat nicht gehalten“

**English**
- **Faster layer switching**: request, offer and invite are sent right away instead of every 2 seconds, the helper is picked right after the first offer, and you leave the group without delay after the switch
- **Layer switch is verified**: the group is only left once the new layer is clearly detected (two creatures or one for 1.5 s). Afterwards it checks for 10 s that the layer holds – only then are thanks and counter updated, otherwise you get a "did not hold" notice

## 2.30.0

**Deutsch**
- **Einheitliches Design**: Alle Fenster, die GuildPride öffnet (Auktionshaus, Berufe-Einkaufsliste, Flug- und Reisefenster, Rare-Liste, Einladungen, Mitglieder, DKP, Raid, Termine, Umfragen, Sicherung, Kopieren und Einführung), haben jetzt dasselbe dunkle Design mit goldenem Rand

**English**
- **Unified design**: Every window GuildPride opens (auction house, profession shopping list, flight and travel windows, rare list, invites, members, DKP, raid, events, polls, backup, copy and intro) now shares the same dark look with a golden border

## 2.29.0

**Deutsch**
- **Abwesenheiten**: Mitglieder melden sich in der Übersicht mit **Abwesenheit melden …** (oder `/gp abwesend`) von Tag x bis Tag y ab, auf Wunsch mit Grund. Eigene Abmeldungen lassen sich wieder entfernen
- **Liste für die Gildenleitung**: Gildenleitung und Offiziere sehen unter Verwaltung › **Abwesenheitsliste …** (oder `/gp abwesenheiten`), wer von wann bis wann nicht da ist – mit „abwesend“, „in x Tagen“ und dem Grund. Neue Abmeldungen kommen als Hinweis im Chat, wer heute fehlt, steht in der Übersicht
- **Farben der Namensplaketten**: Die Namensplaketten über den Köpfen anderer Spieler lassen sich nach Wunsch einfärben – eine Farbe für alle Gildenmitglieder, eine eigene Farbe je Spieler (Ziel oder Suche) und auf Wunsch auch der Lebensbalken. Die Farben siehst nur du. Einstellungen › Namensplaketten › **Farben …** oder `/gp farben`

**English**
- **Absences**: members report an absence from day x to day y in the overview with **Report absence …** (or `/gp away`), optionally with a reason. Your own entries can be removed again
- **List for officers**: the guild master and officers see under Management › **Absence list …** (or `/gp absences`) who is away from when to when – with "away", "in x days" and the reason. New absences show as a chat notice, and who is away today appears in the overview
- **Nameplate colours**: colour the nameplates above other players' heads however you like – one colour for all guild members, an own colour per player (target or search) and optionally the health bar too. Only you see your colours. Settings › Nameplates › **Colours …** or `/gp nameplates`

## 2.28.1

**Deutsch**
- **Blizzard-Optionen**: Die Seite GuildPride unter Optionen › AddOns ragte über das Fenster hinaus. Die Schalter stehen jetzt in einem Bereich mit Bildlaufleiste

**English**
- **Blizzard options**: the GuildPride page under Options › AddOns ran past the window. The switches now sit in a scrollable area

## 2.28.0

**Deutsch**
- **Mehrere Werbetexte**: Unter Verwaltung › Werbung lassen sich bis zu 10 Werbetexte speichern und mit **<** und **>** wechseln, dazu **Neuer Text** und **Text löschen**. **In den Chat legen** nimmt den gewählten Text; der bisherige Text bleibt als Text 1 erhalten
- **Flugzeiten werden gespeichert**: Die Landung am Ziel wurde auf WoW Forever nicht erkannt, darum blieb überall „ca.“ stehen. Jetzt wird jede geflogene Strecke gemessen und gemerkt, und die gemessene Zeit gilt auch für den Rückflug

**English**
- **Several recruiting texts**: under Management › Recruiting you can store up to 10 recruiting texts and switch with **<** and **>**, plus **New text** and **Delete text**. **Put in chat** uses the chosen text; your previous text stays as text 1
- **Flight times are saved**: landing at the destination was not detected on WoW Forever, so "~" stayed everywhere. Every route you fly is now measured and remembered, and the measured time also counts for the return flight

## 2.27.1

**Deutsch**
- **Berufsfenster**: Die GuildPride-Leiste (AH: Zutaten, Zur Einkaufsliste, Kosten und Gewinn) steht jetzt mittig im rechten Bereich, unten direkt über dem Häkchen unter dem Rezept. Kosten und Gewinn bleiben in einer Zeile und werden bei Bedarf kleiner, damit sie hineinpassen

**English**
- **Profession window**: the GuildPride bar (AH: reagents, To shopping list, cost and profit) now sits centred in the right-hand section, at the bottom just above the checkbox below the recipe. Cost and profit stay on one line and shrink when needed so they fit

## 2.27.0

**Deutsch**
- **Flugzeiten**: Am Flugmeister steht im Tooltip jedes Ziels, wie lange der Flug dauert – geschätzt wie bei Polestar (**ca.**), selbst geflogene Strecken mit der gemessenen Zeit in Gold. Jeder eigene Flug wird gestoppt und gemerkt
- **Flug-Zähler**: Während des Flugs zeigt ein verschiebbares Fenster Ziel, Restzeit bis zur Landung und einen Balken. Beides lässt sich in den Einstellungen (Reisen) abschalten
- **Schwarzes Brett für bestimmte Ränge**: Beim Aushang (Reiter Verwaltung) wählst du per Häkchen, welche Ränge ihn sehen. Alle angekreuzt = für alle
- **Item-ID im Tooltip**: neuer Schalter in den Einstellungen (Allgemein), standardmäßig aus
- **Auktionshaus – Stufenbereich**: In der Suche lässt sich die Stufe von – bis eintragen; leer = ohne Grenze
- **Berufsfenster**: Kosten und Gewinn stehen jetzt unter den Knöpfen „AH: Zutaten“ und „Zur Einkaufsliste“
- **Wunschliste**: Umschalt+Klick auf ein Item fügt es ins Feld ein, ohne vorher hineinzuklicken

**English**
- **Flight times**: at the flight master each destination's tooltip shows how long the flight takes – estimated like Polestar (**~**), routes you have flown with the measured time in gold. Every flight of yours is timed and remembered
- **Flight timer**: while flying, a movable window shows destination, time left until landing and a bar. Both can be switched off in the settings (Travel)
- **Bulletin board for chosen ranks**: when posting (Manage tab) tick which ranks see it. All ticked = everyone
- **Item ID in the tooltip**: new switch in the settings (General), off by default
- **Auction house – level range**: the search takes a level from – to; empty = no limit
- **Profession window**: cost and profit now sit below the "AH: reagents" and "To shopping list" buttons
- **Wish list**: shift-click on an item puts it into the field without clicking into it first

## 2.26.1

**Deutsch**
- **Gildenfenster (J)**: J öffnet immer genau ein Fenster – je nach Einstellung **Dieses Fenster statt Blizzard-Gildenfenster** GuildPride oder Blizzard. Vorher blieb Blizzards Fenster nach dem Abschalten unsichtbar, beim ersten J nach dem Einloggen gingen beide auf, und ein offenes GuildPride-Fenster blieb neben Blizzards stehen
- **Auktionshaus – Komplett-Scan**: nur alle 15 Minuten, auch nach /reload und für alle Charaktere; Scans von Auctionator zählen mit. Der Knopf bleibt bis dahin aus und zeigt die Wartezeit
- **Auktionshaus – weniger Ruckeln**: große Scan-Listen werden in kleineren Stücken gelesen und gespeichert und nicht mehr alle 30 Sekunden neu gelesen

**English**
- **Guild window (J)**: J always opens exactly one window – GuildPride or Blizzard, depending on **Use this window instead of Blizzard's guild window**. Before, Blizzard's window stayed invisible after switching off, both opened on the first J after login, and an open GuildPride window stayed next to Blizzard's
- **Auction house – full scan**: only every 15 minutes, even after /reload and across all characters; Auctionator scans count too. The button stays disabled until then and shows the wait
- **Auction house – less stutter**: large scan lists are read and saved in smaller chunks and no longer re-read every 30 seconds

## 2.26.0

**Deutsch**
- **Dungeons und Raids bei Gildenevents**: Im Fenster **Neues Event** (Reiter Planen) gibt es bei **Art** je einen Knopf für Dungeon und Raid. Die Liste enthält alle Dungeons und Raids von WoW Forever mit Stufe und Spielerzahl; der Name wird als Titel übernommen. Die Event-Liste zeigt eine eigene Spalte (z. B. **Raid · 40**), die Aufstellung richtet sich nach der Gruppengröße, und an Discord geht die Auswahl mit, damit der Bot die passende Gruppe anlegt
- **Teilen ohne Ausnahme**: Schiffs- und Zeppelinzeiten, Rares und Auktionshauspreise werden immer mit allen GuildPride-Spielern geteilt – auch wenn die **Serverweite Gruppensuche** aus ist. Der Schalter gilt nur noch für Gruppensuche und Layer-Wechsel. Die Schalter „Schiffs-Fahrpläne teilen“ und „Rares teilen“ sind entfernt
- **Schiffs-Zähler – Bestätigungen**: Haben mehrere Spieler dieselbe Zeit gemessen, steht **3× bestätigt** dabei; eine einzelne abweichende Meldung verdrängt so eine Zeit nicht mehr
- **Schiffs-Zähler – Erinnerung**: Uhr-Symbol an einer Verbindung anklicken – 1 Minute vor der Abfahrt kommen Raid-Warnung und Ton, auch wenn du nicht mehr am Anleger bist
- **Schiffs-Zähler – Layer automatisch**: Der Layer wird jetzt auch über Händler, Flugmeister, Quest-NPCs, das weiche Ziel, Namensplaketten und die Ziele der Gruppe erkannt
- **Schiffs-Zähler – nach dem Reset**: Gibt es diese Woche noch keine Messung, steht die Zeit der letzten Woche als **vermutet** da, bis jemand neu misst
- **Versuch**: Aus den Kreaturen erkennt GuildPride, wann ein Layer gestartet ist. Passt das bei zwei gemessenen Layern zusammen, gibt es auch für Layer ohne Messung eine Zeit (**geschätzt für deinen Layer**)

**English**
- **Dungeons and raids for guild events**: the **New event** window (Plan tab) has a button each for dungeon and raid under **Type**. The list holds every WoW Forever dungeon and raid with level and player count; the name becomes the title. The event list shows its own column (e.g. **Raid · 40**), the lineup follows the group size, and the choice is sent to Discord so the bot creates the matching group
- **Sharing without exception**: ship and zeppelin times, rares and auction house prices are always shared with all GuildPride players – even with the **Server-wide group finder** off. That switch now only covers the group finder and layer switching. The "share ship timetables" and "share rares" switches are removed
- **Ship timer – confirmations**: when several players measured the same time it shows **confirmed 3×**; a single differing report no longer replaces such a time
- **Ship timer – reminder**: click the clock icon on a connection – 1 minute before departure you get a raid warning and a sound, even if you left the dock
- **Ship timer – automatic layer**: your layer is now also detected from vendors, flight masters, quest NPCs, the soft target, nameplates and your group's targets
- **Ship timer – after the reset**: if nobody has measured this week yet, last week's time shows as **guessed** until someone measures again
- **Experiment**: GuildPride reads from creatures when a layer started. If that matches on two measured layers, layers without a measurement get a time too (**estimated for your layer**)

## 2.25.0

**Deutsch**
- **Schiffs-Zähler je Layer**: Jeder Layer fährt seine Schiffe und Zeppeline versetzt. Messungen merken sich jetzt den Layer (am Abfahrts- und Ziel-Steg), und das Fenster am Anleger zeigt die Zeiten **deines** Layers – wechselst du den Layer, wechselt die Anzeige mit
- **Mit allen GuildPride-Spielern geteilt**: Eigene Messungen gehen außer an die Gilde auch an alle im serverweiten GuildPride-Kanal. Fehlt am Anleger eine Messung für deinen Layer, fragt GuildPride die anderen selbst (nur mit **Serverweite Gruppensuche** an)
- Messungen gelten jetzt bis zur wöchentlichen Wartung statt 6 Stunden; das Fenster zeigt, wie alt sie sind und ob sie von deinem Layer stammen (**dein Layer**, **Layer ?**, **evtl. anderer Layer**)
- Tipp im Fenster: eine Kreatur anvisieren, damit GuildPride deinen Layer erkennt

**English**
- **Ship timer per layer**: every layer runs its ships and zeppelins offset. Measurements now remember the layer (at the departure and arrival dock), and the dock window shows the times of **your** layer – switch layers and the display follows
- **Shared with all GuildPride players**: your measurements go to your guild and to everyone in the server-wide GuildPride channel. If the dock has no measurement for your layer, GuildPride asks the others by itself (only with **Server-wide group finder** on)
- Measurements now last until the weekly maintenance instead of 6 hours; the window shows how old they are and whether they are from your layer (**your layer**, **layer ?**, **maybe other layer**)
- Tip in the window: target a creature so GuildPride detects your layer

## 2.24.1

**Deutsch**
- Rechtsklick auf einen Spieler: Der Eintrag **In Gilde einladen** ist entfernt – WoW Forever blockiert Einladungen aus diesem Menü. Zum Einladen den Knopf **Einladen** im Gildenfenster nehmen (öffnet Blizzards Einladedialog) oder `/ginvite Vor Nachname` im Chat

**English**
- Right-clicking a player: the **Invite to guild** entry is removed – WoW Forever blocks invites from this menu. To invite, use the **Invite** button in the guild window (opens Blizzard's invite dialog) or type `/ginvite First Last` in chat

## 2.24.0

**Deutsch**
- **Gildeneinladung auf WoW Forever repariert**: Ein Klick auf **Einladen** (unten rechts neben dem Chat) bzw. **In Gilde einladen** (Mitgliederliste) öffnet Blizzards normalen Einladedialog – dort den Namen eintippen und annehmen. Vorher meldete das Spiel „nur für Blizzard-Oberfläche“
- Ursache war, dass GuildPride Blizzards Gildenfenster beim Drücken von **J** selbst geschlossen hat. Jetzt wird es nur unsichtbar gemacht – öffnen und schließen tut es weiter nur das Spiel
- Rechtsklick auf einen Spieler › **In Gilde einladen** und `/gp einladen Name` zeigen ein kleines Fenster mit dem Namen; dessen Knopf öffnet Blizzards Einladedialog
- Neu: Einstellungen › Allgemein › **Oben das Gildenwappen statt des Fraktionslogos zeigen**

**English**
- **Guild invites on WoW Forever fixed**: clicking **Invite** (bottom right next to the chat) or **Invite to guild** (member list) opens Blizzard's normal invite dialog – type the name there and accept. Before, the game said "only available to the Blizzard UI"
- The cause was that GuildPride closed Blizzard's guild window itself when pressing **J**. Now it is only made invisible – only the game opens and closes it
- Right-click a player › **Invite to guild** and `/gp einladen Name` show a small window with the name; its button opens Blizzard's invite dialog
- New: Settings › General › **Show the guild emblem instead of the faction logo at the top**

## 2.23.2

**Deutsch**
- Discord: Anmeldungen zu einem Event kommen jetzt auch dann in Discord an, wenn beim Anmelder die Discord-Anbindung aus ist – das Spiel des Event-Erstellers gibt sie nach etwa 30 Sekunden weiter (nur wenn sie nicht schon in Discord steht). Dafür muss beim Ersteller die Discord-Anbindung an sein

**English**
- Discord: event sign-ups now reach Discord even if the signer has the Discord bridge turned off – the event creator's game passes them on after about 30 seconds (only if they are not in Discord yet). The creator needs the Discord bridge turned on

## 2.23.1

**Deutsch**
- Gildenfenster › **Berufe**: Vor den Namen standen Kästchen statt Pfeilen – jetzt Plus- und Minus-Symbole zum Auf- und Zuklappen
- Berufe: Die Berufssymbole stehen jetzt rechts am Zeilenende
- Berufe: **Berufsfenster öffnen** – öffnet das Spiel das Fenster eines Mitspielers nicht, klappt GuildPride stattdessen seine geteilten Rezepte in der Liste auf
- Begrüßung neuer Mitglieder und Discord-Zeilen: Im Kampf kam es zu einer Fehlermeldung („Aktion blockiert“). Der Tastendruck-Helfer von GuildPride pausiert jetzt im Kampf
- Briefkasten: Der Knopf **Twinks** beim Schreiben ist wieder entfernt – GuildPride verändert den Briefkasten nicht mehr

**English**
- Guild window › **Professions**: boxes showed in front of the names instead of arrows – now plus and minus icons to expand and collapse
- Professions: the profession icons now sit at the right end of the row
- Professions: **Open profession window** – if the game does not open another player's window, GuildPride expands their shared recipes in the list instead
- Welcome message for new members and Discord lines: in combat an error ("action blocked") could appear. GuildPride's key-press helper now pauses in combat
- Mailbox: the **Alts** button when writing is removed again – GuildPride no longer changes the mailbox

## 2.23.0

**Deutsch**
- Neu: **Schiffs-Zähler** – stehst du an einem Anleger (Schiff, Zeppelin, Luftschiff), zeigt ein kleines Fenster je Verbindung eine Karte mit Schiffs- bzw. Zeppelin-Symbol und großem Countdown: ob das Schiff gerade **am Steg liegt und wann es ablegt**, wann das **nächste kommt** und wann das danach. Die Zeiten werden gemessen, wenn jemand mitfährt: fahr einmal mit, dann zählt GuildPride für dich – und für deine Gilde, die die Messung automatisch bekommt (gleicher Realm, 6 Stunden gültig). Ungemessen steht dort die mittlere Wartezeit. Fenster verschiebbar, **X** blendet es aus, bis du den Anleger verlässt. Einstellungen › **Reisen**. Fahrpläne und Messverfahren stammen aus **Polestar** (nach Shortest Path Forever von Cillian Berragan, GPL-3) – danke!
- Auktionshaus: Beim Öffnen kommt jetzt standardmäßig wieder **Blizzards Auktionshaus**. Das GuildPride-Fenster erscheint erst, wenn du einmal selbst auf den Knopf **GuildPride** klickst – ab dann merkt es sich deine Wahl, bis du wieder **Blizzard-AH** wählst. Die Zutaten-Suche aus dem Berufsfenster öffnet es nur für dieses eine Mal
- Auktionshaus: **Favoriten** – der Stern an jeder Zeile unter **Suchen** und in der Kaufansicht merkt ein Item als Favorit (auch in Blizzards eigenen Auktionshaus-Favoriten, wenn das Spiel es zulässt)
- Neuer Reiter **Einkaufsliste** (zwischen **Meine Auktionen** und **Aufträge**): links **Favoriten** und deine eigenen Listen (**Neue Liste**, **Umbenennen**, **Liste löschen**; den Namen bestimmst du selbst), rechts die Items der gewählten Liste mit Item-ID und bekanntem Preis. Oben **Item-IDs eintragen** – mehrere mit Komma getrennt, Umschalt+Klick auf ein Item oder ein Wowhead-Link gehen auch. **Suchen** (oder Klick auf die Zeile) öffnet gleich die Kaufansicht des Items, **X** nimmt es aus der Liste
- Neu im **Berufsfenster** (direkt unter den Materialien des Rezepts): **AH: Zutaten** sucht im GuildPride-Auktionshaus nur die Zutaten des gewählten Rezepts – unter **Suchen** stehen dann nur diese Items, jeweils mit „benötigt N“ für die eingestellte Anzahl; fehlt etwas im Auktionshaus, steht es oben. **Zur Einkaufsliste** fragt nach der Anzahl zum Herstellen und der Liste (oder **Neue Liste …**) und trägt die Zutaten mit Menge ein – mehrere verschiedene Rezepte in einer Liste werden zusammengezählt
- Einkaufsliste: Spalte **Menge** je Item (änderbar), Knopf **Alle im AH suchen** zeigt unter **Suchen** nur die Items der Liste mit der benötigten Menge
- **Temporäre Liste** (Knopf im Reiter Einkaufsliste oder im Berufsfenster unter **Zur Einkaufsliste**): für einen Einkauf. Jeder Kauf im GuildPride-Auktionshaus zieht die gekaufte Menge ab, erledigte Items verschwinden – ist alles gekauft, entfernt sich die Liste von selbst. Deine festen Listen bleiben unverändert
- Berufsfenster: unter den Materialien, über den GuildPride-Knöpfen stehen **Kosten der Zutaten**, **Verkaufswert** und **Gewinn** (nach 5 % Gebühr) des gewählten Rezepts – mit den geteilten GuildPride-Preisen. Was du schon in Taschen oder Bank hast, wird bei **AH: Zutaten** abgezogen
- Einkaufsliste: Spalte **Bestand** („hast 5 · noch 7“, grün „genug“), Preis für die noch fehlende Menge und unten **noch zu kaufen, ungefähr …** für die ganze Liste
- **Preisalarm**: Knopf **Alarm** je Zeile der Einkaufsliste – Wunschpreis eingeben (z. B. 1g 50s oder 1,5). Taucht das Item bei einer Suche so billig auf (auch im Blizzard-Fenster oder mit Auctionator), gibt es einen Hinweis mit Ton
- Kaufansicht: **Preisverlauf** der letzten 7 Tage als Balken (tiefster und höchster Preis) und **wer in der Gilde das Item herstellen kann** (aus dem Handwerker-Verzeichnis)
- **Liste kaufen**: zeigt die Items einer Einkaufsliste nacheinander in der Kaufansicht, mit der noch fehlenden Menge; nach jedem Kauf kommt das nächste, **Weiter ›** überspringt
- Einkaufslisten **exportieren** (Text zum Kopieren und Teilen) und **importieren** – GuildPride-Text, Auctionator-Listen oder einfach Item-IDs
- Verkaufen: Items, die du schon einmal eingestellt hattest und die wieder in den Taschen liegen (z. B. unverkauft zurück), sind mit **(zurück)** markiert. **Zurückgekommene einstellen** wählt sie nacheinander mit aktuellem Preisvorschlag
- Neu: Reiter **Aufträge** im Auktionshaus – **Gildenaufträge**: Item-ID (oder Umschalt+Klick) und Menge eingeben, **Auftrag einstellen**. Die ganze Gilde mit GuildPride sieht die Aufträge mit Menge, Auftraggeber, Alter und Status; Hersteller klicken **Annehmen** (und können wieder **Abgeben**), der Auftraggeber bekommt einen Hinweis. Eigene Aufträge **löschen**, **Suchen** zeigt das Item im Auktionshaus. Höchstens 20 eigene Aufträge, sie verfallen nach 14 Tagen. Abgleich wie bei der Wunschliste: jeder sendet nur seine eigenen Aufträge, angenommen wird nur vom Hersteller selbst (nie weitergeleitet)
- Discord: neue und angenommene Gildenaufträge gehen über die Discord-Anbindung an Discord; in der Kaufansicht meldet **Preis an Discord** den aktuellen Preis (mit aktuellem GameBot als Karte)

**English**
- New: **Ship timer** – standing at a dock (boat, zeppelin, airship), a small window shows a card for each connection with a ship or zeppelin icon and a big countdown: whether the ship is **docked and when it leaves**, when the **next one arrives** and the one after. The times are measured when someone rides along: ride once and GuildPride counts for you – and for your guild, which gets the measurement automatically (same realm, valid for 6 hours). Unmeasured, it shows the average wait. The window can be moved, **X** hides it until you leave the dock. Settings › **Travel**. Timetables and the measuring come from **Polestar** (after Shortest Path Forever by Cillian Berragan, GPL-3) – thank you!
- Auction house: opening it now shows **Blizzard's auction house** by default again. The GuildPride window only appears once you click the **GuildPride** button yourself – from then on your choice is remembered until you pick **Blizzard AH** again. The reagent search from the profession window opens it just that one time
- Auction house: **Favorites** – the star on every row under **Search** and in the buy view marks an item as favorite (also in Blizzard's own auction house favorites if the game allows it)
- New **Shopping list** tab (between **My auctions** and **Orders**): on the left **Favorites** and your own lists (**New list**, **Rename**, **Delete list**; you pick the name), on the right the items of the chosen list with item ID and known price. At the top **enter item IDs** – separate several with commas, shift-click on an item or a Wowhead link work too. **Search** (or a click on the row) opens the item's buy view right away, **X** removes it from the list
- New in the **profession window** (right below the recipe's reagents): **AH: reagents** searches the GuildPride auction house for the chosen recipe's reagents only – **Search** then shows only these items, each with "need N" for the chosen amount; anything missing from the auction house is listed at the top. **To shopping list** asks for the amount to craft and the list (or **New list …**) and adds the reagents with quantities – several different recipes in one list are added up
- Shopping list: **Quantity** column per item (editable), the **Search all in the AH** button shows only the list's items under **Search**, with the quantity needed
- **Temporary list** (button in the Shopping list tab or in the profession window under **To shopping list**): for one shopping trip. Every purchase in the GuildPride auction house subtracts the amount bought, finished items disappear – once everything is bought, the list removes itself. Your regular lists stay unchanged
- Profession window: below the reagents, above the GuildPride buttons you see the **reagent cost**, **sale value** and **profit** (after the 5 % cut) of the chosen recipe – using the shared GuildPride prices. What you already have in bags or bank is subtracted for **AH: reagents**
- Shopping list: **Stock** column ("have 5 · need 7", green "enough"), price for the quantity still missing and at the bottom **still to buy, about …** for the whole list
- **Price alert**: **Alert** button on every shopping list row – enter a target price (e.g. 1g 50s or 1.5). If the item shows up that cheap in any search (also in Blizzard's window or with Auctionator), you get a notice with a sound
- Buy view: **price history** of the last 7 days as bars (lowest and highest price) and **who in the guild can craft the item** (from the crafter directory)
- **Buy list**: shows the items of a shopping list one after another in the buy view, with the quantity still missing; after each purchase the next one comes up, **Next ›** skips
- **Export** shopping lists (text to copy and share) and **import** them – GuildPride text, Auctionator lists or simply item IDs
- Sell: items you posted before that are back in your bags (e.g. returned unsold) are marked **(returned)**. **Repost returned items** picks them one after another with the current price suggestion
- New: **Orders** tab in the auction house – **guild orders**: enter an item ID (or shift-click) and a quantity, **Post order**. Everyone in the guild with GuildPride sees the orders with quantity, requester, age and status; crafters click **Accept** (and can **Give back**), the requester gets a notice. **Delete** your own orders, **Search** shows the item in the auction house. At most 20 own orders, they expire after 14 days. Synced like the wishlist: everyone only sends their own orders, only the crafter can accept for themselves (never relayed)
- Discord: new and accepted guild orders go to Discord via the Discord bridge; in the buy view **Price to Discord** posts the current price (shown as a card with the current GameBot)

## 2.22.1

**Deutsch**
- Der Discord-Support-Knopf im Gildenfenster ist jetzt nur noch das kleine Discord-Logo; der Tooltip nennt weiter „GuildPride Discord Support“, ein Klick zeigt den Einladungslink

**English**
- The Discord support button in the guild window is now just the small Discord logo; its tooltip still says "GuildPride Discord support", a click shows the invite link

## 2.22.0

**Deutsch**
- Neu: Knopf **GuildPride Discord Support** oben rechts im Gildenfenster (in allen Layouts). Ein Klick zeigt den Einladungslink zum Kopieren (Strg+C, dann im Browser einfügen)
- Auktionshaus: Wer das GuildPride-Fenster nicht möchte, schaltet es unter Einstellungen › Auktionshaus › **GuildPride-Auktionshaus nutzen** oder mit `/gp ah aus` ab – sofort, ohne /reload, auch bei offenem Auktionshaus. Dann gibt es nur Blizzards Auktionshaus ohne GuildPride-Knopf; Preise im Tooltip, Mitlesen und Teilen laufen weiter. `/gp ah an` schaltet es wieder ein. Die Tooltips der Umschaltknöpfe nennen den Weg

**English**
- New: **GuildPride Discord support** button at the top right of the guild window (in every layout). A click shows the invite link to copy (Ctrl+C, then paste it into your browser)
- Auction house: if you don't want the GuildPride window, turn it off under Settings › Auction House › **Use the GuildPride auction house** or with `/gp ah off` – right away, without /reload, even with the auction house open. You then get Blizzard's auction house only, without the GuildPride button; tooltip prices, reading along and sharing keep running. `/gp ah on` turns it back on. The switch buttons' tooltips show how

## 2.21.0

**Deutsch**
- Neu: **Auktionshaus**. In WoW Forever ersetzt das Fenster „GuildPride – Auktionshaus“ Blizzards Auktionshaus-Fenster (verschiebbar, ESC schließt; Knopf **Blizzard-Auktionshaus** schaltet zurück, Knopf **GuildPride** in Blizzards Fenster wieder hin, die Wahl wird gemerkt) mit **Suchen** (Kategorien links wie bei Blizzard, ohne WoW-Marke, Liste nach Stückpreis; Klick zeigt alle Angebote zum **Kaufen** direkt im Fenster – bei Waren Menge eingeben oder eine Zeile anklicken, Gesamtpreis, Bestätigung mit dem genauen Preis), **Verkaufen** (rechts die Liste **Deine Taschen** mit allen handelbaren Items, Menge und bekanntem Preis – Klick wählt das Item, oder hineinziehen; große Item-Anzeige mit Menge, Stufe und Händlerpreis; Liste **Gerade im Auktionshaus** mit den aktuellen Angeboten – Klick übernimmt den Preis −1 Kupfer; Preisvorschlag, Menge, Dauer 12/24/48 Std., Einzahlung, **Einstellen**; Ausrüstung immer einzeln), **Meine Auktionen** (alles, was du gerade im Auktionshaus hast, mit Menge, Stück- und Gesamtpreis, Restzeit und dem **Gesamtwert** aller Auktionen; verkaufte Auktionen extra; Knopf **Abbrechen** je Auktion mit Bestätigung und Kosten) und **Scanner** (Komplett-Scan alle 15 Minuten, Stand und bekannte Preise). Jeder Reiter ist in klar abgesetzte Bereiche mit Rahmen und Kopfleisten gegliedert. Zusätzlich liest GuildPride still mit, was du im Blizzard-Auktionshaus oder mit Auctionator suchst. Im alten Auktionshaus (Classic-Clients) hat der Reiter **Suchen** (Liste mit Stückpreis, Klick zeigt die Einzelangebote, Knopf **Kaufen**) und **Verkaufen** (Item hineinziehen, Preisvorschlag, Stapelgröße, Stapel, Dauer 2/8/24 Std., Einzahlung, Knopf **Einstellen**)
- Preisvorschlag beim Einstellen: immer der niedrigste Preis, der gerade im Auktionshaus steht (fremdes Angebot −1 Kupfer, ist dein eigenes das billigste, derselbe Preis); sonst dein eigener Preis der letzten Stunde, ein bestätigter Serverpreis oder ein älterer Preis – jeweils gekennzeichnet. Deine eigenen Auktionen zählen nie als Marktpreis
- Preis im Item-Tooltip: „GuildPride Auktionshaus: … (vor 2 Std.)“, ohne bekannten Preis „noch kein Preis bekannt“, mit Umschalt der Preis für den ganzen Stapel
- Preise werden **für alle serverweit geteilt** (Pflicht, kein Schalter) über den eigenen, ausgeblendeten Kanal `GPAuktionF`: Wer sucht oder einstellt, teilt die gefundenen Preise; fehlt dir ein Preis, fragt GuildPride kurz nach. Nur gleiche Fraktion, Goblin-Auktionshäuser getrennt; ein Serverpreis gilt erst als bestätigt, wenn ihn mindestens zwei Spieler ähnlich melden
- Mit **Auctionator**: GuildPride liest Auctionators Suchergebnisse still mit und teilt sie; in WoW Forever bleibt das GuildPride-Fenster zusätzlich da
- Einstellungen › Auktionshaus: Fenster bzw. Reiter, Tooltip-Preis, Tooltip auch mit Auctionator. Befehle: `/gp ah status`, `/gp ah scan`, `/gp ah fenster`

**English**
- New: **Auction House**. In WoW Forever the "GuildPride – Auction House" window replaces Blizzard's auction house window (movable, ESC closes it; the **Blizzard auction house** button switches back, the **GuildPride** button in Blizzard's window switches again, your choice is remembered) with **Search** (categories on the left like Blizzard's, no WoW Token, list by price per item; click shows every offer to **Buy** right in the window – for commodities enter a quantity or click a row, total price, confirmation with the exact price), **Sell** (on the right the **Your bags** list with every tradeable item, its count and known price – click picks the item, or drag it in; large item display with count, level and vendor price; **Currently in the auction house** list with the current offers – click takes the price −1 copper; price suggestion, quantity, duration 12/24/48 hr, deposit, **Post**; gear always one at a time), **My auctions** (everything you currently have in the auction house with quantity, unit and total price, time left and the **total value** of all auctions; sold auctions listed separately; **Cancel** button per auction with confirmation and cost) and **Scanner** (full scan every 15 minutes, status and known prices). Every tab is split into clearly framed sections with header bars. GuildPride also quietly reads what you search in the Blizzard auction house or with Auctionator. In the old auction house (Classic clients) the tab has **Search** (list with price per item, click shows the single offers, **Buy** button) and **Sell** (drag an item in, price suggestion, stack size, stacks, duration 2/8/24 hr, deposit, **Post** button)
- Price suggestion when posting: always the lowest price currently in the auction house (an offer from others −1 copper; if yours is the cheapest, the same price); otherwise your own price from the last hour, a confirmed server price or an older price – each one labelled. Your own auctions never count as market price
- Price in the item tooltip: "GuildPride Auction House: … (2 hr ago)", without a known price "no price known yet", hold Shift for the whole stack
- Prices are **shared server-wide by everyone** (mandatory, no switch) through the own hidden channel `GPAuktionF`: whoever searches or posts shares the prices found; if you lack a price, GuildPride asks briefly. Same faction only, goblin auction houses kept apart; a server price only counts as confirmed once at least two players report it similarly
- With **Auctionator**: GuildPride quietly reads Auctionator's search results and shares them; in WoW Forever the GuildPride window stays as well
- Settings › Auction House: window or tab, tooltip price, tooltip with Auctionator too. Commands: `/gp ah status`, `/gp ah scan`, `/gp ah window`

## 2.20.0

**Deutsch**
- Weniger Spam im Gildenchat durch die Discord-Anbindung: `[GP]`-Zeilen gehen jetzt automatisch in Blizzards eigenen Discord-Kanal der Gilde, sobald die Gildenleitung **Discord-Chat getrennt** eingeschaltet hat (Gildeneinstellungen → Discord-Einstellungen). Spieler ohne GuildPride sehen sie dann nicht mehr in /g. Landen die Zeilen doch im Gildenchat, bekommen Offiziere einmal einen Hinweis. `/gp discord gilde` erzwingt weiter den Gildenchat
- Anmeldungen werden 10 Sekunden zurückgehalten: Wer schnell umentscheidet (Zusage, Vielleicht, Absage …), erzeugt nur eine Zeile mit dem letzten Stand
- Boss-Erstkills gehen nicht mehr einzeln von jedem Raidmitglied an Discord; die Bosse stehen in der Raid-Zusammenfassung
- Meilensteine (Level, Mythisch+) gehen nur noch von Offizieren an Discord; GameBot nimmt Meilensteine und Umfragen nur von Offizieren an
- Ist der Discord-Chat getrennt, weicht GuildPride nie in den Gildenchat aus (dort käme nichts in Discord an). Kommen die Zeilen im Spiel nicht zurück oder ist der Discord-Kanal nicht erreichbar, gibt es einen Hinweis. Neu: `/gp discord info` zeigt Schritt für Schritt, welchen Weg GuildPride nimmt
- Offiziere ohne verknüpftes Discord bekommen einen Hinweis, dass DKP, Ankündigungen und Umfragen sonst nur über einen verknüpften Offizier ankommen. Solche Zeilen geben nur noch Offiziere weiter
- Neu: Events **bearbeiten** – Knopf „Bearbeiten“ im Event (Ersteller und Offiziere): Titel, Datum, Uhrzeit, Beschreibung und Wiederholung ändern. Die Änderung geht an die Gilde und an Discord (mit aktuellem GameBot)
- Meldet Blizzard direkt nach einer eigenen Discord-Zeile, dass dein Discord nicht verknüpft ist, stellt GuildPride das selbst um und gibt die Zeile über ein verknüpftes Mitglied weiter
- Wartende Discord-Zeilen gehen beim Ausloggen nicht mehr verloren, sie werden beim nächsten Einloggen gesendet (bis 6 Stunden)
- Einstellungen › Gilde: neue Schalter „Discord-Zeilen immer in den Gildenchat“ und „Discord-Zeilen im Chat anzeigen“ sowie ein Knopf **Discord testen**
- GuildPride meldet GameBot höchstens einmal pro Woche (und nach einem Update) die eigene Version, nur über den eigenen Discord-Kanal der Gilde. Im Dashboard sehen Offiziere, wer eine veraltete Version nutzt

**English**
- Less guild chat spam from the Discord bridge: `[GP]` lines now automatically go to Blizzard's own Discord channel of the guild once the guild leader has turned on **Separate Discord chat** (Guild Settings → Discord Settings). Players without GuildPride no longer see them in /g. If the lines still end up in guild chat, officers get a one-time hint. `/gp discord guild` still forces guild chat
- Sign-ups are held back for 10 seconds: changing your mind quickly (attending, maybe, declined …) produces only one line with the final choice
- First boss kills are no longer sent to Discord by every raid member separately; the bosses are listed in the raid summary
- Milestones (level, Mythic+) are only sent to Discord by officers; GameBot only accepts milestones and polls from officers
- With separate Discord chat, GuildPride never falls back to guild chat (nothing would reach Discord there). If the lines do not come back in game or the Discord channel cannot be reached, you get a hint. New: `/gp discord info` shows step by step which way GuildPride takes
- Officers without a linked Discord get a hint that DKP, announcements and polls otherwise only arrive through a linked officer. Only officers pass such lines on
- New: **edit** events – "Edit" button in the event (creator and officers): change title, date, time, description and repeat. The change goes to the guild and to Discord (with the current GameBot)
- If Blizzard reports right after one of your Discord lines that your Discord is not linked, GuildPride switches this by itself and passes the line on through a linked guildmate
- Waiting Discord lines are no longer lost when you log out, they are sent at your next login (up to 6 hours)
- Settings › Guild: new switches "Always send Discord lines to guild chat" and "Show Discord lines in chat", plus a **Test Discord** button
- GuildPride reports its version to GameBot at most once a week (and after an update), only through the guild's own Discord channel. Officers see in the dashboard who uses an outdated version

## 2.19.1

**Deutsch**
- Behoben: Das Menü links wird beim Verkleinern des Fensters nicht mehr zusammengeschoben. Die Reiter oben und „Einstellungen“ mit den Layer-Knöpfen unten überlappen nicht mehr; das Fenster ist immer hoch genug für das ganze Menü und wächst und schrumpft gleichmäßig mit

**English**
- Fixed: the menu on the left no longer gets squeezed when you make the window smaller. The tabs at the top and "Settings" with the layer buttons at the bottom no longer overlap; the window is always tall enough for the whole menu and scales evenly

## 2.19.0

**Deutsch**
- Neu: Die **Layer-Liste** zeigt jetzt serverweit alle Spieler mit GuildPride, nicht nur die Gilde (eigene Fraktion). Gildenmitglieder stehen grün, deine Zone steht oben, mit dem Mausrad scrollst du durch längere Listen. Mit **Hierhin** wechselst du auf den Layer jedes Spielers in deiner Zone
- Wer den serverweiten GuildPride-Kanal an hat, meldet dort Zone und Layer (höchstens alle 30 Sekunden). Abschalten mit `/gp server`
- Gildenmitglieder mit GuildPride stehen auch ohne Layer-Angabe in der Liste, mit ihrer Zone. Ältere Versionen ohne Layer-Teilen sind mit „alt“ markiert

**English**
- New: the **layer list** now shows every player with GuildPride server-wide, not just the guild (own faction). Guild members are green, your zone comes first, scroll longer lists with the mouse wheel. **Go here** switches you to the layer of any player in your zone
- Everyone with the server-wide GuildPride channel on reports zone and layer there (at most every 30 seconds). Turn it off with `/gp server`
- Guild members with GuildPride are listed even without a layer, with their zone. Older versions that do not share layers are marked "old"

---
Ältere Versionen / older versions: [docs/CHANGELOG-ALT.md](https://github.com/Rottgar85/GuildPride-Forever/blob/main/docs/CHANGELOG-ALT.md)
