# Auktionshaus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auktionshaus-Bereich in GuildPride Forever: Preise im Tooltip, Suchen/Kaufen, Einstellen mit Preisvorschlag, Preise serverweit geteilt (Weg C), stilles Mitlesen bei Auctionator.

**Architecture:** Eigener Unter-Namensraum `ns.AH` (wie `GP.Rares`) in fünf Dateien: Daten/Preislogik (rein, gut testbar), Scan (liest AH-Ergebnislisten), Comm (Teilen über den vorhandenen Kanal `GPRaresF`, Präfix `GPAH`, gemeinsame Sendebremse mit den Raren), Tooltip, UI-Reiter. Scan und Comm laufen auch ohne UI, damit das Mitlesen bei Auctionator funktioniert.

**Tech Stack:** Lua 5.1, WoW-API Interface 16001 (altes Auktionshaus), Tests mit `lua5.1 tests/run.lua` + `tests/wow.lua`.

**Spec:** `docs/superpowers/specs/2026-11-17-auktionshaus-design.md`

## Global Constraints

- Interface 16001, altes AH: `QueryAuctionItems`, `GetNumAuctionItems("list")`, `GetAuctionItemInfo("list", i)`, `GetAuctionItemLink("list", i)`, `CanSendAuctionQuery()` (2. Wert = getAll erlaubt), `PostAuction`, `PlaceAuctionBid`, Events `AUCTION_ITEM_LIST_UPDATE`, `AUCTION_HOUSE_SHOW`, `AUCTION_HOUSE_CLOSED`. Dauern 2/8/24 Std.
- `PostAuction` und `PlaceAuctionBid` nur direkt im `OnClick` eines Knopfes aufrufen.
- Addon-Nachrichten ≤ 250 Zeichen; Felder mit `:` getrennt.
- Kein neuer Chatkanal: Kanal `GPRaresF`, Präfix `GPAH`; zusammen mit Raren höchstens 1 Nachricht / 1,5 s.
- Neue SavedVariable `GuildPrideAHDB` (in `.toc` ergänzen).
- Optionen in `GuildPrideDB` mit Standard: `ahTab = true`, `ahTooltip = true`, `ahShare = true`, `ahReadAuctionator = true`, `ahTooltipWithAuctionator = false`.
- Lua 5.1 / 200-Locals-Grenze (`luac5.1 -p`), luacheck grün (`.tools/luacheck.exe . --no-color -q`), `python .github/build-news.py` lässt git sauber.
- Texte über `L["…"]` mit deutschem Schlüssel und englischer Übersetzung in `GuildPrideLocale.lua`.
- CHANGELOG und Commits nennen `GuildPrideMarks.lua` nie.
- Zahlengrenzen beim Empfang: Preis 1 … 1 000 000 000 Kupfer, Menge 1 … 100 000, Zeit ≤ jetzt + 60 s und ≥ jetzt − 7 Tage.

## Review Focus

1. **Eigene Auktionen in der Ergebnisliste** – nie in `own.p`, auch nicht, wenn sie die günstigsten sind (Test in Task 3).
2. **Item mit Zufalls-Suffix** („… des Bären“) – getrennt vom Grund-Item gespeichert und geteilt (Tests in Task 1 und 3).
3. **Spammer mit Absurdpreis** – bestätigt keinen Serverpreis, steuert keinen Vorschlag (Test in Task 2).
4. **AH schließt mitten in der Suche / Suche gedrosselt** – Warteschlange verworfen, kein Lua-Fehler (Test in Task 3).
5. **Auctionator geladen** – keine eigene `QueryAuctionItems`, aber Mitlesen (Test in Task 3).

---

### Task 1: Preis-Speicher und Preislogik

**Files:**
- Create: `GuildPrideAHData.lua`
- Modify: `GuildPrideForever.toc` (SavedVariables + AH-Dateien nach `GuildPrideRaresUI.lua`), `GuildPride.lua:85-90` (Options-Standards aus Global Constraints)
- Modify: `tests/wow.lua` (`NILS` um `GuildPrideAHDB` ergänzen), `tests/run.lua` (Datei laden, neuer Testblock vor der Zusammenfassung am Ende)

**Interfaces – Produces (alles in `ns.AH`, Datei beginnt mit `local ADDON, GP = ...; GP.AH = GP.AH or {}`):**
- `AH.Side() -> "A"|"H"|"N"`; `AH.SetSide(s)` (beim AH-Öffnen). Standard aus `UnitFactionGroup("player")`.
- `AH.Key(itemID, suffixID|nil) -> string` – `"123"` oder `"123.45"` (Suffix 0 = keins).
- `AH.KeyFromLink(link) -> string|nil` – aus `item:ID:ench:g1:g2:g3:g4:suffix:…` (7. Feld nach `item:`).
- `AH.Store() -> table` – `GuildPrideAHDB[realm][side]`, legt an.
- `AH.RecordOwn(key, p, q, t)` – setzt `own`, pflegt `hist` (Tagesminimum, max. 7 Einträge).
- `AH.RecordServer(key, p, q, t, sender) -> bool` – übernimmt nur, wenn `t ≥ srv.t`; `from[sender] = p` (max. 5, ältester raus).
- `AH.ServerConfirmed(key) -> p|nil` – ganzzahliger Mittelwert, wenn ≥ 2 Absender und `max ≤ min * 1.25`.
- `AH.PriceFor(key) -> p, t, source` – `own`, wenn vorhanden und `own.t ≥ srv.t`, sonst `srv`; `source` `"own"|"srv"`; nil ohne Preis.
- `AH.Suggest(key, freshForeignMin|nil, now) -> p|nil, tag` – Spec 2a: `"fresh"` (= `max(1, freshForeignMin - 1)`), `"own"` (< 3600 s), `"server"` (`ServerConfirmed`), `"old"` (älteres `own` oder jüngster `hist`), sonst nil.
- `AH.Prune(now)` – `srv` > 7 Tage, `own` > 30 Tage löschen, leere Einträge entfernen; bei `PLAYER_LOGIN`.

- [ ] **Step 1: Tests schreiben**

```lua
test("AH: Schlüssel mit und ohne Suffix", function()
    eq(AH.Key(2589), "2589")
    eq(AH.Key(15210, 1017), "15210.1017")
    eq(AH.KeyFromLink("|cff1eff00|Hitem:15210:0:0:0:0:0:1017:0|h[x]|h|r"), "15210.1017")
    eq(AH.KeyFromLink("|cffffffff|Hitem:2589:0:0:0:0:0:0:0|h[Leinen]|h|r"), "2589")
end)
test("AH: Serverpreis erst mit 2 Absendern innerhalb 25 %", function()
    AH.RecordServer("9", 100, 5, W.server, "Anna"); eq(AH.ServerConfirmed("9"), nil)
    AH.RecordServer("9", 200, 5, W.server, "Bert"); eq(AH.ServerConfirmed("9"), nil)
    AH.RecordServer("9", 110, 5, W.server, "Bert"); eq(AH.ServerConfirmed("9"), 105)
end)
test("AH: Vorschlag – fresh > own<1h > server > alt > nil", function()
    local p, tag = AH.Suggest("9", 500, W.server); eq(p, 499); eq(tag, "fresh")
    eq(select(2, AH.Suggest("9", nil, W.server)), "server")
    AH.RecordOwn("9", 300, 2, W.server - 600); eq(AH.Suggest("9", nil, W.server), 300)
    AH.RecordOwn("8", 300, 2, W.server - 5 * 3600); eq(select(2, AH.Suggest("8", nil, W.server)), "old")
    eq(AH.Suggest("nix", nil, W.server), nil)
end)
test("AH: älterer Serverwert verdrängt neueren nicht; Aufräumen", function()
    AH.RecordServer("7", 50, 1, W.server, "Anna")
    eq(AH.RecordServer("7", 10, 1, W.server - 100, "Carl"), false)
    AH.Prune(W.server + 8 * 86400); eq(AH.PriceFor("7"), nil)
end)
```

- [ ] **Step 2:** `lua5.1 tests/run.lua` → neue Tests scheitern (`AH` nil).
- [ ] **Step 3:** `GuildPrideAHData.lua` umsetzen; im Test vorher `GuildPrideAHDB = {}`, `W.Load("GuildPrideAHData.lua")`, `local AH = ns.AH`.
- [ ] **Step 4:** Tests grün; `luac5.1 -p GuildPrideAHData.lua`; luacheck grün.
- [ ] **Step 5:** Commit `AH: Preis-Speicher und Preisvorschlag`.

### Task 2: Teilen über `GPRaresF`

**Files:**
- Modify: `GuildPrideRaresComm.lua` (gemeinsame Warteschlange + Beitritt nach außen)
- Create: `GuildPrideAHComm.lua`
- Test: `tests/run.lua`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `GP.SharedChannel.Send(prefix, msg, key)` – dieselbe Warteschlange wie bisher `ns.Send` (gleicher `key` ersetzt älteren Eintrag); der Ticker sendet mit dem Präfix des Eintrags. `ns.Send` der Raren ruft das mit `"GPRare"`.
  - `GP.SharedChannel.Want(who, on)` – beitreten, solange irgendein `who` an ist (`"rares"` nach bisheriger Regel, `"ah"` = `GuildPrideDB.ahShare`); verlassen nicht nötig.
  - `GP.SharedChannel.Id() -> number|nil`.
  - `AH.EncodeP(side, items) -> {string,…}` – `items = { {key,p,q,t}, … }`, Format `P:<side>:<key>=<p>,<q>,<t>;…`, max. 8 Items und 250 Zeichen je Nachricht.
  - `AH.DecodeP(msg) -> side, items` – `items` leer bei Formfehler; ungültige Items (Grenzen aus Global Constraints, Key nicht `^%d+$`/`^%d+%.%d+$`, `GetItemInfoInstant(id)` nil) übersprungen.
  - `AH.Share(keys)` – `P` für Keys mit `own`, je Key höchstens alle 1800 s.
  - `AH.Ask(key)` – `Q:<side>:<key>`, je Key höchstens alle 600 s, insgesamt 10 pro 60 s.
  - `AH.OnMessage(msg, sender)` – Absender-Bremse 10 pro 60 s, sonst 300 s Sperre (`stats.dropped`); fremde Seite ignorieren; `P` → `RecordServer` je Item, `AH.OnPrice(key)` aufrufen falls gesetzt, geplante Antworten für den Key mit `t ≥ own.t` streichen; `Q` → Antwort planen, wenn `own.t` jünger als 6 Std.: fällig nach `1 + math.random() * 3` s, abgearbeitet von einem 0,5-s-Ticker.
  - `AH._answerPlanned(key) -> bool` (für Tests), `AH.stats = { sent, received, dropped }`.
  - Listener: `CHAT_MSG_ADDON` mit Präfix `GPAH`, Kanal `"CHANNEL"`, nicht von sich selbst, ≤ 250 Zeichen → `AH.OnMessage`.

- [ ] **Step 1: Tests schreiben**

```lua
test("AH-Comm: P kodieren/dekodieren, 250 Zeichen, max 8 Items", function()
    local items = {}
    for i = 1, 20 do items[i] = { key = tostring(1000 + i), p = 12345, q = 20, t = W.server } end
    local out = AH.EncodeP("A", items)
    eq(#out, 3)
    for _, m in ipairs(out) do eq(#m <= 250, true) end
    local side, got = AH.DecodeP(out[1]); eq(side, "A"); eq(#got, 8); eq(got[1].p, 12345)
end)
test("AH-Comm: Unsinn wird verworfen", function()
    local _, a = AH.DecodeP("P:A:abc=1,1," .. W.server); eq(#a, 0)
    local _, b = AH.DecodeP("P:A:9=0,1," .. W.server .. ";10=5,1," .. (W.server + 3600)); eq(#b, 0)
end)
test("AH-Comm: Spammer bestätigt nichts", function()
    for _ = 1, 12 do AH.OnMessage("P:A:11=1,1," .. W.server, "Spam") end
    eq(AH.ServerConfirmed("11"), nil); eq(AH.stats.dropped > 0, true)
end)
test("AH-Comm: andere Seite wird nicht gespeichert", function()
    AH.OnMessage("P:H:12=100,1," .. W.server, "Horde1"); eq(AH.PriceFor("12"), nil)
end)
test("AH-Comm: Q nur mit eigenem Preis < 6 Std.; fremdes P stoppt Antwort", function()
    AH.RecordOwn("13", 100, 1, W.server - 7 * 3600)
    AH.OnMessage("Q:A:13", "Anna"); eq(AH._answerPlanned("13"), false)
    AH.RecordOwn("13", 100, 1, W.server)
    AH.OnMessage("Q:A:13", "Anna"); eq(AH._answerPlanned("13"), true)
    AH.OnMessage("P:A:13=101,1," .. W.server, "Bert"); eq(AH._answerPlanned("13"), false)
end)
```

- [ ] **Step 2:** Tests scheitern (im Test `GetItemInfoInstant` über `tests/wow.lua` so nachbauen, dass Zahlen-IDs bekannt sind).
- [ ] **Step 3:** Umsetzen; `GuildPrideRaresComm.lua` behält sein Verhalten.
- [ ] **Step 4:** Tests grün, `luac5.1 -p`, luacheck.
- [ ] **Step 5:** Im Spiel: `/gpr status` zeigt weiter Senden/Empfangen. Commit `AH: Preise serverweit teilen`.

### Task 3: Scan – Ergebnisse lesen, Suchen, Mitlesen bei Auctionator

**Files:**
- Create: `GuildPrideAHScan.lua`
- Modify: `tests/wow.lua` (Mocks: `W.auctions`, `W.canQuery`, `W.queries`, `W.addons`; `GetNumAuctionItems`, `GetAuctionItemInfo` → `name, texture, count, quality, canUse, level, levelColHeader, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, bidderFull, owner`, `GetAuctionItemLink`, `QueryAuctionItems` zählt, `CanSendAuctionQuery`, `C_AddOns.IsAddOnLoaded`)
- Test: `tests/run.lua`

**Interfaces:**
- Consumes: Task 1, Task 2 (`AH.Share`).
- Produces:
  - `AH.AuctionatorLoaded() -> bool`.
  - `AH.ReadList() -> { [key] = { min, qty, n, link, offers = { {owner,count,bid,buyout,index}, … } } }` – Stückpreis = `floor(buyout / count)`; `buyout == 0` nur in `offers`; **`owner == UnitName("player")` nie in `min`**; danach `AH.RecordOwn(key, min, qty, GetServerTime())` für Keys mit `min`.
  - `AH.Search(text, onDone)` – nichts tun, wenn Auctionator geladen; Seiten 0,1,… bei `CanSendAuctionQuery()` (Ticker 0,3 s), Ergebnisse zusammenführen, am Ende `AH.Share(keys)` und `onDone(results)`; `AUCTION_HOUSE_CLOSED` leert alles, `onDone` wird nicht mehr gerufen.
  - `AH.FullScan()` – nur wenn getAll erlaubt; nur `RecordOwn`, kein `Share`.
  - Mitlesen: `AUCTION_ITEM_LIST_UPDATE` mit geladenem Auctionator und `GuildPrideDB.ahReadAuctionator` → `ReadList()`; `Share` nur, wenn die Seite ≤ 200 Einträge hat.
  - `AUCTION_HOUSE_SHOW` → `AH.SetSide("N")` in Goblin-Städten (Gadgetzan, Beutebucht, Ewige Warte; Map-IDs als Konstante, im Spiel prüfen), sonst Fraktion.

- [ ] **Step 1: Tests schreiben** (`LINK_2589`, `LINK_15210_1017`, `LINK_15210_0` als Konstanten im Testblock)

```lua
test("AH-Scan: eigene Auktionen und Angebote ohne Sofortkauf zählen nicht", function()
    W.auctions = {
        { "Leinen", 20, 100, 200, "Tester", LINK_2589 },
        { "Leinen", 10, 100, 0,   "Anna",   LINK_2589 },
        { "Leinen", 5,  100, 150, "Bert",   LINK_2589 },
    }
    local r = AH.ReadList(); eq(r["2589"].min, 30); eq(AH.PriceFor("2589"), 30)
end)
test("AH-Scan: Suffix-Items getrennt", function()
    W.auctions = { { "x", 1, 1, 500, "Anna", LINK_15210_1017 }, { "x", 1, 1, 900, "Anna", LINK_15210_0 } }
    local r = AH.ReadList(); eq(r["15210.1017"].min, 500); eq(r["15210"].min, 900)
end)
test("AH-Scan: mit Auctionator keine eigene Suche, aber Mitlesen", function()
    W.addons.Auctionator = true; W.queries = 0
    AH.Search("Leinen", function() end); eq(W.queries, 0)
    W.auctions = { { "Leinen", 1, 1, 40, "Bert", LINK_2589 } }
    W.Fire("AUCTION_ITEM_LIST_UPDATE"); eq(AH.PriceFor("2589"), 40)
    W.addons.Auctionator = nil
end)
test("AH-Scan: AH schließt mitten in der Suche", function()
    local called = false
    W.canQuery = false; AH.Search("Leinen", function() called = true end)
    W.Fire("AUCTION_HOUSE_CLOSED"); W.canQuery = true; W.Fire("AUCTION_ITEM_LIST_UPDATE")
    eq(called, false)
end)
```

- [ ] **Step 2:** Tests scheitern.
- [ ] **Step 3:** Umsetzen.
- [ ] **Step 4:** Tests grün, `luac5.1 -p`, luacheck.
- [ ] **Step 5:** Commit `AH: Ergebnislisten lesen und suchen`.

### Task 4: Tooltip

**Files:**
- Create: `GuildPrideAHTooltip.lua`
- Modify: `tests/wow.lua` (`W.itemInfo[id] = { quality, bindType, classID, sellPrice }` für `GetItemInfo`; `GetCoinTextureString(p)` → `p .. "c"`)
- Test: `tests/run.lua`

**Interfaces:**
- Consumes: `AH.KeyFromLink`, `AH.PriceFor`, `AH.Ask`, `AH.AuctionatorLoaded`.
- Produces:
  - `AH.Tradeable(link) -> bool` – false bei Qualität 0, `bindType == 1`, `classID == 12` (Quest), oder `sellPrice == 0` und kein bekannter Preis.
  - `AH.TooltipLine(link, count, now, shift) -> string|nil` – `L["Auktionshaus: %s (%s)"]`, zweites Feld „vor <Alter>“ bzw. „Server, vor <Alter>“; Alter „gerade eben“ (< 120 s), „vor N Min.“, „vor N Std.“, „vor N Tagen“; mit `shift` und `count > 1`: Gesamtpreis + „ (x<count>)“ hinter dem Geld.
  - `AH.OnPrice(key)` setzen: zeigt `GameTooltip` noch dieses Item → neu aufbauen.
  - Haken wie `GuildPrideScalesTooltip.lua:92-106` (gleiche Methodenliste, `OnTooltipSetItem`); Zeile nur bei `GuildPrideDB.ahTooltip` und (`not AH.AuctionatorLoaded()` oder `GuildPrideDB.ahTooltipWithAuctionator`); fehlt der Preis oder ist er > 24 Std. alt und `AH.Tradeable` → `AH.Ask(key)`.

- [ ] **Step 1: Tests**

```lua
test("AH-Tooltip: Zeile mit Herkunft und Alter", function()
    AH.RecordOwn("2589", 30, 5, W.server - 7200)
    eq(AH.TooltipLine(LINK_2589, 1, W.server, false), "Auktionshaus: 30c (vor 2 Std.)")
    eq(AH.TooltipLine(LINK_2589, 20, W.server, true), "Auktionshaus: 600c (x20) (vor 2 Std.)")
end)
test("AH-Tooltip: seelengebunden/Quest/grau → nicht handelbar", function()
    W.itemInfo[5000] = { quality = 1, bindType = 1, classID = 0, sellPrice = 10 }
    W.itemInfo[5001] = { quality = 1, bindType = 0, classID = 12, sellPrice = 0 }
    W.itemInfo[5002] = { quality = 0, bindType = 0, classID = 0, sellPrice = 5 }
    eq(AH.Tradeable("|Hitem:5000:0:0:0:0:0:0:0|h"), false)
    eq(AH.Tradeable("|Hitem:5001:0:0:0:0:0:0:0|h"), false)
    eq(AH.Tradeable("|Hitem:5002:0:0:0:0:0:0:0|h"), false)
end)
```

- [ ] **Step 2–4:** scheitern sehen, umsetzen, grün (`luac5.1 -p`, luacheck).
- [ ] **Step 5:** Commit `AH: Preis im Tooltip`.

### Task 5: Reiter „GuildPride“ im Auktionshaus

**Files:**
- Create: `GuildPrideAHUI.lua`

**Interfaces:**
- Consumes: `AH.Search` (Ergebnisform von `AH.ReadList`), `AH.Suggest`, `AH.Share`, `AH.KeyFromLink`, `AH.AuctionatorLoaded`, Stil aus `GuildPrideSkin.lua`/`GuildPrideTheme.lua`.

Verhalten (Spec 3 und 2a):
- Nur bei `GuildPrideDB.ahTab` und ohne Auctionator. Bei `ADDON_LOADED` von `Blizzard_AuctionUI` (oder sofort, falls geladen) einen weiteren `AuctionFrameTab` nach Blizzards Muster anlegen (`PanelTemplates_SetNumTabs`; Umschalten per `hooksecurefunc("AuctionFrameTab_OnClick", …)`), keine Blizzard-Funktion ersetzen.
- **Suchen:** Eingabe + Knopf → `AH.Search`; Liste (Symbol, Name, Stückpreis, Angebote, Menge); Klick → Einzelangebote; **Kaufen** im `OnClick`: prüfen, dass `GetAuctionItemInfo("list", index)` noch Name/Menge/Sofortkauf des Angebots hat, dann `PlaceAuctionBid("list", index, buyout)`; sonst neu suchen und Hinweis.
- **Verkaufen:** Ablagefeld; Item über den Blizzard-Weg ins Verkaufsfeld (`PickupContainerItem` + `ClickAuctionSellItemButton()`), dann `AH.Search(Name)`; Vorschlag `AH.Suggest(key, freshForeignMin, GetServerTime())` mit Kennzeichnung (`fresh` ohne Zusatz; `own` „eigener Preis“; `server` „Serverpreis“; `old` „alt (vor …)“). Nach Suchende ersetzen, solange das Feld nicht von Hand geändert wurde. Felder: Stückpreis, Stapelgröße, Stapel, Dauer 2/8/24 Std. (→ 1/2/3); Einzahlung über `CalculateAuctionDeposit(duration)` (falls vorhanden) bzw. Blizzards Verkaufsfeld. **Einstellen** im `OnClick`: `PostAuction(minBid, buyout, duration, stackSize, numStacks)` mit Preisen pro Stapel; danach `AH.Share({key})`.

- [ ] **Step 1:** Umsetzen.
- [ ] **Step 2:** `luac5.1 -p`, luacheck, `lua5.1 tests/run.lua` ohne Regression.
- [ ] **Step 3:** Prüfliste im Spiel (ohne Auctionator, `/console scriptErrors 1`): Reiter erscheint; Suche „Leinenstoff“ zeigt Ergebnisse; ein billiges Angebot kaufen; Verkaufen schlägt −1 Kupfer vor; eigene Auktion wird beim nächsten Vorschlag nicht unterboten; AH schließen während der Suche → kein Fehler; Goblin-AH speichert getrennt.
- [ ] **Step 4:** Commit `AH: Reiter Suchen und Verkaufen`.

### Task 6: Einstellungen, Befehle, Hilfe, Texte, Version

**Files:**
- Modify: `GuildPrideUI.lua:1750-1775` (Abschnitt `{ header = L["Auktionshaus"] }` mit `ahTab`, `ahTooltip`, `ahTooltipWithAuctionator`, `ahShare`; `ahShare.changed` → `GP.SharedChannel.Want("ah", GuildPrideDB.ahShare)`), `GuildPrideHelp.lua` (Slash-Kette wie bei `/gp server`), `GuildPrideLocale.lua`, `CHANGELOG.md`, `GuildPrideForever.toc` (`## Version: 2.21.0`), `GuildPrideNewsData.lua` (per Skript)

- `ahReadAuctionator` bekommt **keinen** Schalter in den Einstellungen – das ist der zentrale Abschalter für ein späteres Update.
- `/gp ah` → kurze Hilfe; `/gp ah status` → „Preise teilen: an/aus · Kanal GPRaresF: #n|nicht beigetreten · Gesendet: x · Empfangen: y · Verworfen: z · Auctionator: ja/nein (mitlesen: an/aus)“; `/gp ah scan` → `AH.FullScan()` nur am offenen AH, ohne Auctionator, mit getAll; sonst passender Hinweis.

- [ ] **Step 1:** Umsetzen, alle neuen Texte mit Englisch.
- [ ] **Step 2:** Volle Prüfung: `lua5.1 tests/run.lua`; `luac5.1 -p` auf alle `*.lua` (dann `luac.out` löschen); `.tools/luacheck.exe . --no-color -q`; `python .github/build-news.py` → `git status` sauber.
- [ ] **Step 3:** Prüfliste im Spiel mit zwei Charakteren gleicher Fraktion: A sucht ein Item → B sieht „Server, gerade eben“; B fährt über ein unbekanntes Item → genau eine Antwort (`/gp ah status` bei A); mit Auctionator bei A: kein Reiter, Auctionator-Suche → B bekommt Preise; Raren-Teilen läuft weiter.
- [ ] **Step 4:** CHANGELOG (Deutsch + Englisch) und Version 2.21.0; Commit `2.21.0: Auktionshaus mit serverweiten Preisen`. Push und Tag erst nach Freigabe durch den Nutzer.
