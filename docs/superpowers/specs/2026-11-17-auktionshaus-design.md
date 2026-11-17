# Auktionshaus in GuildPride Forever – Entwurf

Stand: 2026-11-17 · Zielversion: 2.21.0

## Absicht und Warum

GuildPride Forever soll das „All in One“-Addon werden, das ein Spieler auf WoW Forever installiert. Der erste große Baustein ist ein **Auktionshaus-Bereich**, der die zwei Kernaufgaben von Auctionator übernimmt:

1. **Preise checken** – was kostet ein Item gerade (Tooltip überall, Suche im Auktionshaus).
2. **Auktionen erstellen** – Item aus der Tasche wählen, Preis vorgeschlagen bekommen, einstellen.

Das Besondere gegenüber Auctionator: **Preise werden serverweit geteilt** (alle Spieler mit GuildPride am selben Auktionshaus). Forever drosselt Suchanfragen am Auktionshaus; wer selten scannt, profitiert von den Scans der anderen.

## Ziele

- Preis im Item-Tooltip (Taschen, Auktionshaus, Links, Bank, Händler), mit Alter und Herkunft (eigener Scan / Server).
- Im Auktionshaus ein eigener Reiter **„GuildPride“** mit zwei Unterseiten:
  - **Suchen:** Name eingeben → Ergebnisse gruppiert nach Item (günstigster Stückpreis, Anzahl Angebote, Menge), Klick zeigt die Einzelangebote, Sofortkauf eines Angebots.
  - **Verkaufen:** Item aus der Tasche (Klick oder Ziehen), automatische Suche danach, Preisvorschlag = günstigstes fremdes Angebot pro Stück minus 1 Kupfer (eigene Angebote zählen nicht), Stapelgröße, Anzahl Stapel, Dauer (2/8/24 Std.), Einzahlung sichtbar, Knopf **Einstellen**.
- Optional **Komplett-Scan**, wenn Forever ihn erlaubt – Ergebnis nur lokal.
- Serverweites Teilen nach Weg **C** (siehe unten).
- Deutsch und Englisch wie im Rest des Addons.

## Nicht-Ziele (jetzt)

- Kein vollständiger Auctionator-Nachbau: keine Einkaufslisten, kein Abbrechen-Reiter mit Massen-Unterbieten, keine Verkaufsstatistik, keine Posting-Gruppen.
- Keine Preisdiagramme, keine Bank-/Postfach-Automatik.

Diese Dinge können später als eigene Schritte kommen.

## Anti-Ziele (Fehlschlag, auch wenn es „funktioniert“)

- **Gefälschte Preise steuern Verkäufe:** Ein fremder Preis allein bestimmt nie den Verkaufsvorschlag.
- **Kanal-Flut:** Teilen darf den Kanal nicht dauerhaft belegen; Raren-Meldungen und Gruppensuche müssen weiter durchkommen.
- **Doppelte Suchanfragen mit Auctionator:** Ist Auctionator geladen, schickt GuildPride keine eigenen Suchanfragen und drängt keinen zweiten Reiter auf.
- **Taint/Fehler** im Auktionshaus-Fenster von Blizzard.
- Spürbare Ruckler beim Tooltip, oder SavedVariables, die das Einloggen merklich verlangsamen.

## Einschränkungen

- Interface 16001; Forever nutzt das **alte Auktionshaus** (wie Classic): `QueryAuctionItems`, `GetAuctionItemInfo("list", i)`, `GetNumAuctionItems`, `CanSendAuctionQuery()`, `PostAuction`, `PlaceAuctionBid`, `AUCTION_ITEM_LIST_UPDATE`; Dauern 2/8/24 Std. (Auctionator lädt hier `Source_LegacyAH` und `Source_Forever/Constants.lua` – gute Referenz für das Verhalten). Ob `getAll` erlaubt ist, liefert `CanSendAuctionQuery()` als zweiten Wert – zur Laufzeit abfragen.
- Kaufen und Einstellen sind geschützt: **nur direkt aus einem Klick**.
- Höchstens 10 eigene Chatkanäle; GuildPride belegt schon Datenkanal, Gruppensuche-Kanal und `GPRaresF`.
- Addon-Nachrichten ≤ 250 Zeichen (Hausregel).
- Lua 5.1, 200-Locals-Grenze (`luac5.1 -p` in CI), luacheck grün, `python .github/build-news.py` lässt git sauber.
- Neue Dateien in `GuildPrideForever.toc`; neue SavedVariable `GuildPrideAHDB`, damit `GuildPrideDB` klein bleibt.
- Tests: `lua5.1 tests/run.lua` mit dem WoW-Nachbau `tests/wow.lua`.

## Erwogene Wege

**Verteilung der Preise:**

- **A) Nach jedem Scan alles rundsenden.** Einfach, aber Tausende Items bei 1,5 s pro Nachricht belegen den Kanal stundenlang. *Verworfen.*
- **B) Nur auf Nachfrage.** Sehr wenig Verkehr, aber Preise erscheinen im Tooltip immer verzögert. *Allein zu träge.*
- **C) Mischung – gewählt.** Aktiv gesuchte oder eingestellte Items gehen kurz an alle (Dutzende, nicht Tausende). Für den Rest fragt das Addon bei Bedarf, und genau ein Besitzer eines frischen Preises antwortet.

**Reichweite:** „nur Gilde“ wurde erwogen, gewählt ist **serverweit** (gleiches Auktionshaus), weil so jeder von den meisten Scans profitiert.

## Entscheidungen des Nutzers

- Auktionshaus-Bereich: **Preise checken** und **Auktionen erstellen** wie Auctionator.
- Preise **serverweit** teilen, Verteilung nach **Weg C**.

## Vorschläge von mir (genannt, nicht widersprochen)

- **Auctionator geladen → GuildPride hält sich zurück:** kein Reiter, keine eigenen Suchanfragen, Tooltip-Zeile aus (Einstellung, um sie trotzdem zu zeigen). GuildPride liest keine SavedVariables von Auctionator.
- **Mitlesen bei Auctionator (Entscheidung des Nutzers):** Ist Auctionator geladen, liest GuildPride still die Ergebnisse mit, die Auctionators Suchen ins Auktionshaus holen (`AUCTION_ITEM_LIST_UPDATE` → `GetAuctionItemInfo("list", i)`), füllt damit `own` und teilt sie nach Weg C (sendet `P` für so gesuchte Items, beantwortet `Q`). Eine eingeschaltete Tooltip-Zeile darf auch `Q` senden. Scannen-Lesen und Teilen laufen dafür **ohne** den Reiter. Komplett-Scans von Auctionator gelten wie eigene Komplett-Scans (kein Massen-`P`).
  - Der Nutzer will das **später abschalten können**, wenn genug Spieler den GuildPride-Teil nutzen. Deshalb hängt das Mitlesen an einem eigenen, zentralen Schalter (eine Konstante bzw. Option `ahReadAuctionator`, Standard **an**), sodass ein späteres Update es mit einer Zeile ausschalten kann, ohne andere Teile anzufassen.
- **Eigener Scan geht immer vor.** Fremde Preise erscheinen im Tooltip mit Alter („Server, vor 2 Std.“). In den Verkaufsvorschlag fließen sie nur, wenn kein eigener Preis jünger als 1 Std. existiert **und** mindestens **2 verschiedene Absender** Preise gemeldet haben, die höchstens 25 % auseinanderliegen; dann als „Serverpreis“ markiert. Beim Öffnen von „Verkaufen“ wird ohnehin frisch gesucht, sobald die Drosselung es erlaubt.
- **Kein neuer Kanal:** Das Auktionshaus nutzt den offenen Forever-Kanal `GPRaresF` mit eigenem Präfix `GPAH`. Kanalbeitritt passiert, wenn Raren-Teilen **oder** Preise-Teilen an ist.

## Teile und Verhalten

### 1. Preis-Speicher (`GuildPrideAHDB`)

- Schlüssel oben: Realm + AH-Seite (Allianz / Horde / Neutral). Die Seite wird beim Öffnen des AH bestimmt (Neutral bei Goblin-AH); ohne offenes AH gilt die eigene Fraktion.
- Pro Item (Item-ID, bei Zufalls-Suffix Item-ID + Suffix-ID):
  - `own = { p, q, t }` – jüngster eigener Stückpreis (min. Sofortkauf/Menge, Kupfer), Gesamtmenge, Zeit
  - `srv = { p, q, t, from = { [Absender] = p } }` – jüngster Serverwert und bis zu 5 Absender mit Preis
  - `hist` – höchstens 7 Tagesminima aus eigenen Scans
- Aufräumen beim Einloggen: Serverwerte > 7 Tage, eigene > 30 Tage löschen.

### 2. Suchen und Scannen

- Anfragen nur, wenn `CanSendAuctionQuery()` es erlaubt; Warteschlange über Seiten (50 pro Seite), Abbruch beim Schließen des AH.
- Jede gelesene Seite aktualisiert `own` aller gefundenen Items (Angebote ohne Sofortkauf zählen nicht). **Eigene Auktionen des Spielers zählen nie** in `own.p` – sonst würde ein Verkäufer seinen eigenen Unterbiet-Preis als Marktpreis verbreiten, und zwei Spieler würden sich gegenseitig nach unten ziehen. *(Entscheidung von mir.)*
- Komplett-Scan: Knopf nur sichtbar, wenn `getAll` gerade erlaubt ist, mit Hinweis auf kurzes Ruckeln. Ergebnis wird **nicht als Massen-`P` rundgesendet** (Grund: Verkehr, nicht Vertrauen). Es landet normal in `own` und darf deshalb `Q`-Nachfragen beantworten. *(Entscheidung von mir.)*

### 2a. Preisvorschlag beim Verkaufen – Reihenfolge

1. Frische Suche (gerade eben) mit fremden Angeboten → günstigstes fremdes Stückpreis-Angebot −1 Kupfer.
2. Sonst eigener Preis `own` jünger als 1 Std. → dieser.
3. Sonst Serverpreis nach der 2-Absender-Regel → Mittelwert der passenden Absender, markiert „Serverpreis“.
4. Sonst älterer eigener Preis oder `hist` → dieser, markiert „alt (vor X)“.
5. Sonst leeres Feld; der Spieler trägt selbst ein.

Findet die frische Suche nichts Fremdes (nur eigene oder gar keine Angebote), gilt Schritt 2 ff. Ist die Suche gedrosselt, wird der Vorschlag nach Schritt 2 ff. vorbelegt und nach dem Eintreffen der Suche ersetzt, solange der Spieler das Feld nicht selbst geändert hat. Eingestellt wird immer erst per Klick – ein vorgeschlagener Preis geht nie ungesehen raus. *(Entscheidung von mir.)*

### 3. Reiter „GuildPride“ im Auktionshaus

- Eigener Reiter unten am `AuctionFrame`, Inhalt im GuildPride-Stil (`GuildPrideSkin` / `GuildPrideTheme`).
- **Suchen:** Eingabefeld, Item-Liste (Symbol, Name, günstigster Stückpreis, Angebote, Menge), Detailansicht der Einzelangebote (Verkäufer, Menge, Stückpreis, Gebot/Sofortkauf), Knopf **Kaufen** (Sofortkauf, nur per Klick).
- **Verkaufen:** wie unter Ziele; mehrere Stapel nacheinander – jeder weitere Stapel per erneutem Klick auf **Einstellen**, sofern das alte AH kein Mehrfach-Einstellen in einem Aufruf erlaubt.

### 4. Tooltip

- Zeile „Auktionshaus: 1g 20s (vor 2 Std.)“ bzw. „(Server, vor 2 Std.)“; mit Shift Gesamtpreis des Stapels.
- Gleicher Haken-Weg wie `GuildPrideScalesTooltip.lua` (Classic-Methoden `SetBagItem`, `SetAuctionItem`, `SetHyperlink`, `SetInventoryItem`, `SetMerchantItem` …).
- Kein oder zu alter Preis (> 24 Std.) → Nachfrage (siehe 5); die Zeile erscheint, wenn die Antwort kommt und der Tooltip noch dasselbe Item zeigt.
- Keine Nachfrage und keine Zeile für Items, die nicht ins Auktionshaus können: seelengebunden beim Aufheben, Questgegenstände, graue Qualität, Items mit Händlerpreis 0 und ohne Handelbarkeit. *(Entscheidung von mir.)*

### 5. Teilen (Weg C) – Kanal `GPRaresF`, Präfix `GPAH`

Nachrichten, Felder mit `:`, ≤ 250 Zeichen:

- `P:<seite>:<item>=<p>,<q>,<t>;<item>=…` – **Preis-Paket**, bis zu ~8 Items. Gesendet für Items, die man gerade **gesucht** oder **eingestellt** hat (nie aus Komplett-Scan). Pro Item höchstens alle 30 Min.
- `Q:<seite>:<item>` – **Nachfrage**, höchstens 1 pro Item alle 10 Min. und 10 pro Minute insgesamt.
- Antwort auf `Q`: ein `P` mit genau diesem Item, nur mit **eigenem** Preis jünger als 6 Std. Jeder Antwortwillige wartet zufällig 1–4 s; hört er inzwischen ein `P` mit gleich neuem oder neuerem Stand, antwortet er nicht.
- `<item>` = Item-ID oder `ID.Suffix`.
- Gemeinsame Sendebremse mit dem Raren-Teilen: zusammen höchstens 1 Nachricht pro 1,5 s.
- Empfangsschutz wie `GuildPrideRaresComm.lua`: nur Kanal, nicht von sich selbst, Längengrenze, je Absender max. 10 Nachrichten/Min. (sonst 5 Min. Sperre), Zahlen in Grenzen (Preis 1 Kupfer … 100 000 Gold, Menge 1 … 100 000, Zeit nicht in der Zukunft und ≤ 7 Tage alt), Item-IDs, die `GetItemInfoInstant` nicht kennt, verwerfen.
- Nur die eigene Seite wird gespeichert.
- Einstellung **Preise serverweit teilen** (Standard an), unabhängig vom Raren-Teilen.

### 6. Einstellungen und Befehle

- Einstellungen › Abschnitt „Auktionshaus“: Reiter an/aus, Tooltip-Zeile an/aus, Preise teilen an/aus.
- `/gp ah` (Hilfe), `/gp ah status` (gesendet/empfangen/verworfen, wie `/gpr status`), `/gp ah scan` (Komplett-Scan am offenen AH).
- Hilfetext in `GuildPrideHelp.lua`, Texte in `GuildPrideLocale.lua` (deutsche Schlüssel + englische Übersetzung).

### 7. Tests

- Automatisch (`tests/run.lua`): Nachrichten bauen/lesen, Empfangsschutz, Regel „2 Absender, ≤ 25 %“, „genau einer antwortet“ (Zufall im Test fest), Aufräumen, Preisvorschlag (eigene Angebote ignorieren, −1 Kupfer).
- Im Spiel (Prüfliste im Plan): Suche, Kaufen, Einstellen, Tooltip, Teilen mit zwei Charakteren, Verhalten mit geladenem Auctionator.

## Dem Bauenden überlassen

- Dateiaufteilung (Vorschlag: `GuildPrideAHData.lua`, `GuildPrideAHScan.lua`, `GuildPrideAHComm.lua`, `GuildPrideAHUI.lua`, `GuildPrideAHTooltip.lua`) und der konkrete Umbau des gemeinsamen Kanalbeitritts.
- Genaues Layout, solange es zum GuildPride-Stil passt.
- Wie die Goblin-AH-Seite erkannt wird, solange sie zuverlässig getrennt gespeichert wird.
- Feinwerte der Bremsen, wenn Tests im Spiel bessere zeigen (die Anti-Ziele bleiben).
- CHANGELOG-Text (nennt `GuildPrideMarks.lua` nie).
